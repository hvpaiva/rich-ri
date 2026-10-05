# frozen_string_literal: true

require "test_helper"

class ConfigurationRecoveryTest < Minitest::Test
  def test_invalid_ri_abbreviations_fail_lookup_but_allow_recovery_actions
    environment = { "RI" => "--wid=44" }
    out, err, status = cli("--show-config", docs: false, env: environment)

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_includes err, "invalid option: --wid"
    refute_includes err, "--help"
    %w[--help --version --config-path --completion=bash].each do |action|
      out, err, status = cli(action, docs: false, env: environment)

      assert_predicate status, :success?, err
      refute_empty out
    end
    # The command line is read first, so its own mistake is the one reported.
    _out, err, status = cli("--vers", docs: false, env: environment)

    assert_equal 2, status.exitstatus
    assert_includes err, "invalid option: --vers"
  end

  def test_recovery_actions_are_recognized_as_the_parser_reads_them
    with_config("theme: [broken") do |path|
      environment = { "RICH_RI_CONFIG" => path }
      [%w[-ah], %w[-Tv], %w[--width 44 --help], %w[RichRIExample -h]].each do |args|
        out, err, status = cli(*args, docs: false, env: environment)

        assert_predicate status, :success?, "#{args.inspect}: #{err}"
        refute_empty out
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
        refute_empty out
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
        refute_empty out
      end
    end
  end

  def test_recovery_actions_survive_any_failure_to_read_the_configuration
    source = <<~RUBY
      require "rich_ri"
      RichRI::ConfigurationFile.prepend(Module.new { def read = raise(NoMethodError, "planted defect") })
      exit RichRI::CLI.run(ARGV)
    RUBY
    with_config({ "width" => 44 }) do |path|
      run = lambda do |*args|
        Open3.capture3(TestSupport::ENVIRONMENT, RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", "-e", source,
                       "--", "--config", path, *args)
      end
      ["--help", "--version", "--config-path", "--completion=bash"].each do |action|
        out, err, status = run.call(action)

        assert_predicate status, :success?, "#{action}: #{err}"
        refute_empty out
      end
      out, err, status = run.call("--show-config")

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: planted defect\n", err
    end
  end
end
