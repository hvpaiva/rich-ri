# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/ci"
require_relative "release_support"

class CITest < Minitest::Test
  include ReleaseFixtures

  def test_documentation_changes_include_config_examples_and_unquoted_git_paths
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      head = commit(root, "README.md" => "Read me", "docs/a guide\nin 日本語.md" => "Example",
                          "docs/config.example.yml" => "theme: terminal", "docs/images/example.png" => "image")

      assert_equal "docs", scope(root, base, head)
      assert_equal "docs", scope(root, base, head, event: "push", ref: "refs/heads/main")
    end
  end

  def test_changed_paths_are_read_the_same_way_in_a_c_locale
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      head = commit(root, "docs/日本語.md" => "Example")
      source = 'puts CI.scope(root: ARGV[0], base: ARGV[1], head: ARGV[2], event: "pull_request", ref: "")'
      out, err, status = Open3.capture3({ "LC_ALL" => "C" }, RbConfig.ruby, "-r",
                                        File.join(TestSupport::ROOT, "rakelib/ci"), "-e", source, root, base, head)

      assert_predicate status, :success?, err
      assert_equal "docs\n", out
    end
  end

  def test_scripts_fixtures_generated_manual_and_unknown_paths_require_full_checks
    %w[docs/images/render_comparison.rb test/fixtures/GUIDE.rdoc lib/rich_ri/cli.rb
       .github/workflows/ci.yml Gemfile.lock man/man1/rich-ri.1 new-tool].each do |path|
      refute CI.documentation?(path), path
    end
    refute CI.documentation?("docs/invalid-\xff.md")
  end

  def test_the_whole_pull_request_is_considered_after_a_documentation_only_commit
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      commit(root, "lib/code.rb" => "puts :example")
      head = commit(root, "README.md" => "Documentation")

      assert_equal "full", scope(root, base, head)
    end
  end

  def test_pull_requests_compare_from_the_merge_base
    repository do |root|
      original = git(root, "rev-parse", "HEAD")
      base = commit(root, "lib/code.rb" => "Unrelated base-branch change")
      git(root, "switch", "-c", "docs", original)
      head = commit(root, "README.md" => "Documentation")

      assert_equal "docs", scope(root, base, head)
    end
  end

  def test_renaming_code_to_documentation_does_not_hide_the_deleted_code
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      FileUtils.mkdir_p(File.join(root, "docs"))
      git(root, "mv", "lib/rich_ri/version.rb", "docs/version.md")
      head = commit(root, {})

      assert_equal "full", scope(root, base, head)
    end
  end

  def test_empty_or_unavailable_changes_fall_back_to_the_full_suite
    repository do |root|
      head = git(root, "rev-parse", "HEAD")

      [head, nil, "0" * 40, "--all"].each do |base|
        assert_equal "full", scope(root, base, head)
      end
    end
  end

  def test_bin_ci_says_why_it_runs_every_check_when_git_cannot_compare
    repository do |root|
      head = git(root, "rev-parse", "HEAD")
      environment = GitSupport::ENVIRONMENT.merge("GIT_DIR" => File.join(root, ".git"), "CI_FORCE_FULL" => nil,
                                                  "GITHUB_EVENT_NAME" => "pull_request", "GITHUB_REF" => "",
                                                  "CI_BASE" => "a" * 40, "CI_HEAD" => head)
      out, err, status = Open3.capture3(environment, RbConfig.ruby, File.join(TestSupport::ROOT, "bin/ci"), "scope")

      reason = "fatal: Invalid symmetric difference expression #{'a' * 40}...#{head}"

      assert_equal [0, "scope=full\n", "ci: every check runs because the changed files are unknown: #{reason}\n"],
                   [status.exitstatus, out, err]
    end
  end

  def test_a_range_that_looks_like_an_option_is_read_as_a_revision
    repository do |root|
      injected = File.join(root, "injected")
      error = assert_raises(CI::Error) { CI.changed_paths("--output=#{injected}", root) }

      assert_equal "fatal: bad revision '--output=#{injected}'", error.message
      refute_path_exists injected
    end
  end

  def test_releases_and_other_events_cannot_select_the_documentation_shortcut
    repository do |root|
      base = git(root, "rev-parse", "HEAD")
      head = commit(root, "README.md" => "Documentation")

      assert_equal "full", scope(root, base, head, force_full: true)
      assert_equal "full", scope(root, base, head, event: "workflow_dispatch")
      assert_equal "full", scope(root, base, head, event: "push", ref: "refs/tags/v0.1.0")
      assert_equal "scheduled", scope(root, base, head, event: "schedule")
      assert_equal "full", scope(root, base, head, event: "schedule", force_full: true)
    end
  end

  private

  def scope(root, base, head, **)
    CI.scope(root: root, base: base, head: head, event: "pull_request", ref: "refs/pull/1/merge", **)
  end
end
