# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def in_config(data = {}, env: {})
    Dir.mktmpdir("rich-ri-config-") do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, data.is_a?(String) ? data : Psych.dump(data))
      values = TestSupport::ENVIRONMENT.merge("RICH_RI_CONFIG" => path, "HOME" => dir).merge(env)
      with_environment(values) { yield path, dir }
    end
  end

  def options(*args, defaults: "")
    RichRI::Options.new.parse(args, defaults: defaults)
  end

  def test_precedence_and_role_merging_are_independent
    data = { "width" => 50, "theme" => "light", "styles" => { "method" => "green", "comment" => "magenta" } }
    in_config(data, env: { "RICH_RI_WIDTH" => "60", "RICH_RI_THEME" => "dark", "RICH_RI_STYLE_METHOD" => "red" }) do
      config = options("--width=70", "--theme=terminal", "--style=method=blue",
                       defaults: "--width=40 --style=string=yellow")

      assert_equal 70, config.settings.fetch("width")
      assert_equal "terminal", config.settings.fetch("theme")
      assert_equal({ "string" => "yellow", "method" => "blue", "comment" => "magenta" },
                   config.settings.fetch("styles"))
      assert_equal 60, options(defaults: "--width=40").settings.fetch("width")
      assert_equal "dark", options.settings.fetch("theme")
      with_environment("RICH_RI_WIDTH" => nil) do
        assert_equal 50, options(defaults: "--width=40").settings.fetch("width")
        assert_equal 40, options("--no-config", defaults: "--width=40").settings.fetch("width")
      end
    end
  end

  def test_sources_and_relative_directories_merge_with_ri_and_cli
    in_config do |path, dir|
      source = File.join(dir, "local, docs")
      FileUtils.mkdir_p(source)
      File.write(path,
                 Psych.dump({ "doc_dirs" => ["local, docs"], "sources" => { "system" => false, "gems" => false } }))
      config = options("--system", "--doc-dir", TestSupport::STORE, defaults: "--no-standard-docs --site")

      assert_equal [source, TestSupport::STORE], config.settings.fetch("doc_dirs")
      assert_equal({ "system" => true, "site" => true, "home" => false, "gems" => false },
                   config.settings.fetch("sources"))
    end
  end

  def test_default_path_uses_only_absolute_xdg_or_user_home
    in_config do |_path, dir|
      [nil, "", "relative"].each do |xdg|
        config = RichRI::Configuration.new([], env: { "HOME" => dir, "XDG_CONFIG_HOME" => xdg }, load: false)

        assert_equal File.join(dir, ".config/rich-ri/config.yml"), config.path
      end
      config = RichRI::Configuration.new([], env: { "HOME" => dir, "XDG_CONFIG_HOME" => "/tmp/xdg" }, load: false)

      assert_equal "/tmp/xdg/rich-ri/config.yml", config.path
      assert_empty RichRI::Configuration.new([], env: { "HOME" => dir }).arguments
    end
  end

  def test_file_selectors_use_last_value_and_respect_option_boundaries
    in_config do |path, _dir|
      assert_nil RichRI::Configuration.new(["--config", path, "--no-config"]).path
      assert_equal path, RichRI::Configuration.new(["--no-config", "--config=#{path}"]).path
      assert_equal path, RichRI::Configuration.new(["--", "--config=/missing"]).path
      assert_equal path, RichRI::Configuration.new(["--pager-command", "--config=/missing"]).path
      assert_raises(RichRI::UsageError) { RichRI::Configuration.new(["--config="]) }
      assert_raises(RichRI::UsageError) do
        RichRI::Configuration.new(["--config=/tmp/\e]52;c;AAAA\a", "--config-path"])
      end
      assert_raises(RichRI::UsageError) { RichRI::Configuration.new(["--config"]) }
      assert_raises(RichRI::ConfigurationError) { RichRI::Configuration.new(["--config=/missing/rich-ri.yml"]) }
    end
  end

  def test_invalid_documents_fail_without_evaluating_yaml
    invalid = ["false", "0", "theme: [dark]", "width: 12", "width: '80'", "pager: 0", "sources: []",
               "sources: {gmes: true}",
               "sources: {gems: 'yes'}", "doc_dirs: docs", "doc_dirs: [false]", "unknown: true", "--- []",
               "styles: {method: 208}", "styles: {unknown: cyan}", "styles: {method: bogus}",
               "theme: dark\ntheme: light", "styles: {method: red, method: blue}",
               "--- !ruby/object:Object {}", "styles: &s {method: red}\nsources: *s", "theme: [", "--- {}\n--- {}",
               "bat_theme: \"bad\\u001bname\"", "#" * (RichRI::ConfigurationFile::MAX_BYTES + 1),
               "styles: #{'[' * 40}#{']' * 40}"]
    invalid.each do |data|
      in_config(data) do
        assert_raises(RichRI::ConfigurationError, "Invalid document accepted: #{data[0, 80]}") do
          RichRI::Configuration.new([])
        end
      end
    end
  end

  def test_environment_values_are_validated_and_empty_values_ignored
    in_config({ "theme" => "light" }, env: { "RICH_RI_THEME" => "" }) do
      assert_equal "light", options.settings.fetch("theme")
      { "RICH_RI_THEME" => "unknown", "RICH_RI_WIDTH" => "3", "RICH_RI_COLOR" => "yes",
        "RICH_RI_STYLE_UNKNOWN" => "red", "RICH_RI_COLOR_DEPTH" => "17" }.each do |key, value|
        with_environment(key => value) do
          assert_raises(RichRI::ConfigurationError) { RichRI::Configuration.new([]) }
        end
      end
    end
  end

  def test_width_from_file_and_environment_has_the_same_bounds_as_the_option
    in_config({ "width" => 10_000 }) { assert_equal 10_000, options.settings.fetch("width") }
    in_config({ "width" => 10_001 }) { assert_raises(RichRI::ConfigurationError) { options } }
    in_config do
      with_environment("RICH_RI_WIDTH" => "10000") { assert_equal 10_000, options.settings.fetch("width") }
      %w[040 0x20 1_0_0 10001 99999999999999999999 19].each do |value|
        with_environment("RICH_RI_WIDTH" => value) do
          error = assert_raises(RichRI::ConfigurationError, value) { options }

          assert_equal "RICH_RI_WIDTH must be an integer from 20 to 10000", error.message
        end
      end
    end
  end

  def test_pager_and_bat_preferences_keep_explicit_overrides
    in_config({ "pager" => "less -R", "bat_theme" => "base16", "shell_theme" => "ansi" },
              env: { "RI_PAGER" => "more", "BAT_THEME" => "Monokai Extended" }) do
      assert_equal "more", options.pager_command
      assert_equal "Monokai Extended", options.bat_theme
      assert_equal "cat", options("--pager-command=cat").pager_command
      refute options("--no-pager").settings.fetch("pager")
      with_environment("RICH_RI_BAT_THEME" => "ansi", "RICH_RI_SHELL_THEME" => "base16") do
        assert_equal "ansi", options.bat_theme
        assert_equal "base16", options.shell_theme
      end
      assert_equal "ansi", options("--bat-theme=ansi").bat_theme
    end
  end

  def test_utility_words_used_as_values_do_not_change_parsing_or_recovery
    in_config do |path, _dir|
      %w[--help --version --config-path --completion=bash].each do |value|
        config = options("--no-config", "--pager-command", value, "--show-config", defaults: "--width=51")

        assert_equal 51, config.settings.fetch("width")
        assert_equal value, config.pager_command
        File.write(path, "theme: [invalid")
        assert_raises(RichRI::ConfigurationError) { options("--pager-command", value, "--show-config") }
      end
    end
  end

  def test_end_of_ri_defaults_does_not_swallow_other_layers
    in_config({ "width" => 50 }, env: { "RICH_RI_THEME" => "light" }) do
      config = options("--width=60", "RichRIExample", defaults: "--no-standard-docs --")

      assert_equal 60, config.settings.fetch("width")
      assert_equal "light", config.settings.fetch("theme")
      assert_equal ["RichRIExample"], config.driver_options.fetch(:names)
      assert_equal 50, options(defaults: "--width=40 --").settings.fetch("width")
    end
  end

  def test_parsing_does_not_mutate_arguments_or_other_instances
    in_config do
      argv = %w[--theme=dark --style=method=red --width=60]
      first = RichRI::Options.new.parse(argv, defaults: "")
      second = options

      assert_equal %w[--theme=dark --style=method=red --width=60], argv
      assert_equal "dark", first.theme.name
      assert_equal "terminal", second.theme.name
      assert_empty second.settings.fetch("styles")
    end
  end
end
