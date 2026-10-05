# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/changelog_lint"
require_relative "release_support"

class ChangelogLintTest < Minitest::Test
  include ReleaseFixtures

  def test_each_change_users_can_see_needs_an_entry
    %w[lib/rich_ri/cli.rb exe/rich-ri completions/rich-ri.zsh man/man1/rich-ri.1 rich-ri.gemspec].each do |path|
      assert_equal [Changelog::Lint::ENTRY_REQUIRED], lint_after(path => "changed", "test/cli_test.rb" => "test"),
                   path
    end
  end

  def test_maintenance_and_guides_need_no_entry
    assert_empty lint_after("rakelib/release.rb" => "#", "test/cli_test.rb" => "#", "README.md" => "Read me",
                            "library/notes.md" => "Notes", "gemfiles/rich-ri.gemspec.lock" => "#")
  end

  def test_a_new_line_under_unreleased_is_the_entry
    assert_empty(lint_after("lib/rich_ri/cli.rb" => "changed") do |changelog|
      changelog.sub("- Readable documentation.\n", "- Readable documentation.\n- Faster lookups.\n")
    end)
  end

  def test_an_edit_outside_unreleased_is_not_an_entry
    assert_equal([Changelog::Lint::ENTRY_REQUIRED], lint_after("lib/rich_ri/cli.rb" => "changed") do |changelog|
      changelog.sub("# Changelog", "# Changelog\n\nNotable changes to rich-ri.")
    end)
  end

  def test_entries_the_base_released_after_the_branch_forked_are_not_the_branch_entry
    repository do |root|
      original = git(root, "rev-parse", "HEAD")
      changelog = File.read(File.join(root, Changelog::PATH))
      base = commit(root, Changelog::PATH => Changelog.cut(changelog, "0.2.0", Date.new(2026, 10, 4)))
      git(root, "switch", "-qc", "topic", original)
      commit(root, "lib/rich_ri/cli.rb" => "changed")

      assert_equal [Changelog::Lint::ENTRY_REQUIRED], Changelog::Lint.problems(root: root, base: base)
    end
  end

  def test_a_release_records_the_entries_it_moves_out_of_unreleased
    assert_empty(lint_after("lib/rich_ri/version.rb" => "VERSION = \"0.2.0\"\n") do |changelog|
      Changelog.cut(changelog, "0.2.0", Date.new(2026, 10, 4))
    end)
  end

  def test_without_a_base_only_the_structure_is_checked
    repository do |root|
      commit(root, "man/man1/rich-ri.1" => ".TH RICH-RI 1")

      assert_empty Changelog::Lint.problems(root: root)
    end
  end

  def test_a_file_name_that_is_not_utf8_is_still_classified
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit_in_index(root, "notes-\xFF.txt".b)

      assert_empty Changelog::Lint.problems(root: root, base: base)
      commit_in_index(root, "lib/rich_ri/\xFF.rb".b)

      assert_equal [Changelog::Lint::ENTRY_REQUIRED], Changelog::Lint.problems(root: root, base: base)
    end
  end

  def test_the_comparison_starts_where_the_branch_left_its_base
    repository do |root|
      original = git(root, "rev-parse", "HEAD")
      commit(root, "lib/base.rb" => "# merged to the base branch meanwhile")
      base = git(root, "rev-parse", "HEAD")
      git(root, "switch", "-qc", "topic", original)
      commit(root, "docs/usage.md" => "Usage")

      assert_empty Changelog::Lint.problems(root: root, base: base)
    end
  end

  def test_a_comparison_git_refuses_carries_the_reason_git_gives
    repository do |root|
      error = assert_raises(Changelog::Lint::Error) { Changelog::Lint.problems(root: root, base: "missing") }

      assert_equal "cannot compare HEAD with missing: fatal: bad revision 'missing...HEAD'", error.message
    end
  end

  private

  def lint_after(files)
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      changelog = File.read(File.join(root, Changelog::PATH))
      files = files.merge(Changelog::PATH => yield(changelog)) if block_given?
      commit(root, files)
      Changelog::Lint.problems(root: root, base: base)
    end
  end

  # APFS refuses file names that are not UTF-8, so the name reaches Git through the index alone.
  def commit_in_index(root, path)
    blob = git(root, "hash-object", "-w", File::NULL)
    git(root, "update-index", "--add", "--cacheinfo", "100644,#{blob},#{path}")
    git(root, "commit", "-qm", "test: change fixture")
  end
end
