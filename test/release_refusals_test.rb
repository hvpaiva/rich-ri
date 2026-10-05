# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release_workflow"
require_relative "release_support"

class ReleaseRefusalsTest < Minitest::Test
  include ReleaseFixtures

  def test_a_version_the_changelog_already_released_is_refused
    repository do |root|
      changelog = File.read(File.join(root, Changelog::PATH))
      commit(root, Changelog::PATH => Changelog.cut(changelog, "0.2.0", Date.new(2026, 10, 4)))

      assert_release_error("version already appears in the changelog") { Release.changes("0.2.0", root: root) }
    end
  end

  def test_a_release_without_notes_under_unreleased_is_refused
    repository do |root|
      commit(root, Changelog::PATH => "## [Unreleased]\n\n[Unreleased]: https://github.com/hvpaiva/rich-ri/commits/main\n")

      assert_release_error("add release notes under Unreleased first") { Release.changes("0.2.0", root: root) }
    end
  end

  def test_a_release_starts_only_from_its_base_or_its_own_branch
    assert_release_error("run from main or release/v0.2.0\n#{resume('bin/release 0.2.0')}") do
      run_release(branch: "feature")
    end
  end

  def test_unrelated_work_stops_the_resumption_of_an_open_pull_request
    assert_release_error("commit or stash unrelated work before continuing\n#{resume('bin/release 0.2.0')}") do
      run_release(pr: release_pr("OPEN"), dirty: " M README.md\n")
    end
  end

  def test_a_base_behind_origin_is_refused
    behind = lambda do |runner|
      lambda do |argv, **options|
        output, status = runner.call(argv, **options)
        [argv == %w[git rev-parse origin/main] ? "#{'f' * 40}\n" : output, status]
      end
    end

    assert_release_error("local main must match origin/main; pull first\n#{resume('bin/release 0.2.0')}") do
      run_release(wrap: behind)
    end
  end

  def test_unrelated_changes_on_the_release_branch_are_refused
    assert_release_error("unrelated changes on release/v0.2.0; commit or stash them first\n" \
                         "#{resume('bin/release 0.2.0')}") do
      run_release(branch: "release/v0.2.0", dirty: " M README.md\n")
    end
  end

  def test_a_local_tag_on_another_commit_is_never_replaced
    assert_release_error("local v0.2.0 is not an annotated tag of the release merge; it will never be replaced\n" \
                         "#{resume}") do
      run_release(push: true, pr: release_pr, local_tag: true, tag_sha: "d" * 40)
    end
  end

  private

  def run_release(push: false, wrap: ->(runner) { runner }, **state)
    repository do |root|
      workflow("0.2.0", root: root, push: push, runner: wrap.call(workflow_runner([], state: state)),
                        out: StringIO.new).run
    end
  end
end
