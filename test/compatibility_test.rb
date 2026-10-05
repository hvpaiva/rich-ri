# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/compatibility"

class CompatibilityTest < Minitest::Test
  def test_both_bundles_stay_in_a_private_directory_and_never_reach_the_active_gem_home
    recorded_run do |home, calls|
      environments = calls.map(&:first)

      assert_equal(%w[legacy legacy minimum minimum],
                   environments.map { |environment| File.basename(environment.fetch("BUNDLE_GEMFILE"), ".gemfile") })
      assert_equal(%w[legacy legacy minimum minimum].map { |name| File.join(home, name) },
                   environments.map { |environment| environment.fetch("BUNDLE_PATH") })
      assert_empty environments.flat_map(&:keys).grep(/\AGEM_/)
      assert_equal([%w[bundle install], %w[bundle exec], %w[bundle install], %w[bundle exec]],
                   calls.map { |_environment, command| command.first(2) })
    end
  end

  def test_the_minimum_bundle_reads_the_store_the_legacy_bundle_wrote
    recorded_run do |home, calls|
      store = File.join(home, "legacy-ri")
      _environment, generate = calls.fetch(1)
      environment, _tests = calls.fetch(3)

      assert_equal store, generate.fetch(generate.index("--op") + 1)
      assert_equal store, environment.fetch("LEGACY_RI_STORE")
    end
  end

  def test_only_runtime_tests_run_with_the_minimum_bundle
    names = Compatibility.runtime_tests.map { |path| File.basename(path, "_test.rb") }

    assert_empty %w[cli completion legacy_store manual rendering shell] - names
    assert_empty names & %w[benchmark changelog ci ci_result ci_workflow compatibility github github_templates
                            release release_commands setup tools]
  end

  def test_a_failed_step_stops_the_run_and_names_the_bundle
    environment = Compatibility.environment("legacy")
    error = assert_raises(Compatibility::Error) do
      Compatibility.execute(environment, RbConfig.ruby, "-e", "exit 3")
    end

    assert_match(/\Alegacy bundle: .+ -e exit 3 failed\z/, error.message)
  end

  private

  def recorded_run
    Dir.mktmpdir("rich-ri-compatibility-") do |home|
      calls = []
      Compatibility.run(home: home, runner: ->(environment, *command) { calls << [environment, command] })
      yield home, calls
    end
  end
end
