# frozen_string_literal: true

module RichRI
  # Only the user's selected file is read; documentation directories never
  # supply configuration, and YAML values are data rather than Ruby objects.
  class Configuration
    KEYS = %w[theme color color_depth width pager bat_theme shell_theme all expand_refs doc_dirs sources styles].freeze
    SOURCES = %w[system site home gems].freeze
    COLOR_MODES = %w[auto always never].freeze
    ENVIRONMENT = {
      "RICH_RI_THEME" => "theme", "RICH_RI_COLOR" => "color", "RICH_RI_COLOR_DEPTH" => "color_depth",
      "RICH_RI_WIDTH" => "width", "RICH_RI_BAT_THEME" => "bat_theme", "RICH_RI_SHELL_THEME" => "shell_theme"
    }.freeze
    # Rules and padding are built one column at a time, so the width bounds an allocation.
    WIDTH = 20..10_000

    attr_reader :path

    def initialize(file = :default, env: ENV)
      @env = env
      @path, @named = case file
                      when :default then default_path
                      when :none then [nil, false]
                      else [file, true]
                      end
    end

    # Lowest precedence first.
    def arguments
      @arguments ||= (@path && (@named || File.exist?(@path)) ? file_arguments : []) + environment_arguments
    end

    # Kernel#Integer alone would take a sign, 0x20, 1_0 and spaces, and read 040 as octal.
    def self.integer(text)
      Integer(text, 10) if text.match?(/\A(?:0|[1-9][0-9]*)\z/)
    end

    def self.text?(value)
      value.is_a?(String) && !value.strip.empty? && RichRI.printable?(value) && !value.match?(/[\r\n\t]/)
    end

    private

    def default_path
      path, origin, named = environment_path
      return [nil, false] unless path
      unless self.class.text?(path)
        raise ConfigurationError, "#{origin} must be a nonempty string without control characters"
      end

      [RichRI.expand_path(path), named]
    end

    def environment_path
      path = variable("RICH_RI_CONFIG").to_s
      return [path, "RICH_RI_CONFIG", true] unless path.empty?

      base = variable("XDG_CONFIG_HOME")
      return [File.join(base, "rich-ri/config.yml"), "XDG_CONFIG_HOME", false] if base&.start_with?("/")

      # Without a home directory there is no default file, which is not an error.
      home = variable("HOME") || RichRI.home
      [home&.start_with?("/") ? File.join(home, ".config/rich-ri/config.yml") : nil, "HOME", false]
    end

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

      key = section ? "#{section}.#{unknown.first}" : unknown.first
      raise ConfigurationError, "unknown key #{key.inspect}; choose #{keys.join(', ')}"
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
      values = { "theme" => Theme::NAMES, "color" => COLOR_MODES, "color_depth" => Theme::DEPTHS }[key]
      raise ConfigurationError, "#{name} must be one of #{values.join(', ')}" if values && !values.include?(value)

      flag = key == "pager" ? "pager-command" : key.tr("_", "-")
      key == "pager" ? ["--pager", "--#{flag}=#{value}"] : ["--#{flag}=#{value}"]
    end

    def boolean(flag, value, name = flag)
      raise ConfigurationError, "#{name} must be true or false" unless [true, false].include?(value)

      ["--#{'no-' unless value}#{flag}"]
    end

    def style(role, value, origin = nil)
      text!(value, origin || "styles.#{role}")
      Theme.new(styles: { role => value })
      ["--style=#{role}=#{value}"]
    rescue ThemeError => e
      raise ConfigurationError, [origin, e.message].compact.join(": ")
    end

    def text!(value, name)
      return if self.class.text?(value)

      raise ConfigurationError, "#{name} must be a nonempty string without control characters"
    end
  end
end
