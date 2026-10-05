# frozen_string_literal: true

module RichRI
  # Asks for the names of an interactive session. A person at a terminal gets
  # the line editor, with history and Tab completion. The editor draws its
  # prompt with cursor movements, so when either end is not a terminal the
  # names are read as plain lines and nothing is drawn.
  class Prompt
    TEXT = ">> "
    FAILURES = 3

    # The completion answers the candidates for the word being typed.
    def initialize(completion)
      @completion = completion
    end

    # The next name, or nil at a blank line or the end of input.
    def read
      name = RichRI.utf8($stdin.tty? && $stdout.tty? ? edit : $stdin.gets).strip
      name unless name.empty?
    end

    private

    def edit
      Reline.completion_proc = @completion
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
  end
end
