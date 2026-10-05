# frozen_string_literal: true

module RichRI
  # A pager or man(1) shares the terminal's foreground process group with this
  # process, so Ctrl-C reaches both. Leaving first would orphan a child that
  # still holds the terminal in raw mode while the shell takes it back.
  module Signals
    # Runs the block with Ctrl-C only recorded for as long as active says such
    # a child is running, so that the child decides what the key means;
    # otherwise Ctrl-C interrupts as usual. Returns whether it was recorded.
    def self.defer_interrupt(active = -> { true })
      interrupted = false
      # A handler block, not "IGNORE": an ignored signal would be inherited by
      # the child, and less then could not stop a search with Ctrl-C either.
      previous = trap("INT") do
        raise Interrupt unless active.call

        interrupted = true
      end
      yield
      interrupted
    ensure
      trap("INT", previous || "DEFAULT")
    end

    # Whether the child just waited for was ended by a signal. A child that
    # handled Ctrl-C and exited by itself leaves the command a normal exit.
    def self.killed?
      Process.last_status&.signaled? || false
    end
  end
end
