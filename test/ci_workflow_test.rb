# frozen_string_literal: true

require "test_helper"
require "yaml"
require_relative "../rakelib/ci"
require_relative "../rakelib/github_configuration"

class CIWorkflowTest < Minitest::Test
  def test_required_check_covers_every_ci_job
    jobs = ci.fetch("jobs")
    gate = jobs.fetch("ci")

    assert_equal ["ci"], GitHub::Configuration::REQUIRED_CHECKS
    assert_equal "${{ always() }}", gate.fetch("if")
    assert_equal (jobs.keys - ["ci"]).sort, gate.fetch("needs").sort
    assert_equal CI::JOBS.sort, gate.fetch("needs").sort
  end

  def test_full_ci_keeps_the_supported_ruby_and_platform_matrix
    jobs = ci.fetch("jobs")
    matrix = jobs.fetch("test").fetch("strategy").fetch("matrix")
    platforms = matrix.fetch("os").product(matrix.fetch("ruby"))
    platforms += matrix.fetch("include").map { |entry| entry.values_at("os", "ruby") }

    assert_equal [["macos-latest", "4.0"], ["ubuntu-latest", "3.4"], ["ubuntu-latest", "4.0"]], platforms.sort
  end

  def test_a_rehearsal_checks_the_artifact_but_only_a_publication_attests_it
    jobs = release.fetch("jobs")
    steps = jobs.fetch("attest").fetch("steps")
    attestation = steps.find { |step| step["uses"].to_s.start_with?("actions/attest@") }

    assert_equal "needs.verify.outputs.publish == 'true'", attestation.fetch("if")
    assert_equal([attestation], steps.select { |step| step.key?("if") })
    refute jobs.fetch("attest").key?("if")
    assert_equal "needs.verify.outputs.publish == 'true'", jobs.fetch("publish").fetch("if")
    assert_equal %w[verify attest], jobs.fetch("publish").fetch("needs")
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
