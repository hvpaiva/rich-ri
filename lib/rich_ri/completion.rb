# frozen_string_literal: true

module RichRI
  # The protocol is tab-separated value/description pairs. Only source options
  # reach the driver: pressing Tab can never start a pager, server or cache dump.
  class Completion
    SOURCES = /\A--(?:no-)?(?:system|site|home|gems|standard-docs)\z/
    VALUES = %w[-w --width --server --dump --bat-theme --shell-theme --pager-command].freeze

    def write(words, io)
      # Bound discovery even when a documentation store is unusually large.
      Timeout.timeout(4) do
        words = words.drop(1).map { |word| shell_word(word) } if %w[--shell=bash --shell=zsh].include?(words.first)
        candidates(words).each do |value, description|
          next if [value, description].any? { |text| text.match?(/[\t\r\n]/) || RichRI.sanitize(text) != text }

          io.puts "#{value}\t#{description}"
        end
      end
    rescue StandardError
      # A broken/missing RI store must not interrupt shell input.
      nil
    end

    def candidates(words)
      return [] if words[0...-1].include?("--install-man")

      current, previous, prefix = context(words)
      values = option_values(previous, current)
      values ||= if current.start_with?("-") && !words[0...-1].include?("--")
                   Options.new.entries
                 else
                   names(words[0...-1], current).map { |v| [v, ""] }
                 end
      values.select { |value, _| value.start_with?(current) }
            .map { |value, desc| [prefix + value, desc] }.uniq.sort
    end

    private

    def option_values(previous, current)
      case previous
      when "--color" then %w[auto always never].map { |v| [v, "Color mode"] }
      when "--format", "-f" then Options.formats.map { |v| [v, "RDoc formatter"] }
      when "--completion" then %w[bash zsh fish].map { |v| [v, "Shell completion script"] }
      when "--theme" then Theme::NAMES.map { |v| [v, "Page theme"] }
      when "--color-depth" then Theme::DEPTHS.map { |v| [v, "Terminal color depth"] }
      when "--style" then styles(current)
      when "--config" then paths(current)
      when "--doc-dir", "-d", "--install-man" then directories(current)
      when *VALUES then []
      end
    end

    def shell_word(word)
      # Bash and Zsh retain quotes in their words. Shellwords removes them without
      # evaluating substitutions; the current word may have an unclosed quote.
      ["", "'", '"'].each do |suffix|
        parts = Shellwords.split(word + suffix)
        return parts.first.to_s if parts.length <= 1
      rescue ArgumentError
        next
      end
      word
    end

    def context(words)
      current = words.last || ""
      previous = words[-2]
      prefix = ""
      if current.start_with?("--") && current.include?("=")
        previous, current = current.split("=", 2)
        prefix = "#{previous}="
      elsif previous == "--color"
        # Optional values require '='; a bare switch does not consume a name.
        previous = nil
      end
      [current, previous, prefix]
    end

    def styles(prefix)
      return [] if prefix.include?("=")

      RichRI::COLORS.keys.map { |role| ["#{role}=", "Override #{role} style"] }
    end

    def directories(prefix)
      paths(prefix, directories_only: true).map { |path, _description| [path, "Documentation directory"] }
    end

    def paths(prefix, directories_only: false)
      # Escape glob metacharacters typed by the user; do not interpret patterns.
      escaped = prefix.gsub(/[\[\]{}*?\\]/) { |char| "\\#{char}" }
      Dir.glob("#{escaped}*").filter_map do |path|
        directory = File.directory?(path)
        next if directories_only && !directory
        next unless directory || File.file?(path)

        [directory ? "#{path}/" : path, directory ? "Directory" : "Configuration file"]
      end
    end

    def names(words, prefix)
      defaults = Shellwords.split(ENV.fetch("RI", ""))
      configured = Configuration.new(words).arguments
      args = [defaults, configured, words].flat_map { |layer| source_arguments(layer) }
      options = Options.new.parse(args, defaults: "", configuration: false).driver_options
      Driver.new(options.merge(use_stdout: true, interactive: false)).complete(prefix)
    end

    def source_arguments(words)
      args = []
      flags = Options.new.entries.map { |flag, _description| flag.delete_suffix("=") }
      index = 0
      while index < words.length
        word = words[index]
        break if word == "--"

        raise OptionParser::InvalidOption, word if word.start_with?("--") && !flags.include?(word.split("=", 2).first)

        if word.match?(SOURCES) || word.start_with?("--doc-dir=") || (word.start_with?("-d") && word.length > 2)
          args << word
        elsif %w[--doc-dir -d].include?(word)
          args.concat(words[index, 2])
          index += 1
        elsif Configuration::VALUE_OPTIONS.include?(word) || word == "--config"
          # An option value that resembles a source flag is still just data.
          index += 1
        end
        index += 1
      end
      args
    end
  end
end
