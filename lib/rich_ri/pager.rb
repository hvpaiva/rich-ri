# frozen_string_literal: true

module RichRI
  # The program a page is read in. A pager the user named, with
  # --pager-command, the pager key, RI_PAGER or PAGER, has to start and to end
  # well: passing over it for another, or losing the page with it, would look
  # like success. When none is named the usual programs are tried in turn, and
  # without any of them the page goes straight to the terminal.
  #
  # The command is split into words as a shell would split it and then run
  # directly. No shell reads it, so a pipe, a variable or a redirection in it
  # is one more word for the pager.
  class Pager
    USUAL = %w[pager less more].freeze
    # What less is given when the user has no preferences of their own: leave
    # at once if the page fits the screen, and ignore case in searches.
    LESS = "-Fi"
    HINT = "Use --no-pager to write to the terminal instead."

    # The pipe a page is written to.
    attr_reader :io

    # Starts the command, or else PAGER, or else the first usual pager there
    # is. Returns nil when no pager is named and none is found.
    def self.start(command = nil, env: ENV)
      command = RichRI.utf8(env["PAGER"]) if command.nil?
      return named(command, env) unless command.strip.empty?

      USUAL.each do |program|
        return new(program, [program], env)
      rescue SystemCallError
        next
      end
      nil
    end

    def self.named(command, env)
      new(command, words(command), env)
    rescue SystemCallError => e
      raise Error.new("cannot run the pager #{command.inspect}: #{e.class.new.message}", hint: HINT)
    end

    def self.words(command)
      Shellwords.split(command)
    rescue ArgumentError
      raise Error.new("the pager #{command.inspect} has an unmatched quote", hint: HINT)
    end
    private_class_method :named, :words

    def initialize(command, words, env)
      @command = command
      # less shows colors only with -R. It goes first: an option that takes a
      # string, such as -Pprompt, runs to the end of LESS and would take it in.
      @io = IO.popen({ "LESS" => "-R #{env.fetch('LESS', LESS)}" }, words, "w")
      @pid = @io.pid
    end

    # To be called once the page is written and the pipe closed. A pager that
    # did not end well took the page with it, which is a failure unless
    # Ctrl-C is what made it leave.
    def finish(interrupted)
      status = Process.last_status
      return if status.nil? || status.pid != @pid || status.success?
      raise Interrupt if interrupted

      ending = status.signaled? ? "was ended by signal #{status.termsig}" : "exited with status #{status.exitstatus}"
      raise Error, "the pager #{@command.inspect} #{ending}"
    end
  end
end
