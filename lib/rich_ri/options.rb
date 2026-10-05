# frozen_string_literal: true

module RichRI
  # One option parser supplies both the CLI and completion descriptions.
  class Options
    include ConfigurationOptions
    include OptionValues

    PORTS = 1..65_535
    DEFAULT_PORT = 8214
    RECOVERY_ACTIONS = %i[help version config_path completion].freeze
    LOOKUPS = { interactive: :interactive, list: :list, list_doc_dirs: :list_doc_dirs, server: :server,
                dump: :dump_path }.freeze

    attr_reader :parser, :driver_options, :color

    # What runs instead of a lookup, as a name and its arguments, or nil.
    attr_reader :action

    def initialize
      @driver_options = Driver.default_options
      @color = "auto"
      @actions = Actions.new
      @action = nil
      @parser = OptionParser.new
      # Completion inspects flags before parsing and takes them by full name.
      @parser.require_exact = true
      # Every OptionParser also answers --*-completion-bash=WORD and
      # --*-completion-zsh, printing to stdout and exiting in mid-parse.
      @parser.base.long.delete_if { |name, _switch| name.start_with?("*-") }
      @parser.banner = "Usage: rich-ri [options] [Class | Class#method | Class.method | gem:page ...]"
      configuration_options
      presentation_options
      lookup_options
      source_options
      utility_options
      @parser.separator ""
      @parser.separator "Run without a name for interactive lookup and Tab completion."
      @parser.separator "Write long options in full; abbreviations are not accepted."
      @parser.separator "Examples: rich-ri Array#map; rich-ri ruby:syntax/pattern_matching"
      @parser.separator "Pager keys: / search, n next match, Space next page, q quit."
      @parser.separator "Defaults: RI options < config file < environment < explicit arguments."
      @parser.separator "File: $XDG_CONFIG_HOME/rich-ri/config.yml or ~/.config/rich-ri/config.yml."
      @parser.separator "RICH_RI_CONFIG selects another file; --no-config skips it."
      @parser.separator "Environment overrides: RICH_RI_THEME, RICH_RI_COLOR, RICH_RI_COLOR_DEPTH,"
      @parser.separator "  RICH_RI_WIDTH, RICH_RI_BAT_THEME, RICH_RI_SHELL_THEME."
      @parser.separator "RICH_RI_STYLE_<ROLE> overrides one style; --style takes precedence."
      @parser.separator "RI_PAGER/PAGER choose the pager; LESS sets its preferences."
      @parser.separator "NO_COLOR and TERM=dumb disable automatic color; COLORTERM helps detect RGB."
      @parser.separator "RICH_RI_DEBUG adds the error class and backtrace to a failure."
      @parser.separator "Styles: ANSI name, 0-255, #RRGGBB or fg=COLOR:bg=COLOR:bold:italic."
      @parser.separator "Also supported: dim, underline, strike, reverse; none disables a role."
      @parser.separator "Style roles:"
      Theme::ROLES.each_slice(6) { |roles| @parser.separator "  #{roles.join(', ')}" }
      @parser.separator "See rich-ri --man or docs/configuration.md for all settings and examples."
      @parser.separator "Ruby highlighting is built in; bat optionally highlights other languages."
      @parser.separator "Exit status: 0 success, 1 failure, 2 usage error, 130 interrupted."
    end

    def parse(argv, defaults: RichRI.utf8(ENV.fetch("RI", "")), configuration: true)
      command = self.class.new.command_line(argv)
      names = configured_defaults(command, defaults, configuration)
      finish(names + arguments(argv))
      # Naming a pager on the command line asks for paging, whatever the file says.
      @pager_enabled ||= command.pager_named?
      # RDoc's own ri stops paging under --interactive but not at the prompt
      # it opens when given no name; here the two are one session.
      @driver_options[:use_stdout] = !(@pager_enabled && $stdout.tty?)
      @theme = Theme.new(name: @theme_name, styles: @styles, depth: @color_depth)
      self
    end

    # Read alone first: the file and the action it selects decide what else is read.
    def command_line(argv)
      finish(arguments(argv))
      self
    end

    # These have to work while the file or the environment is broken: they are how it is found out.
    def recovery?
      RECOVERY_ACTIONS.include?(@action&.first)
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

    # Options are read wherever they stand, up to "--". OptionParser#parse!
    # would stop at the first name instead whenever POSIXLY_CORRECT is set.
    def arguments(argv)
      read(argv.dup)
    rescue OptionParser::ParseError => e
      raise UsageError, e.message
    end

    def read(words)
      names = @parser.permute!(words)
      @actions.settle
      names
    end

    def finish(names)
      name, value = @actions.current
      if name == :interactive && !names.empty?
        raise UsageError, "--interactive does not accept lookup names; enter them at its prompt"
      elsif name.nil? && names.empty? && @actions.declined?(:interactive)
        raise UsageError, "--no-interactive requires a name to look up"
      end

      LOOKUPS.each { |action, key| @driver_options[key] = action == name && (value || true) }
      @action = (@actions.current unless LOOKUPS.key?(name))
      @driver_options[:names] = names
    end

    def toggle(option, name, chosen)
      chosen ? @actions.choose(option, name) : @actions.decline(name)
    end

    def presentation_options
      @parser.separator ""
      @parser.separator "Presentation:"
      @parser.on("--color[=MODE]", "Color: auto (TTY, respects NO_COLOR), always or never.") do |mode|
        @color = mode ? choice("--color", mode, Configuration::COLOR_MODES) : "always"
      end
      @parser.on("--no-color", "Plain text with the same page layout.") { @color = "never" }
      @parser.on("--[no-]pager", "Display through a pager (automatically disabled in pipes).") do |value|
        @pager_enabled = value
      end
      @parser.on("-T", "Write directly to stdout.") { @pager_enabled = false }
      @parser.on("-w", "--width=WIDTH", "Text width in terminal columns (20 to 10000).") do |width|
        @driver_options[:width] = integer("--width", width, Configuration::WIDTH)
      end
      @parser.on("-f", "--format=NAME",
                 "Select an original RDoc formatter: #{self.class.formats.join(', ')}.") do |name|
        name = choice("--format", name, self.class.formats)
        @driver_options[:formatter] = RDoc::Markup.const_get("To#{name.capitalize}")
      end
    end

    def lookup_options
      @parser.separator ""
      @parser.separator "Lookup:"
      @parser.on("-i", "--[no-]interactive", "Repeated lookup with Tab completion.") do |value|
        toggle("--interactive", :interactive, value)
      end
      @parser.on("-a", "--[no-]all", "Include all methods in a class page.") do |value|
        @driver_options[:show_all] = value
      end
      @parser.on("-l", "--[no-]list", "List known classes and modules.") { |value| toggle("--list", :list, value) }
      @parser.on("--[no-]expand-refs", "Expand RDoc references at the end of a page.") do |value|
        @driver_options[:expand_refs] = value
      end
      @parser.on("--server[=PORT]", "Serve RDoc in a browser (port: 8214; requires webrick).") do |port|
        @actions.choose("--server", :server, port ? integer("--server", port, PORTS) : DEFAULT_PORT)
      end
    end

    def source_options
      @parser.separator ""
      @parser.separator "Documentation sources:"
      @parser.on("-d", "--doc-dir=DIRS", "Read RI stores from these directories; repeatable.") do |value|
        @driver_options[:extra_doc_dirs].concat(directories(value))
      end
      @parser.on("--no-standard-docs", "Use only directories provided with --doc-dir.") do
        Driver::STANDARD_SOURCES.each { |key| @driver_options[key] = false }
      end
      Configuration::SOURCES.each do |source|
        @parser.on("--[no-]#{source}", "Include #{source} documentation (default: enabled).") do |value|
          @driver_options[:"use_#{source}"] = value
        end
      end
      @parser.on("--[no-]list-doc-dirs", "List the directories searched for RI documentation.") do |value|
        toggle("--list-doc-dirs", :list_doc_dirs, value)
      end
    end

    def utility_options
      @parser.separator ""
      @parser.separator "Tools:"
      @parser.on("--completion=SHELL", "Print a completion script for bash, zsh or fish.") do |shell|
        @actions.choose("--completion", :completion, choice("--completion", shell, Completion::SHELLS))
      end
      @parser.on("--man", "Open the bundled manual with man.") { @actions.choose("--man", :man) }
      @parser.on("--man-path", "Print the path to the bundled manual.") { @actions.choose("--man-path", :man_path) }
      @parser.on("--install-man[=DIR]", "Install or update the manual in a user man1 directory.") do |directory|
        @actions.choose("--install-man", :install_man, directory)
      end
      @parser.on("--dump=CACHE", "Inspect a trusted RI cache file.") do |path|
        raise UsageError, "--dump requires a nonempty file path" if path.empty?

        @actions.choose("--dump", :dump, path)
      end
      @parser.on("--[no-]profile", "Run Ruby's profiler (requires the profile gem).") do |value|
        @driver_options[:profile] = value
      end
      @parser.on("-h", "--help", "Show this help.") { @actions.choose("--help", :help) }
      @parser.on("-v", "--version", "Show the rich-ri version.") { @actions.choose("--version", :version) }
    end
  end
end
