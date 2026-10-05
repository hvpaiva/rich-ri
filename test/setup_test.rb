# frozen_string_literal: true

require "test_helper"
require "program_support"
require_relative "../rakelib/tools"

class SetupTest < Minitest::Test
  include ProgramSupport

  NEXT_STEPS = "Run bundle exec rake for tests and Ruby lint, bundle exec rake check for the CI quality checks\n" \
               "and bundle exec rake test:compatibility for the oldest supported dependencies.\n"
  NO_SHELLS = "setup: shell integration checks need Bash, Zsh, Fish and bash-completion 2.x, or a running " \
              "Docker or Podman engine. Start the engine and rerun bundle exec rake test:shells.\n"

  def setup
    @bin = Dir.mktmpdir("rich-ri-setup-")
    @log = File.join(@bin, "mise.log")
    program("bundle")
    link_program(@bin, "dirname")
    link_ruby(@bin, bundler: false)
  end

  def teardown
    FileUtils.remove_entry(@bin)
  end

  def test_a_failed_mise_install_does_not_hide_the_missing_programs
    program("mise", "echo 'mise ERROR network unreachable' >&2\nexit 1")
    out, err, status = run_setup

    assert_equal 1, status.exitstatus
    assert_equal "mise ERROR network unreachable\n" \
                 "setup: mise install failed; the lines below name what is still missing.\n" \
                 "#{missing_programs}#{NO_SHELLS}", err
    assert_equal NEXT_STEPS, out
  end

  def test_mise_installs_the_pinned_tools_by_name_and_never_ruby
    program("mise", %(echo "$*" >> "#{@log}"))
    run_setup

    assert_equal ["install #{Tools.mise_tools.join(' ')}\n"], File.readlines(@log).grep(/\Ainstall /)
  end

  def test_a_complete_environment_succeeds
    program("mise")
    (Tools.required + ["docker"]).each { |tool| program(tool) }
    out, err, status = run_setup

    assert_predicate status, :success?, err
    assert_empty err
    assert_equal "Shell integration checks will use docker.\n#{NEXT_STEPS}", out
  end

  def test_without_mise_each_missing_program_says_how_to_install_it
    out, err, status = run_setup

    assert_equal 1, status.exitstatus
    assert_equal "#{missing_programs}#{NO_SHELLS}", err
    assert_equal NEXT_STEPS, out
  end

  def test_a_failed_bundle_install_stops_before_any_report
    program("bundle", "exit 7")
    out, err, status = run_setup

    assert_equal [1, "", ""], [status.exitstatus, out, err]
  end

  private

  def program(name, body = "exit 0") = write_program(@bin, name, body)

  def missing_programs
    pinned = Tools.mise_tools.map do |tool|
      "setup: #{tool} is not installed; install the version mise.toml pins with: mise install #{tool}\n"
    end
    system = Tools::SYSTEM.map { |tool| "setup: #{tool} is not installed; install it with your package manager\n" }
    (pinned + system).join
  end

  def run_setup
    Open3.capture3({ "PATH" => @bin, "RICH_RI_CONTAINER_RUNTIME" => nil }, which("bash"), "bin/setup",
                   chdir: TestSupport::ROOT)
  end
end
