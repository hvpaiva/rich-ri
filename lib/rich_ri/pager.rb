# frozen_string_literal: true

module RichRI
  # A pager the user named must start and end well: falling back or losing the page would pass for
  # success. No shell reads the command, so a pipe or a redirection in it is one more word.
  class Pager
    USUAL = %w[pager less more].freeze
    # Without LESS: quit if the page fits the screen, ignore case in searches.
    LESS = "-Fi"
    HINT = "Use --no-pager to write to the terminal instead."

    attr_reader :io

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

    # Call once the pipe is closed: the pager's status is Process.last_status.
    def finish(interrupted)
      status = Process.last_status
      return if status.nil? || status.pid != @pid || status.success?
      raise Interrupt if interrupted

      ending = status.signaled? ? "was ended by signal #{status.termsig}" : "exited with status #{status.exitstatus}"
      raise Error, "the pager #{@command.inspect} #{ending}"
    end
  end
end
