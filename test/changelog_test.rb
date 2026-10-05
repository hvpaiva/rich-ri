# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/changelog"
require_relative "release_support"

class ChangelogTest < Minitest::Test
  include ReleaseFixtures

  URL = "https://github.com/hvpaiva/rich-ri"
  TODAY = Date.new(2026, 10, 4)
  RELEASED = <<~TEXT.freeze
    # Changelog

    ## [Unreleased]

    ### Fixed

    - A pending fix.

    ## [0.2.0] - 2026-10-04

    ### Added

    - The second release.

    ## [0.1.0] - 2026-10-01 [YANKED]

    ### Added

    - The first release.

    [Unreleased]: #{URL}/compare/v0.2.0...HEAD
    [0.2.0]: #{URL}/releases/tag/v0.2.0
    [0.1.0]: #{URL}/releases/tag/v0.1.0
  TEXT
  REFERENCES = RELEASED.lines.last(3).freeze

  def test_the_project_changelog_is_well_formed
    assert_empty Changelog.problems(File.read(File.join(TestSupport::ROOT, Changelog::PATH)))
  end

  def test_released_and_unreleased_only_changelogs_are_accepted
    unreleased = "# Changelog\n\n## [Unreleased]\n\n- A change.\n\n[Unreleased]: #{URL}/commits/main\n"

    assert_empty Changelog.problems(RELEASED, today: TODAY)
    assert_empty Changelog.problems(unreleased, today: TODAY)
    assert_equal %w[0.2.0 0.1.0], Changelog.releases(RELEASED).map(&:version)
  end

  def test_headings_dates_and_sections_must_follow_the_format
    { 'Heading "## 0.2.0" must be "## [Unreleased]" or "## [X.Y.Z] - YYYY-MM-DD"' =>
        RELEASED.sub("## [0.2.0] - 2026-10-04", "## 0.2.0"),
      '"## [Unreleased]" must appear once, before every release' => RELEASED.sub("## [Unreleased]\n", ""),
      "[0.1.0] has an invalid date: 2026-02-30" => RELEASED.sub("2026-10-01", "2026-02-30"),
      "[0.2.0] is dated in the future: 2026-10-05" => RELEASED.sub("2026-10-04", "2026-10-05"),
      'Section "### New" must be one of Added, Changed, Deprecated, Removed, Fixed, Security' =>
        RELEASED.sub("### Fixed", "### New") }.each do |problem, text|
      assert_includes Changelog.problems(text, today: TODAY), problem
    end
  end

  def test_releases_are_unique_newest_first_and_never_empty
    swapped = RELEASED.sub("2026-10-04", "2026-09-30")
    repeated = RELEASED.sub("## [0.1.0] - 2026-10-01 [YANKED]", "## [0.2.0] - 2026-10-01")

    assert_includes Changelog.problems(swapped, today: TODAY), "Releases must be listed newest first"
    assert_includes Changelog.problems(repeated, today: TODAY), "[0.2.0] appears more than once"
    assert_includes Changelog.problems(RELEASED.sub("- The first release.\n", ""), today: TODAY),
                    '[0.1.0] has no entries; add at least one "- " line'
  end

  def test_link_references_follow_the_headings_in_order
    expected = "Link references must be, in this order:\n[Unreleased]: #{URL}/compare/v0.2.0...HEAD\n" \
               "[0.2.0]: #{URL}/releases/tag/v0.2.0\n[0.1.0]: #{URL}/releases/tag/v0.1.0"
    ascending = RELEASED.sub(REFERENCES.join, REFERENCES.values_at(0, 2, 1).join)

    [ascending, RELEASED.sub("compare/v0.2.0", "compare/v0.1.0"), RELEASED.sub(REFERENCES.last, ""),
     RELEASED.sub("releases/tag/v0.2.0", "tree/v0.2.0")].each do |text|
      assert_equal [expected], Changelog.problems(text, today: TODAY)
    end
    assert_empty Changelog.problems("#{RELEASED}[an issue]: #{URL}/issues/1\n", today: TODAY)
  end

  def test_a_later_hotfix_is_listed_first_while_unreleased_compares_with_the_highest_version
    text = <<~TEXT
      ## [Unreleased]

      ## [0.1.1] - 2026-10-04

      - A fix for the previous series.

      ## [0.2.0] - 2026-10-02

      - The next series.

      [Unreleased]: #{URL}/compare/v0.2.0...HEAD
      [0.1.1]: #{URL}/releases/tag/v0.1.1
      [0.2.0]: #{URL}/releases/tag/v0.2.0
    TEXT

    assert_empty Changelog.problems(text, today: TODAY)
    assert_equal 1, Changelog.problems(text.sub("compare/v0.2.0", "compare/v0.1.1"), today: TODAY).length
  end

  def test_cutting_a_release_dates_the_entries_and_lists_its_link_first
    cut = Changelog.cut(RELEASED, "0.3.0", TODAY)

    assert_empty Changelog.problems(cut, today: TODAY)
    assert_includes cut, "## [Unreleased]\n\n## [0.3.0] - 2026-10-04\n\n### Fixed\n\n- A pending fix.\n"
    assert cut.end_with?("[Unreleased]: #{URL}/compare/v0.3.0...HEAD\n[0.3.0]: #{URL}/releases/tag/v0.3.0\n" \
                         "[0.2.0]: #{URL}/releases/tag/v0.2.0\n[0.1.0]: #{URL}/releases/tag/v0.1.0\n")
    refute Changelog.entries?(cut, "Unreleased")
  end

  def test_notes_are_the_entries_of_one_section_only
    assert_equal "### Fixed\n\n- A pending fix.", Changelog.notes(RELEASED, "Unreleased")
    assert_equal "### Added\n\n- The first release.", Changelog.notes(RELEASED, "0.1.0")
    assert_empty Changelog.notes(RELEASED, "9.9.9")
    assert Changelog.released?(RELEASED, "0.1.0")
    refute Changelog.released?(RELEASED, "0.1")
  end

  def test_user_visible_changes_need_an_entry
    visible = %w[lib/rich_ri/cli.rb exe/rich-ri completions/rich-ri.zsh man/man1/rich-ri.1]

    assert_equal(visible, visible.select { |path| Changelog.entry_missing?([path, "test/cli_test.rb"]) })
    assert_empty(visible.select { |path| Changelog.entry_missing?([path, "CHANGELOG.md"]) })
    refute Changelog.entry_missing?(%w[rakelib/release.rb test/cli_test.rb README.md library/notes.md])
    refute Changelog.entry_missing?([])
  end

  def test_a_branch_that_changes_what_users_see_needs_an_entry
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "README.md" => "Read me", "rakelib/tools.rb" => "# maintenance")

      assert_empty Changelog.lint(root: root, base: base)
      commit(root, "man/man1/rich-ri.1" => ".TH RICH-RI 1")

      assert_equal [Changelog::ENTRY_REQUIRED], Changelog.lint(root: root, base: base)
      assert_empty Changelog.lint(root: root)
      commit(root, "CHANGELOG.md" => File.read(File.join(root, "CHANGELOG.md")).sub("- Readable", "- More readable"))

      assert_empty Changelog.lint(root: root, base: base)
    end
  end

  def test_the_comparison_starts_where_the_branch_left_its_base
    repository do |root|
      original = git(root, "rev-parse", "HEAD")
      commit(root, "lib/base.rb" => "# merged to the base branch meanwhile")
      base = git(root, "rev-parse", "HEAD")
      git(root, "switch", "-qc", "topic", original)
      commit(root, "docs/usage.md" => "Usage")

      assert_empty Changelog.lint(root: root, base: base)
      error = assert_raises(Changelog::Error) { Changelog.lint(root: root, base: "missing") }

      assert_equal "Cannot compare HEAD with missing", error.message
    end
  end

  def test_the_command_checks_the_repository_it_runs_in
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "lib/rich_ri.rb" => "# changed")
      _out, err, status = lint_changelog(root, base)

      assert_equal 1, status.exitstatus
      assert_equal "#{Changelog::PATH}: #{Changelog::ENTRY_REQUIRED}\n", err
    end
  end

  def test_the_command_reports_a_base_it_cannot_compare_with
    repository do |root|
      _out, err, status = lint_changelog(root, "missing-base")

      assert_equal 1, status.exitstatus
      assert_equal "lint-changelog: Cannot compare HEAD with missing-base\n", err
    end
  end

  def test_the_command_honors_the_waiver
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "lib/rich_ri.rb" => "# changed")
      _out, err, status = lint_changelog(root, base, waiver: "true")

      assert_predicate status, :success?, err
    end
  end

  def test_the_command_outside_a_repository_names_the_file_it_cannot_read
    Dir.mktmpdir("rich-ri-empty-") do |root|
      _out, err, status = lint_changelog(root)

      assert_equal 1, status.exitstatus
      assert_equal "lint-changelog: Cannot read CHANGELOG.md in #{root}: No such file or directory\n", err
    end
  end

  private

  def lint_changelog(root, *, waiver: nil)
    Open3.capture3(GitSupport::ENVIRONMENT.merge("SKIP_CHANGELOG" => waiver), RbConfig.ruby,
                   File.join(TestSupport::ROOT, "bin/lint-changelog"), *, chdir: root)
  end
end
