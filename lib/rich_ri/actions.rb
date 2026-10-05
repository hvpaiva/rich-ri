# frozen_string_literal: true

module RichRI
  # The one action a command asks for instead of a lookup. Within a layer of options --help and
  # --version win and any other two conflict; a later layer (RI, file, command line) replaces it.
  class Actions
    FIRST = %i[help version].freeze

    attr_reader :current

    def initialize
      @current = nil
      @chosen = {}
      @declined = []
    end

    def choose(option, name, *arguments)
      @declined.delete(name)
      @chosen[name] = [option, [name, *arguments]]
    end

    def decline(name)
      @declined |= [name]
      @chosen.delete(name)
      @current = nil if @current&.first == name
    end

    def declined?(name)
      @declined.include?(name)
    end

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
