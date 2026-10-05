# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release_workflow"
require_relative "release_support"

class ReleasePublicationTest < Minitest::Test
  include ReleaseFixtures

  def test_a_dry_run_asks_for_the_tag_only_while_it_is_missing_from_origin
    ready = "Release merge #{'b' * 40} is ready. Run bin/release 0.2.0 --push to"

    assert_equal "#{ready} sign and push its tag.\n", dry_run(pr: release_pr)
    assert_equal "#{ready} push the signed tag.\n", dry_run(pr: release_pr, local_tag: true)
  end

  def test_a_dry_run_reports_the_release_run_of_a_tag_already_on_origin
    { {} => "Release run 123 succeeded; nothing is left to do",
      { run_status: "in_progress" } => "Release run 123 is in_progress; run bin/release 0.2.0 to watch it",
      { conclusion: "failure" } => "Release run 123 ended with failure; run bin/release 0.2.0 for the recovery steps",
      { runs: [] } => "no Release run was found; inspect Actions before dispatching one" }.each do |run, state|
      output = dry_run(pr: release_pr, local_tag: true, remote_tag: "b" * 40, **run)

      assert_equal "v0.2.0 is already on origin at #{'b' * 40}: #{state}.\n", output
    end
  end

  private

  def dry_run(**state)
    repository do |root|
      commands = []
      output = StringIO.new
      workflow("0.2.0", root: root, dry_run: true, runner: workflow_runner(commands, state: state), out: output,
                        sleeper: nil).run

      refute(commands.any? { |args| args.first(3) == %w[gh run watch] })
      return output.string.lines.grep_v(/\A==> /).join
    end
  end
end
