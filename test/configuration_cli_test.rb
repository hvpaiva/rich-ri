# frozen_string_literal: true

require "test_helper"
require "command_helper"

class ConfigurationCLITest < Minitest::Test
  include CommandSupport

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

  def test_config_selectors_require_the_full_option_name
    with_config({ "width" => 44 }) do |path|
      [["--confi", path], ["--confi=#{path}"], ["--no-conf"]].each do |selector|
        out, err, status = cli(*selector, "--show-config", docs: false, env: { "RICH_RI_CONFIG" => path })

        assert_equal 2, status.exitstatus
        assert_empty out
        assert_includes err, "invalid option: #{selector.first.split('=', 2).first}"
      end
      [["--config", path], ["--config=#{path}"]].each do |selector|
        out, err, status = cli(*selector, "--show-config", docs: false)

        assert_predicate status, :success?, err
        assert_equal 44, Psych.safe_load(out).fetch("width")
      end
      out, err, status = cli("--no-config", "--show-config", docs: false, env: { "RICH_RI_CONFIG" => path })

      assert_predicate status, :success?, err
      refute_equal 44, Psych.safe_load(out).fetch("width")
    end
  end

  def test_empty_file_means_no_overrides
    defaults, err, status = cli("--no-config", "--show-config", docs: false)

    assert_predicate status, :success?, err
    ["", "\n", "# nothing yet\n", "---\n", "--- ~\n"].each do |content|
      with_config(content) do |path|
        out, err, status = cli("--show-config", docs: false, env: { "RICH_RI_CONFIG" => path })

        assert_predicate status, :success?, "#{content.inspect}: #{err}"
        assert_equal defaults, out
        out, err, status = cli("RichRIExample#map", env: { "RICH_RI_CONFIG" => path })

        assert_predicate status, :success?, "#{content.inspect}: #{err}"
        assert_includes out, "Return transformed values."
      end
    end
  end

  def test_ri_cannot_select_the_configuration_file
    with_config({ "width" => 44 }) do |path|
      { "--no-config" => "--no-config", "--config=#{path}" => "--config", "--config #{path}" => "--config",
        "--width=50 --no-config --list" => "--no-config" }.each do |defaults, option|
        out, err, status = cli("--show-config", docs: false, env: { "RI" => defaults, "RICH_RI_CONFIG" => path })

        assert_equal 1, status.exitstatus, defaults
        assert_empty out
        assert_equal "rich-ri: RI: #{option} cannot be set in RI; choose the configuration file with " \
                     "RICH_RI_CONFIG or on the command line\n", err
      end
    end
  end

  def test_help_works_while_ri_names_a_configuration_file
    out, err, status = cli("--help", docs: false, env: { "RI" => "--no-config" })

    assert_predicate status, :success?, err
    assert_includes out, "Usage: rich-ri"
  end

  def test_a_file_selector_that_is_the_value_of_another_option_in_ri_selects_nothing
    with_config({ "width" => 44 }) do |path|
      environment = { "RI" => "--pager-command --no-config", "RICH_RI_CONFIG" => path }
      out, err, status = cli("--show-config", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_equal 44, Psych.safe_load(out).fetch("width")
      assert_equal "--no-config", Psych.safe_load(out).fetch("pager")
    end
  end

  def test_options_are_read_after_names_whatever_the_environment_says
    with_config("theme: [broken") do |path|
      environment = { "POSIXLY_CORRECT" => "1", "RICH_RI_CONFIG" => path }
      out, err, status = cli("RichRIExample#map", "--no-config", "--color=always", env: environment)

      assert_predicate status, :success?, err
      assert_includes out, "\e["
      assert_includes RichRI.plain(out), "Return transformed values."
    end
  end

  def test_double_dash_ends_the_options_whatever_the_environment_says
    out, err, status = cli("RichRIExample#map", "--", "--no-config", env: { "POSIXLY_CORRECT" => "1" })

    assert_equal 1, status.exitstatus
    assert_includes out, "Return transformed values."
    assert_equal "rich-ri: Nothing known about --no-config\n", err
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

  def test_show_config_prints_terminal_controls_in_values_as_yaml_escapes
    Dir.mktmpdir("rich-ri-config-") do |dir|
      # Not U+202A to U+202E: on macOS, Ruby drops them from the paths it expands.
      names = ["reversed\u2067text", "quoted\"\u2066isolate", "bell\a\e[31m", "plain"]
      directories = names.map { |name| File.join(dir, name).tap { |path| Dir.mkdir(path) } }
      sources = directories.flat_map { |directory| ["--doc-dir", directory] }
      out, err, status = cli("--no-config", *sources, "--show-config", docs: false)

      assert_predicate status, :success?, err
      refute_match(RichRI::CONTROL, out)
      assert_includes out, "reversed\\u2067text"
      assert_includes out, "quoted\\\"\\u2066isolate"
      assert_equal directories, Psych.safe_load(out).fetch("doc_dirs")
    end
  end

  def test_show_config_refuses_to_print_anything_but_plain_data
    defect = <<~RUBY
      require "rich_ri"
      RichRI::Options.prepend(Module.new { def settings = super.merge("pager" => Object.new) })
    RUBY
    out, err, status = with_planted(defect) { |env| cli("--no-config", "--show-config", docs: false, env: env) }

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_includes err, "rich-ri: Tried to dump unspecified class: Object"
  end

  TEXT = "must be a nonempty string without control characters"
  ROLES = RichRI::Theme::ROLES.join(", ")
  COLORS = "use an ANSI name, 0..255, #RRGGBB or default"
  REFUSED_VALUES = {
    "--theme=missing" => '--theme must be one of terminal, dark, light, not "missing"',
    "--style=unknown=red" => %(--style: style "unknown": unknown style role "unknown"; choose #{ROLES}),
    "--style=method=999" => %(--style: style "method": invalid color "999"; #{COLORS}),
    "--color-depth=bad" => '--color-depth must be one of auto, basic, 256, truecolor, not "bad"',
    "--bat-theme=" => "--bat-theme #{TEXT}", "--shell-theme=" => "--shell-theme #{TEXT}",
    "--pager-command=" => "--pager-command #{TEXT}"
  }.freeze

  def test_explicit_themes_and_color_depth_reach_help_and_errors_are_controlled
    out, err, status = cli("--no-config", "--theme=light", "--color-depth=truecolor", "--color", "--help", docs: false)

    assert_predicate status, :success?, err
    assert_includes out, "\e[38;2;"
    REFUSED_VALUES.each do |option, message|
      out, err, status = cli("--no-config", option, "--show-config", docs: false)

      assert_equal 2, status.exitstatus, option
      assert_empty out
      assert_equal "rich-ri: #{message}\nRun rich-ri --help for usage.\n", err
    end
  end

  def test_config_path_never_emits_terminal_controls
    output, err, status = cli("--config=/tmp/\e]52;c;AAAA\a", "--config-path", docs: false)

    assert_equal 2, status.exitstatus
    assert_empty output
    refute_includes err, "\e"
    assert_includes err, "--config must be a nonempty string without control characters"
  end
end
