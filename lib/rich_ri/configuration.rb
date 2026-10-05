# frozen_string_literal: true

module RichRI
  # Only the user's selected file is read; documentation directories never
  # supply configuration, and YAML values are data rather than Ruby objects.
  class Configuration
    KEYS = %w[theme color color_depth width pager bat_theme shell_theme all expand_refs doc_dirs sources styles].freeze
    SOURCES = %w[system site home gems].freeze
    ENVIRONMENT = {
      "RICH_RI_THEME" => "theme", "RICH_RI_COLOR" => "color", "RICH_RI_COLOR_DEPTH" => "color_depth",
      "RICH_RI_WIDTH" => "width", "RICH_RI_BAT_THEME" => "bat_theme", "RICH_RI_SHELL_THEME" => "shell_theme"
    }.freeze
    VALUE_OPTIONS = %w[-w --width -f --format -d --doc-dir --dump --completion --theme --color-depth
                       --style --bat-theme --shell-theme --pager-command].freeze
    MAX_BYTES = 65_536

    attr_reader :path, :arguments

    def initialize(argv, env: ENV, load: true)
      @env = env
      @path, explicit = select_path(argv)
      @arguments = []
      return unless load

      data = @path && (explicit || File.exist?(@path)) ? read_file : {}
      @arguments = file_arguments(data) + environment_arguments
    rescue Psych::Exception => e
      raise ConfigurationError, "Invalid configuration #{@path}: #{e.message}"
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

    # Whether a setting can be shown and passed on as it is: a nonempty string
    # holding no terminal control, line break or tab.
    def self.text?(value)
      value.is_a?(String) && !value.strip.empty? && RichRI.sanitize(value) == value && !value.match?(/[\r\n\t]/)
    end

    private

    def select_path(argv)
      base = @env["XDG_CONFIG_HOME"]
      base = File.join(@env.fetch("HOME") { Dir.home }, ".config") unless base&.start_with?("/")
      explicit = !@env.fetch("RICH_RI_CONFIG", "").empty?
      path = explicit ? @env.fetch("RICH_RI_CONFIG") : File.join(base, "rich-ri/config.yml")
      refused = ConfigurationError
      self.class.switches(argv).each do |word, argument|
        if word == "--no-config"
          path = nil
        elsif word == "--config" || word.start_with?("--config=")
          path = word == "--config" ? argument : word.split("=", 2).last
          raise UsageError, "--config requires a nonempty file path" if path.nil? || path.empty?

          explicit = true
          refused = UsageError
        end
      end
      unless path.nil? || self.class.text?(path)
        raise refused, "Configuration path must be a nonempty string without control characters"
      end

      [path && File.expand_path(path), explicit]
    end

    def read_file
      raise ConfigurationError, "Configuration is not a readable regular file: #{@path}" unless File.file?(@path)

      content = File.read(@path, MAX_BYTES + 1)
      raise ConfigurationError, "Configuration exceeds #{MAX_BYTES} bytes: #{@path}" if content.bytesize > MAX_BYTES

      stream = Psych.parse_stream(content, filename: @path)
      raise ConfigurationError, "Configuration must contain one YAML document: #{@path}" if stream.children.length > 1

      check_duplicate_keys(stream)
      data = Psych.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false, filename: @path)
      data = {} if data.nil?
      mapping!(data, KEYS, "configuration")
      data
    end

    def check_duplicate_keys(root)
      pending = [[root, 0]]
      until pending.empty?
        node, depth = pending.pop
        raise ConfigurationError, "Configuration nesting exceeds 20 levels: #{@path}" if depth > 20

        if node.is_a?(Psych::Nodes::Mapping)
          keys = node.children.each_slice(2).map { |key, _value| key.value if key.is_a?(Psych::Nodes::Scalar) }
          raise ConfigurationError, "Duplicate configuration key in #{@path}" unless keys.uniq.length == keys.length
        end
        pending.concat(Array(node.children).map { |child| [child, depth + 1] })
      end
    end

    def mapping!(value, keys, context)
      raise ConfigurationError, "#{context} must be a mapping" unless value.is_a?(Hash)

      unknown = value.keys - keys
      raise ConfigurationError, "Unknown #{context} key: #{unknown.first.inspect}" unless unknown.empty?
    end

    def file_arguments(data)
      args = data.except("sources", "styles", "doc_dirs").flat_map { |key, value| setting(key, value) }
      sources = data.fetch("sources", {})
      mapping!(sources, SOURCES, "sources")
      args.concat(sources.flat_map { |key, value| boolean(key, value) })
      styles = data.fetch("styles", {})
      mapping!(styles, COLORS.keys.map(&:to_s), "styles")
      args.concat(styles.flat_map { |key, value| style(key, value) })
      directories = data.fetch("doc_dirs", [])
      raise ConfigurationError, "doc_dirs must be a list of directory paths" unless directories.is_a?(Array)

      directories.each do |directory|
        text!(directory, "doc_dirs")
        args.push("--doc-dir", File.expand_path(directory, File.dirname(@path)))
      end
      args
    end

    def environment_arguments
      args = ENVIRONMENT.flat_map do |name, key|
        value = @env[name]
        next [] if value.nil? || value.empty?

        setting(key, key == "width" && value.match?(/\A[0-9]+\z/) ? value.to_i : value)
      end
      args.concat(setting("bat_theme", @env["BAT_THEME"])) if @env["BAT_THEME"] && !@env["BAT_THEME"].empty? &&
                                                              @env.fetch("RICH_RI_BAT_THEME", "").empty?
      unless @env.fetch("RI_PAGER", "").empty?
        text!(@env["RI_PAGER"], "RI_PAGER")
        args << "--pager-command=#{@env['RI_PAGER']}"
      end
      @env.each do |name, value|
        next unless name.start_with?("RICH_RI_STYLE_") && !value.to_s.empty?

        args.concat(style(name.delete_prefix("RICH_RI_STYLE_").downcase, value))
      end
      args
    end

    def setting(key, value)
      return boolean(key.tr("_", "-"), value) if %w[all expand_refs].include?(key)
      return boolean("pager", value) if key == "pager" && [true, false].include?(value)

      if key == "width"
        raise ConfigurationError, "width must be an integer of at least 20" unless value.is_a?(Integer) && value >= 20
      else
        text!(value, key)
      end
      values = { "theme" => Theme::NAMES, "color" => %w[auto always never], "color_depth" => Theme::DEPTHS }[key]
      raise ConfigurationError, "#{key} must be one of: #{values.join(', ')}" if values && !values.include?(value)

      flag = key == "pager" ? "pager-command" : key.tr("_", "-")
      key == "pager" ? ["--pager", "--#{flag}=#{value}"] : ["--#{flag}=#{value}"]
    end

    def boolean(key, value)
      raise ConfigurationError, "#{key} must be true or false" unless [true, false].include?(value)

      ["--#{'no-' unless value}#{key}"]
    end

    def style(role, value)
      text!(value, "style #{role}")
      Theme.new(styles: { role => value })
      ["--style=#{role}=#{value}"]
    rescue ThemeError => e
      raise ConfigurationError, e.message
    end

    def text!(value, name)
      return if self.class.text?(value)

      raise ConfigurationError, "#{name} must be a nonempty string without control characters"
    end
  end
end
