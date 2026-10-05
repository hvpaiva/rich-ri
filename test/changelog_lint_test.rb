# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/changelog_lint"
require_relative "release_support"

class ChangelogLintTest < Minitest::Test
  include ReleaseFixtures

  def test_user_visible_changes_need_an_entry
    visible = %w[lib/rich_ri/cli.rb exe/rich-ri completions/rich-ri.zsh man/man1/rich-ri.1]

    assert_equal(visible, visible.select { |path| Changelog::Lint.entry_missing?([path, "test/cli_test.rb"]) })
    assert_empty(visible.select { |path| Changelog::Lint.entry_missing?([path, "CHANGELOG.md"]) })
    refute Changelog::Lint.entry_missing?(%w[rakelib/release.rb test/cli_test.rb README.md library/notes.md])
    refute Changelog::Lint.entry_missing?([])
  end

  def test_a_branch_that_changes_what_users_see_needs_an_entry
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "README.md" => "Read me", "rakelib/tools.rb" => "# maintenance")

      assert_empty Changelog::Lint.problems(root: root, base: base)
      commit(root, "man/man1/rich-ri.1" => ".TH RICH-RI 1")

      assert_equal [Changelog::Lint::ENTRY_REQUIRED], Changelog::Lint.problems(root: root, base: base)
      assert_empty Changelog::Lint.problems(root: root)
      commit(root, "CHANGELOG.md" => File.read(File.join(root, "CHANGELOG.md")).sub("- Readable", "- More readable"))

      assert_empty Changelog::Lint.problems(root: root, base: base)
    end
  end

  def test_a_file_name_that_is_not_utf8_is_still_classified
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "notes-\xFF.txt".b => "maintenance")

      assert_empty Changelog::Lint.problems(root: root, base: base)
      commit(root, "lib/rich_ri/\xFF.rb".b => "# user-visible")

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

      assert_equal "Cannot compare HEAD with missing: fatal: bad revision 'missing...HEAD'", error.message
    end
  end
end
