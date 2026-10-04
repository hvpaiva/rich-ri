# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release_workflow"
require_relative "release_support"

class ReleaseRecoveryTest < Minitest::Test
  include ReleaseFixtures

  def test_preflight_failure_prevents_worktree_or_remote_changes
    repository do |root|
      configuration = Object.new
      def configuration.verify! = raise(GitHub::Error, "missing release environment")
      commands = []
      error = assert_raises(GitHub::Error) do
        Release::Workflow.new("0.2.0", root: root, configuration: configuration,
                                       runner: workflow_runner(commands), out: StringIO.new).run
      end

      assert_match(/release environment/, error.message)
      assert_equal [%w[git remote get-url origin]], commands
      assert_equal "0.1.0", Release.version(root: root)
    end
  end

  def test_partial_preparation_can_resume_on_a_later_day_without_overwriting_unrelated_edits
    repository do |root|
      source = [Release::VERSION_FILE, "CHANGELOG.md"].to_h { |path| [path, File.read(File.join(root, path))] }
      yesterday = Time.now.utc.to_date - 1
      changes = Release.changes("0.2.0", root: root, date: yesterday)
      File.write(File.join(root, "CHANGELOG.md"), changes.fetch("CHANGELOG.md"))
      state = { branch: "release/v0.2.0", dirty: " M CHANGELOG.md\n", source: source.transform_keys do |key|
        "HEAD:#{key}"
      end }
      commands = []
      workflow("0.2.0", root: root, runner: workflow_runner(commands, state: state), out: StringIO.new).run

      assert_equal changes.fetch("CHANGELOG.md"), File.read(File.join(root, "CHANGELOG.md"))
      assert_equal "0.2.0", Release.version(root: root)
      assert(commands.any? { |args| args.first(3) == %w[gh pr create] })
      File.write(File.join(root, "CHANGELOG.md"), "#{changes.fetch('CHANGELOG.md')}unrelated\n")
      commands.clear
      assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, runner: workflow_runner(commands, state: state), out: StringIO.new).run
      end

      refute(commands.any? { |args| args.first(2) == %w[git commit] })
    end
  end

  def test_open_pr_is_reused_but_foreign_pr_and_wrong_version_are_never_merged
    [{ pr: release_pr("OPEN"), release_version: "0.3.0" },
     { pr: release_pr("OPEN").merge("isCrossRepository" => true) }].each do |state|
      repository do |root|
        commands = []
        assert_raises(RuntimeError) do
          workflow("0.2.0", root: root, push: true, runner: workflow_runner(commands, state: state),
                            out: StringIO.new).run
        end

        refute(commands.any? { |args| args.first(3) == %w[gh pr merge] })
        refute(commands.any? { |args| args.first(3) == %w[gh pr create] })
      end
    end
  end

  def test_merged_pr_and_local_tag_resume_without_duplicate_commit_pr_or_tag
    repository do |root|
      commands = []
      workflow("0.2.0", root: root, push: true,
                        runner: workflow_runner(commands, state: { pr: release_pr, local_tag: true }),
                        out: StringIO.new).run

      assert_includes commands, %w[git push origin v0.2.0]
      refute(commands.any? { |args| args.first(2) == %w[git commit] })
      refute_includes commands.map { |args| args.first(3) }, %w[git tag -s]
      refute_includes commands.map { |args| args.first(3) }, %w[gh pr create]
    end
  end

  def test_open_pr_resumes_at_pinned_merge_and_missing_push_never_creates_a_tag
    repository do |root|
      commands = []
      workflow("0.2.0", root: root, push: true,
                        runner: workflow_runner(commands, state: { pr: release_pr("OPEN") }), out: StringIO.new).run

      refute(commands.any? { |args| args.first(3) == %w[gh pr create] })
      merge = commands.find { |args| args.first(3) == %w[gh pr merge] }

      assert_equal "a" * 40, merge.fetch(merge.index("--match-head-commit") + 1)
      commands.clear
      workflow("0.2.0", root: root, runner: workflow_runner(commands, state: { pr: release_pr }), out: StringIO.new).run

      refute_includes commands.map { |args| args.first(3) }, %w[git tag -s]
      refute(commands.any? { |args| args.first(2) == %w[git push] })
    end
  end

  def test_existing_remote_tag_is_observation_only_and_other_target_is_refused
    repository do |root|
      commands = []
      state = { pr: release_pr, local_tag: true, remote_tag: "b" * 40 }
      workflow("0.2.0", root: root, push: true, runner: workflow_runner(commands, state: state), out: StringIO.new).run

      refute(commands.any? { |args| args.first(2) == %w[git push] || args.first(3) == %w[gh run rerun] })
      commands.clear
      state[:remote_tag] = "d" * 40
      error = assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, push: true, runner: workflow_runner(commands, state: state),
                          out: StringIO.new).run
      end

      assert_match(/never be moved/, error.message)
      refute(commands.any? { |args| args.first(2) == %w[git push] })
    end
  end

  def test_dry_run_is_read_only_for_open_pr_prepared_branch_and_tags
    mutations = %w[commit push create merge]
    [{ pr: release_pr("OPEN") }, { branch: "release/v0.2.0" }, { pr: release_pr },
     { pr: release_pr, local_tag: true }, { pr: release_pr, local_tag: true, remote_tag: "b" * 40 }].each do |state|
      repository do |root|
        commands = []
        before = File.read(File.join(root, "CHANGELOG.md"))
        workflow("0.2.0", root: root, dry_run: true, runner: workflow_runner(commands, state: state),
                          out: StringIO.new).run

        assert_equal before, File.read(File.join(root, "CHANGELOG.md"))
        refute(commands.any? { |args| mutations.include?(args[1]) })
        refute(commands.any? { |args| args.first == "bundle" || args.first(3) == %w[git tag -s] })
      end
    end
  end

  def test_a_failure_after_waiting_classifies_publication_before_suggesting_recovery
    repository do |root|
      commands = []
      state = { pr: release_pr, local_tag: true, remote_tag: "b" * 40, run_status: "in_progress", conclusion: "failure",
                jobs: [{ "name" => "publish", "conclusion" => "success", "databaseId" => 40 },
                       { "name" => "github-release", "conclusion" => "failure", "databaseId" => 41 }] }
      error = assert_raises(RuntimeError) do
        workflow("0.2.0", root: root, push: true, runner: workflow_runner(commands, state: state),
                          out: StringIO.new).run
      end

      assert_includes commands, %w[gh run watch 123 --repo hvpaiva/rich-ri]
      assert_match(/RubyGems publication succeeded/, error.message)
      assert_match(/gh run rerun 123 --job 41/, error.message)
      refute(commands.any? { |args| args.first(3) == %w[gh run rerun] })
    end
  end

  def test_verification_rejects_invalid_date_empty_notes_wrong_links_and_duplicates
    [released_changelog.sub("2026-10-04", "2026-99-99"), released_changelog.sub("- Readable documentation.", ""),
     released_changelog.sub("releases/tag/v0.2.0", "unrelated"),
     "#{released_changelog}\n## [0.2.0] - 2026-10-04\n"].each do |text|
      assert_raises(RuntimeError) { Release.verify(tag: "v0.2.0", version: "0.2.0", changelog: text) }
    end
  end
end
