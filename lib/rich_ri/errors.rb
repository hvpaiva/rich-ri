# frozen_string_literal: true

module RichRI
  # Base class for every failure rich-ri explains to the user. The command
  # prints "rich-ri: message", then the hint when there is one, and exits with
  # exit_status. Any other exception reaching the command is a defect.
  class Error < StandardError
    DEBUG_VARIABLE = "RICH_RI_DEBUG"
    # Ruby words a failed system call as "reason @ function - subject".
    SYSTEM_CALL = /\A(?<reason>.+?) @ \S+ - (?<subject>.+)\z/m
    STREAMS = { "<STDOUT>" => "standard output", "<STDERR>" => "standard error" }.freeze

    # Advice printed on its own line after the message, or nil.
    attr_reader :hint

    # Writes any exception as the single failure the user sees and returns the
    # exit status it calls for. Text in a message can come from the command
    # line, a path or a store, so no terminal control in it is passed on. The
    # exception class and backtrace, which a user cannot act on, are shown only
    # when RICH_RI_DEBUG is set.
    def self.report(error, io = $stderr)
      explained = error.is_a?(Error)
      io.puts "rich-ri: #{RichRI.sanitize(summary(error))}"
      io.puts error.hint if explained && error.hint
      trace(error, io) unless ENV.fetch(DEBUG_VARIABLE, "").empty?
      explained ? error.exit_status : 1
    end

    # A failed system call reads as tools usually print it: what it failed on,
    # then why, without the name of the C function that noticed.
    def self.summary(error)
      match = SYSTEM_CALL.match(error.message) if error.is_a?(SystemCallError)
      match ? "#{STREAMS.fetch(match[:subject], match[:subject])}: #{match[:reason]}" : error.message
    end

    def self.trace(error, io)
      io.puts error.class.name
      while error
        Array(error.backtrace).each { |line| io.puts "    #{RichRI.sanitize(line)}" }
        error = error.cause
        io.puts "caused by #{error.class.name}: #{RichRI.sanitize(error.message)}" if error
      end
    end
    private_class_method :summary, :trace

    def initialize(message = nil, hint: nil)
      super(message)
      @hint = hint
    end

    def exit_status = 1
  end

  # The command line itself is wrong: an unknown option, a refused value or
  # arguments that cannot be combined. Only these failures point at --help.
  class UsageError < Error
    def initialize(message = nil, hint: "Run rich-ri --help for usage.")
      super
    end

    def exit_status = 2
  end

  # The configuration file or an environment variable holds something rich-ri
  # refuses. Correcting the command line would not help, so there is no hint.
  class ConfigurationError < Error; end

  # RI data that cannot be read: damaged, or written by a Ruby or RDoc whose
  # format this one does not understand. The message names the store, or the
  # file given to --dump, because regenerating it is the only remedy.
  class StoreError < Error
    HINT = "Regenerate the documentation with your current Ruby and RDoc. For gems: gem rdoc GEM_NAME --ri.\n" \
           "For Ruby core documentation, see https://github.com/hvpaiva/rich-ri/blob/main/docs/troubleshooting.md"

    attr_reader :path

    def initialize(path)
      @path = path
      super("incompatible or damaged RI data in #{path}", hint: HINT)
    end
  end

  # A style role, style string or color is invalid. Theme, Style and Color raise
  # it without knowing where the value was written; the option parser and the
  # configuration loader report it as their own kind of failure.
  class ThemeError < Error; end
end
