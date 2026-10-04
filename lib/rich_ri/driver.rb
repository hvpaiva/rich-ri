# frozen_string_literal: true

module RichRI
  class Driver < RDoc::RI::Driver
    # RDoc's class listing writes directly to its pager, outside the formatter.
    class ListOutput
      def initialize(io)
        @io = io
      end

      def puts(*values)
        @io.puts(*values.map { |value| RichRI.sanitize(value.to_s) })
      end

      def tty?
        @io.tty?
      end
    end

    def self.default_options
      columns = $stdout.tty? ? $stdout.winsize.last : 80
      columns = 80 unless columns.positive?
      super.merge(width: (columns - 2).clamp(30, 96))
    rescue SystemCallError
      super
    end

    def initialize(options)
      @rich_ri_color = options.delete(:rich_ri_color)
      super
    end

    def formatter(io)
      return super if @formatter_klass

      Formatter.new(color: @rich_ri_color, classes: classes)
    end

    def run
      return super unless @list_doc_dirs && !@formatter_klass

      puts(@doc_dirs.map { |path| RichRI.sanitize(path) })
    end

    def page
      super { |io| yield(@list && !@formatter_klass ? ListOutput.new(io) : io) }
    end

    def complete(name)
      # RI completes classes/methods but does not offer ruby: or gem pages.
      # Use the loaded stores so discovery follows this Ruby and --doc-dir.
      if (match = /\A([^:]+):([^:]*)\z/.match(name))
        source, prefix = match.captures
        matching = stores.select do |store|
          store.source == source || (store.type == :gem && store.source.match?(/\A#{Regexp.escape(source)}-\d/))
        end
        return matching.flat_map { |store| store.cache[:pages] || [] }
                       .select { |page| page.start_with?(prefix) }
                       .map { |page| "#{source}:#{page}" }.uniq.sort
      end

      candidates = super
      candidates.push("#{name}#", "#{name}.", "#{name}::") if classes.key?(name)
      unless name.match?(/[.#:]/)
        stores.each do |store|
          next if (store.cache[:pages] || []).empty?

          source = store.type == :gem ? store.source.sub(/-\d[^-]*\z/, "") : store.source
          candidates << "#{source}:" if source.start_with?(name)
        end
      end
      candidates.uniq.sort
    end

    def render_method_arguments(out, arglists)
      start = out.parts.length
      super
      return if @formatter_klass

      out.parts[start..].grep(RDoc::Markup::Verbatim).each { |part| part.format = :rich_ri_signature }
    end

    def render_method_type_signature(out, lines)
      start = out.parts.length
      super
      return if @formatter_klass

      out.parts[start..].grep(RDoc::Markup::Verbatim).each { |part| part.format = :rbs }
    end

    def add_method_list(out, methods, name)
      return super if @formatter_klass
      return if methods.empty?

      out << RDoc::Markup::Heading.new(2, "#{name}:")
      out << RDoc::Markup::BlankLine.new
      out << MethodList.new(2, methods.join(", "))
      out << RDoc::Markup::BlankLine.new
    end
  end
end
