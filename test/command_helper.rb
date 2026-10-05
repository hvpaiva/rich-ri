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

  # An interactive session with a home of its own and no line editor settings of the user's.
  def with_session(env = {})
    Dir.mktmpdir("rich-ri-session-") do |home|
      yield({ "HOME" => home, "INPUTRC" => File::NULL, "NO_COLOR" => "1" }.merge(env))
    end
  end

  # A copy of the fixture store that a test may damage.
  def with_store
    Dir.mktmpdir("rich-ri-store-") do |dir|
      store = File.join(dir, "ri")
      FileUtils.cp_r(TestSupport::STORE, store)
      yield store
    end
  end

  # The command that cli runs, for a test that connects its streams itself.
  def executable(*)
    coverage = ENV["COVERAGE"] ? ["-r#{TestSupport::ROOT}/test/coverage_helper"] : []
    [RbConfig.ruby, *coverage, "-I#{TestSupport::ROOT}/lib", File.join(TestSupport::ROOT, "exe/rich-ri"), *]
  end

  private

  def current(env, name)
    env.fetch(name) { ENV.fetch(name, nil) }
  end

  def joined(separator, *parts)
    parts.reject { |part| part.to_s.empty? }.join(separator)
  end
end
