# frozen_string_literal: true

require "test_helper"

class RubyHighlightingTest < Minitest::Test
  def highlighter(enabled: true)
    RichRI::Highlighter.new(enabled)
  end

  def assert_role(source, fragment, role, format: :ruby)
    output = highlighter.highlight(source, format)

    assert_equal source, RichRI.plain(output), source
    assert_includes output, RichRI.paint(fragment, role), source
  end

  def test_named_calls_with_punctuation_receivers_and_continuations
    [
      ["re.match('food')", "match"], ["re.match?('food')", "match?"],
      ["items.empty?", "empty?"], ["items.map! { it }", "map!"],
      ["obj.foo?('a')", "foo?"], ["obj.save!()", "save!"],
      ["ready?", "ready?"], ["save! value", "save!"],
      ["obj&.ready?", "ready?"], ["Factory::build", "build"],
      ["obj.name = value", "name"], ["obj.name=(value)", "name"],
      ["obj.name += 1", "name"], ["obj.name ||= value", "name"],
      ["obj.\n  # Keep reading.\n  ready?", "ready?"],
      ["obj.ação?", "ação?"], ["obj.結果!", "結果!"]
    ].each { |source, name| assert_role(source, name, :method) }
  end

  def test_definitions_include_setters_keywords_and_operator_methods
    %w[ready? save! value= class if Foo [] []= + - +@ -@ ~ ! % ** == === !=
       =~ !~ <=> << >> & | ^ * /].each do |name|
      parameters = case name
                   when "!", "~", "+@", "-@" then ""
                   when "[]=" then "key, value"
                   else "value"
                   end

      assert_role("def #{name}(#{parameters})\nend\n", name, :method)
      assert_role("def self.#{name}(#{parameters})\nend\n", name, :method)
    end
  end

  def test_explicit_operator_calls_do_not_change_infix_or_indexing_styles
    %w[[] []= + - % ** === <=> << & | ^].each do |name|
      assert_role("obj.#{name}(1)", name, :method)
    end
    %w[+ - * / ** == === != =~ !~ < > <= >= <=> && || & | ^ << >>].each do |operator|
      assert_role("left #{operator} right", operator, :operator)
    end
    ["%", "%=", "+=", "-=", "**=", "&&=", "||="].each do |operator|
      assert_role("value #{operator} 2", operator, :operator)
    end
    output = highlighter.highlight("items = [1]\nitems[0]", :ruby)

    assert_includes output, "[#{RichRI.paint('0', :number)}]"
    refute_includes output, RichRI.paint("[", :method)
  end

  def test_parser_distinguishes_calls_from_local_variables
    source = "value = 1\nputs value\nvalue\n"
    output = highlighter.highlight(source, :ruby)

    assert_equal source, RichRI.plain(output)
    assert_includes output, RichRI.paint("puts", :method)
    refute_includes output, RichRI.paint("value", :method)
    assert_role("Namespace::Value", "Value", :constant)
    assert_role("value = ->(x) { x }\nvalue.call(1)", "call", :method)
  end

  def test_symbols_keep_their_role_even_when_the_name_is_a_keyword_or_method
    %w[if nil true self String match? save! [] []= + %].each do |name|
      assert_role(":#{name}", name, :symbol)
    end
    [
      ["{ ready?: true }", "ready?:"], ["%i[ready? save!]", "ready?"],
      ["%s(match?)", "match?"], [":\"ready?\"", "ready?"],
      ["alias new_name old_name", "old_name"], ["undef obsolete!", "obsolete!"]
    ].each { |source, symbol| assert_role(source, symbol, :symbol) }
  end

  def test_literals_and_comments_are_not_mistaken_for_method_calls
    %w[q Q w W r x].each do |form|
      assert_role("%#{form}(match?)", "match?", :string)
    end
    assert_role("?a", "?a", :string)
    assert_role("# match? map! %\n", "match?", :comment)
    %w[0xff 0b101 1_000 1.25 2r 3i 1.5ri].each do |source|
      assert_role(source, source, :number)
    end
    assert_role("$stdout", "$stdout", :code)
    assert_role("$1", "$1", :code)
  end

  def test_interpolation_and_heredocs_preserve_source
    sources = [
      <<~'RUBY',
        name = "Ruby"
        text = "#{name.empty? ? 'empty' : name.upcase}"
        pattern = /#{name.downcase}+/i
        words = %W[hello #{name.upcase}]
        symbols = %I[hello #{name.downcase}]
      RUBY
      <<~'RUBY'
        first, second = <<~FIRST, <<~SECOND
          olá #{name.empty?}
        FIRST
          世界 #{items.map!(&:to_s)}
        SECOND
      RUBY
    ]

    sources.each { |source| assert_preserved(source) }
    assert_role(sources[0], "empty?", :method)
    assert_role(sources[1], "map!", :method)
  end

  def test_modern_syntax_and_data_sections_preserve_source
    source = <<~RUBY
      case data
      in {name:, values: [first, *rest]} if name.match?(/a/)
        rest.map { it.to_s }
      else
        nil
      end
      def forward(...) = target(...)
      list.map { _1.to_s }
      =begin
      match? is documentation here.
      =end
      __END__
      match? plain data
    RUBY
    assert_preserved(source)
    assert_role(source, "match?", :method)
  end

  def assert_preserved(source)
    output = highlighter.highlight(source, :ruby)

    assert_equal source, RichRI.plain(output)
    assert_equal source, highlighter(enabled: false).highlight(source, :ruby)
  end

  def test_incomplete_examples_and_ri_signatures_still_highlight_methods
    ["re.match?('food'", "obj.save!(", "def ready?(", "def []=(index,",
     "obj.", "obj&."].each do |source|
      output = highlighter.highlight(source, :ruby)

      assert_equal source, RichRI.plain(output)
    end
    assert_role("re.match?('food'", "match?", :method)
    assert_role("def []=(index,", "[]=", :method)
    assert_role("match?(string, pos = 0) -> true or false", "match?", :method, format: :rich_ri_signature)
    assert_role("value=(value)", "value", :method, format: :rich_ri_signature)
    assert_role("value=(value)", "=", :operator, format: :rich_ri_signature)
  end

  def test_documentation_lookup_colors_predicates_and_bang_calls
    out, err, status = cli("--color=always", "RichRIExample#ready?")

    assert_predicate status, :success?, err
    %w[ready? match match? empty? map!].each do |name|
      assert_includes out, RichRI.paint(name, :method)
    end
  end
end
