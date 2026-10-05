# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release"
require_relative "../rakelib/release_workflow"

require_relative "release_support"
require "program_support"

class ReleaseTest < Minitest::Test
  include ReleaseFixtures
  include ProgramSupport

  def test_preparation_updates_version_and_preserves_unreleased_for_next_changes
    repository do |root|
      changes = Release.changes("0.2.0", root: root, date: Date.new(2026, 10, 4))
      changelog = changes.fetch("CHANGELOG.md")

      assert_equal "VERSION = \"0.2.0\"\n", changes.fetch(Release::VERSION_FILE)
      assert_includes changelog, "## [Unreleased]\n\n## [0.2.0] - 2026-10-04"
      assert_includes changelog, "- Readable documentation."
      assert_includes changelog, "compare/v0.2.0...HEAD"
    end
  end

  def test_preparation_refuses_a_version_lower_than_the_current_one
    repository do |root|
      assert_release_error(/\Aversion cannot go backwards\z/) { Release.changes("0.0.1", root: root) }
    end
  end

  def test_preparation_refuses_a_version_that_is_not_stable_x_y_z
    repository do |root|
      %w[01.2.3 invalid 1.0.0.rc1].each do |version|
        assert_release_error(/\Ause a stable X\.Y\.Z version\z/) { Release.changes(version, root: root) }
      end
    end
  end

  def test_preparation_refuses_a_dirty_tree
    repository do |root|
      File.write(File.join(root, "unfinished"), "work")

      assert_release_error(/\Acommit or stash changes before preparing a release\z/) do
        Release.changes("0.2.0", root: root)
      end
    end
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
      assert_release_error(%r{origin repository must be hvpaiva/rich-ri}) do
        workflow("0.2.0", root: root, push: true, runner: runner, out: StringIO.new).run
      end

      assert_equal "0.1.0", Release.version(root: root)
      refute(commands.any? { |args| args.first(2) == %w[git switch] })
    end
  end

  def test_a_defect_is_not_reported_as_a_condition_the_maintainer_can_correct
    repository do |root|
      runner = ->(_argv, **) { raise NoMethodError, "defect" }
      error = assert_raises(NoMethodError) do
        workflow("0.2.0", root: root, runner: runner, out: StringIO.new).run
      end

      assert_equal "defect", error.message
    end
  end

  def test_bin_release_reports_a_condition_the_maintainer_can_correct_in_one_line
    out, err, status = Open3.capture3(RbConfig.ruby, File.join(TestSupport::ROOT, "bin/release"), "01.2.3")

    assert_equal [1, "", "release: use a stable X.Y.Z version\n"], [status.exitstatus, out, err]
  end

  def test_bin_release_without_gh_says_how_to_install_it_and_resume
    github_origin do |environment|
      Dir.mktmpdir("rich-ri-no-gh-") do |bin|
        link_ruby(bin, bundler: false)
        link_program(bin, "git")
        out, err, status = Open3.capture3(environment.merge("PATH" => bin), RbConfig.ruby,
                                          File.join(TestSupport::ROOT, "bin/release"), "0.2.0")

        assert_equal [1, "==> git remote get-url origin\n",
                      "release: gh is not installed; install it with your package manager\n" \
                      "After resolving the problem, rerun bin/release 0.2.0. " \
                      "Existing pull requests and tags are inspected before any new action.\n"],
                     [status.exitstatus, out, err]
      end
    end
  end

  def test_bin_release_keeps_the_class_and_backtrace_of_a_defect
    github_origin do |environment|
      Dir.mktmpdir("rich-ri-gh-") do |bin|
        link_ruby(bin, bundler: false)
        link_program(bin, "git")
        # The repository settings arrive as a list, which the configuration code does not expect.
        write_program(bin, "gh", "printf 'HTTP/2.0 200 OK\\r\\n\\r\\n[]'")
        script = File.join(TestSupport::ROOT, "bin/release")
        out, err, status = Open3.capture3(environment.merge("PATH" => bin), RbConfig.ruby, script, "0.2.0")

        assert_equal [1, "==> git remote get-url origin\n"], [status.exitstatus, out]
        assert_match(/\A\S+:\d+:in '.+': no implicit conversion of String into Integer \(TypeError\)\n/, err)
        assert_match(/^\tfrom #{Regexp.escape(script)}:\d+:in '<main>'\n\z/, err)
      end
    end
  end

  def test_failed_checks_leave_edits_for_review_without_a_commit_or_push
    repository do |root|
      commands = []
      runner = workflow_runner(commands, fail_at: %w[bundle exec rake check])
      assert_release_error(/bundle exec rake check failed/) do
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
      create = commands.find { |args| args.first(3) == %w[gh pr create] }

      assert_includes create, "--body-file"
      assert_equal %w[@me release], [create.fetch(create.index("--assignee") + 1),
                                     create.fetch(create.index("--label") + 1)]
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
      assert_release_error(/gh pr checks .+ failed/) do
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
      assert_release_error(/git merge-base --is-ancestor .+ failed/) do
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
