# frozen_string_literal: true

require "test_helper"

class CommitPolicyTest < Minitest::Test
  def git(root, *)
    # Keep background Git maintenance out of disposable test repositories.
    out, err, status = Open3.capture3(TestSupport::GIT_ENVIRONMENT, "git", "-c", "maintenance.auto=false",
                                      "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *, chdir: root)

    assert_predicate status, :success?, err
    out
  end

  def repository
    Dir.mktmpdir("rich-ri-commits-") do |root|
      git(root, "init", "-q", "-b", "main")
      git(root, "config", "user.name", "Test Contributor")
      git(root, "config", "user.email", "contributor@example.org")
      git(root, "commit", "--allow-empty", "-qm", "chore: initialize")
      yield root
    end
  end

  def lint(root, range = "HEAD", **env)
    Open3.capture3({ "PR_TITLE" => nil, "PR_BODY" => nil }.merge(env), RbConfig.ruby,
                   File.join(TestSupport::ROOT, "bin/lint-commits"), range, chdir: root)
  end

  def test_real_messages_separators_titles_and_human_coauthors
    repository do |root|
      git(root, "commit", "--allow-empty", "-qm",
          "fix: preserve documentation\n\nCo-Authored-By: Claude Monet <claude@example.org>")
      _out, err, status = lint(root, "HEAD", "PR_TITLE" => "fix: preserve documentation")

      assert_predicate status, :success?, err
      _out, err, status = lint(root, "HEAD", "PR_TITLE" => "An unstructured title")

      refute_predicate status, :success?
      assert_includes err, "PR title: Use a Conventional Commit"
    end
  end

  def test_attribution_in_commits_and_pr_bodies_is_rejected
    repository do |root|
      ["Generated-by: a tool", "Assisted-by: Codex",
       "Co-Authored-By: Claude <noreply@anthropic.com>", "Generated with [Claude](https://example.org)"].each do |line|
        _out, err, status = lint(root, "HEAD", "PR_BODY" => "Fix completion.\n\n#{line}")

        refute_predicate status, :success?, line
        assert_includes err, "PR body: Remove generated attribution"
      end
      git(root, "commit", "--allow-empty", "-qm", "fix: correct rendering\n\nGenerated-with: Codex")
      _out, err, status = lint(root)

      refute_predicate status, :success?
      assert_includes err, "Remove generated attribution"
    end
  end

  def test_shallow_merge_uses_stored_parents_but_still_checks_its_body
    repository do |root|
      git(root, "switch", "-qc", "topic")
      git(root, "commit", "--allow-empty", "-qm", "fix: improve completion")
      git(root, "switch", "-q", "main")
      git(root, "commit", "--allow-empty", "-qm", "docs: explain completion")
      git(root, "merge", "--no-ff", "topic", "-m", "Merge synthetic PR")
      Dir.mktmpdir("rich-ri-shallow-") do |clone|
        git(root, "clone", "-q", "--depth=1", "file://#{root}", clone)
        _out, err, status = lint(clone)

        assert_predicate status, :success?, err
      end
      git(root, "commit", "--amend", "-qm", "Merge synthetic PR\n\nGenerated-by: Codex")
      _out, err, status = lint(root)

      refute_predicate status, :success?
      assert_includes err, "Remove generated attribution"
    end
  end

  def test_invalid_subject_and_range_fail_with_actionable_messages
    repository do |root|
      git(root, "commit", "--allow-empty", "-qm", "unstructured commit")
      _out, err, status = lint(root)

      refute_predicate status, :success?
      assert_includes err, "Use a Conventional Commit"
      _out, err, status = lint(root, "missing..HEAD")

      refute_predicate status, :success?
      assert_includes err, "Cannot read commits"
    end
  end
end
