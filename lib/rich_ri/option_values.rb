# frozen_string_literal: true

module RichRI
  module OptionValues
    private

    # Matched whole: OptionParser would take any unambiguous prefix and call an empty one ambiguous.
    def choice(option, value, allowed)
      return value if allowed.include?(value)

      raise UsageError, "#{option} must be one of #{allowed.join(', ')}, not #{value.inspect}"
    end

    def integer(option, text, range)
      number = Configuration.integer(text)
      return number if number && range.cover?(number)

      raise UsageError, "#{option} must be an integer from #{range.min} to #{range.max}, not #{text.inspect}"
    end

    def text(option, value)
      return value if Configuration.text?(value)

      raise UsageError, "#{option} must be a nonempty string without control characters"
    end

    def style(role, value)
      Theme.new(styles: { role => value })
      value
    rescue ThemeError => e
      raise UsageError, "--style: #{e.message}"
    end

    # Prefer an existing literal path, including commas, over RI's list form.
    def directories(value)
      listed = File.directory?(value) ? [value] : value.split(",")
      refused = listed.empty? ? value : listed.find { |directory| !File.directory?(directory) }
      raise UsageError, "--doc-dir must be a directory, not #{refused.inspect}" if refused

      listed.map { |directory| RichRI.expand_path(directory) }
    end
  end
end
