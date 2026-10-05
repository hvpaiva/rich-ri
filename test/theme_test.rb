# frozen_string_literal: true

require "test_helper"
require "rich_ri/theme"

class ThemeTest < Minitest::Test
  def test_terminal_palette_preserves_all_existing_styles_at_every_depth
    RichRI::Theme::DEPTHS.each do |depth|
      theme = RichRI::Theme.new(depth:)
      RichRI::COLORS.each do |role, sgr|
        assert_equal sgr, theme.sgr(role)
        assert_equal "\e[#{sgr}mword\e[0m", theme.paint("word", role)
      end
    end
  end

  def test_color_depth_detection_has_explicit_and_portable_fallbacks
    { {} => "basic", { "TERM" => "xterm-256color" } => "256",
      { "COLORTERM" => "truecolor", "TERM" => "xterm-256color" } => "truecolor",
      { "COLORTERM" => "24BIT" } => "truecolor", { "TERM" => "dumb" } => "basic" }.each do |env, depth|
      assert_equal depth, RichRI::Theme.new(env:).depth
    end
    assert_equal "basic", RichRI::Theme.new(depth: "basic", env: { "COLORTERM" => "truecolor" }).depth
  end

  def test_presets_cover_semantic_roles_without_imposing_background_colors
    %w[dark light].each do |name|
      theme = RichRI::Theme.new(name:, depth: "truecolor")

      assert_equal name, theme.name
      assert_match(/38;2;/, theme.sgr(:comment))
      refute_equal RichRI::COLORS.fetch(:comment), theme.sgr(:comment)
      RichRI::Theme::ROLES.each { |role| refute_match(/(?:\A|;)48;/, theme.sgr(role)) }
    end
  end

  def test_presets_keep_the_terminal_palette_at_basic_depth
    terminal = RichRI::Theme.new(depth: "basic")
    %w[dark light].each do |name|
      theme = RichRI::Theme.new(name:, depth: "basic")

      RichRI::Theme::ROLES.each { |role| assert_equal terminal.sgr(role), theme.sgr(role), "#{name} #{role}" }
    end
  end

  def test_overrides_replace_whole_role_and_none_preserves_other_roles
    theme = RichRI::Theme.new(name: "dark", styles: { title: "red", comment: "none" })

    assert_equal "31", theme.sgr(:title)
    assert_empty theme.sgr(:comment)
    assert_equal "comment text", theme.paint("comment text", :comment)
    assert_equal "\e[1mtext\e[0m", theme.paint("text", :comment, :bold)
    refute_empty theme.sgr(:method)
  end

  def test_paint_preserves_all_whitespace_and_resets_each_word
    theme = RichRI::Theme.new(styles: { code: "fg=#123456:bg=#abcdef:bold" }, depth: "truecolor")
    source = "  hello\t世界\n\nnext line  "
    output = theme.paint(source, :code)

    assert_equal source, RichRI.plain(output)
    assert_equal 4, output.scan(RichRI::RESET).length
    assert_includes output, "\e[38;2;18;52;86;48;2;171;205;239;1m世界\e[0m"
    assert_equal source, theme.paint(source, :code, enabled: false)
    assert_equal source, theme.paint(source)
  end

  def test_theme_instances_never_mutate_input_or_each_other
    styles = { "method" => +"red" }
    custom = RichRI::Theme.new(styles:)
    styles["method"].replace("green")
    styles["comment"] = "none"

    assert_equal "31", custom.sgr(:method)
    assert_equal "90", custom.sgr(:comment)
    assert_equal "36", RichRI::Theme.new.sgr(:method)
    assert_predicate custom, :frozen?
    assert_raises(FrozenError) { custom.sgr(:method).replace("35") }
  end

  def test_unknown_names_depths_roles_and_duplicate_roles_are_rejected
    [{ name: "missing" }, { depth: "16million" }, { styles: [] },
     { styles: { unknown: "red" } }, { styles: { 1 => "red" } },
     { styles: { "code" => "red", code: "blue" } }].each do |options|
      error = assert_raises(ArgumentError) { RichRI::Theme.new(**options) }

      refute_empty error.message
    end
    assert_raises(ArgumentError) { RichRI::Theme.new.sgr(:missing) }
  end
end

