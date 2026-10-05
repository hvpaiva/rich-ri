# frozen_string_literal: true

module RichRI
  # A pager or man(1) shares the foreground process group, so Ctrl-C reaches both; leaving first
  # would orphan a child holding the terminal in raw mode.
  module Signals
    def self.defer_interrupt(active = -> { true })
      interrupted = false
      # Not "IGNORE": the child would inherit it, and less could not stop a search with Ctrl-C.
      previous = trap("INT") do
        raise Interrupt unless active.call

        interrupted = true
      end
      yield
      interrupted
    ensure
      trap("INT", previous || "DEFAULT")
    end

    def self.killed?
      Process.last_status&.signaled? || false
    end
  end
end
