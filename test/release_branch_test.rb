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
      error = assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, branch: "hotfix/0.2", runner: runner, out: StringIO.new).run
      end

      assert_includes error.message, "rerun bin/release 0.2.0 --branch hotfix/0.2"
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
      assert_raises(RuntimeError) { Release.validate_branch(branch, "0.2.1") }
    end
    assert_equal "main", Release.validate_branch("main", "0.2.1")
    assert_equal "hotfix/0.2", Release.validate_branch("hotfix/0.2", "0.2.1")
  end

  def test_ci_checks_real_git_ancestry_before_publication
    repository do |root|
      sha = git(root, "rev-parse", "HEAD")
      Dir.chdir(root) do
        assert_raises(RuntimeError) { Release.verify_ref(sha: sha, version: "0.2.1") }
        git(root, "update-ref", "refs/remotes/origin/hotfix/0.2", sha)
        Release.verify_ref(sha: sha, version: "0.2.1")
        assert_raises(RuntimeError) { Release.verify_ref(sha: sha, version: "0.3.0") }
      end
    end
  end
end
