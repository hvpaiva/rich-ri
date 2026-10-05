# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/changelog"
require_relative "release_support"

class ChangelogCommandTest < Minitest::Test
  include ReleaseFixtures

  HELP = <<~TEXT
    Usage: ruby bin/lint-changelog [BASE]

    Checks the structure of CHANGELOG.md in the current repository. With BASE, a revision
    such as origin/main, a branch that changes lib/, exe/, completions/ or man/ also needs
    an entry under "## [Unreleased]". SKIP_CHANGELOG=1 waives that entry.
  TEXT

  def test_checks_the_repository_it_runs_in
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "lib/rich_ri.rb" => "# changed")
      _out, err, status = lint_changelog(root, base)

      assert_equal 1, status.exitstatus
      assert_equal "#{Changelog::PATH}: #{Changelog::ENTRY_REQUIRED}\n", err
    end
  end

  def test_reports_a_base_it_cannot_compare_with
    repository do |root|
      git(root, "switch", "-q", "--orphan", "unrelated")
      unrelated = commit(root, "README.md" => "Unrelated history")
      git(root, "switch", "-q", "main")
      _out, err, status = lint_changelog(root, unrelated)

      assert_equal 1, status.exitstatus
      assert_equal "lint-changelog: Cannot compare HEAD with #{unrelated}: " \
                   "fatal: #{unrelated}...HEAD: no merge base\n", err
    end
  end

  def test_honors_the_documented_waiver_values
    %w[1 true].each do |waiver|
      repository do |root|
        base = git(root, "rev-parse", "HEAD")
        commit(root, "lib/rich_ri.rb" => "# changed")
        _out, err, status = lint_changelog(root, base, waiver: waiver)

        assert_predicate status, :success?, "SKIP_CHANGELOG=#{waiver}: #{err}"
      end
    end
  end

  def test_explains_its_base_and_waiver
    out, err, status = lint_changelog(TestSupport::TEMP, "--help")

    assert_predicate status, :success?, err
    assert_equal HELP, out
  end

  def test_refuses_an_option_or_a_name_that_is_not_a_revision_as_its_base
    repository do |root|
      injected = File.join(root, "injected")
      { "--output=#{injected}" => "invalid option: --output=#{injected}",
        "missing-base" => "invalid argument: missing-base (use a revision such as origin/main)" }.each do |base, reason|
        out, err, status = lint_changelog(root, base)

        assert_equal [2, "", "lint-changelog: #{reason}\n#{HELP}"], [status.exitstatus, out, err]
      end
      assert_empty Dir.glob("#{injected}*")
    end
  end

  def test_refuses_more_than_one_base
    out, err, status = lint_changelog(TestSupport::TEMP, "origin/main", "HEAD")

    assert_equal [2, "", "lint-changelog: needless argument: HEAD\n#{HELP}"], [status.exitstatus, out, err]
  end

  def test_outside_a_repository_names_the_file_it_cannot_read
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
