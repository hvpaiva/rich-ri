# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/changelog_lint"
require_relative "release_support"
require "program_support"

class ChangelogCommandTest < Minitest::Test
  include ReleaseFixtures
  include ProgramSupport

  UNWAIVED = GitSupport::ENVIRONMENT.merge("SKIP_CHANGELOG" => nil).freeze
  HELP = <<~TEXT
    Usage: ruby bin/lint-changelog [BASE]

    Checks the structure of CHANGELOG.md in the current directory.

    BASE is a revision such as origin/main. When it is given, a branch that changes
    lib/, exe/, completions/, man/ or rich-ri.gemspec needs a new entry under
    "## [Unreleased]". SKIP_CHANGELOG=1 or SKIP_CHANGELOG=true waives that entry;
    the structure is still checked.
  TEXT
  ENTRY_REQUIRED = "lint-changelog: CHANGELOG.md: changes to lib/, exe/, completions/, man/ or rich-ri.gemspec " \
                   'need a new entry under "## [Unreleased]"; if users cannot see the change, set ' \
                   "SKIP_CHANGELOG=1 and ask a maintainer for the skip-changelog label on the pull request\n"

  def test_checks_the_repository_it_runs_in
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "lib/rich_ri.rb" => "# changed")
      _out, err, status = lint_changelog(root, base)

      assert_equal 1, status.exitstatus
      assert_equal ENTRY_REQUIRED, err
    end
  end

  def test_reports_a_base_it_cannot_compare_with
    repository do |root|
      git(root, "switch", "-q", "--orphan", "unrelated")
      unrelated = commit(root, "README.md" => "Unrelated history")
      git(root, "switch", "-q", "main")
      _out, err, status = lint_changelog(root, unrelated)

      assert_equal 1, status.exitstatus
      assert_equal "lint-changelog: cannot compare HEAD with #{unrelated}: " \
                   "fatal: #{unrelated}...HEAD: no merge base\n", err
    end
  end

  def test_a_changelog_git_cannot_read_where_the_branch_forked_stops_the_check
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      blob = git(root, "rev-parse", "#{base}:CHANGELOG.md")
      commit(root, "lib/rich_ri.rb" => "# changed")
      File.delete(File.join(root, ".git/objects", blob[0, 2], blob[2..]))
      out, err, status = lint_changelog(root, base)

      assert_equal [1, "", "lint-changelog: cannot read CHANGELOG.md at #{base}: " \
                           "fatal: bad object #{base}:CHANGELOG.md\n"], [status.exitstatus, out, err]
    end
  end

  def test_control_characters_in_the_changelog_are_shown_as_text
    repository do |root|
      changelog = File.read(File.join(root, Changelog::PATH))
      commit(root, Changelog::PATH => changelog.sub("### Added", "### \e]0;renamed\a\e[31mAdded")
                                               .sub("[Unreleased]: ", "## \e[2JNews\n[Unreleased]: "))
      out, err, status = lint_changelog(root)

      assert_equal [1, "", "lint-changelog: CHANGELOG.md: heading \"## \\e[2JNews\" must be \"## [Unreleased]\" or " \
                           "\"## [X.Y.Z] - YYYY-MM-DD\"\n" \
                           "lint-changelog: CHANGELOG.md: section \"### \\e]0;renamed\\a\\e[31mAdded\" " \
                           "must be one of Added, Changed, Deprecated, Removed, Fixed, Security\n"],
                   [status.exitstatus, out, err]
    end
  end

  def test_control_characters_in_the_base_are_shown_as_text
    repository do |root|
      out, err, status = lint_changelog(root, "\e[31mred")

      assert_equal [2, "", "lint-changelog: invalid argument: \\e[31mred " \
                           "(use a revision such as origin/main)\n#{HELP}"], [status.exitstatus, out, err]
    end
  end

  def test_control_characters_in_a_base_git_cannot_compare_with_are_shown_as_text
    repository do |root|
      git(root, "switch", "-q", "--orphan", "unrelated")
      git(root, "commit", "--allow-empty", "-qm", "\e]0;unrelated")
      git(root, "switch", "-q", "main")
      out, err, status = lint_changelog(root, "unrelated^{/\e]0}")

      assert_equal [1, "", "lint-changelog: cannot compare HEAD with unrelated^{/\\e]0}: " \
                           "fatal: unrelated^{/?]0}...HEAD: no merge base\n"], [status.exitstatus, out, err]
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
      assert_equal "lint-changelog: cannot read CHANGELOG.md in #{root}: No such file or directory\n", err
    end
  end

  def test_the_rake_task_compares_with_origin_main_when_the_clone_has_it
    repository do |root|
      git(root, "update-ref", "refs/remotes/origin/main", git(root, "rev-parse", "HEAD"))
      commit(root, "lib/rich_ri.rb" => "# changed")
      _out, err, status = rake("lint:changelog", env: UNWAIVED, chdir: root)

      assert_equal 1, status.exitstatus
      assert_equal [ENTRY_REQUIRED], err.lines.grep(/\Alint-changelog: /)
    end
  end

  def test_the_rake_task_checks_only_the_structure_in_a_clone_without_origin_main
    repository do |root|
      commit(root, "lib/rich_ri.rb" => "# changed")
      _out, err, status = rake("lint:changelog", env: UNWAIVED, chdir: root)

      assert_predicate status, :success?, err
    end
  end

  def test_the_rake_task_names_both_waiver_values
    description = "Check CHANGELOG.md, and an Unreleased entry for user-visible changes since base (origin/main); " \
                  "SKIP_CHANGELOG=1 or true waives the entry"
    out, err, status = rake("--describe", "lint:changelog")

    assert_equal [0, "", "rake lint:changelog[base]\n    #{description}\n\n"], [status.exitstatus, err, out]
  end

  def test_the_documentation_check_includes_the_changelog_check
    out, err, status = rake("--prereqs", "docs:check")

    assert_predicate status, :success?, err
    assert_includes out[/^rake docs:check\n((?:    .+\n)+)/, 1].split, "lint:changelog"
  end

  private

  def lint_changelog(root, *, waiver: nil)
    Open3.capture3(GitSupport::ENVIRONMENT.merge("SKIP_CHANGELOG" => waiver), RbConfig.ruby,
                   File.join(TestSupport::ROOT, "bin/lint-changelog"), *, chdir: root)
  end
end
