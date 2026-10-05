# frozen_string_literal: true

module RichRI
  # Reads the selected YAML file as plain data: a single document of bounded
  # size and depth, with no alias, object tag or duplicate key. What is wrong
  # is described without the path, which Configuration puts in front.
  class ConfigurationFile
    MAX_BYTES = 65_536
    MAX_DEPTH = 20

    def initialize(path)
      @path = path
    end

    def read
      raise ConfigurationError, "not a readable regular file" unless File.file?(@path)

      content = File.read(@path, MAX_BYTES + 1)
      raise ConfigurationError, "larger than #{MAX_BYTES} bytes" if content.bytesize > MAX_BYTES

      stream = Psych.parse_stream(content, filename: @path)
      raise ConfigurationError, "must contain a single YAML document" if stream.children.length > 1

      check_structure(stream)
      Psych.safe_load(content, permitted_classes: [], permitted_symbols: [], aliases: false, filename: @path) || {}
    rescue Psych::Exception => e
      raise ConfigurationError, problem(e)
    end

    private

    # Psych words its messages for the programmer calling it and repeats the path.
    def problem(error)
      case error
      when Psych::SyntaxError
        "invalid YAML at line #{error.line} column #{error.column}: #{[error.problem, error.context].compact.join(' ')}"
      when Psych::BadAlias then "YAML aliases are not accepted"
      when Psych::DisallowedClass then "YAML tags that create objects are not accepted"
      else error.message
      end
    end

    def check_structure(root)
      pending = [[root, 0]]
      until pending.empty?
        node, depth = pending.pop
        raise ConfigurationError, "nesting deeper than #{MAX_DEPTH} levels" if depth > MAX_DEPTH

        check_keys(node) if node.is_a?(Psych::Nodes::Mapping)
        pending.concat(Array(node.children).map { |child| [child, depth + 1] })
      end
    end

    def check_keys(mapping)
      keys = mapping.children.each_slice(2).map { |key, _value| key.value if key.is_a?(Psych::Nodes::Scalar) }
      return if keys.uniq.length == keys.length

      raise ConfigurationError, "duplicate key #{keys.find { |key| keys.count(key) > 1 }.inspect}"
    end
  end
end
