# frozen_string_literal: true

module RichRI
  # One option parser supplies both the CLI and completion descriptions.
  class Options
    include ConfigurationOptions

    PORTS = 1..65_535
    DEFAULT_PORT = 8214

    attr_reader :parser, :driver_options, :color, :action

    def initialize
      @driver_options = Driver.default_options
      @color = "auto"
      @action = nil
      @parser = OptionParser.new
      # Configuration selection and completion inspect flags before parsing.
      # Require the same full option names throughout those paths.
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
      names = configured_defaults(argv, defaults, configuration)
      @driver_options[:names] = names + arguments(argv)
      @driver_options[:use_stdout] ||= !$stdout.tty? || @driver_options[:interactive]
      @theme = Theme.new(name: @theme_name, styles: @styles, depth: @color_depth)
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

    def arguments(argv)
      @parser.parse!(argv.dup)
    rescue OptionParser::ParseError => e
      raise UsageError, e.message
    end

    # OptionParser would complete a listed value from any unambiguous prefix
    # and call an empty one ambiguous; these are matched whole, like options.
    def choice(option, value, allowed)
      return value if allowed.include?(value)

      raise UsageError, "#{option} must be one of #{allowed.join(', ')}, not #{value.inspect}"
    end

    def integer(option, text, range)
      number = Configuration.integer(text)
      return number if number && range.cover?(number)

      raise UsageError, "#{option} must be an integer from #{range.min} to #{range.max}, not #{text.inspect}"
    end

    def presentation_options
      @parser.separator ""
      @parser.separator "Presentation:"
      @parser.on("--color[=MODE]", "Color: auto (TTY, respects NO_COLOR), always or never.") do |mode|
        @color = mode ? choice("--color", mode, %w[auto always never]) : "always"
      end
      @parser.on("--no-color", "Plain text with the same page layout.") { @color = "never" }
      @parser.on("--[no-]pager", "Display through a pager (automatically disabled in pipes).") do |value|
        @pager_enabled = value
        @driver_options[:use_stdout] = !value
      end
      @parser.on("-T", "Write directly to stdout.") do
        @pager_enabled = false
        @driver_options[:use_stdout] = true
      end
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
      { "interactive" => ["-i", :interactive, "Repeated lookup with Tab completion."],
        "all" => ["-a", :show_all, "Include all methods in a class page."],
        "list" => ["-l", :list, "List known classes and modules."] }.each do |name, (short, key, desc)|
        @parser.on(short, "--[no-]#{name}", desc) { |value| @driver_options[key] = value }
      end
      @parser.on("--[no-]expand-refs", "Expand RDoc references at the end of a page.") do |value|
        @driver_options[:expand_refs] = value
      end
      @parser.on("--server[=PORT]", "Serve RDoc in a browser (port: 8214; requires webrick).") do |port|
        @driver_options[:server] = port ? integer("--server", port, PORTS) : DEFAULT_PORT
      end
    end

    def source_options
      @parser.separator ""
      @parser.separator "Documentation sources:"
      @parser.on("-d", "--doc-dir=DIRS", "Read RI stores from these directories; repeatable.") do |value|
        # Prefer an existing literal path, including commas, over RI's list form.
        directories = File.directory?(value) ? [value] : value.split(",")
        directories.each do |dir|
          raise UsageError, "--doc-dir must be a directory, not #{dir.inspect}" unless File.directory?(dir)

          @driver_options[:extra_doc_dirs] << RichRI.expand_path(dir)
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
      @parser.on("--completion=SHELL", "Print a completion script for bash, zsh or fish.") do |shell|
        @action = [:completion, choice("--completion", shell, %w[bash zsh fish])]
      end
      @parser.on("--man", "Open the bundled manual with man.") { @action = [:man] }
      @parser.on("--man-path", "Print the path to the bundled manual.") { @action = [:man_path] }
      @parser.on("--install-man[=DIR]", "Install or update the manual in a user man1 directory.") do |directory|
        @action = [:install_man, directory]
      end
      @parser.on("--dump=CACHE", "Inspect a trusted RI cache file.") { |path| @driver_options[:dump_path] = path }
      @parser.on("--[no-]profile", "Run Ruby's profiler (requires the profile gem).") do |value|
        @driver_options[:profile] = value
      end
      @parser.on("-h", "--help", "Show this help.") { @action = [:help] }
      @parser.on("-v", "--version", "Show the rich-ri version.") { @action = [:version] }
    end
  end
end
