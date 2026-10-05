# frozen_string_literal: true

require "test_helper"
require "commit_support"

class CommitCommandTest < Minitest::Test
  include CommitSupport

  HELP = <<~TEXT
    Usage: ruby bin/lint-commits [RANGE]

    Checks that each commit in RANGE, such as origin/main..HEAD (default: HEAD),
    has a finished Conventional Commit subject and no generated attribution.
    PR_TITLE, when set, is checked like a subject, and PR_BODY for attribution.
  TEXT

  def test_explains_what_it_checks
    repository do |root|
      out, err, status = lint(root, "--help")

      assert_equal [0, HELP, ""], [status.exitstatus, out, err]
    end
  end

  def test_refuses_an_option_as_its_range
    repository do |root|
      injected = File.join(root, "injected")
      out, err, status = lint(root, "--output=#{injected}")

      assert_equal [2, "", "lint-commits: invalid option: --output=#{injected}\n#{HELP}"], [status.exitstatus, out, err]
      refute_path_exists injected
    end
  end

  def test_a_range_after_a_double_dash_is_still_a_range
    repository do |root|
      injected = File.join(root, "injected")
      out, err, status = lint(root, "--", "--output=#{injected}")

      assert_equal [1, "", "lint-commits: cannot read commits: fatal: bad revision '--output=#{injected}'\n"],
                   [status.exitstatus, out, err]
      refute_path_exists injected
    end
  end

  def test_refuses_more_than_one_range
    repository do |root|
      out, err, status = lint(root, "HEAD", "HEAD~1..HEAD")

      assert_equal [2, "", "lint-commits: needless argument: HEAD~1..HEAD\n#{HELP}"], [status.exitstatus, out, err]
    end
  end

  def test_control_characters_in_an_option_are_shown_as_text
    repository do |root|
      out, err, status = lint(root, "--\e[2J")

      assert_equal [2, "", "lint-commits: invalid option: --\\e[2J\n#{HELP}"], [status.exitstatus, out, err]
    end
  end
end
