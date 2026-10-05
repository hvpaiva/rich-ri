# frozen_string_literal: true

require "test_helper"

class ErrorMessagesTest < Minitest::Test
  def with_config(data)
    Dir.mktmpdir("rich-ri-messages-") do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, data.is_a?(String) ? data : Psych.dump(data))
      yield path
    end
  end

  def test_refused_option_values_say_why_in_every_spelling
    directory = '--doc-dir must be a directory, not "/no/such/directory"'
    width = '--width must be an integer from 20 to 10000, not "19"'
    { %w[--doc-dir=/no/such/directory] => directory, %w[--doc-dir /no/such/directory] => directory,
      %w[-d /no/such/directory] => directory, %w[--width=19] => width, %w[--width 19] => width, %w[-w 19] => width,
      %w[--bat-theme=] => "--bat-theme must be a nonempty string without control characters",
      %w[--pager-command=] => "--pager-command must be a nonempty string without control characters",
      %w[--style=method=wat] => 'style "method": invalid color "wat"' }.each do |args, message|
      out, err, status = cli("--no-config", *args, "--show-config", docs: false)

      assert_equal 2, status.exitstatus, args.inspect
      assert_empty out
      assert_includes err.lines.first, "rich-ri: #{message}"
      assert_equal "Run rich-ri --help for usage.\n", err.lines.last
    end
  end

  def test_listed_values_must_be_written_in_full
    { %w[--theme=] => "--theme must be one of terminal, dark, light", %w[--theme=d] => "--theme must be one of",
      %w[--color=] => "--color must be one of auto, always, never", %w[--color=n] => "--color must be one of",
      %w[--color-depth=true] => "--color-depth must be one of auto, basic, 256, truecolor",
      %w[--completion=ba] => "--completion must be one of bash, zsh, fish",
      %w[-f m] => "--format must be one of ansi, bs, markdown, rdoc" }.each do |args, message|
      out, err, status = cli("--no-config", *args, "--show-config", docs: false)

      assert_equal 2, status.exitstatus, args.inspect
      assert_empty out
      assert_includes err.lines.first, "rich-ri: #{message}"
      assert_includes err.lines.first, ", not #{args.last.split('=', 2).last.inspect}"
      refute_includes err, "ambiguous"
    end
  end

  def test_configuration_failures_name_the_file
    { { "doc_dirs" => ["missing"] } => "doc_dirs must list directories, not ",
      { "width" => 19 } => "width must be an integer from 20 to 10000",
      { "sources" => { "gems" => "yes" } } => "sources.gems must be true or false",
      { "styles" => { "method" => "wat" } } => 'style "method": invalid color "wat"',
      "theme: [broken" => "invalid YAML at line 1 column 8: did not find expected",
      "styles: &s {method: red}\nsources: *s" => "YAML aliases are not accepted",
      "theme: dark\ntheme: light" => 'duplicate key "theme"' }.each do |data, message|
      with_config(data) do |path|
        out, err, status = cli("--config", path, "--show-config", docs: false)

        assert_equal 1, status.exitstatus, data.inspect
        assert_empty out
        assert_operator err, :start_with?, "rich-ri: #{path}: #{message}"
        refute_includes err, "--help"
      end
    end
  end

  def test_environment_failures_name_the_variable
    { { "RICH_RI_WIDTH" => "abc" } => "RICH_RI_WIDTH must be an integer from 20 to 10000\n",
      { "RICH_RI_THEME" => "d" } => "RICH_RI_THEME must be one of terminal, dark, light\n",
      { "RICH_RI_STYLE_METHOD" => "wat" } => 'RICH_RI_STYLE_METHOD: style "method": invalid color "wat"',
      { "BAT_THEME" => "bad\tname" } => "BAT_THEME must be a nonempty string without control characters\n",
      { "RICH_RI_CONFIG" => "/tmp/\e]52;c;AAAA\a" } =>
        "RICH_RI_CONFIG must be a nonempty string without control characters\n",
      { "RI" => "--bogus" } => "RI: invalid option: --bogus\n",
      { "RI" => "--width=abc" } => "RI: --width must be an integer from 20 to 10000, not \"abc\"\n",
      { "RI" => "--doc-dir '/unclosed" } => "RI: unmatched quote\n" }.each do |env, message|
      out, err, status = cli("--show-config", docs: false, env: env)

      assert_equal 1, status.exitstatus, env.inspect
      assert_empty out
      assert_operator err, :start_with?, "rich-ri: #{message}"
      refute_includes err, "--help"
    end
  end
end
