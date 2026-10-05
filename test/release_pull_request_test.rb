# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release_workflow"
require_relative "release_support"

class ReleasePullRequestTest < Minitest::Test
  include ReleaseFixtures

  def test_a_pull_request_from_a_fork_cannot_block_or_become_the_release
    %w[OPEN CLOSED].each do |state|
      repository do |root|
        commands = []
        output = release(root, commands, prs: [fork_pr(state)])

        assert_equal [CREATED], created_pull_requests(commands)
        assert(commands.any? { |args| args.first(3) == %w[gh pr merge] && args.include?(release_pr["url"]) })
        refute(commands.any? { |args| args.include?(fork_pr(state)["url"]) })
        assert_includes output, "Ignoring #{fork_pr(state)['url']}: it comes from a fork"
      end
    end
  end

  def test_a_merged_release_is_tagged_despite_a_fork_using_the_branch_name
    repository do |root|
      commands = []
      release(root, commands, prs: [release_pr, fork_pr("CLOSED")])

      assert_includes commands, ["git", "tag", "-s", "v0.2.0", "-m", "Release 0.2.0", "b" * 40]
      refute(commands.any? { |args| args.first(3) == %w[gh pr create] })
    end
  end

  def test_an_abandoned_pull_request_does_not_stop_its_replacement
    repository do |root|
      commands = []
      abandoned = release_pr("CLOSED").merge("url" => "https://github.com/hvpaiva/rich-ri/pull/7")
      output = release(root, commands, prs: [abandoned, release_pr("OPEN")])
      merge = commands.find { |args| args.first(3) == %w[gh pr merge] }

      assert_includes merge, release_pr["url"]
      refute(commands.any? { |args| args.first(3) == %w[gh pr create] })
      assert_includes output, "Ignoring #{abandoned['url']}: it was closed without merging"
    end
  end

  def test_a_release_restarts_after_its_only_pull_request_was_closed
    repository do |root|
      commands = []
      release(root, commands, prs: [release_pr("CLOSED")])

      assert_equal [CREATED], created_pull_requests(commands)
    end
  end

  def test_a_local_branch_left_by_a_closed_pull_request_is_prepared_again_from_main
    repository do |root|
      commands = []
      release(root, commands, prs: [release_pr("CLOSED")], local_branch: "a" * 40)

      assert_includes commands, %w[git switch -C release/v0.2.0]
      assert_equal [CREATED], created_pull_requests(commands)
    end
  end

  def test_a_remote_branch_left_by_a_closed_pull_request_is_replaced_only_at_the_closed_head
    repository do |root|
      commands = []
      release(root, commands, prs: [release_pr("CLOSED").merge("headRefOid" => "c" * 40)], remote_branch: "c" * 40)

      assert_includes commands, ["git", "push", "--force-with-lease=refs/heads/release/v0.2.0:#{'c' * 40}", "-u",
                                 "origin", "release/v0.2.0"]
      assert_equal [CREATED], created_pull_requests(commands)
    end
  end

  def test_a_remote_branch_with_other_commits_is_never_overwritten
    repository do |root|
      commands = []
      closed = release_pr("CLOSED").merge("headRefOid" => "c" * 40)
      error = assert_raises(Release::Error) { release(root, commands, prs: [closed], remote_branch: "e" * 40) }

      assert_equal "git push -u origin release/v0.2.0 failed.\n\n#{resume}", error.message
      assert_equal([%w[git push -u origin release/v0.2.0]], commands.select { |args| args.first(2) == %w[git push] })
    end
  end

  def test_a_local_branch_with_other_commits_is_never_overwritten
    repository do |root|
      commands = []
      assert_release_error("local release/v0.2.0 has commits outside its closed pull request; delete or rename it, " \
                           "then rerun\n#{resume}") do
        release(root, commands, prs: [release_pr("CLOSED")], local_branch: "e" * 40)
      end

      refute(commands.any? { |args| args.first(2) == %w[git switch] })
    end
  end

  def test_two_live_pull_requests_for_one_release_are_refused
    repository do |root|
      commands = []
      assert_release_error("several pull requests use release/v0.2.0; reconcile them before releasing\n#{resume}") do
        release(root, commands, prs: [release_pr, release_pr("OPEN")])
      end

      actions = [%w[gh pr merge], %w[gh pr create], %w[git tag -s]]

      refute(commands.any? { |args| actions.include?(args.first(3)) })
    end
  end

  def test_a_release_pull_request_carries_a_label_repository_setup_creates
    repository do |root|
      commands = []
      workflow("0.2.0", root: root, runner: workflow_runner(commands), out: StringIO.new).run
      created = created_pull_requests(commands).first

      assert_includes GitHub::Configuration::LABELS.map { |label| label.fetch("name") },
                      created.fetch(created.index("--label") + 1)
    end
  end

  def test_a_new_pull_request_names_the_command_that_merges_it
    repository do |root|
      output = StringIO.new
      workflow("0.2.0", root: root, runner: workflow_runner([]), out: output).run

      assert_equal "Release pull request: https://github.com/hvpaiva/rich-ri/pull/1. " \
                   "Run bin/release 0.2.0 --push to merge, sign and publish.\n", output.string.lines.last
    end
  end

  def test_a_dry_run_names_the_open_pull_request
    repository do |root|
      output = StringIO.new
      workflow("0.2.0", root: root, dry_run: true, runner: workflow_runner([], state: { pr: release_pr("OPEN") }),
                        out: output).run

      assert_equal "Existing release pull request: https://github.com/hvpaiva/rich-ri/pull/1 (dry run).\n",
                   output.string.lines.last
    end
  end

  def test_a_tag_without_a_merged_pull_request_stops_the_release
    repository do |root|
      error = assert_raises(Release::Error) do
        release(root, [], remote_tag: "b" * 40)
      end

      assert_equal "v0.2.0 already exists without a matching merged release pull request; inspect it before " \
                   "continuing\n#{resume}", error.message
    end
  end

  def test_a_local_branch_ahead_of_the_open_pull_request_is_not_merged
    repository do |root|
      commands = []
      error = assert_raises(Release::Error) do
        release(root, commands, branch: "release/v0.2.0", pr: release_pr("OPEN").merge("headRefOid" => "c" * 40))
      end

      assert_equal "local release/v0.2.0 differs from the pull request head; push its reviewed changes before " \
                   "retrying\n#{resume}", error.message
      refute(commands.any? { |args| args.first(3) == %w[gh pr merge] })
    end
  end

  def test_a_pull_request_whose_checks_never_start_is_kept_for_the_retry
    repository do |root|
      sleeper = Object.new
      def sleeper.sleep(_seconds) = nil
      runner = workflow_runner([], state: { pr: release_pr("OPEN") })
      no_checks = lambda do |argv, **options|
        argv.include?("statusCheckRollup") ? ["0\n", Struct.new(:success?).new(true)] : runner.call(argv, **options)
      end
      error = assert_raises(Release::Error) do
        workflow("0.2.0", root: root, push: true, sleeper: sleeper, runner: no_checks, out: StringIO.new).run
      end

      assert_equal "timed out waiting for checks on https://github.com/hvpaiva/rich-ri/pull/1; the existing pull " \
                   "request will be reused on retry\n#{resume}", error.message
    end
  end

  private

  def release(root, commands, local_branch: nil, remote_branch: nil, **state)
    output = StringIO.new
    runner = branches(workflow_runner(commands, state: state), local_branch, remote_branch)
    workflow("0.2.0", root: root, push: true, runner: runner, out: output).run
    output.string
  end

  # Git refuses to create a branch that exists or to replace a remote branch without a lease.
  def branches(runner, local, remote)
    lambda do |argv, **options|
      output, status = runner.call(argv, **options)
      case argv.first(3)
      when %w[git for-each-ref --format=%(objectname)] then [local ? "#{local}\n" : "", status]
      when %w[git ls-remote --heads] then [remote ? "#{remote}\trefs/heads/release/v0.2.0\n" : "", status]
      when %w[git switch -c] then [output, Struct.new(:success?).new(local.nil?)]
      when %w[git push -u] then [output, Struct.new(:success?).new(remote.nil?)]
      else [output, status]
      end
    end
  end
end
