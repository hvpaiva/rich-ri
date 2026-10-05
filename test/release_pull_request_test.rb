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

        assert(commands.any? { |args| args.first(3) == %w[gh pr create] })
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

      assert(commands.any? { |args| args.first(3) == %w[gh pr create] })
    end
  end

  def test_two_live_pull_requests_for_one_release_are_refused
    repository do |root|
      commands = []
      assert_release_error(%r{\Aseveral pull requests use release/v0\.2\.0; reconcile them before releasing$}) do
        release(root, commands, prs: [release_pr, release_pr("OPEN")])
      end

      actions = [%w[gh pr merge], %w[gh pr create], %w[git tag -s]]

      refute(commands.any? { |args| actions.include?(args.first(3)) })
    end
  end

  private

  def release(root, commands, **state)
    output = StringIO.new
    workflow("0.2.0", root: root, push: true, runner: workflow_runner(commands, state: state), out: output).run
    output.string
  end
end
