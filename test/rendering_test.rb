# frozen_string_literal: true

require "test_helper"

class RenderingTest < Minitest::Test
  class RecordingHighlighter < RichRI::Highlighter
    attr_reader :shell_inputs

    def initialize(enabled: true)
      super(enabled)
      @shell_inputs = []
    end

    def other_language(text, format, **_options)
      @shell_inputs << [text, format]
      RichRI.paint(text, :string)
    end
  end

  def render(source, color: true, width: 48)
    formatter = RichRI::Formatter.new(color: color, classes: { "Array" => true })
    formatter.width = width
    RDoc::Markup.parse(source).accept(formatter)
  end

  def test_ruby_highlighting_preserves_unicode_heredocs_and_incomplete_code
    examples = [
      "names = [:ana, 'ação', 2]\nnames.map { |x| x.to_s } # => output\n",
      "message = <<~TEXT\n  olá 世界\nTEXT\nputs message\n",
      "a, b = <<~FIRST, <<~SECOND\n  a\nFIRST\n  b\nSECOND\n",
      "x = /a\#{b}+/i\ny = %w[one two]\n",
      "def incomplete(x)\n  x +\n",
      "# comment\nx = 1\n__END__\nraw data\n"
    ]
    examples.each do |source|
      output = RichRI::Highlighter.new(true).highlight(source, :ruby)

      assert_equal source, RichRI.plain(output)
      assert_includes output, "\e["
    end
  end

  def test_explicit_plaintext_and_unmarked_prose_are_not_ruby
    highlighter = RichRI::Highlighter.new(true)

    assert_equal 'puts "hello"', highlighter.highlight('puts "hello"', :text)
    assert_equal "a documentation paragraph", highlighter.highlight("a documentation paragraph")
    assert_equal "if true\n", highlighter.highlight("if true\n")
    assert_includes highlighter.highlight("if true\n", :ruby), "\e[35m"
  end

  def test_no_color_preserves_the_same_layout_including_lists_and_tables
    source = <<~RDOC
      = Title

      A paragraph with +self+, *bold*, _emphasis_, and Array#map.

      * A list entry with +inline code+ and enough words to wrap across lines.
        * A nested entry.

      name:: Description with a {link}[https://example.org/docs].

        values = [:one, 2, 'ação']

      | First | Second |
      |-------|--------|
      | Value | +code+ |
    RDOC
    colored = render(source)
    plain = render(source, color: false)

    refute_includes plain, "\e"
    assert_equal plain, RichRI.plain(colored)
    assert_includes colored, "\e[36mArray#map"
    assert_includes plain, "https://example.org/docs"
  end

  def test_wrapping_respects_visible_width_with_long_links_and_wide_characters
    source = "A <b>long bold phrase that spans multiple lines</b> with +#{'abc' * 30}+ and 世界."
    colored = render(source, width: 24)

    assert_equal render(source, color: false, width: 24), RichRI.plain(colored)
    colored.lines.each { |line| assert_operator RichRI.width(line.chomp), :<=, 24 }
    assert_equal source.gsub(%r{</?b>|[+\s]}, ""), RichRI.plain(colored).gsub(/\s/, "")
    assert(colored.lines.all? { |line| line.end_with?("\e[0m\n") })
  end

  def test_markdown_raw_controls_are_escaped_through_the_executable
    Dir.mktmpdir("rich-ri-markdown-") do |dir|
      source = File.join(dir, "example.rb")
      store = File.join(dir, "ri")
      controls = "\e]52;c;AAAA\a\rhidden\u202e"
      File.write(source, "# :markup: markdown\n# <div>#{controls}</div>\nclass RichRIControls\nend\n")
      RDoc::RDoc.new.document(["--ri", "--quiet", "--op", store, source])
      %w[always never].each do |mode|
        out, err, status = cli("--no-standard-docs", "--doc-dir", store, "--color=#{mode}",
                               "RichRIControls", docs: false)

        assert_predicate status, :success?, err
        refute_match(/[\e\a\r\u202e]/, RichRI.plain(out))
        assert_includes out, "<div>\\u001b]52;c;AAAA\\u0007\\u000dhidden\\u202e</div>"
      end
    end
  end

  def test_inline_controls_are_escaped_in_headings_lists_tables_and_links
    controls = "\e]8;;https://example.org\a\u009b\u202e"
    source = "= #{controls}\n\n#{controls}:: Value\n\n{#{controls}}[https://example.org/#{controls}]\n"
    table = RDoc::Markup::Table.new([controls], [:left], [[controls]])
    [true, false].each do |color|
      output = render(source, color: color)
      output << RDoc::Markup::Document.new(table).accept(RichRI::Formatter.new(color: color))

      refute_match(/[\e\a\u009b\u202e]/, RichRI.plain(output))
      assert_includes output, "\\u001b"
    end
  end

  def test_shell_transcripts_distinguish_commands_from_output
    source = <<~'SESSION'
      $ echo "Open the pod bay doors, Hal." | ruby t.rb
      ["ARGV", []]
      ["ARGF.read", "Open the pod bay doors, Hal.\n"]

      $ cat foo.txt
      Foo 0
      Foo 1
      $ ruby t.rb --xyzzy --mojo foo.txt bar.txt
      ["ARGV", ["--xyzzy", "--mojo", "foo.txt", "bar.txt"]]
    SESSION
    highlighter = RecordingHighlighter.new
    output = highlighter.highlight(source)

    assert_equal source, RichRI.plain(output)
    assert_equal [
      ["echo \"Open the pod bay doors, Hal.\" | ruby t.rb\n", :bash],
      ["cat foo.txt\n", :bash],
      ["ruby t.rb --xyzzy --mojo foo.txt bar.txt\n", :bash]
    ], highlighter.shell_inputs
    source.lines.zip(output.lines).each do |original, colored|
      if original.start_with?("$ ")
        assert_includes colored, "\e["
      else
        assert_equal original, colored
      end
    end
  end

  def test_shell_recognition_accepts_commands_paths_and_environment_assignments
    commands = [
      "bundle exec rake test", "git log --oneline", "custom-tool --verbose",
      "./bin/task", "../bin/task", "/usr/bin/env ruby t.rb", "~/bin/task",
      'LC_ALL=C FILE="file with spaces" ruby t.rb'
    ]
    commands.each do |command|
      highlighter = RecordingHighlighter.new
      source = "\n  $\t#{command}\r\n  output\r\n"

      assert_equal source, RichRI.plain(highlighter.highlight(source))
      assert_equal [["#{command}\r\n", :bash]], highlighter.shell_inputs
    end
  end

  def test_shell_detection_does_not_steal_ruby_or_plain_text
    examples = [
      ["$stdout.write('hello')\n$LOAD_PATH << './lib'\n", nil],
      ["message = <<~TEXT\n$ echo hello\nTEXT\n", nil],
      ["text = \"\n$ echo hello\n\"\n", nil],
      ["Example output:\n$ echo hello\n", nil],
      ["$ 100.00\n", nil],
      ["$$ ruby example.rb\n", nil],
      ["$ echo hello\n", :text],
      ["$ echo hello\n", :ruby],
      ["$ echo 'unclosed\n", nil],
      ["$ cat <<'TEXT'\n$ echo this is literal text\nTEXT\n", nil],
      ["$ echo hello\nhello\n$ cat <<'TEXT'\n$ echo this is literal text\nTEXT\n", nil]
    ]
    examples.each do |source, format|
      highlighter = RecordingHighlighter.new

      assert_equal source, RichRI.plain(highlighter.highlight(source, format))
      assert_empty highlighter.shell_inputs
    end
  end

  def test_shell_continuation_and_output_with_greater_than_sign
    source = <<~'SESSION'
      $ printf '%s\n' \
      > 'one' \
      > 'two'
      one
      two
      > this is output
    SESSION
    highlighter = RecordingHighlighter.new
    output = highlighter.highlight(source, :console)

    assert_equal source, RichRI.plain(output)
    expected = <<~'BASH'
      printf '%s\n' \
      'one' \
      'two'
    BASH
    assert_equal [[expected, :bash]], highlighter.shell_inputs
    assert_equal source.lines.last(3), output.lines.last(3)
  end

  def test_shell_commands_are_cached_and_no_color_bypasses_highlighting
    highlighter = RecordingHighlighter.new
    highlighter.highlight("$ cat file.txt\none\n")
    highlighter.highlight("$ cat file.txt\ntwo\n")

    assert_equal 1, highlighter.shell_inputs.length
    plain = RecordingHighlighter.new(enabled: false)
    source = "$ echo hello\nhello\n"

    assert_equal source, plain.highlight(source)
    assert_empty plain.shell_inputs
  end
end
