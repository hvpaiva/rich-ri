# frozen_string_literal: true

require "test_helper"

class DocumentStructureTest < Minitest::Test
  def render(source, color: true, width: 48)
    formatter = RichRI::Formatter.new(color: color)
    formatter.width = width
    RDoc::Markup.parse(source).accept(formatter)
  end

  def test_heading_levels_and_rules_remain_searchable_with_and_without_color
    source = "= Title\n\n== Section\n\n=== Topic\n\n==== Detail\n\n===== Note\n\n====== Aside\n\n---\n"
    plain = render(source, color: false)
    colored = render(source)

    assert_equal plain, RichRI.plain(colored)
    assert_equal source.lines.grep(/^=+ /), plain.lines.grep(/^=+ /)
    assert_equal ["=== Topic\n"], plain.lines.grep(/^=== /)
    assert_equal ["#{'-' * 48}\n"], plain.lines.grep(/^---/)
    refute_includes plain, "─"
    assert_includes colored, "\e[1;36m=\e[0m \e[1;36mTitle\e[0m"
    assert_includes colored, "\e[1;34m==\e[0m \e[1;34mSection\e[0m"
    assert_includes colored, "\e[1;35m===\e[0m \e[1;35mTopic\e[0m"
    assert_includes colored, "\e[90m#{'-' * 48}\e[0m"
  end

  def test_heading_markers_fit_within_the_page_width_without_repeating_on_wrap
    source = "==== A long heading with 世界 and more words to wrap\n"
    colored = render(source, width: 24)
    plain = render(source, color: false, width: 24)

    assert_equal plain, RichRI.plain(colored)
    assert_equal 1, plain.lines.grep(/^==== /).length
    assert_operator plain.lines.length, :>, 1
    assert_equal source.split, plain.split
    colored.lines.each { |line| assert_operator RichRI.width(line.chomp), :<=, 24 }
  end
end
