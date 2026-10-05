# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../rakelib/ci"

class CIResultTest < Minitest::Test
  def test_documentation_code_and_scheduled_checks_can_pass
    assert_equal "docs", CI.verify!(results("docs"), event: "pull_request")
    assert_equal "full", CI.verify!(results("full"), event: "pull_request")
    assert_equal "scheduled", CI.verify!(results("scheduled", event: "schedule"), event: "schedule")
    assert_equal "full", CI.verify!(results("full", event: "push"), event: "push", force_full: true)
    assert_equal "full", CI.verify!(results("full", event: "workflow_dispatch"), event: "workflow_dispatch")
  end

  def test_failures_cancellations_and_unexpected_skips_block_full_checks
    CI::FULL_JOBS.product(%w[failure cancelled skipped]).each do |job, result|
      data = results("full")
      data.fetch(job)["result"] = result

      assert_rejected(%(#{job}: expected success, got "#{result}"), data)
    end
  end

  def test_documentation_and_commit_failures_block_documentation_changes
    %w[docs commits].each do |job|
      data = results("docs")
      data.fetch(job)["result"] = "failure"

      assert_rejected(%(#{job}: expected success, got "failure"), data)
    end
  end

  def test_missing_results_cannot_pass
    data = results("full")
    data.delete("test")

    assert_rejected("incomplete CI job results", data)
  end

  def test_change_detection_that_did_not_succeed_cannot_pass
    %w[failure cancelled skipped].each do |result|
      data = results("docs")
      data.fetch("changes")["result"] = result

      assert_rejected("change detection did not succeed", data)
    end
  end

  def test_an_unknown_scope_cannot_pass
    data = results("docs")
    data.fetch("changes")["outputs"] = { "scope" => "unknown" }

    assert_rejected('unknown CI scope: "unknown"', data)
  end

  def test_a_scheduled_run_needs_the_audit_and_freshly_resolved_dependencies
    assert_equal %w[audit fresh-dependencies], CI::SCHEDULED_JOBS
    CI::SCHEDULED_JOBS.each do |job|
      data = results("scheduled", event: "schedule")
      data.fetch(job)["result"] = "skipped"

      assert_rejected(%(#{job}: expected success, got "skipped"), data, event: "schedule")
    end
  end

  def test_a_release_cannot_pass_with_only_documentation_checks
    assert_rejected("this run requires the full suite", results("docs"), force_full: true)
  end

  def test_only_a_scheduled_run_can_use_the_scheduled_checks
    assert_rejected("only scheduled runs may use scheduled scope", results("scheduled", event: "push"), event: "push")
  end

  def test_only_pushes_and_pull_requests_can_use_the_documentation_checks
    %w[workflow_dispatch schedule].each do |event|
      assert_rejected("only pushes and pull requests may use docs scope", results("docs", event: event), event: event)
    end
  end

  def test_bin_ci_says_which_checks_passed
    out, err, status = verify(results("docs"))

    assert_equal [0, "Docs CI checks passed.\n", ""], [status.exitstatus, out, err]
  end

  def test_bin_ci_names_itself_when_it_rejects_the_results
    data = results("full")
    data.delete("test")
    out, err, status = verify(data)

    assert_equal [1, "", "ci: incomplete CI job results\n"], [status.exitstatus, out, err]
  end

  private

  def assert_rejected(reason, data, event: "pull_request", **)
    error = assert_raises(CI::Error) { CI.verify!(data, event: event, **) }

    assert_equal reason, error.message
  end

  def verify(data)
    environment = { "GITHUB_EVENT_NAME" => "pull_request", "CI_FORCE_FULL" => nil, "CI_RESULTS" => JSON.generate(data) }
    Open3.capture3(environment, RbConfig.ruby, File.join(TestSupport::ROOT, "bin/ci"), "verify")
  end

  def results(scope, event: "pull_request")
    needed = case scope
             when "docs" then ["docs"]
             when "scheduled" then CI::SCHEDULED_JOBS.dup
             else CI::FULL_JOBS.dup
             end
    needed += ["changes"]
    needed += ["commits"] if event == "pull_request"
    CI::JOBS.to_h do |job|
      [job, { "result" => needed.include?(job) ? "success" : "skipped", "outputs" => { "scope" => scope } }]
    end
  end
end
