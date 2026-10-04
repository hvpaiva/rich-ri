# frozen_string_literal: true

module RichRI
  # Configuration switches share the normal parser, so defaults and explicit
  # arguments use the same validation and completion descriptions.
  module ConfigurationOptions
    attr_reader :theme, :bat_theme, :shell_theme, :pager_command, :configuration_path

    def configuration_options
      @theme_name = "terminal"
      @color_depth = "auto"
      @styles = {}
      @bat_theme = "base16"
      @shell_theme = "ansi"
      @pager_enabled = true
      @parser.separator ""
      @parser.separator "Configuration and themes:"
      @parser.on("--config=FILE", "Read a YAML configuration file instead of the user default.") do |path|
        Configuration.text!(path, "Configuration path")
        @configuration_path = File.expand_path(path)
      end
      @parser.on("--no-config", "Skip the configuration file; environment options still apply.") do
        @configuration_path = nil
      end
      @parser.on("--config-path", "Print the selected configuration path; blank when disabled.") do
        @action = [:config_path]
      end
      @parser.on("--show-config", "Print effective preferences as YAML without opening documentation.") do
        @action = [:show_config]
      end
      theme_options
    end

    def theme_options
      @parser.on("--theme=NAME", Theme::NAMES, "Palette: terminal (default), dark or light.") { |name| @theme_name = name }
      @parser.on("--color-depth=DEPTH", Theme::DEPTHS,
                 "Color depth: auto (default), basic, 256 or truecolor.") do |depth|
        @color_depth = depth
      end
      @parser.on("--style=ROLE=STYLE",
                 "Override a style role; repeat for several roles. Example: method=green:bold.") do |value|
        role, style = value.split("=", 2)
        Theme.new(styles: { role => style })
        @styles[role] = style
      end
      @parser.on("--bat-theme=NAME", "bat theme for tagged non-Ruby, non-shell code (default: base16).") do |name|
        Configuration.text!(name, "bat_theme")
        @bat_theme = name
      end
      @parser.on("--shell-theme=NAME", "bat theme for shell input (default: ansi).") do |name|
        Configuration.text!(name, "shell_theme")
        @shell_theme = name
      end
      @parser.on("--pager-command=COMMAND", "Choose a trusted pager command, overriding RI_PAGER/PAGER.") do |command|
        Configuration.text!(command, "pager command")
        @pager_command = command
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

    private

    def configured_defaults(argv, defaults, enabled)
      selection = Configuration.new(argv, load: false)
      @configuration_path = selection.path
      return [] if Configuration.switches(argv).any? { |word, _| word == "--config-path" }

      words = Shellwords.split(defaults)
      @parser.parse!(words)
      @parser.parse!(Configuration.new(argv).arguments) if enabled
      words
    rescue ArgumentError, OptionParser::ParseError, SystemCallError
      raise unless recovery_request?(argv)

      initialize
      @configuration_path = selection&.path
      []
    end

    def recovery_request?(argv)
      Configuration.switches(argv).any? do |word, _|
        %w[--help -h --version -v --config-path --completion].include?(word) || word.start_with?("--completion=")
      end
    end
  end
end
