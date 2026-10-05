# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release_workflow"
require_relative "release_support"

class ReleaseBranchTest < Minitest::Test
  include ReleaseFixtures

  def test_new_hotfix_release_creates_a_pr_against_the_hotfix_branch
    repository do |root|
      commands = []
      output = StringIO.new
      workflow("0.2.0", root: root, branch: "hotfix/0.2", out: output,
                        runner: workflow_runner(commands, state: { branch: "hotfix/0.2" })).run

      assert_includes commands, ["git", "rev-parse", "origin/hotfix/0.2"]
      create = commands.find { |args| args.first(3) == %w[gh pr create] }

      assert_equal "hotfix/0.2", create.fetch(create.index("--base") + 1)
      assert_includes output.string, "bin/release 0.2.0 --branch hotfix/0.2 --push"
    end
  end

  def test_hotfix_retry_keeps_the_selected_branch
    repository do |root|
      runner = workflow_runner([], fail_at: %w[git push], state: { branch: "hotfix/0.2" })
      assert_release_error("git push -u origin release/v0.2.0 failed.\n\n" \
                           "#{resume('bin/release 0.2.0 --branch hotfix/0.2')}") do
        workflow("0.2.0", root: root, branch: "hotfix/0.2", runner: runner, out: StringIO.new).run
      end
    end
  end

  def test_hotfix_release_targets_and_checks_the_selected_branch
    repository do |root|
      commands = []
      state = { branch: "hotfix/0.2", pr: release_pr("OPEN") }
      workflow("0.2.0", root: root, branch: "hotfix/0.2", push: true,
                        runner: workflow_runner(commands, state: state), out: StringIO.new).run

      assert(commands.any? { |args| args.first(3) == %w[gh pr list] && args.include?("hotfix/0.2") })
      assert_includes commands, ["git", "merge-base", "--is-ancestor", "b" * 40, "origin/hotfix/0.2"]
      refute_includes commands, ["git", "merge-base", "--is-ancestor", "b" * 40, "origin/main"]
    end
  end

  def test_hotfix_branch_must_match_the_release_version
    %w[feature/foo hotfix/0.1 hotfix/0.2/extra --all].each do |branch|
      assert_release_error("release branch must be main or hotfix/0.2") { Release.validate_branch(branch, "0.2.1") }
    end
    assert_equal "main", Release.validate_branch("main", "0.2.1")
    assert_equal "hotfix/0.2", Release.validate_branch("hotfix/0.2", "0.2.1")
  end

  def test_ci_refuses_a_release_commit_outside_main_and_the_matching_hotfix_branch
    repository do |root|
      sha = git(root, "rev-parse", "HEAD")
      git(root, "update-ref", "refs/remotes/origin/hotfix/0.2", sha)
      Dir.chdir(root) do
        Release.verify_ref(sha: sha, version: "0.2.1")
        assert_release_error("release commit must belong to main or its matching hotfix branch") do
          Release.verify_ref(sha: sha, version: "0.3.0")
        end
      end
    end
  end

  def test_ci_refuses_to_check_ancestry_without_a_release_commit
    assert_release_error("invalid release commit: set GITHUB_SHA to a full commit ID") do
      Release.verify_ref(sha: nil, version: "0.2.1")
    end
  end
end
