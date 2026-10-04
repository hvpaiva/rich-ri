# frozen_string_literal: true

module RichRI
  # One option parser supplies both the CLI and completion descriptions.
  class Options
    attr_reader :parser, :driver_options, :color, :action

    def initialize
      @driver_options = Driver.default_options
      @color = "auto"
      @action = nil
      @parser = OptionParser.new
      @parser.banner = "Usage: rich-ri [options] [Class | Class#method | Class.method | gem:page ...]"
      presentation_options
      lookup_options
      source_options
      utility_options
      @parser.separator ""
      @parser.separator "Run without a name for interactive lookup and Tab completion."
      @parser.separator "Examples: rich-ri Array#map; rich-ri ruby:syntax/pattern_matching"
      @parser.separator "Pager keys: / search, n next match, Space next page, q quit."
      @parser.separator "RI supplies default options; RI_PAGER/PAGER choose the pager."
      @parser.separator "Ruby highlighting is built in; bat optionally highlights other languages."
    end

    def parse(argv, defaults: ENV.fetch("RI", ""))
      args = Shellwords.split(defaults) + argv
      @parser.parse!(args)
      @driver_options[:names] = args
      @driver_options[:use_stdout] ||= !$stdout.tty? || @driver_options[:interactive]
      self
    end

    def self.formats
      RDoc::Markup.constants.grep(/^To[A-Z][a-z]+$/)
                  .map { |name| name.to_s.delete_prefix("To").downcase }.sort - %w[html label test]
    end

    def entries
      @parser.top.list.flat_map do |switch|
        next [] unless switch.respond_to?(:long)

        (switch.short + switch.long).flat_map do |flag|
          flags = flag.include?("[no-]") ? [flag.sub("[no-]", ""), flag.sub("[no-]", "no-")] : [flag]
          flags.map { |name| [name == "--color" ? "--color=" : name, switch.desc.join(" ")] }
        end
      end
    end

    private

    def presentation_options
      @parser.separator ""
      @parser.separator "Presentation:"
      @parser.on("--color[=MODE]", %w[auto always never],
                 "Color: auto (TTY, respects NO_COLOR), always or never.") do |mode|
        @color = mode || "always"
      end
      @parser.on("--no-color", "Plain text with the same page layout.") { @color = "never" }
      @parser.on("--[no-]pager", "Display through a pager (automatically disabled in pipes).") do |value|
        @driver_options[:use_stdout] = !value
      end
      @parser.on("-T", "Write directly to stdout.") { @driver_options[:use_stdout] = true }
      @parser.on("-w", "--width=WIDTH", Integer, "Text width in terminal columns (at least 20).") do |width|
        raise OptionParser::InvalidArgument, "width must be at least 20" if width < 20

        @driver_options[:width] = width
      end
      @parser.on("-f", "--format=NAME", self.class.formats,
                 "Select an original RDoc formatter: #{self.class.formats.join(', ')}.") do |name|
        @driver_options[:formatter] = RDoc::Markup.const_get("To#{name.capitalize}")
      end
    end

    def lookup_options
      @parser.separator ""
      @parser.separator "Lookup:"
      { "interactive" => ["-i", :interactive, "Repeated lookup with Tab completion."],
        "all" => ["-a", :show_all, "Include all methods in a class page."],
        "list" => ["-l", :list, "List known classes and modules."] }.each do |name, (short, key, desc)|
        @parser.on(short, "--[no-]#{name}", desc) { |value| @driver_options[key] = value }
      end
      @parser.on("--[no-]expand-refs", "Expand RDoc references at the end of a page.") do |value|
        @driver_options[:expand_refs] = value
      end
      @parser.on("--server[=PORT]", Integer, "Serve RDoc in a browser (default port: 8214).") do |port|
        @driver_options[:server] = port || 8214
      end
    end

    def source_options
      @parser.separator ""
      @parser.separator "Documentation sources:"
      @parser.on("-d", "--doc-dir=DIRS", Array, "Read RI stores from these directories; repeatable.") do |dirs|
        dirs.each do |dir|
          raise OptionParser::InvalidArgument, "#{dir} is not a directory" unless File.directory?(dir)

          @driver_options[:extra_doc_dirs] << File.expand_path(dir)
        end
      end
      @parser.on("--no-standard-docs", "Use only directories provided with --doc-dir.") do
        %i[system site home gems].each { |key| @driver_options[:"use_#{key}"] = false }
      end
      %w[system site home gems].each do |source|
        @parser.on("--[no-]#{source}", "Include #{source} documentation (default: enabled).") do |value|
          @driver_options[:"use_#{source}"] = value
        end
      end
      @parser.on("--[no-]list-doc-dirs", "List the directories searched for RI documentation.") do |value|
        @driver_options[:list_doc_dirs] = value
      end
    end

    def utility_options
      @parser.separator ""
      @parser.separator "Tools:"
      @parser.on("--completion=SHELL", %w[bash zsh fish], "Print a completion script for bash, zsh or fish.") do |shell|
        @action = [:completion, shell]
      end
      @parser.on("--man", "Open the bundled manual with man.") { @action = [:man] }
      @parser.on("--man-path", "Print the path to the bundled manual.") { @action = [:man_path] }
      @parser.on("--install-man[=DIR]", "Install or update the manual in a user man1 directory.") do |directory|
        @action = [:install_man, directory]
      end
      @parser.on("--dump=CACHE", "Inspect a trusted RI cache file.") { |path| @driver_options[:dump_path] = path }
      @parser.on("--[no-]profile", "Run with Ruby's optional profile library.") do |value|
        @driver_options[:profile] = value
      end
      @parser.on("-h", "--help", "Show this help.") { @action = [:help] }
      @parser.on("-v", "--version", "Show the rich-ri version.") { @action = [:version] }
    end
  end
end
