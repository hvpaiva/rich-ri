# frozen_string_literal: true

module RichRI
  # The protocol is one "value<TAB>description" line per candidate and a last line for the script:
  # ":" offers them, ":nospace" offers the only one as the start of a word, and ":files" or
  # ":directories" leave the word to the shell, which knows "~", its variables and its quoting.
  # Only source options reach the driver: pressing Tab can never start a pager, server or cache dump.
  class Completion
    SHELLS = %w[bash zsh fish].freeze
    PATHS = { "--config" => "files", "--dump" => "files", "--doc-dir" => "directories", "-d" => "directories",
              "--install-man" => "directories" }.freeze
    # A candidate that only starts a word, such as "Class#", "source:" or "--option="; a method
    # name may itself end in "=", after one of the other marks.
    UNFINISHED = /[:#.]\z|\A[^:#.]*=\z/

    Answer = Struct.new(:candidates, :action)

    def write(words, io)
      io.puts lines(words)
    end

    def answer(words)
      current, option, prefix = context(words)
      return Answer.new([], PATHS.fetch(option)) if PATHS.key?(option)

      values = option ? option_values(option, current) : word_values(words[0...-1], current)
      found = values.select { |value, _| value.start_with?(current) }
                    .map { |value, description| [prefix + value, description] }.uniq.sort
      Answer.new(found, ("nospace" if found.one? && found.first.first.match?(UNFINISHED)))
    end

    private

    def lines(words)
      # Bound discovery even when a documentation store is unusually large.
      Timeout.timeout(4) do
        words = words.drop(1).map { |word| shell_word(word) } if %w[--shell=bash --shell=zsh].include?(words.first)
        found = answer(words)
        # A line break or a tab inside a candidate would pass for the protocol's own.
        shown = found.candidates.reject do |pair|
          pair.any? { |text| text.match?(Driver::LAYOUT_CONTROLS) || !RichRI.printable?(text) }
        end
        [*shown.map { |value, description| "#{value}\t#{description}" }, ":#{found.action}"]
      end
    rescue StandardError
      # A broken/missing RI store must not interrupt shell input.
      [":"]
    end

    def option_values(option, current)
      case option
      when "--color" then Configuration::COLOR_MODES.map { |v| [v, "Color mode"] }
      when "--format", "-f" then Options.formats.map { |v| [v, "RDoc formatter"] }
      when "--completion" then SHELLS.map { |v| [v, "Shell completion script"] }
      when "--theme" then Theme::NAMES.map { |v| [v, "Page theme"] }
      when "--color-depth" then Theme::DEPTHS.map { |v| [v, "Terminal color depth"] }
      when "--style" then styles(current)
      else []
      end
    end

    def word_values(before, current)
      return Options.new.entries if current.start_with?("-") && !before.include?("--")

      names(before, current).map { |name| [name, ""] }
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

    # The word being typed, the option it is the value of and the text before that value.
    def context(words)
      current = words.last || ""
      return [current, awaited_option(words[0...-1]), ""] unless current.start_with?("--") && current.include?("=")

      option, value = current.split("=", 2)
      [value, option, "#{option}="]
    end

    # None after "--", after an option whose optional value comes only with "=", or after a value.
    def awaited_option(words)
      Options.new.parser.permute(words)
      nil
    rescue OptionParser::MissingArgument => e
      e.args.first
    rescue OptionParser::ParseError, Error
      nil
    end

    def styles(prefix)
      return [] if prefix.include?("=")

      RichRI::COLORS.keys.map { |role| ["#{role}=", "Override #{role} style"] }
    end

    # Read as the lookup reads it, with RI and the configuration, so a command line it refuses,
    # such as --interactive with the name being typed, offers no names.
    def names(words, prefix)
      options = Options.new.parse([*words, prefix]).driver_options
      sources = options.slice(*Driver::STANDARD_SOURCES, :extra_doc_dirs)
      Driver.new(sources.merge(use_stdout: true)).complete(prefix)
    end
  end
end
