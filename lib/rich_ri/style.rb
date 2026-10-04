# frozen_string_literal: true

require_relative "color"

module RichRI
  # Parse a small declarative style language, never arbitrary ANSI sequences.
  class Style
    ATTRIBUTES = { "bold" => "1", "dim" => "2", "italic" => "3", "underline" => "4",
                   "reverse" => "7", "strike" => "9" }.freeze

    def initialize(value)
      unless value.is_a?(String) && !value.empty? && RichRI.sanitize(value) == value
        raise ArgumentError, "style must be a nonempty string without control characters"
      end

      @parts = []
      return if value == "none"

      seen = {}
      value.split(":", -1).each do |token|
        key, part = parse_token(token)
        raise ArgumentError, "duplicate #{key} in style #{value.inspect}" if seen[key]

        seen[key] = true
        @parts << [key, part]
      end
    end

    def sgr(depth)
      @parts.map do |key, part|
        part.is_a?(Color) ? part.sgr(depth, background: key == "bg") : part
      end.join(";")
    end

    private

    def parse_token(token)
      return [token, ATTRIBUTES.fetch(token)] if ATTRIBUTES.key?(token)

      key, value = token.include?("=") ? token.split("=", 2) : ["fg", token]
      unless %w[fg bg].include?(key)
        raise ArgumentError, "unknown style property #{key.inspect}; use fg, bg or a text attribute"
      end

      [key, Color.new(value)]
    end
  end
end
