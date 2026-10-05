# frozen_string_literal: true

module RichRI
  # Base class for every failure rich-ri explains to the user. The command
  # prints "rich-ri: message", then the hint when there is one, and exits with
  # exit_status. Any other exception reaching the command is a defect.
  class Error < StandardError
    # Advice printed on its own line after the message, or nil.
    attr_reader :hint

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

  # A style role, style string or color is invalid. Theme, Style and Color raise
  # it without knowing where the value was written; the option parser and the
  # configuration loader report it as their own kind of failure.
  class ThemeError < Error; end
end
