# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/changelog"

class ChangelogTest < Minitest::Test
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
  end

  def test_releases_are_read_newest_first_with_yanked_ones
    assert_equal %w[0.2.0 0.1.0], Changelog.releases(RELEASED).map(&:version)
  end

  def test_headings_dates_and_sections_must_follow_the_format
    { 'heading "## 0.2.0" must be "## [Unreleased]" or "## [X.Y.Z] - YYYY-MM-DD"' =>
        RELEASED.sub("## [0.2.0] - 2026-10-04", "## 0.2.0"),
      '"## [Unreleased]" must appear once, before every release' => RELEASED.sub("## [Unreleased]\n", ""),
      "[0.1.0] is dated 2026-02-30, which is not a calendar date; use YYYY-MM-DD" =>
        RELEASED.sub("2026-10-01", "2026-02-30"),
      "[0.2.0] is dated in the future: 2026-10-05" => RELEASED.sub("2026-10-04", "2026-10-05"),
      'section "### New" must be one of Added, Changed, Deprecated, Removed, Fixed, Security' =>
        RELEASED.sub("### Fixed", "### New") }.each do |problem, text|
      assert_includes Changelog.problems(text, today: TODAY), problem
    end
  end

  def test_releases_must_be_listed_newest_first
    assert_includes Changelog.problems(RELEASED.sub("2026-10-04", "2026-09-30"), today: TODAY),
                    "releases must be listed newest first"
  end

  def test_a_release_must_appear_once
    repeated = RELEASED.sub("## [0.1.0] - 2026-10-01 [YANKED]", "## [0.2.0] - 2026-10-01")

    assert_includes Changelog.problems(repeated, today: TODAY), "[0.2.0] appears more than once"
  end

  def test_a_release_must_have_entries
    assert_includes Changelog.problems(RELEASED.sub("- The first release.\n", ""), today: TODAY),
                    '[0.1.0] has no entries; add at least one "- " line'
  end

  def test_link_references_follow_the_headings_in_order
    expected = "link references must be, in this order:\n[Unreleased]: #{URL}/compare/v0.2.0...HEAD\n" \
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
    assert_equal ["link references must be, in this order:\n#{text.lines.last(3).join.chomp}"],
                 Changelog.problems(text.sub("compare/v0.2.0", "compare/v0.1.1"), today: TODAY)
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
  end

  def test_a_version_is_released_only_with_its_full_heading
    assert Changelog.released?(RELEASED, "0.1.0")
    refute Changelog.released?(RELEASED, "0.1")
  end
end
