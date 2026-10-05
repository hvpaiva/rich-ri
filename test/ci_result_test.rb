# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/ci"

class CIResultTest < Minitest::Test
  def test_documentation_code_and_scheduled_checks_can_pass
    assert_equal "docs", CI.verify!(results("docs"), event: "pull_request")
    assert_equal "full", CI.verify!(results("full"), event: "pull_request")
    assert_equal "scheduled", CI.verify!(results("scheduled", event: "schedule"), event: "schedule")
    assert_equal "full", CI.verify!(results("full", event: "push"), event: "push", force_full: true)
  end

  def test_failures_cancellations_and_unexpected_skips_block_full_checks
    CI::FULL_JOBS.product(%w[failure cancelled skipped]).each do |job, result|
      data = results("full")
      data.fetch(job)["result"] = result

      assert_rejected(/^#{job}: expected success, got "#{result}"$/, data)
    end
  end

  def test_documentation_and_commit_failures_block_documentation_changes
    %w[docs commits].each do |job|
      data = results("docs")
      data.fetch(job)["result"] = "failure"

      assert_rejected(/^#{job}: expected success, got "failure"$/, data)
    end
  end

  def test_missing_results_and_broken_change_detection_cannot_pass
    data = results("full")
    data.delete("test")

    assert_rejected(/Incomplete CI job results/, data)
    %w[failure cancelled skipped].each do |result|
      data = results("docs")
      data.fetch("changes")["result"] = result

      assert_rejected(/Change detection did not succeed/, data)
    end
    data = results("docs")
    data.fetch("changes")["outputs"] = { "scope" => "unknown" }

    assert_rejected(/Unknown CI scope: "unknown"/, data)
  end

  def test_a_scheduled_run_needs_the_audit_and_freshly_resolved_dependencies
    assert_equal %w[audit fresh-dependencies], CI::SCHEDULED_JOBS
    CI::SCHEDULED_JOBS.each do |job|
      data = results("scheduled", event: "schedule")
      data.fetch(job)["result"] = "skipped"

      assert_rejected(/^#{job}: expected success, got "skipped"$/, data, event: "schedule")
    end
  end

  def test_a_release_cannot_pass_using_only_documentation_or_scheduled_checks
    assert_rejected(/requires the full suite/, results("docs"), force_full: true)
    assert_rejected(/Only scheduled runs/, results("scheduled", event: "push"), event: "push")
    assert_rejected(/Only pushes and pull requests/, results("docs", event: "workflow_dispatch"),
                    event: "workflow_dispatch")
    assert_rejected(/Only pushes and pull requests/, results("docs", event: "schedule"), event: "schedule")
  end

  private

  def assert_rejected(reason, data, event: "pull_request", **)
    error = assert_raises(CI::Error) { CI.verify!(data, event: event, **) }

    assert_match reason, error.message
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
