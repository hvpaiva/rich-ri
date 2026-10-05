# frozen_string_literal: true

require_relative "errors"

module RichRI
  # Explicit colors degrade to the closest xterm palette entry. Named ANSI
  # colors stay symbolic so terminal themes retain control over their palette.
  class Color
    NAMES = %w[black red green yellow blue magenta cyan white].freeze
    BASIC = [
      [0, 0, 0], [128, 0, 0], [0, 128, 0], [128, 128, 0],
      [0, 0, 128], [128, 0, 128], [0, 128, 128], [192, 192, 192],
      [128, 128, 128], [255, 0, 0], [0, 255, 0], [255, 255, 0],
      [0, 0, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255]
    ].map(&:freeze).freeze
    CUBE = [0, 95, 135, 175, 215, 255].freeze
    PALETTE = (BASIC + CUBE.repeated_permutation(3).to_a +
      Array.new(24) { |index| Array.new(3, 8 + (index * 10)) }).map(&:freeze).freeze

    def initialize(value)
      @value = value
      @index = NAMES.index(value.delete_prefix("bright_"))
      @index += 8 if @index && value.start_with?("bright_")
      @number = value.to_i if value.match?(/\A(?:0|[1-9]\d{0,2})\z/) && value.to_i <= 255
      @rgb = value.delete_prefix("#").scan(/../).map { |part| part.to_i(16) } if value.match?(/\A#[0-9a-fA-F]{6}\z/)
      return if @index || @number || @rgb || value == "default"

      raise ThemeError, "invalid color #{value.inspect}; use an ANSI name, 0..255, #RRGGBB or default"
    end

    def sgr(depth, background: false)
      return background ? "49" : "39" if @value == "default"
      return basic(@index, background:) if @index

      rgb = @rgb || PALETTE.fetch(@number)
      return basic(nearest(rgb, BASIC), background:) if depth == "basic"

      prefix = background ? "48" : "38"
      return "#{prefix};5;#{@number || nearest(rgb, PALETTE)}" if depth == "256" || @number

      "#{prefix};2;#{rgb.join(';')}"
    end

    private

    def basic(index, background:)
      ((index < 8 ? 30 : 90) + (index % 8) + (background ? 10 : 0)).to_s
    end

    def nearest(rgb, palette)
      palette.each_index.min_by do |index|
        palette[index].zip(rgb).sum { |candidate, channel| (candidate - channel)**2 }
      end
    end
  end
end
