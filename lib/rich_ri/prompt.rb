# frozen_string_literal: true

module RichRI
  # The line editor draws with cursor movements, so unless both ends are terminals names are
  # read as plain lines.
  class Prompt
    TEXT = ">> "
    FAILURES = 3

    def initialize(completion)
      @completion = completion
      @pasted = []
    end

    def read
      return @pasted.shift unless @pasted.empty?

      # The editor takes line breaks in a bracketed paste for text: several names arrive as one line.
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
        # Completion fails inside the editor; ask again, but not forever, or a broken prompt would spin.
        raise if (failures += 1) == FAILURES

        Error.report(e)
        retry
      end
    end

    # Reline completes only what follows the last space, quote or one of "<>=;|&{(`", which after
    # "Array#<" or "Hash#=" is nothing; the line is one name.
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
