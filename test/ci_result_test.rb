# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/ci"

class CIResultTest < Minitest::Test
  def test_documentation_code_and_scheduled_checks_can_pass
    assert_equal "docs", CI.verify!(results("docs"), event: "pull_request")
    assert_equal "full", CI.verify!(results("full"), event: "pull_request")
    assert_equal "audit", CI.verify!(results("audit", event: "schedule"), event: "schedule")
    assert_equal "full", CI.verify!(results("full", event: "push"), event: "push", force_full: true)
  end

  def test_failures_cancellations_and_unexpected_skips_block_full_checks
    CI::FULL_JOBS.product(%w[failure cancelled skipped]).each do |job, result|
      data = results("full")
      data.fetch(job)["result"] = result
      error = assert_raises(RuntimeError) { CI.verify!(data, event: "pull_request") }

      assert_includes error.message, job
    end
  end

  def test_documentation_and_commit_failures_block_documentation_changes
    %w[docs commits].each do |job|
      data = results("docs")
      data.fetch(job)["result"] = "failure"

      assert_raises(RuntimeError) { CI.verify!(data, event: "pull_request") }
    end
  end

  def test_missing_results_and_broken_change_detection_cannot_pass
    data = results("full")
    data.delete("test")

    assert_raises(RuntimeError) { CI.verify!(data, event: "pull_request") }
    %w[failure cancelled skipped].each do |result|
      data = results("docs")
      data.fetch("changes")["result"] = result

      assert_raises(RuntimeError) { CI.verify!(data, event: "pull_request") }
    end
    data = results("docs")
    data.fetch("changes")["outputs"] = { "scope" => "unknown" }

    assert_raises(RuntimeError) { CI.verify!(data, event: "pull_request") }
  end

  def test_a_release_cannot_pass_using_only_documentation_or_audit_checks
    assert_raises(RuntimeError) { CI.verify!(results("docs"), event: "pull_request", force_full: true) }
    assert_raises(RuntimeError) { CI.verify!(results("audit", event: "push"), event: "push") }
    assert_raises(RuntimeError) { CI.verify!(results("docs", event: "workflow_dispatch"), event: "workflow_dispatch") }
    assert_raises(RuntimeError) { CI.verify!(results("docs", event: "schedule"), event: "schedule") }
  end

  private

  def results(scope, event: "pull_request")
    needed = case scope
             when "docs" then ["docs"]
             when "audit" then ["audit"]
             else CI::FULL_JOBS.dup
             end
    needed += ["changes"]
    needed += ["commits"] if event == "pull_request"
    CI::JOBS.to_h do |job|
      [job, { "result" => needed.include?(job) ? "success" : "skipped", "outputs" => { "scope" => scope } }]
    end
  end
end
