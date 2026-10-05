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

    STANDARD_SOURCES = %i[use_system use_site use_home use_gems].freeze

    def self.default_options
      columns = $stdout.tty? ? $stdout.winsize.last : 80
      columns = 80 unless columns.positive?
      super.merge(width: (columns - 2).clamp(30, 96))
    rescue SystemCallError
      super
    end

    def self.dump(path)
      super
    rescue TypeError, ArgumentError
      raise StoreError, path
    end

    def initialize(options)
      @rich_ri_color = options.delete(:rich_ri_color)
      @rich_ri_theme = options.delete(:rich_ri_theme) || Theme.new
      @rich_ri_bat_theme = options.delete(:rich_ri_bat_theme) || ENV.fetch("BAT_THEME", "base16")
      @rich_ri_shell_theme = options.delete(:rich_ri_shell_theme) || "ansi"
      options = self.class.default_options.merge(options)
      optional_gem("profile", "--profile") if options[:profile]
      # RDoc would load every store itself, as plain RDoc stores that cannot
      # say which of them failed. Start it without any and load them here.
      super(options.merge(STANDARD_SOURCES.to_h { |source| [source, false] }, extra_doc_dirs: []))
      load_stores(*options.values_at(*STANDARD_SOURCES), *options[:extra_doc_dirs])
    end

    def formatter(io)
      return super if @formatter_klass

      Formatter.new(color: @rich_ri_color, classes: classes, theme: @rich_ri_theme,
                    bat_theme: @rich_ri_bat_theme, shell_theme: @rich_ri_shell_theme)
    end

    def run
      return super unless @list_doc_dirs && !@formatter_klass

      puts(@doc_dirs.map { |path| RichRI.sanitize(path) })
    end

    def page
      super { |io| yield(@list && !@formatter_klass ? ListOutput.new(io) : io) }
    end

    def start_server
      optional_gem("webrick", "--server")
      super
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

    def add_method_documentation(out, klass)
      klass.method_list.each do |method|
        add_method(out, method.full_name)
      rescue NotFoundError
        next
      rescue StoreError => e
        # One unreadable method must not cost the rest of the class page.
        out << RDoc::Markup::Heading.new(1, method.full_name) << RDoc::Markup::BlankLine.new
        out << RDoc::Markup::Paragraph.new("(not shown: #{e.message})") << RDoc::Markup::BlankLine.new
      end
    end

    def add_method_list(out, methods, name)
      return super if @formatter_klass
      return if methods.empty?

      out << RDoc::Markup::Heading.new(2, "#{name}:")
      out << RDoc::Markup::BlankLine.new
      out << MethodList.new(2, methods.join(", "))
      out << RDoc::Markup::BlankLine.new
    end

    private

    # webrick and profile are not dependencies of the gem. RDoc answers their
    # absence with abort or a bare LoadError; say which gem the option needs.
    def optional_gem(name, option)
      require name
    rescue LoadError => e
      raise unless e.path == name

      raise Error.new("#{option} requires the optional #{name} gem.",
                      hint: "Install it for your active Ruby: gem install #{name}")
    end

    def load_stores(*selection)
      RDoc::RI::Paths.each(*selection) do |path, type|
        @doc_dirs << path
        # Listing the searched directories is how a broken store is found.
        next if @list_doc_dirs

        store = Store.new(RDoc::Options.new, path: path, type: type)
        store.load_cache
        @stores << store
      end
    end
  end
end
