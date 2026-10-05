# frozen_string_literal: true

module RichRI
  # Asks for the names of an interactive session. A person at a terminal gets
  # the line editor, with history and Tab completion. The editor draws its
  # prompt with cursor movements, so when either end is not a terminal the
  # names are read as plain lines and nothing is drawn.
  class Prompt
    TEXT = ">> "
    FAILURES = 3

    # The completion answers the candidates for the name being typed.
    def initialize(completion)
      @completion = completion
      @pasted = []
    end

    # The next name, or nil at a blank line or the end of input.
    def read
      return @pasted.shift unless @pasted.empty?

      # A terminal marks what is pasted, and the editor then takes its line
      # breaks for text: several names arrive as one line.
      text = RichRI.utf8($stdin.tty? && $stdout.tty? ? edit : $stdin.gets)
      name, *@pasted = text.lines.map(&:strip).reject(&:empty?)
      name
    end

    private

    def edit
      complete_whole_line
      failures = 0
      begin
        Reline.readline(TEXT, true)
      rescue IOError, SystemCallError
        raise
      rescue StandardError => e
        # Completion runs inside the line editor. Show its failure and ask
        # again, but not forever: a prompt that cannot start would spin.
        raise if (failures += 1) == FAILURES

        Error.report(e)
        retry
      end
    end

    # The line is one name. The editor would complete only what follows the
    # last space, quote or one of "<>=;|&{(`", as a shell does with a command,
    # and after "Array#<" or "Hash#=" that is nothing at all.
    def complete_whole_line
      Reline.completer_word_break_characters = ""
      Reline.completer_quote_characters = ""
      Reline.completion_proc = method(:candidates)
    end

    def candidates(line)
      indentation = line[/\A\s*/]
      @completion.call(line.delete_prefix(indentation)).map { |name| indentation + name }
    end
  end
end
