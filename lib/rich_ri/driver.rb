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

    STANDARD_SOURCES = Configuration::SOURCES.map { |source| :"use_#{source}" }.freeze

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
      @rich_ri_pager = options.delete(:rich_ri_pager)
      options = self.class.default_options.merge(options)
      optional_gem("profile", "--profile") if options[:profile]
      # RDoc resolves ~/.rdoc as soon as its list of stores is loaded and
      # fails there with a TypeError when the user has no home directory.
      RichRI.home!
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

    # Returns the exit status: 1 when a name was not found, otherwise 0.
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
        missing = display_names(@names)
        # Similar names or the pages of a source shown in its place are output, not the failure.
        missing.each { |name| Error.report(LookupError.new(name)) }
        return missing.empty? ? 0 : 1
      end
      0
    rescue NotFoundError => e
      # RDoc ends the process here with Kernel#abort and the name as typed.
      raise LookupError.from(e)
    end

    # Looks every name up, as RDoc does, and returns those that were not found.
    def display_names(names)
      names.reject { |name| display_name(expand_name(name)) }
    end

    # Whether the name was found. RDoc answers false after showing similar
    # names, but true after listing the pages of a source in place of a page
    # it does not have, as it does when that list is what was asked for.
    def display_name(name)
      @page_list = false
      super && (name.end_with?(":") || !@page_list)
    end

    def display_page_list(*)
      @page_list = true
      super
    end

    def page
      interrupted = Signals.defer_interrupt(method(:paging?)) do
        super { |io| yield(@formatter_klass ? io : Output.new(io)) }
      end
      @pager&.finish(interrupted)
      # RDoc takes this answer for whether a class page was shown, and looks
      # the name up again as a method when it is not true.
      true
    ensure
      @pager = nil
    end

    # RDoc tries RI_PAGER, PAGER and three programs in turn and passes over
    # any that does not start, the one the user asked for included.
    def setup_pager
      return if @use_stdout

      @pager = Pager.start(@rich_ri_pager)
      @paging = !@pager.nil?
      # With no pager on this system, write to the terminal from now on.
      @use_stdout = !@paging
      @pager&.io
    end

    # RDoc looks for the colon of a page only after splitting the name at every
    # "." and "#", and so loses a source that holds one, such as "json-2.9.1".
    def expand_name(name)
      page = PageSources::NAME.match(name)
      page ? "#{find_store(page[:source])}:#{page[:page]}" : super
    end

    def find_store(name)
      page_sources.resolve(name) or raise NotFoundError, name
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
      puts "\nEnter a name to look up; Tab completes it."
      puts "Enter a blank line to exit.\n\n"
      prompt = Prompt.new(method(:complete))
      while (name = prompt.read)
        answer(name)
      end
    end

    def start_server
      optional_gem("webrick", "--server")
      Server.new(port: @server, doc_dirs: @stores.select { |store| store.type == :extra }.map(&:path)).start
    end

    # RDoc completes classes and methods. The sources of pages and the pages
    # themselves come from the loaded stores, so that discovery follows this
    # Ruby and --doc-dir. A line editor and a shell write a candidate as it
    # is, so a name from a store that holds a terminal control is not offered.
    def complete(name)
      candidates = PageSources::NAME.match?(name) ? [] : super + selectors(name)
      (candidates + page_sources.complete(name)).uniq.select { |candidate| RichRI.printable?(candidate) }.sort
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

    def answer(name)
      display_name(expand_name(name))
    rescue StandardError, ScriptError => e
      Error.report(e.is_a?(NotFoundError) ? LookupError.from(e) : e)
    end

    # webrick and profile are not dependencies of the gem. RDoc answers their
    # absence with abort or a bare LoadError; say which gem the option needs.
    def optional_gem(name, option)
      require name
    rescue LoadError => e
      raise unless e.path == name

      raise Error.new("#{option} requires the optional #{name} gem",
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
        store.gem_name = gem_names[path] if type == :gem
        store.load_cache
        @stores << store
      end
    end

    # The name of each installed gem by the directory of its RI data. RDoc
    # finds those directories through the specifications and keeps only the paths.
    def gem_names
      @gem_names ||= Gem::Specification.to_h { |spec| [RichRI.utf8(File.join(spec.doc_dir, "ri")), spec.name] }
    end

    # What can follow the name of a class.
    def selectors(name)
      classes.key?(name) ? ["#{name}#", "#{name}.", "#{name}::"] : []
    end

    def page_sources
      @page_sources ||= PageSources.new(stores)
    end
  end
end
