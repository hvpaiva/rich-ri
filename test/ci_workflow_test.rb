# frozen_string_literal: true

require "test_helper"
require "yaml"
require "workflow_expression"
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
    minutes = triggers.fetch("schedule").map { |entry| Integer(entry.fetch("cron").split.first, 10) }

    assert_equal 1, minutes.length
    refute_includes minutes, 0
  end

  def test_the_full_run_can_be_started_by_hand
    assert triggers.key?("workflow_dispatch")
  end

  def test_pull_request_title_body_and_label_changes_rerun_the_commit_checks
    assert_empty %w[opened edited synchronize reopened labeled unlabeled] - triggers.dig("pull_request", "types")
  end

  def test_pull_requests_run_the_commit_and_changelog_scripts
    scripts = commands("commits").filter_map { |command| command[%r{\Aruby bin/(lint-\w+) }, 1] }

    assert_equal %w[lint-commits lint-changelog], scripts
  end

  def test_rake_check_runs_the_commit_and_changelog_checks
    assert_empty %w[lint:commits lint:changelog] - check_tasks
  end

  def test_the_quality_job_runs_rake_check
    assert_includes commands("quality"), "bundle exec rake check"
  end

  def test_the_compatibility_job_runs_the_local_compatibility_script
    assert_equal "ruby bin/test-compatibility", commands("compatibility").last
  end

  def test_the_changelog_waiver_in_ci_is_a_label_repository_setup_creates
    step = ci.dig("jobs", "commits", "steps").find { |entry| entry["run"].to_s.include?("lint-changelog") }
    label = step.dig("env", "SKIP_CHANGELOG")[/labels\.\*\.name, '([^']+)'/, 1]

    assert_includes GitHub::Configuration::LABELS.map { |entry| entry.fetch("name") }, label
  end

  def test_ci_tests_the_oldest_ruby_the_gem_supports
    assert_includes ci.dig("jobs", "test", "strategy", "matrix", "ruby"), oldest_ruby
  end

  def test_ci_tests_the_ruby_mise_toml_pins_on_linux_and_macos
    pinned = File.read(File.join(TestSupport::ROOT, "mise.toml"))[/^ruby = "(\d+\.\d+)\./, 1]
    matrix = ci.dig("jobs", "test", "strategy", "matrix")
    runs = matrix.fetch("os").product(matrix.fetch("ruby")) +
           Array(matrix["include"]).map { |run| run.values_at("os", "ruby") }

    assert_equal %w[macos-latest ubuntu-latest], runs.select { |_os, ruby| ruby == pinned }.map(&:first).sort
  end

  def test_fresh_dependencies_are_resolved_before_the_tests_run
    steps = commands("fresh-dependencies")

    assert_operator steps.index("bundle update --all"), :<, steps.index("bundle exec rake test package:check")
  end

  # A shared group would cancel a waiting push run and leave that commit without a complete result.
  def test_only_runs_for_the_same_pull_request_share_a_concurrency_group
    runs = [1, 2]
    groups = %w[pull_request push schedule workflow_dispatch].to_h do |event|
      [event, runs.map { |run| concurrency_group(event, run) }.uniq.length]
    end

    assert_equal({ "pull_request" => 1, "push" => 2, "schedule" => 2, "workflow_dispatch" => 2 }, groups)
  end

  def test_the_compatibility_job_runs_on_the_oldest_ruby
    versions = ci.dig("jobs", "compatibility", "steps").filter_map { |step| step.dig("with", "ruby-version") }

    assert_equal [oldest_ruby], versions
  end

  def test_workflows_only_read_the_repository_unless_a_release_job_asks_for_more
    [ci, release].each { |workflow| assert_equal({ "contents" => "read" }, workflow.fetch("permissions")) }
    writes = ci.fetch("jobs").select { |_name, job| job.fetch("permissions", {}).value?("write") }

    assert_empty writes.keys
  end

  def test_a_second_release_run_for_the_same_ref_never_cancels_a_publication
    assert_same false, release.dig("concurrency", "cancel-in-progress")
  end

  def test_a_manual_release_run_is_a_rehearsal_by_default
    assert_same true, triggers(release).dig("workflow_dispatch", "inputs", "dry_run", "default")
  end

  def test_only_a_tag_run_that_is_not_a_rehearsal_publishes
    decision = release.dig("jobs", "verify", "steps").find { |step| step["id"] == "decision" }.dig("env", "PUBLISH")
    # A push carries no inputs; a manual run says whether it is a dry run.
    runs = [["push", "tag", nil], ["push", "branch", nil]] +
           %w[tag branch].product([true, false]).map { |ref_type, dry_run| ["workflow_dispatch", ref_type, dry_run] }
    published = runs.select do |event, ref_type, dry_run|
      inputs = dry_run.nil? ? {} : { "dry_run" => dry_run }
      context = { "github" => { "event_name" => event, "ref_type" => ref_type }, "inputs" => inputs }
      WorkflowExpression.render(decision, context) == "true"
    end

    assert_equal [["push", "tag", nil], ["workflow_dispatch", "tag", false]], published
  end

  def test_only_a_run_that_publishes_receives_an_identity_token
    jobs = release.fetch("jobs").select { |_name, job| job.dig("permissions", "id-token") == "write" }

    assert_equal({ "attest" => PUBLISH, "publish" => PUBLISH }, jobs.transform_values { |job| job["if"] })
  end

  def test_a_rehearsal_verifies_the_transferred_artifact_as_a_publication_does
    verification = rehearsals.keys.flat_map { |job| commands(job, release) }

    assert_equal commands("attest", release), verification
  end

  def test_a_rehearsal_asks_for_no_permissions
    assert_empty(rehearsals.select { |_name, job| job.key?("permissions") }.keys)
  end

  # mise installs the latest release of an unpinned tool, so CI would drift without failing.
  def test_ci_installs_through_mise_only_the_versions_mise_toml_pins
    installs = ci.fetch("jobs").transform_values do |job|
      mise = job.fetch("steps").select { |step| step["uses"].to_s.start_with?("jdx/mise-action@") }
      mise.flat_map { |step| step.dig("with", "install_args").split }
    end

    assert_equal Tools.mise_tools.sort, installs.fetch("quality").sort
    assert_empty installs.values.flatten - Tools.mise_tools
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

  def commands(job, workflow = ci) = workflow.dig("jobs", job, "steps").filter_map { |step| step["run"] }

  def check_tasks = File.read(File.join(TestSupport::ROOT, "Rakefile"))[/^task check: %w\[(.+?)\]/m, 1].split

  def rehearsals = release.fetch("jobs").select { |_name, job| job["if"] == PUBLISH.sub("==", "!=") }

  def concurrency_group(event, run)
    github = { "workflow" => "CI", "event_name" => event, "ref" => "refs/pull/7/merge", "run_id" => run }
    WorkflowExpression.render(ci.dig("concurrency", "group"), "github" => github)
  end

  def oldest_ruby
    floor = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec")).required_ruby_version
    floor.requirements.map(&:last).min.segments.first(2).join(".")
  end

  # YAML 1.1 reads the bare key "on" as true.
  def triggers(workflow = ci) = workflow["on"] || workflow[true]
end