class StyleTest < Minitest::Test
  def test_named_ansi_colors_remain_terminal_palette_entries_at_all_depths
    depths = %w[basic 256 truecolor]
    RichRI::Color::NAMES.each_with_index do |name, index|
      depths.each do |depth|
        assert_equal (30 + index).to_s, RichRI::Style.new(name).sgr(depth)
        assert_equal (90 + index).to_s, RichRI::Style.new("bright_#{name}").sgr(depth)
        assert_equal (40 + index).to_s, RichRI::Style.new("bg=#{name}").sgr(depth)
        assert_equal (100 + index).to_s, RichRI::Style.new("bg=bright_#{name}").sgr(depth)
      end
    end
  end

  def test_attributes_and_default_foreground_background_are_supported
    style = RichRI::Style.new("fg=default:bg=default:bold:dim:italic:underline:reverse:strike")

    assert_equal "39;49;1;2;3;4;7;9", style.sgr("truecolor")
    assert_empty RichRI::Style.new("none").sgr("basic")
  end

  def test_rgb_and_indexed_colors_downgrade_by_nearest_palette_color
    assert_equal "38;2;255;0;0", RichRI::Style.new("#FF0000").sgr("truecolor")
    assert_equal "38;5;9", RichRI::Style.new("#ff0000").sgr("256")
    assert_equal "91", RichRI::Style.new("#ff0000").sgr("basic")
    assert_equal "48;5;46", RichRI::Style.new("bg=46").sgr("truecolor")
    assert_equal "102", RichRI::Style.new("bg=46").sgr("basic")
    assert_equal "38;5;0", RichRI::Style.new("0").sgr("256")
    assert_equal "38;5;255", RichRI::Style.new("255").sgr("256")
  end

  def test_invalid_ambiguous_and_unsafe_styles_are_rejected_with_role_context
    ["", "wat", "256", "-1", "01", "#fff", "#GGFFFF", "fg=", "background=red",
     "red:blue", "red:fg=blue", "bold:bold", "none:bold", "red:", ":red",
     "bg=red:bg=blue", "red\e[0m", "red\u202e", "red\n", 31, nil].each do |style|
      error = assert_raises(ArgumentError) { RichRI::Theme.new(styles: { code: style }) }

      assert_includes error.message, "style :code:"
    end
  end
end

class ThemeIntegrationTest < Minitest::Test
  def test_ruby_syntax_and_formatter_share_the_selected_semantic_palette
    theme = RichRI::Theme.new(styles: { title: "red", method: "green", comment: "none", code: "blue" })
    formatter = RichRI::Formatter.new(theme:)
    source = "= Title\n\nUse +code+.\n\n  obj.match?('x') # comment\n"
    output = RDoc::Markup.parse(source).accept(formatter)
    plain = RDoc::Markup.parse(source).accept(RichRI::Formatter.new(color: false))

    assert_equal plain, RichRI.plain(output)
    assert_includes output, "\e[31mTitle\e[0m"
    assert_includes output, "\e[31m=\e[0m"
    assert_includes output, "\e[34mcode\e[0m"
    assert_includes output, "\e[32mmatch?\e[0m"
    assert_includes output, "# comment"
    refute_includes output, "\e[90m"
  end

  def test_bat_and_shell_theme_arguments_and_prompt_styling_are_independent
    Dir.mktmpdir do |directory|
      bat = File.join(directory, "bat")
      File.write(bat, "#!#{RbConfig.ruby}\n" + <<~'RUBY')
        theme = ARGV.find { |arg| arg.start_with?("--theme=") }
        code = theme == "--theme=custom shell" ? "32" : "35"
        source = STDIN.read
        print "\e[#{code}m", source.delete_suffix("\n"), "\e[0m"
        print "\n" if source.end_with?("\n")
      RUBY
      File.chmod(0o755, bat)
      with_environment("PATH" => directory) do
        theme = RichRI::Theme.new(styles: { code: "red" })
        highlighter = RichRI::Highlighter.new(true, theme:, bat_theme: "custom code", shell_theme: "custom shell")
        session = highlighter.highlight("$ echo hi\nhi\n")
        json = highlighter.highlight('{"number":42}', :json)

        assert_includes session, "\e[31m$\e[0m"
        assert_includes session, "\e[32mecho hi"
        assert_equal "$ echo hi\nhi\n", RichRI.plain(session)
        assert_includes json, "\e[35m"
        assert_equal '{"number":42}', RichRI.plain(json)
        assert_includes highlighter.highlight("echo hi", :bash), "\e[32mecho hi"
      end
    end
  end

  def test_manual_uses_theme_unless_the_user_has_pager_preferences
    keys = RichRI::Manual::PAGER_SETTINGS + ENV.keys.grep(/^LESS_TERMCAP_/)
    with_environment(keys.to_h { |key| [key, nil] }) do
      theme = RichRI::Theme.new(styles: { heading: "red", link: "green:underline" })
      palette = RichRI::Manual.new.send(:pager_environment, color: true, theme:)

      assert_equal "\e[31m", palette.fetch("LESS_TERMCAP_md")
      assert_equal "\e[32;4m", palette.fetch("LESS_TERMCAP_us")
      assert_empty RichRI::Manual.new.send(:pager_environment, color: false, theme:)
      with_environment("PAGER" => "custom") do
        assert_empty RichRI::Manual.new.send(:pager_environment, color: true, theme:)
      end
    end
  end
end
