# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release"
require_relative "../rakelib/release_workflow"

require_relative "release_support"

class ReleaseTest < Minitest::Test
  include ReleaseFixtures

  def test_preparation_updates_version_and_preserves_unreleased_for_next_changes
    repository do |root|
      assert_equal "0.2.0", Release.prepare("0.2.0", root: root)
      assert_equal "0.2.0", Release.version(root: root)
      changelog = File.read(File.join(root, "CHANGELOG.md"))

      assert_includes changelog, "## [Unreleased]\n\n## [0.2.0] - #{Time.now.utc.to_date.iso8601}"
      assert_includes changelog, "- Readable documentation."
      assert_includes changelog, "compare/v0.2.0...HEAD"
    end
  end

  def test_preparation_refuses_dirty_tree_and_invalid_versions_without_writing
    repository do |root|
      original = File.read(File.join(root, "CHANGELOG.md"))
      assert_raises(RuntimeError) { Release.prepare("0.0.1", root: root) }
      assert_raises(RuntimeError) { Release.prepare("01.2.3", root: root) }
      assert_raises(RuntimeError) { Release.prepare("invalid", root: root) }
      File.write(File.join(root, "unfinished"), "work")
      assert_raises(RuntimeError) { Release.prepare("0.2.0", root: root) }
      assert_equal original, File.read(File.join(root, "CHANGELOG.md"))
    end
  end

  def test_commands_parse_standard_output_only_and_report_failures_with_both_streams
    commands = Release::Commands.new(root: TestSupport::ROOT, out: StringIO.new)
    noisy = [RbConfig.ruby, "-e", "warn 'noise'; puts '{\"ok\": true}'"]

    assert_equal({ "ok" => true }, commands.json(noisy))
    error = assert_raises(RuntimeError) { commands.call([RbConfig.ruby, "-e", "puts 'partial'; warn 'why'; exit 1"]) }

    assert_includes error.message, "partial"
    assert_includes error.message, "why"
  end

  def test_dry_run_checks_remote_but_never_writes_or_pushes
    repository do |root|
      commands = []
      before = File.read(File.join(root, "CHANGELOG.md"))
      workflow("0.2.0", root: root, dry_run: true, runner: workflow_runner(commands),
                        out: StringIO.new).run

      assert_equal before, File.read(File.join(root, "CHANGELOG.md"))
      assert_equal "0.1.0", Release.version(root: root)
      mutations = %w[switch commit push create tag]

      refute(commands.any? { |args| mutations.include?(args[1]) && args[2] != "--list" })
    end
  end

  def test_release_refuses_another_repository_before_writing
    repository do |root|
      commands = []
      runner = workflow_runner(commands, repository: "someone/another-project")
      error = assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, push: true, runner: runner, out: StringIO.new).run
      end

      assert_match(/origin repository/, error.message)
      assert_equal "0.1.0", Release.version(root: root)
      refute(commands.any? { |args| args.first(2) == %w[git switch] })
    end
  end

  def test_failed_checks_leave_edits_for_review_without_a_commit_or_push
    repository do |root|
      commands = []
      runner = workflow_runner(commands, fail_at: %w[bundle exec rake check])
      assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, push: true, runner: runner, out: StringIO.new).run
      end

      assert_equal "0.2.0", Release.version(root: root)
      mutations = %w[commit push]

      refute(commands.any? { |args| mutations.include?(args[1]) })
    end
  end

  def test_default_stops_at_pull_request_and_push_mode_tags_the_verified_merge
    repository do |root|
      commands = []
      workflow("0.2.0", root: root, runner: workflow_runner(commands), out: StringIO.new).run

      assert_includes commands, ["git", "commit", "-S", "-m", "chore: release v0.2.0"]
      refute(commands.any? { |args| args.first(3) == %w[gh pr merge] })
      assert(commands.any? { |args| args.first(3) == %w[gh pr create] && args.include?("--body-file") })
    end
    repository do |root|
      commands = []
      workflow("0.2.0", root: root, push: true, runner: workflow_runner(commands), out: StringIO.new).run
      checks = commands.index { |args| args.first(3) == %w[gh pr checks] }
      merge = commands.index { |args| args.first(3) == %w[gh pr merge] }

      assert_operator checks, :<, merge
      assert_includes commands, ["git", "tag", "-s", "v0.2.0", "-m", "Release 0.2.0", "b" * 40]
      assert_includes commands, %w[git push origin v0.2.0]
      assert_includes commands, %w[git verify-tag v0.2.0]
    end
  end

  def test_failed_remote_checks_never_merge_or_tag
    repository do |root|
      commands = []
      runner = workflow_runner(commands, fail_at: %w[gh pr checks])
      assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, push: true, runner: runner, out: StringIO.new).run
      end

      refute(commands.any? { |args| args.first(3) == %w[gh pr merge] })
      refute(commands.any? { |args| args.first(3) == %w[git tag -s] })
    end
  end

  def test_merge_is_pinned_and_ancestry_failure_prevents_tagging
    repository do |root|
      commands = []
      runner = workflow_runner(commands, fail_at: %w[git merge-base --is-ancestor])
      assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, push: true, runner: runner, out: StringIO.new).run
      end
      merge = commands.find { |args| args.first(3) == %w[gh pr merge] }

      assert_equal "a" * 40, merge.fetch(merge.index("--match-head-commit") + 1)
      assert_includes commands, %w[git verify-commit HEAD]
      assert_includes commands, ["git", "merge-base", "--is-ancestor", "a" * 40, "b" * 40]
      refute(commands.any? { |args| args.first(3) == %w[git tag -s] })
    end
  end
end
