# frozen_string_literal: true

module RichRI
  # Only the user's selected file is read; documentation directories never
  # supply configuration. File and environment values become the options the
  # command line would have used, each checked first so that a refused one is
  # reported under the file or variable it was written in.
  class Configuration
    KEYS = %w[theme color color_depth width pager bat_theme shell_theme all expand_refs doc_dirs sources styles].freeze
    SOURCES = %w[system site home gems].freeze
    ENVIRONMENT = {
      "RICH_RI_THEME" => "theme", "RICH_RI_COLOR" => "color", "RICH_RI_COLOR_DEPTH" => "color_depth",
      "RICH_RI_WIDTH" => "width", "RICH_RI_BAT_THEME" => "bat_theme", "RICH_RI_SHELL_THEME" => "shell_theme"
    }.freeze
    VALUE_OPTIONS = %w[-w --width -f --format -d --doc-dir --dump --completion --theme --color-depth
                       --style --bat-theme --shell-theme --pager-command].freeze
    # Rules and padding are built one column at a time, so an unbounded width
    # is an unbounded allocation. No terminal comes near the upper limit.
    WIDTH = 20..10_000

    attr_reader :path, :arguments

    def initialize(argv, env: ENV, load: true)
      @env = env
      @path, explicit = select_path(argv)
      @arguments = []
      return unless load

      selected = @path && (explicit || File.exist?(@path))
      @arguments = (selected ? file_arguments : []) + environment_arguments
    end

    def self.switches(argv)
      options = []
      index = 0
      while index < argv.length
        word = argv[index]
        break if word == "--"

        options << [word, argv[index + 1]]
        index += VALUE_OPTIONS.include?(word) || word == "--config" ? 2 : 1
      end
      options
    end

    # The number written as plain decimal digits, or nil. Kernel#Integer would
    # also take a sign, 0x20, 1_0 and surrounding spaces, and read 040 as octal.
    def self.integer(text)
      Integer(text, 10) if text.match?(/\A(?:0|[1-9][0-9]*)\z/)
    end

    # Whether a setting can be shown and passed on as it is: a nonempty string
    # holding no terminal control, line break or tab.
    def self.text?(value)
      value.is_a?(String) && !value.strip.empty? && RichRI.printable?(value) && !value.match?(/[\r\n\t]/)
    end

    private

    def select_path(argv)
      path, origin, explicit = default_path
      self.class.switches(argv).each do |word, argument|
        if word == "--no-config"
          path = nil
        elsif word == "--config" || word.start_with?("--config=")
          path = word == "--config" ? argument : word.split("=", 2).last
          raise UsageError, "--config requires a nonempty file path" if path.nil? || path.empty?

          origin = "--config"
          explicit = true
        end
      end
      unless path.nil? || self.class.text?(path)
        refused = origin == "--config" ? UsageError : ConfigurationError
        raise refused, "#{origin} must be a nonempty string without control characters"
      end

      [path && RichRI.expand_path(path), explicit]
    end

    # The path, where it comes from and whether the file was asked for by name.
    def default_path
      path = variable("RICH_RI_CONFIG").to_s
      return [path, "RICH_RI_CONFIG", true] unless path.empty?

      base = variable("XDG_CONFIG_HOME")
      return [File.join(base, "rich-ri/config.yml"), "XDG_CONFIG_HOME", false] if base&.start_with?("/")

      [File.join(variable("HOME") || RichRI.utf8(Dir.home), ".config/rich-ri/config.yml"), "HOME", false]
    end

    # Whatever is wrong with the file is reported after its path.
    def file_arguments
      data = ConfigurationFile.new(@path).read
      mapping!(data, KEYS)
      args = data.except("sources", "styles", "doc_dirs").flat_map { |key, value| setting(key, value) }
      args + sources(data.fetch("sources", {})) + styles(data.fetch("styles", {})) +
        directories(data.fetch("doc_dirs", []))
    rescue ConfigurationError => e
      raise ConfigurationError, "#{@path}: #{e.message}"
    end

    def mapping!(value, keys, section = nil)
      raise ConfigurationError, "#{section || 'configuration'} must be a mapping" unless value.is_a?(Hash)

      unknown = value.keys - keys
      return if unknown.empty?

      raise ConfigurationError, "unknown key #{(section ? "#{section}.#{unknown.first}" : unknown.first).inspect}"
    end

    def sources(data)
      mapping!(data, SOURCES, "sources")
      data.flat_map { |source, value| boolean(source, value, "sources.#{source}") }
    end

    def styles(data)
      mapping!(data, COLORS.keys.map(&:to_s), "styles")
      data.flat_map { |role, value| style(role, value) }
    end

    def directories(data)
      raise ConfigurationError, "doc_dirs must be a list of directory paths" unless data.is_a?(Array)

      data.flat_map do |directory|
        text!(directory, "doc_dirs")
        directory = RichRI.expand_path(directory, File.dirname(@path))
        next ["--doc-dir", directory] if File.directory?(directory)

        raise ConfigurationError, "doc_dirs must list directories, not #{directory.inspect}"
      end
    end

    # A refused value is reported under the name of its variable.
    def environment_arguments
      args = ENVIRONMENT.flat_map do |name, key|
        value = variable(name).to_s
        next [] if value.empty?

        setting(key, key == "width" ? self.class.integer(value) || value : value, name)
      end
      bat_theme = variable("BAT_THEME").to_s
      unless bat_theme.empty? || !variable("RICH_RI_BAT_THEME").to_s.empty?
        args.concat(setting("bat_theme", bat_theme, "BAT_THEME"))
      end
      pager = variable("RI_PAGER").to_s
      unless pager.empty?
        text!(pager, "RI_PAGER")
        args << "--pager-command=#{pager}"
      end
      @env.each do |name, value|
        next unless name.start_with?("RICH_RI_STYLE_") && !value.to_s.empty?

        args.concat(style(name.delete_prefix("RICH_RI_STYLE_").downcase, RichRI.utf8(value), name))
      end
      args
    end

    def variable(name)
      value = @env[name]
      value && RichRI.utf8(value)
    end

    def setting(key, value, name = key)
      return boolean(key.tr("_", "-"), value, name) if %w[all expand_refs].include?(key)
      return boolean("pager", value, name) if key == "pager" && [true, false].include?(value)

      if key == "width"
        unless value.is_a?(Integer) && WIDTH.cover?(value)
          raise ConfigurationError, "#{name} must be an integer from #{WIDTH.min} to #{WIDTH.max}"
        end
      else
        text!(value, name)
      end
      values = { "theme" => Theme::NAMES, "color" => %w[auto always never], "color_depth" => Theme::DEPTHS }[key]
      raise ConfigurationError, "#{name} must be one of #{values.join(', ')}" if values && !values.include?(value)

      flag = key == "pager" ? "pager-command" : key.tr("_", "-")
      key == "pager" ? ["--pager", "--#{flag}=#{value}"] : ["--#{flag}=#{value}"]
    end

    def boolean(flag, value, name = flag)
      raise ConfigurationError, "#{name} must be true or false" unless [true, false].include?(value)

      ["--#{'no-' unless value}#{flag}"]
    end

    def style(role, value, variable = nil)
      text!(value, variable || "styles.#{role}")
      Theme.new(styles: { role => value })
      ["--style=#{role}=#{value}"]
    rescue ThemeError => e
      raise ConfigurationError, [variable, e.message].compact.join(": ")
    end

    def text!(value, name)
      return if self.class.text?(value)

      raise ConfigurationError, "#{name} must be a nonempty string without control characters"
    end
  end
end
