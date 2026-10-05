# frozen_string_literal: true

module RichRI
  # A failure explained to the user; any other exception reaching the command is a defect.
  class Error < StandardError
    DEBUG_VARIABLE = "RICH_RI_DEBUG"
    # Ruby words a failed system call as "reason @ function - subject".
    SYSTEM_CALL = /\A(?<reason>.+?) @ \S+ - (?<subject>.+)\z/m
    STREAMS = { "<STDOUT>" => "standard output", "<STDERR>" => "standard error" }.freeze

    attr_reader :hint

    # A message can hold text from the command line, a path or a store, so it is sanitized.
    def self.report(error, io = $stderr)
      explained = error.is_a?(Error)
      io.puts "rich-ri: #{RichRI.sanitize(summary(error))}"
      io.puts error.hint if explained && error.hint
      trace(error, io) unless ENV.fetch(DEBUG_VARIABLE, "").empty?
      explained ? error.exit_status : 1
    end

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

  class UsageError < Error
    def initialize(message = nil, hint: "Run rich-ri --help for usage.")
      super
    end

    def exit_status = 2
  end

  # A value refused in the configuration file or an environment variable.
  class ConfigurationError < Error; end

  class StoreError < Error
    HINT = "Regenerate the documentation with your current Ruby and RDoc. For gems: gem rdoc GEM_NAME --ri.\n" \
           "For Ruby core documentation, see https://github.com/hvpaiva/rich-ri/blob/main/docs/troubleshooting.md"

    attr_reader :path

    def initialize(path)
      @path = path
      super("incompatible or damaged RI data in #{path}", hint: HINT)
    end
  end

  # Raised without knowing where the value was written; the option parser and the
  # configuration loader report it as their own kind of failure.
  class ThemeError < Error; end
end
