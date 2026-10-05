# frozen_string_literal: true

require "test_helper"

module CommandSupport
  # The executable requires the file before its own code runs, so cli and
  # terminal_cli run a command with the code in place and nothing else changed.
  def with_planted(code, env: {})
    Dir.mktmpdir("rich-ri-planted-") do |dir|
      File.write(File.join(dir, "rich_ri_planted.rb"), code)
      yield env.merge("RUBYLIB" => joined(File::PATH_SEPARATOR, dir, current(env, "RUBYLIB")),
                      "RUBYOPT" => joined(" ", current(env, "RUBYOPT"), "-rrich_ri_planted"))
    end
  end

  private

  def current(env, name)
    env.fetch(name) { ENV.fetch(name, nil) }
  end

  def joined(separator, *parts)
    parts.reject { |part| part.to_s.empty? }.join(separator)
  end
end
