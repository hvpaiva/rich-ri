# frozen_string_literal: true

module RichRI
  # The protocol is tab-separated value/description pairs. Only source options
  # reach the driver: pressing Tab can never start a pager, server or cache dump.
  class Completion
    SOURCES = /\A--(?:no-)?(?:system|site|home|gems|standard-docs)\z/
    VALUES = %w[-w --width --server --dump].freeze

    def write(words, io)
      # Bound discovery even when a documentation store is unusually large.
      Timeout.timeout(4) do
        candidates(words).each do |value, description|
          next if [value, description].any? { |text| text.match?(/[\x00-\x1f\x7f]/) }

          io.puts "#{value}\t#{description}"
        end
      end
    rescue StandardError
      # A broken/missing RI store must not interrupt shell input.
      nil
    end

    def candidates(words)
      current, previous, prefix = context(words)
      values = case previous
               when "--color" then %w[auto always never].map { |v| [v, "Color mode"] }
               when "--format", "-f" then Options.formats.map { |v| [v, "RDoc formatter"] }
               when "--completion" then %w[bash zsh fish].map { |v| [v, "Shell completion script"] }
               when "--doc-dir", "-d" then directories(current)
               when *VALUES then []
               else
                 if current.start_with?("-") && !words[0...-1].include?("--")
                   Options.new.entries
                 else
                   names(words[0...-1], current).map { |v| [v, ""] }
                 end
               end
      values.select { |value, _| value.start_with?(current) }
            .map { |value, desc| [prefix + value, desc] }.uniq.sort
    end

    private

    def context(words)
      current = words.last || ""
      previous = words[-2]
      prefix = ""
      if current.start_with?("--") && current.include?("=")
        previous, current = current.split("=", 2)
        prefix = "#{previous}="
      elsif previous == "--color"
        # The bare switch forces color; it does not consume the next name.
        previous = nil
      end
      [current, previous, prefix]
    end

    def directories(prefix)
      # Escape glob metacharacters typed by the user; do not interpret patterns.
      escaped = prefix.gsub(/[\[\]{}*?\\]/) { |char| "\\#{char}" }
      paths = Dir.glob("#{escaped}*").select { |path| File.directory?(path) }
      paths.map { |path| ["#{path}/", "Documentation directory"] }
    end

    def names(words, prefix)
      args = []
      index = 0
      while index < words.length
        word = words[index]
        break if word == "--"

        if word.match?(SOURCES) || word.start_with?("--doc-dir=") || (word.start_with?("-d") && word.length > 2)
          args << word
        elsif %w[--doc-dir -d].include?(word)
          args.concat(words[index, 2])
          index += 1
        end
        index += 1
      end
      options = Options.new.parse(args, defaults: "").driver_options
      Driver.new(options.merge(use_stdout: true, interactive: false)).complete(prefix)
    end
  end
end
