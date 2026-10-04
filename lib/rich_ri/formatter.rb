# frozen_string_literal: true

module RichRI
  class MethodList < RDoc::Markup::IndentedParagraph
    def accept(visitor)
      visitor.respond_to?(:accept_method_list) ? visitor.accept_method_list(self) : super
    end
  end

  class Formatter < RDoc::Markup::ToAnsi
    REFERENCES = /(?<!\w)(?:[A-Z]\w*(?:::\w+)*(?:[#.]\w+[!?=]?)?|\#\w+[!?=]?)/

    def initialize(color: true, classes: {}, theme: Theme.new, bat_theme: ENV.fetch("BAT_THEME", "base16"),
                   shell_theme: "ansi")
      super()
      @color = color
      @classes = classes
      @theme = theme
      @highlighter = Highlighter.new(color, theme:, bat_theme:, shell_theme:)
    end

    def paint(text, *roles)
      @theme.paint(text, *roles, enabled: @color)
    end

    def start_accepting
      super
      @res = []
      @first_heading = true
    end

    def accept_heading(heading)
      role = if @first_heading && heading.level == 1
               :title
             elsif heading.level <= 2
               :heading
             else
               :subheading
             end
      @first_heading = false
      wrap paint(RichRI.plain(attributes(heading.text)), role)
    end

    def accept_rule(_rule)
      use_prefix or @res << (" " * @indent)
      @res << paint("─" * [@width - @indent, 1].max, :muted) << "\n"
    end

    def accept_paragraph(paragraph)
      text = paragraph.text(@hard_break)
      if text.start_with?("(from ")
        wrap paint(RichRI.plain(attributes(text)), :muted)
      else
        super
      end
    end

    def accept_verbatim(verbatim)
      text = @highlighter.highlight(verbatim.text, verbatim.format)
      text.each_line do |line|
        @res << (" " * (@indent + 2)) unless line == "\n"
        @res << line
      end
      @res << "\n" unless text.end_with?("\n")
      @res << "\n"
    end

    def accept_raw(raw)
      # Markdown HTML blocks bypass the inline visitors in RDoc.
      @res << RichRI.sanitize(raw.parts.join("\n"))
    end

    def accept_method_list(list)
      @indent += list.indent
      wrap paint(RichRI.sanitize(list.text(@hard_break)), :reference)
      @indent -= list.indent
    end

    def accept_list_item_start(item)
      super
      return unless @prefix

      role = %i[NOTE LABEL].include?(@list_type.last) ? :label : :reference
      @prefix = paint(RichRI.plain(@prefix), role)
    end

    def accept_list_item_end(item)
      # ToAnsi 8.1 uses byte length for numbered prefixes; ours contain SGRs.
      RDoc::Markup::ToRdoc.instance_method(:accept_list_item_end).bind_call(self, item)
    end

    def add_text(text)
      text = RichRI.sanitize(text)
      attrs = @attributes.keys
      roles = []
      roles << :bold if attrs.include?(:BOLD)
      roles << :emphasis if attrs.include?(:EM)
      roles << :strike if attrs.include?(:STRIKE)
      roles << :code if attrs.include?(:TT)
      text = if roles.empty?
               text.gsub(REFERENCES) do |reference|
                 klass = reference.split(/[.#]/, 2).first
                 reference.start_with?("#") || @classes.key?(klass) ? paint(reference, :reference) : reference
               end
             else
               paint(text, *roles)
             end
      emit_inline(text)
    end

    def handle_TIDYLINK(children, url)
      start = @inline_output.length
      traverse_inline_nodes(children)
      label = RichRI.plain(@inline_output.slice!(start..))
      emit_inline(paint(label, :link))
      # Internal RDoc addresses are implementation details, not useful terminal
      # URLs. External destinations remain visible and can be opened/copied.
      return if url.start_with?("rdoc-", "#") || url == label

      emit_inline(" (#{paint(RichRI.sanitize(url), :reference)})")
    end

    def calculate_text_width(text)
      RichRI.width(text)
    end

    def wrap(text)
      return if text.nil? || text.empty?

      limit = [@width - @indent, 12].max
      prefix = @prefix || (" " * @indent)
      @prefix = nil
      line = +""
      pending_space = ""
      flush = lambda do
        @res << prefix << line
        @res << RESET if @color
        @res << "\n"
        prefix = " " * @indent
        line = +""
      end

      text.scan(/(?:\e\[[\d;]*m|[^\s\e])+|[^\S\n]+|\n/).each do |word|
        if word == "\n"
          flush.call
          pending_space = ""
        elsif word.match?(/\A\s+\z/)
          pending_space = " " unless line.empty?
        else
          if !line.empty? && RichRI.width(line + pending_space + word) > limit
            flush.call
            pending_space = ""
          end
          # Split long URLs/identifiers using terminal cell widths, never SGR
          # bytes or the middle of a wide Unicode character.
          chunks = Reline::Unicode.split_by_width(word, limit).first
          chunks.pop while chunks.length > 1 && RichRI.plain(chunks.last).empty?
          chunks.each_with_index do |chunk, index|
            flush.call if index.positive?
            line << pending_space << chunk
            pending_space = ""
          end
        end
      end
      flush.call unless line.empty?
    end
  end
end
