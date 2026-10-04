# frozen_string_literal: true

require "test_helper"

class ConfigurationCLITest < Minitest::Test
  def with_config(data)
    Dir.mktmpdir("rich-ri-config-cli-") do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, data.is_a?(String) ? data : Psych.dump(data))
      yield path
    end
  end

  def test_custom_theme_reaches_ruby_rendering_without_changing_plain_text
    with_config({ "color" => "always", "styles" => { "method" => "red:bold" } }) do |path|
      colored, err, status = cli("--config", path, "RichRIExample#map")

      assert_predicate status, :success?, err
      assert_includes colored, "\e[31;1mmap\e[0m"
      plain, err, status = cli("--config", path, "--no-color", "RichRIExample#map")

      assert_predicate status, :success?, err
      assert_equal plain, RichRI.plain(colored)
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
      assert_includes err, "Invalid configuration"
      refute_match(/from .*\.rb:\d+/, err)
      _out, err, status = cli("--config", path, "--no-config", "--show-config", docs: false)

      assert_predicate status, :success?, err
    end
  end

  def test_help_and_version_work_with_unreadable_file
    with_config({ "theme" => "dark" }) do |path|
      File.chmod(0o000, path)
      next if File.readable?(path)

      ["--help", "--version"].each do |action|
        out, err, status = cli("--config", path, action, docs: false)

        assert_predicate status, :success?, err
        refute_empty out
      end
    end
  end

  def test_show_config_is_roundtrippable_and_has_no_lookup_or_pager_side_effects
    data = { "theme" => "light", "styles" => { "heading" => "blue:bold" }, "pager" => "command-that-must-not-run" }
    with_config(data) do |path|
      output, err, status = cli("--config", path, "--show-config", docs: false)

      assert_predicate status, :success?, err
      effective = Psych.safe_load(output)

      assert_equal RichRI::Configuration::KEYS.sort, effective.keys.sort
      assert_equal "light", effective.fetch("theme")
      assert_equal data.fetch("pager"), effective.fetch("pager")
      File.write(path, output)
      repeated, err, status = cli("--config", path, "--show-config", docs: false)

      assert_predicate status, :success?, err
      assert_equal output, repeated
    end
  end

  def test_explicit_themes_and_color_depth_reach_help_and_errors_are_controlled
    out, err, status = cli("--no-config", "--theme=light", "--color-depth=truecolor", "--color", "--help", docs: false)

    assert_predicate status, :success?, err
    assert_includes out, "\e[38;2;"
    ["--theme=missing", "--style=unknown=red", "--style=method=999", "--color-depth=bad",
     "--bat-theme=", "--shell-theme=", "--pager-command="].each do |option|
      _out, err, status = cli("--no-config", option, "--show-config", docs: false)

      assert_equal 1, status.exitstatus
      refute_match(/from .*\.rb:\d+/, err)
    end
  end

  def test_config_path_never_emits_terminal_controls
    output, err, status = cli("--config=/tmp/\e]52;c;AAAA\a", "--config-path", docs: false)

    assert_equal 1, status.exitstatus
    assert_empty output
    refute_includes err, "\e"
    assert_includes err, "Configuration path"
  end

  def test_rich_pager_environment_is_restored_after_lookup
    with_environment(TestSupport::ENVIRONMENT.merge("RI_PAGER" => "original", "LESS" => "-i")) do
      _out, err = capture_io do
        assert_equal 0, RichRI::CLI.run(["--no-config", "--no-standard-docs", "--list", "--pager-command=cat"])
      end

      assert_empty err
      assert_equal "original", ENV.fetch("RI_PAGER")
      assert_equal "-i", ENV.fetch("LESS")
    end
  end
end
