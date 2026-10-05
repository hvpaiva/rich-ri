# frozen_string_literal: true

require "test_helper"
require "command_helper"

class ConfigurationRecoveryTest < Minitest::Test
  include CommandSupport

  # What a recovery action prints, with the configuration file it reports.
  def recovered(action, path)
    case action
    when "--help", "-h" then RichRI::Options.new.parser.to_s
    when "--version", "-v" then "rich-ri #{RichRI::VERSION}\n"
    when "--config-path" then "#{path}\n"
    when "--completion=bash" then File.read(File.join(TestSupport::ROOT, "completions/rich-ri.bash"))
    end
  end

  def test_invalid_ri_abbreviations_fail_lookup_but_allow_recovery_actions
    environment = { "RI" => "--wid=44" }
    out, err, status = cli("--show-config", docs: false, env: environment)

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_includes err, "invalid option: --wid"
    refute_includes err, "--help"
    default = File.join(TestSupport::TEMP, "config/rich-ri/config.yml")
    %w[--help --version --config-path --completion=bash].each do |action|
      out, err, status = cli(action, docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_equal recovered(action, default), out
    end
    # The command line is read first, so its own mistake is the one reported.
    _out, err, status = cli("--vers", docs: false, env: environment)

    assert_equal 2, status.exitstatus
    assert_includes err, "invalid option: --vers"
  end

  def test_recovery_actions_are_recognized_as_the_parser_reads_them
    with_config("theme: [broken") do |path|
      environment = { "RICH_RI_CONFIG" => path }
      { %w[-ah] => "--help", %w[-Tv] => "--version", %w[--width 44 --help] => "--help",
        %w[RichRIExample -h] => "--help" }.each do |args, action|
        out, err, status = cli(*args, docs: false, env: environment)

        assert_predicate status, :success?, "#{args.inspect}: #{err}"
        assert_equal recovered(action, path), out
      end
      # Here --help is the pager command, not a request for help.
      out, err, status = cli("--pager-command", "--help", "--show-config", docs: false, env: environment)

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_includes err, "#{path}: invalid YAML"
    end
  end

  def test_help_respects_valid_styles_and_recovers_from_invalid_configuration
    with_config({ "color" => "always", "styles" => { "title" => "red:bold" } }) do |path|
      out, err, status = cli("--config", path, "--help", docs: false)

      assert_predicate status, :success?, err
      assert_includes out, "\e[31;1mUsage:"
    end
    with_config("theme: [broken") do |path|
      ["--help", "--version", "--config-path", "--completion=bash"].each do |action|
        out, err, status = cli("--config", path, action, docs: false)

        assert_predicate status, :success?, "#{action}: #{err}"
        assert_equal recovered(action, path), out
      end
      _out, err, status = cli("--config", path, "--show-config", docs: false)

      assert_equal 1, status.exitstatus
      assert_includes err, "#{path}: invalid YAML"
      refute_includes err, "--help"
      refute_match(/from .*\.rb:\d+/, err)
      _out, err, status = cli("--config", path, "--no-config", "--show-config", docs: false)

      assert_predicate status, :success?, err
    end
  end

  def test_help_and_version_work_with_unreadable_file
    with_config({ "theme" => "dark" }) do |path|
      File.chmod(0o000, path)
      skip "File permissions do not apply to this user" if File.readable?(path)

      ["--help", "--version"].each do |action|
        out, err, status = cli("--config", path, action, docs: false)

        assert_predicate status, :success?, err
        assert_equal recovered(action, path), out
      end
    end
  end

  def test_recovery_actions_survive_a_failed_system_call_while_reading_the_configuration
    failure = <<~RUBY
      require "rich_ri"
      RichRI::ConfigurationFile.prepend(Module.new { def read = raise(Errno::EIO, "planted") })
    RUBY
    with_config({ "width" => 44 }) do |path|
      run = ->(*args) { with_planted(failure) { |env| cli("--config", path, *args, docs: false, env: env) } }
      ["--help", "--version", "--config-path", "--completion=bash"].each do |action|
        out, err, status = run.call(action)

        assert_predicate status, :success?, "#{action}: #{err}"
        assert_equal recovered(action, path), out
      end
      out, err, status = run.call("--show-config")

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: Input/output error - planted\n", err
    end
  end

  def test_recovery_actions_do_not_hide_a_defect
    defect = <<~RUBY
      require "rich_ri"
      RichRI::ConfigurationFile.prepend(Module.new { def read = raise(NoMethodError, "planted defect") })
    RUBY
    with_config({ "width" => 44 }) do |path|
      out, err, status = with_planted(defect) { |env| cli("--config", path, "--help", docs: false, env: env) }

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: planted defect\n", err
    end
  end

  def test_config_path_reports_a_refused_file_selection
    out, err, status = cli("--config-path", docs: false, env: { "RICH_RI_CONFIG" => "/tmp/a\e[31mb.yml" })

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_equal "rich-ri: RICH_RI_CONFIG must be a nonempty string without control characters\n", err
  end
end
