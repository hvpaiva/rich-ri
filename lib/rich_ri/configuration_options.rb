# frozen_string_literal: true

module RichRI
  # Configuration switches share the normal parser, so defaults and explicit
  # arguments use the same validation and completion descriptions.
  module ConfigurationOptions
    attr_reader :theme, :bat_theme, :shell_theme, :pager_command, :configuration_path

    # What the command line says about the file: the path given to --config,
    # :none after --no-config or :default when it names no file.
    attr_reader :configuration_file

    def configuration_options
      @configuration_file = :default
      @theme_name = "terminal"
      @color_depth = "auto"
      @styles = {}
      @bat_theme = "base16"
      @shell_theme = "ansi"
      @pager_enabled = true
      @parser.separator ""
      @parser.separator "Configuration and themes:"
      @parser.on("--config=FILE", "Read a YAML configuration file instead of the user default.") do |path|
        @configuration_file = RichRI.expand_path(text("--config", path))
      end
      @parser.on("--no-config", "Skip the configuration file; environment options still apply.") do
        @configuration_file = :none
      end
      @parser.on("--config-path", "Print the selected configuration path; blank when disabled.") do
        @actions.choose("--config-path", :config_path)
      end
      @parser.on("--show-config", "Print effective preferences as YAML without opening documentation.") do
        @actions.choose("--show-config", :show_config)
      end
      theme_options
    end

    def theme_options
      @parser.on("--theme=NAME", "Palette: terminal (default), dark or light.") do |name|
        @theme_name = choice("--theme", name, Theme::NAMES)
      end
      @parser.on("--color-depth=DEPTH", "Color depth: auto (default), basic, 256 or truecolor.") do |depth|
        @color_depth = choice("--color-depth", depth, Theme::DEPTHS)
      end
      @parser.on("--style=ROLE=STYLE",
                 "Override a style role; repeat for several roles. Example: method=green:bold.") do |value|
        role, description = value.split("=", 2)
        @styles[role] = style(role, description)
      end
      @parser.on("--bat-theme=NAME", "bat theme for tagged non-Ruby, non-shell code (default: base16).") do |name|
        @bat_theme = text("--bat-theme", name)
      end
      @parser.on("--shell-theme=NAME", "bat theme for shell input (default: ansi).") do |name|
        @shell_theme = text("--shell-theme", name)
      end
      @parser.on("--pager-command=COMMAND", "Choose a trusted pager command, overriding RI_PAGER/PAGER.") do |command|
        @pager_command = text("--pager-command", command)
      end
    end

    def settings
      { "theme" => @theme_name, "color" => @color, "color_depth" => @color_depth,
        "width" => @driver_options.fetch(:width), "pager" => @pager_enabled && (@pager_command || true),
        "bat_theme" => @bat_theme, "shell_theme" => @shell_theme,
        "all" => @driver_options.fetch(:show_all), "expand_refs" => @driver_options.fetch(:expand_refs),
        "doc_dirs" => @driver_options.fetch(:extra_doc_dirs).map(&:dup),
        "sources" => Configuration::SOURCES.to_h { |key| [key, @driver_options.fetch(:"use_#{key}")] },
        "styles" => @styles.transform_values(&:dup) }
    end

    # Whether a pager command is named here and paging not turned off beside it.
    def pager_named?
      @pager_enabled && !@pager_command.nil?
    end

    private

    # Puts RI, then the file and the environment, under the command line that
    # was read on its own as command. Returns the names RI holds.
    def configured_defaults(command, defaults, enabled)
      selection = Configuration.new(command.configuration_file)
      @configuration_path = selection.path
      # The path is printed without opening the file.
      return [] if command.action == [:config_path]

      words = ri_defaults(defaults)
      parse_defaults(selection.arguments, "configuration") if enabled
      words
    rescue StandardError
      # Not only the failures rich-ri raises itself: nothing that goes wrong
      # under the command line may take a recovery action away.
      raise unless command.recovery?

      initialize
      @configuration_path = selection&.path
      []
    end

    def ri_defaults(defaults)
      words = default_words(defaults)
      parse_defaults(words, "RI")
      return words if @configuration_file == :default

      # The file is chosen before RI is read: RI could only seem to choose it.
      raise ConfigurationError, "RI: #{@configuration_file == :none ? '--no-config' : '--config'} cannot be set " \
                                "in RI; choose the configuration file with RICH_RI_CONFIG or on the command line"
    end

    def default_words(defaults)
      Shellwords.split(defaults)
    rescue ArgumentError
      raise ConfigurationError, "RI: unmatched quote"
    end

    # RI and the configuration go through the command-line parser, but a value
    # refused there is not a mistake in the command line: say where it is.
    def parse_defaults(words, origin)
      read(words)
    rescue OptionParser::ParseError, UsageError => e
      raise ConfigurationError, "#{origin}: #{e.message}"
    end
  end
end
