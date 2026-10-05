# frozen_string_literal: true

require "test_helper"
require "json"

class ShellRunnerTest < Minitest::Test
  IMAGE_ID = "sha256:#{'a' * 64}".freeze

  def setup
    @directory = Dir.mktmpdir("rich-ri-shell-runner-")
    @log = File.join(@directory, "calls.jsonl")
    @bin = File.join(@directory, "bin")
    FileUtils.mkdir_p(@bin)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_missing_native_shells_use_the_first_running_engine
    engines("docker", "podman")
    _out, err, status = run_runner(env: { "SHELL_RUNNER_DOCKER_INFO" => "1" })

    assert_predicate status, :success?, err
    assert_equal [%w[docker info], %w[podman info], %w[podman build], %w[podman run]], steps
  end

  def test_docker_takes_precedence_when_both_engines_are_running
    engines("docker", "podman")
    _out, err, status = run_runner

    assert_predicate status, :success?, err
    assert_equal [%w[docker info], %w[docker build], %w[docker run]], steps
  end

  def test_explicit_engine_selection_is_respected
    engines("docker", "podman")
    _out, err, status = run_runner(env: { "RICH_RI_CONTAINER_RUNTIME" => "podman" })

    assert_predicate status, :success?, err
    assert_equal [%w[podman info], %w[podman build], %w[podman run]], steps
  end

  def test_unknown_engine_selection_cannot_execute_a_command
    engines("docker", "podman")
    _out, err, status = run_runner(env: { "RICH_RI_CONTAINER_RUNTIME" => "docker; echo unsafe" })

    refute_predicate status, :success?
    assert_includes err, "RICH_RI_CONTAINER_RUNTIME must be docker or podman"
    assert_empty calls
  end

  def test_unavailable_selected_engine_does_not_fall_back_silently
    engines("docker", "podman")
    _out, err, status = run_runner(env: { "RICH_RI_CONTAINER_RUNTIME" => "podman", "SHELL_RUNNER_PODMAN_INFO" => "1" })

    refute_predicate status, :success?
    assert_includes err, "running podman engine"
    assert_includes err, "Start the engine"
    assert_equal [%w[podman info]], steps
  end

  def test_missing_engines_explain_how_to_run_the_required_checks
    _out, err, status = run_runner

    refute_predicate status, :success?
    assert_includes err, "Bash, Zsh, Fish and bash-completion 2.x"
    assert_includes err, "Docker or Podman"
    assert_includes err, "bundle exec rake test:shells"
  end

  def test_explicit_container_mode_ignores_available_native_shells
    engines("docker")
    _out, err, status = run_runner(native: true, container: true)

    assert_predicate status, :success?, err
    assert_equal [%w[docker info], %w[docker build], %w[docker run]], steps
  end

  def test_failed_build_stops_before_running_tests
    engines("docker")
    _out, err, status = run_runner(env: { "SHELL_RUNNER_BUILD_STATUS" => "23" })

    refute_predicate status, :success?
    assert_includes err, "Shell test image build failed"
    assert_equal [%w[docker info], %w[docker build]], steps
  end

  def test_failed_container_tests_fail_the_task
    engines("docker")
    _out, err, status = run_runner(env: { "SHELL_RUNNER_RUN_STATUS" => "42" })

    refute_predicate status, :success?
    assert_includes err, "Container shell integration tests failed"
    assert_equal "run", steps.last.last
  end

  def test_invalid_build_identity_cannot_start_a_container
    engines("docker")
    _out, err, status = run_runner(env: { "SHELL_RUNNER_IMAGE_ID" => "a mutable tag" })

    refute_predicate status, :success?
    assert_includes err, "Container build did not return an image ID"
    assert_equal [%w[docker info], %w[docker build]], steps
  end

  def test_runs_the_built_image_with_isolated_temporary_storage
    engines("docker")
    _out, err, status = run_runner

    assert_predicate status, :success?, err
    build, run = calls.last(2).map { |call| call.fetch("arguments") }

    assert_equal IMAGE_ID, run.last
    refute_equal build.fetch(build.index("--tag") + 1), run.last
    assert_includes run, "--read-only"
    assert_includes run, "--network=none"
    assert_includes run, "--security-opt=no-new-privileges"
    assert_includes run, "--cap-drop=ALL"
    temporary = run.fetch(run.index("--tmpfs") + 1)

    assert_match(%r{\A/tmp:.*\bexec\b}, temporary)
    refute(run.any? { |arg| arg.match?(/\A(?:-v|--volume|--mount)(?:=|\z)/) })
    refute_path_exists build.fetch(build.index("--iidfile") + 1)
  end

  private

  def calls
    return [] unless File.exist?(@log)

    File.readlines(@log).map { |line| JSON.parse(line) }
  end

  def steps
    calls.map { |call| [call.fetch("engine"), call.fetch("arguments").first] }
  end

  def engines(*names)
    names.each do |name|
      path = File.join(@bin, name)
      File.write(path, "#!#{RbConfig.ruby}\n" + <<~'RUBY')
        require "json"
        engine = File.basename($PROGRAM_NAME)
        File.open(ENV.fetch("SHELL_RUNNER_LOG"), "a") do |file|
          file.puts JSON.generate("engine" => engine, "arguments" => ARGV)
        end
        case ARGV.first
        when "info"
          exit Integer(ENV.fetch("SHELL_RUNNER_#{engine.upcase}_INFO", "0"))
        when "build"
          status = Integer(ENV.fetch("SHELL_RUNNER_BUILD_STATUS", "0"))
          exit status unless status.zero?

          File.write(ARGV.fetch(ARGV.index("--iidfile") + 1), ENV.fetch("SHELL_RUNNER_IMAGE_ID"))
        when "run"
          exit Integer(ENV.fetch("SHELL_RUNNER_RUN_STATUS", "0"))
        else
          abort "Unexpected engine command: #{ARGV.inspect}"
        end
      RUBY
      FileUtils.chmod(0o755, path)
    end
  end

  def run_runner(native: false, container: false, env: {})
    script = <<~RUBY
      require #{File.join(TestSupport::ROOT, 'rakelib/shell_tests').inspect}
      ShellSupport.define_singleton_method(:available?) { #{native} }
      begin
        ShellTests.run(container: #{container})
      rescue ShellTests::Error => error
        warn error.message
        exit 1
      end
    RUBY
    environment = { "PATH" => @bin, "RICH_RI_CONTAINER_RUNTIME" => nil,
                    "SHELL_RUNNER_LOG" => @log, "SHELL_RUNNER_IMAGE_ID" => IMAGE_ID }
    Open3.capture3(environment.merge(env), RbConfig.ruby, "-e", script, chdir: TestSupport::ROOT)
  end
end
