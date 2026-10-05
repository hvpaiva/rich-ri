# frozen_string_literal: true

module RichRI
  class Driver < RDoc::RI::Driver
    # RDoc prints class lists and suggested names straight to its pager with
    # puts, outside the formatter, and writes a formatted page with write. The
    # names come from stores and from the command line; the page was escaped
    # by the formatter and carries this reader's own styles.
    class Output
      def initialize(io)
        @io = io
      end

      def puts(*values)
        @io.puts(*values.map { |value| RichRI.sanitize(value.to_s) })
      end

      def write(text)
        @io.write(text)
      end

      def tty?
        @io.tty?
      end
    end

    STANDARD_SOURCES = %i[use_system use_site use_home use_gems].freeze
    PROMPT_FAILURES = 3

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
      if @list_doc_dirs
        puts(@formatter_klass ? @doc_dirs : @doc_dirs.map { |path| RichRI.sanitize(path) })
      elsif @list
        list_known_classes(@names)
      elsif @server
        start_server
      elsif @interactive || @names.empty?
        interactive
      else
        display_names(@names)
      end
    rescue NotFoundError => e
      # RDoc ends the process here with Kernel#abort and the name as typed.
      raise Error, e.message
    end

    def page
      super { |io| yield(@formatter_klass ? io : Output.new(io)) }
    end

    # RDoc interpolates the name into a pattern unescaped. A class name holds
    # only word characters and "::", so anything else abbreviates no class.
    def expand_class(klass)
      raise NotFoundError, klass unless klass.match?(/\A[\w:]*\z/)

      super
    end

    # RDoc reads the names as patterns as well; they are prefixes.
    def list_known_classes(names = [])
      classes = stores.flat_map(&:module_names).uniq.sort
      classes = classes.select { |name| name.start_with?(*names) } unless names.empty?
      page do |io|
        if paging? || io.tty?
          io.puts "Classes and Modules #{names.empty? ? 'known to ri' : "starting with #{names.join(', ')}"}:"
          io.puts
        end
        io.puts classes.join("\n")
      end
    end

    # RDoc's own loop leaves on the first exception other than an unknown name
    # and answers Ctrl-C with a successful exit. Here a failed lookup is
    # reported and the prompt returns; Ctrl-C reaches the command as Interrupt.
    def interactive
      puts "\nEnter the method name you want to look up."
      Reline.completion_proc = method(:complete)
      puts "You can use tab to autocomplete."
      puts "Enter a blank line to exit.\n\n"
      while (name = read_name)
        answer(name)
      end
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

    # The name typed at the prompt, or nil at a blank line or the end of input.
    def read_name
      failures = 0
      begin
        name = Reline.readline(">> ", true)
      rescue IOError, SystemCallError
        raise
      rescue StandardError => e
        # Completion runs inside the line editor. Show its failure and ask
        # again, but not forever: a prompt that cannot start would spin.
        raise if (failures += 1) == PROMPT_FAILURES

        Error.report(e)
        retry
      end
      RichRI.utf8(name).strip unless name.nil? || name.empty?
    end

    def answer(name)
      display_name(expand_name(name))
    rescue StandardError, ScriptError => e
      Error.report(e)
    end

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
        # RubyGems labels its directories BINARY; a store source built from one
        # cannot be joined with other text.
        path = RichRI.utf8(path)
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
