# frozen_string_literal: true

module RichRI
  # Answers a shell that asks what may follow the words typed so far. The
  # answer is one candidate a line, as "value<TAB>description", and a last
  # line saying what the script is to do: ":" offers the candidates,
  # ":nospace" offers the only one as the start of a longer word, and
  # ":files" or ":directories" leave the word to the shell, which completes
  # the name of a file better than this could: it knows "~", its variables and
  # its own quoting.
  #
  # The words are read by the parser of the command itself, so that what is
  # offered is what the command accepts, but only the choice of sources
  # reaches the driver: pressing Tab can never start a pager, server or cache dump.
  class Completion
    SHELLS = %w[bash zsh fish].freeze
    # The options whose value is a path, and what the shell completes there.
    PATHS = { "--config" => "files", "--dump" => "files", "--doc-dir" => "directories", "-d" => "directories",
              "--install-man" => "directories" }.freeze
    # A candidate that only starts a word: a class before its method, a source
    # before its page, an option or a style role before its value. A method
    # name may itself end in "=", after one of the other marks.
    UNFINISHED = /[:#.]\z|\A[^:#.]*=\z/

    # Candidates, each a value and its description, and what to do with them.
    Answer = Struct.new(:candidates, :action)

    def write(words, io)
      io.puts lines(words)
    end

    def answer(words)
      return Answer.new([], nil) if words[0...-1].include?("--install-man")

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
          pair.any? { |text| text.match?(/[\t\r\n]/) || !RichRI.printable?(text) }
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
    rescue OptionParser::ParseError, Error
      nil
    end

    def styles(prefix)
      return [] if prefix.include?("=")

      RichRI::COLORS.keys.map { |role| ["#{role}=", "Override #{role} style"] }
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
