# frozen_string_literal: true

require "test_helper"

class CorpusTest < Minitest::Test
  def test_real_ruby_pages_preserve_content_at_different_widths
    widths = [20, 58, 96]
    modes = [false, true]
    Dir[File.join(__dir__, "fixtures/corpus/*.rdoc")].each do |path|
      document = RDoc::Markup.parse(File.read(path))
      method = File.read(path).lines.first.split("#").last.strip
      widths.each do |width|
        plain, colored = modes.map do |color|
          formatter = RichRI::Formatter.new(color: color)
          formatter.width = width
          document.accept(formatter)
        end

        assert_equal plain, RichRI.plain(colored), "#{File.basename(path)}, width #{width}"
        assert_includes colored, "\e[36m#{method}\e[0m", "Ruby calls should be highlighted in #{path}"
        refute_includes plain, "\e"
      end
      document.parts.grep(RDoc::Markup::Verbatim).each do |block|
        highlighted = RichRI::Highlighter.new(true).highlight(block.text, block.format)

        assert_equal block.text, RichRI.plain(highlighted), path
      end
    end
  end
end
