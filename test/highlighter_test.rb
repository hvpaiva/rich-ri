# frozen_string_literal: true

require "test_helper"

class HighlighterTest < Minitest::Test
  def fake_bat(body, &)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bat")
      File.write(path, "#!#{RbConfig.ruby}\n#{body}\n")
      FileUtils.chmod(0o755, path)
      with_environment("PATH" => dir, &)
    end
  end

  def test_missing_bat_and_failure_leave_text_readable
    input = "{\"answer\":42}\n\n"

    with_environment("PATH" => "") do
      assert_equal input, RichRI::Highlighter.new(true).highlight(input, :json)
    end
    fake_bat("exit 1") do
      assert_equal input, RichRI::Highlighter.new(true).highlight(input, :json)
    end
  end

  def test_bat_cannot_change_content_or_inject_terminal_sequences
    input = "echo hello\n"
    ["puts 'changed'", 'print "\e]52;c;AAAA\a"; print STDIN.read'].each do |body|
      fake_bat(body) do
        assert_equal input, RichRI::Highlighter.new(true).highlight(input, :bash)
      end
    end
  end

  def test_bat_ansi_output_preserves_trailing_newlines
    fake_bat('print "\e[32m", STDIN.read, "\e[0m"') do
      ["echo hello", "echo hello\n", "echo hello\n\n"].each do |input|
        output = RichRI::Highlighter.new(true).highlight(input, :bash)

        assert_includes output, "\e[32m"
        assert_equal input, RichRI.plain(output)
      end
    end
  end

  def test_examples_never_execute
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "executed")
      fake_bat("print STDIN.read") do
        highlighter = RichRI::Highlighter.new(true)
        highlighter.highlight("$ touch #{marker}\n")
        highlighter.highlight("File.write(#{marker.inspect}, 'bad')", :ruby)
      end

      refute_path_exists marker
    end
  end

  def test_terminal_controls_are_visible_in_colored_and_plain_output
    source = "puts \"\e]52;c;AAAA\a\"\rhidden\u202e\n"
    [true, false].each do |color|
      output = RichRI::Highlighter.new(color).highlight(source, :ruby)
      plain = RichRI.plain(output)

      refute_match(/[\e\a\r\u202e]/, plain)
      assert_includes plain, "\\u001b"
      assert_includes plain, "\\u202e"
    end
  end

  def test_real_bat_shell_colors_preserve_the_transcript
    _out, status = Open3.capture2("bat", "--version", err: File::NULL)
    skip "bat is unavailable" unless status.success?
    source = "$ echo \"hello\" | cat\nhello\n"
    output = RichRI::Highlighter.new(true).highlight(source)

    assert_equal source, RichRI.plain(output)
    assert_includes output.lines.first, "\e[32m"
    assert_equal "hello\n", output.lines.last
  rescue Errno::ENOENT
    skip "bat is unavailable; CI exercises real bat"
  end
end
