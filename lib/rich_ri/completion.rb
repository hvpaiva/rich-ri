# frozen_string_literal: true

module RichRI
  # The protocol is tab-separated value/description pairs. The words are read
  # by the parser of the command itself, so that what is offered is what the
  # command accepts, but only the choice of sources reaches the driver:
  # pressing Tab can never start a pager, server or cache dump.
  class Completion
    SHELLS = %w[bash zsh fish].freeze

    def write(words, io)
      # Bound discovery even when a documentation store is unusually large.
      Timeout.timeout(4) do
        words = words.drop(1).map { |word| shell_word(word) } if %w[--shell=bash --shell=zsh].include?(words.first)
        candidates(words).each do |value, description|
          next if [value, description].any? { |text| text.match?(/[\t\r\n]/) || !RichRI.printable?(text) }

          io.puts "#{value}\t#{description}"
        end
      end
    rescue StandardError
      # A broken/missing RI store must not interrupt shell input.
      nil
    end

    def candidates(words)
      return [] if words[0...-1].include?("--install-man")

      current, option, prefix = context(words)
      values = option_values(option, current)
      values ||= if current.start_with?("-") && !words[0...-1].include?("--")
                   Options.new.entries
                 else
                   names(words[0...-1], current).map { |v| [v, ""] }
                 end
      values.select { |value, _| value.start_with?(current) }
            .map { |value, desc| [prefix + value, desc] }.uniq.sort
    end

    private

    def option_values(option, current)
      case option
      when nil then nil
      when "--color" then Configuration::COLOR_MODES.map { |v| [v, "Color mode"] }
      when "--format", "-f" then Options.formats.map { |v| [v, "RDoc formatter"] }
      when "--completion" then SHELLS.map { |v| [v, "Shell completion script"] }
      when "--theme" then Theme::NAMES.map { |v| [v, "Page theme"] }
      when "--color-depth" then Theme::DEPTHS.map { |v| [v, "Terminal color depth"] }
      when "--style" then styles(current)
      when "--config" then paths(current)
      when "--doc-dir", "-d", "--install-man" then directories(current)
      else []
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

    # The word being typed, the option it is the value of and what precedes
    # that value in the word.
    def context(words)
      current = words.last || ""
      return [current, awaited_option(words[0...-1]), ""] unless current.start_with?("--") && current.include?("=")

      option, value = current.split("=", 2)
      [value, option, "#{option}="]
    end

    # The option whose value is the next word, as the parser reads the words
    # so far. It is none after "--", after an option whose value is optional
    # and comes only with "=", or when the last word was itself a value.
    def awaited_option(words)
      Options.new.parser.permute(words)
      nil
    rescue OptionParser::MissingArgument => e
      e.args.first
    rescue StandardError
      nil
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

    # A command line the reader refuses has no names to offer: it is read
    # here as the lookup would read it, with RI and the configuration under it
    # and the name being typed at its end, which --interactive does not take.
    def names(words, prefix)
      options = Options.new.parse([*words, prefix]).driver_options
      sources = options.slice(*Driver::STANDARD_SOURCES, :extra_doc_dirs)
      Driver.new(sources.merge(use_stdout: true)).complete(prefix)
    end
  end
end
