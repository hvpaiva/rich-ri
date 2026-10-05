# frozen_string_literal: true

require_relative "ansi"
require_relative "style"

module RichRI
  class Theme
    NAMES = %w[terminal dark light].freeze
    DEPTHS = %w[auto basic 256 truecolor].freeze
    ROLES = COLORS.keys.freeze
    PALETTES = {
      "dark" => {
        title: "fg=#80d4ff:bold", heading: "fg=#82aaff:bold", subheading: "fg=#c792ea:bold",
        code: "#89ddff", reference: "#89ddff", link: "fg=#89ddff:underline", label: "fg=#ffcb6b:bold",
        muted: "#a6accd", keyword: "#c792ea", string: "#c3e88d", number: "#f78c6c", constant: "#ffcb6b",
        symbol: "#ffcb6b", method: "#82aaff", comment: "#a6accd", operator: "#c792ea"
      }.freeze,
      "light" => {
        title: "fg=#005a8b:bold", heading: "fg=#244fbd:bold", subheading: "fg=#7634a2:bold",
        code: "#006b75", reference: "#006b75", link: "fg=#005a8b:underline", label: "fg=#885b00:bold",
        muted: "#606060", keyword: "#7634a2", string: "#226b2f", number: "#a14300", constant: "#885b00",
        symbol: "#885b00", method: "#005a8b", comment: "#606060", operator: "#7634a2"
      }.freeze
    }.freeze

    attr_reader :name, :depth

    def initialize(name: "terminal", styles: {}, depth: "auto", env: ENV)
      raise ArgumentError, "unknown theme #{name.inspect}; choose #{NAMES.join(', ')}" unless NAMES.include?(name)
      unless DEPTHS.include?(depth)
        raise ArgumentError, "unknown color depth #{depth.inspect}; choose #{DEPTHS.join(', ')}"
      end
      raise ArgumentError, "styles must be a mapping of roles to style strings" unless styles.is_a?(Hash)

      @name = name.dup.freeze
      @depth = (depth == "auto" ? self.class.detect_depth(env) : depth).dup.freeze
      @styles = COLORS.dup
      # Sixteen colors cannot tell the shades of a preset apart; the terminal's own palette can.
      apply_styles(PALETTES.fetch(name, {})) unless @depth == "basic"
      apply_styles(styles)
      @styles.transform_values!(&:freeze)
      @styles.freeze
      freeze
    end

    def self.detect_depth(env)
      return "truecolor" if %w[truecolor 24bit].include?(env["COLORTERM"].to_s.downcase)
      return "256" if env["TERM"].to_s.include?("256color")

      "basic"
    end

    def sgr(role)
      unless (role.is_a?(String) || role.is_a?(Symbol)) && @styles.key?(role.to_sym)
        raise ArgumentError, "unknown style role #{role.inspect}; choose #{ROLES.join(', ')}"
      end

      @styles.fetch(role.to_sym)
    end

    def paint(text, *roles, enabled: true)
      return text unless enabled && !roles.empty?

      codes = roles.map { |role| sgr(role) }.reject(&:empty?).join(";")
      return text if codes.empty?

      text.gsub(/\S+/) { |word| "\e[#{codes}m#{word}#{RESET}" }
    end

    private

    def apply_styles(styles)
      seen = {}
      styles.each do |role, value|
        unless (role.is_a?(String) || role.is_a?(Symbol)) && ROLES.include?(role.to_sym)
          raise ArgumentError, "unknown style role #{role.inspect}; choose #{ROLES.join(', ')}"
        end

        key = role.to_sym
        raise ArgumentError, "duplicate style role #{role.inspect}" if seen[key]

        seen[key] = true
        @styles[key] = Style.new(value).sgr(@depth)
      rescue ArgumentError => e
        raise ArgumentError, "style #{role.inspect}: #{e.message}"
      end
    end
  end
end
