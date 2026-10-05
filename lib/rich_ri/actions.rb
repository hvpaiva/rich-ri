# frozen_string_literal: true

module RichRI
  # What a command line asks for in place of looking its names up, such as
  # --help, --list or --man. A command does one of them. --help answers before
  # anything else and --version before the rest, so either can be added to any
  # command line; two of the others are refused, where one of them would have
  # to win unannounced.
  #
  # Options are read in layers, RI first and the command line last. The rules
  # hold within a layer, and an action chosen in a later layer replaces the one
  # under it.
  class Actions
    FIRST = %i[help version].freeze

    # The action that stands after the layers read so far, as its name
    # followed by its arguments, or nil.
    attr_reader :current

    def initialize
      @current = nil
      @chosen = {}
      @declined = []
    end

    # Records that the option asks for the named action in this layer.
    def choose(option, name, *arguments)
      @declined.delete(name)
      @chosen[name] = [option, [name, *arguments]]
    end

    # Takes the named action back, as --no-list does, wherever it was chosen.
    def decline(name)
      @declined |= [name]
      @chosen.delete(name)
      @current = nil if @current&.first == name
    end

    # Whether the last word on the named action was to take it back.
    def declined?(name)
      @declined.include?(name)
    end

    # Ends a layer and returns the action that stands.
    def settle
      name = FIRST.find { |first| @chosen.key?(first) }
      if name.nil? && @chosen.length > 1
        raise UsageError, "#{@chosen.values.first(2).map(&:first).join(' and ')} cannot be used together"
      end

      name ||= @chosen.keys.first
      @current = @chosen.fetch(name).last if name
      @chosen = {}
      @current
    end
  end
end
