# frozen_string_literal: true

require "test_helper"
require "yaml"
require_relative "../rakelib/ci"
require_relative "../rakelib/github_configuration"
require_relative "../rakelib/tools"

class CIWorkflowTest < Minitest::Test
  PUBLISH = "needs.verify.outputs.publish == 'true'"

  def test_required_check_covers_every_ci_job
    jobs = ci.fetch("jobs")
    gate = jobs.fetch("ci")

    assert_equal ["ci"], GitHub::Configuration::REQUIRED_CHECKS
    assert_equal "${{ always() }}", gate.fetch("if")
    assert_equal (jobs.keys - ["ci"]).sort, gate.fetch("needs").sort
    assert_equal CI::JOBS.sort, gate.fetch("needs").sort
  end

  def test_each_job_runs_for_exactly_the_scopes_that_require_it
    scopes = ci.fetch("jobs").transform_values { |job| job["if"].to_s.scan(/scope == '(\w+)'/).flatten }
    jobs = %w[full scheduled docs].to_h { |scope| [scope, scopes.select { |_job, list| list.include?(scope) }.keys] }

    assert_equal CI::FULL_JOBS.sort, jobs.fetch("full").sort
    assert_equal CI::SCHEDULED_JOBS.sort, jobs.fetch("scheduled").sort
    assert_equal ["docs"], jobs.fetch("docs")
  end

  def test_the_weekly_run_starts_off_the_hour
    minutes = triggers.fetch("schedule").map { |entry| entry.fetch("cron").split.first }

    refute_empty minutes
    assert(minutes.none? { |minute| minute.match?(/\A0+\z/) })
  end

  def test_the_full_run_can_be_started_by_hand
    assert triggers.key?("workflow_dispatch")
  end

  def test_pull_requests_run_the_scripts_behind_the_local_commit_and_changelog_checks
    commands = ci.dig("jobs", "commits", "steps").filter_map { |step| step["run"] }
    local = File.read(File.join(TestSupport::ROOT, "Rakefile"))[/^task check: %w\[(.+?)\]/m, 1].split

    %w[commits changelog].each do |check|
      assert_includes commands.map { |command| command[%r{\Aruby bin/lint-(\w+) }, 1] }, check
      assert_includes local, "lint:#{check}"
    end
  end

  def test_the_changelog_waiver_in_ci_is_a_label_repository_setup_creates
    step = ci.dig("jobs", "commits", "steps").find { |entry| entry["run"].to_s.include?("lint-changelog") }
    label = step.dig("env", "SKIP_CHANGELOG")[/labels\.\*\.name, '([^']+)'/, 1]

    assert_includes GitHub::Configuration::LABELS.map { |entry| entry.fetch("name") }, label
  end

  def test_ci_tests_the_oldest_ruby_the_gem_supports
    floor = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec")).required_ruby_version
    oldest = floor.requirements.map(&:last).min.segments.first(2).join(".")
    matrix = ci.dig("jobs", "test", "strategy", "matrix")

    assert_includes matrix.fetch("ruby"), oldest
    compatibility = ci.dig("jobs", "compatibility", "steps").filter_map { |step| step.dig("with", "ruby-version") }

    assert_equal [oldest], compatibility
  end

  def test_only_a_run_that_publishes_receives_an_identity_token
    jobs = release.fetch("jobs").select { |_name, job| job.dig("permissions", "id-token") == "write" }

    refute_empty jobs
    jobs.each { |name, job| assert_equal PUBLISH, job["if"], name }
  end

  def test_a_rehearsal_still_verifies_the_transferred_artifact
    rehearsals = release.fetch("jobs").values.select { |job| job["if"] == PUBLISH.sub("==", "!=") }
    commands = rehearsals.flat_map { |job| job.fetch("steps").filter_map { |step| step["run"] } }

    assert(commands.any? { |command| command.include?("sha256sum --check SHA256SUMS") })
    assert(rehearsals.none? { |job| job.key?("permissions") })
  end

  # mise installs the latest release of an unpinned tool, so CI would drift without failing.
  def test_ci_installs_through_mise_only_the_versions_mise_toml_pins
    installs = ci.fetch("jobs").transform_values do |job|
      mise = job.fetch("steps").select { |step| step["uses"].to_s.start_with?("jdx/mise-action@") }
      mise.flat_map { |step| step.dig("with", "install_args").split }
    end

    assert_equal Tools.mise_tools.sort, installs.fetch("quality").sort
    assert_empty installs.values.flatten - Tools.pinned.keys
  end

  def test_reusable_ci_and_release_explicitly_require_the_full_suite
    assert_same true, triggers.dig("workflow_call", "inputs", "force_full", "default")
    assert_same true, release.dig("jobs", "ci", "with", "force_full")
    refute triggers.fetch("pull_request").key?("paths")
    refute triggers.fetch("pull_request").key?("paths-ignore")
  end

  private

  def ci = @ci ||= workflow("ci")

  def release = @release ||= workflow("release")

  def workflow(name) = YAML.load_file(File.join(TestSupport::ROOT, ".github/workflows/#{name}.yml"))

  # YAML 1.1 reads the bare key "on" as true.
  def triggers = ci["on"] || ci[true]
end
