# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/compatibility"

class CompatibilityTest < Minitest::Test
  # They test the repository's own tooling, which the minimum bundle does not install.
  MAINTENANCE = %w[benchmark changelog changelog_command changelog_lint ci ci_result ci_workflow commit_policy
                   compatibility github github_templates project release release_artifact release_branch
                   release_commands release_publication release_pull_request release_recovery setup shell_runner
                   test_environment tools].freeze

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

  def test_every_test_file_runs_with_the_minimum_bundle_or_is_a_maintenance_test
    names = Dir.glob("*_test.rb", base: File.join(TestSupport::ROOT, "test")).map { |path| path.delete_suffix("_test.rb") }

    assert_empty Compatibility::RUNTIME & MAINTENANCE
    assert_equal names.sort, (Compatibility::RUNTIME + MAINTENANCE).sort
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
