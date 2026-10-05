# frozen_string_literal: true

require_relative "git_support"

module ReleaseFixtures
  include GitSupport

  def repository
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib/rich_ri"))
      File.write(File.join(dir, "lib/rich_ri/version.rb"), "VERSION = \"0.1.0\"\n")
      File.write(File.join(dir, "CHANGELOG.md"), <<~TEXT)
        # Changelog
        ## [Unreleased]

        ### Added
        - Readable documentation.

        [Unreleased]: https://github.com/hvpaiva/rich-ri/commits/main
      TEXT
      git(dir, "init", "-q")
      git(dir, "add", ".")
      git(dir, "commit", "-qm", "chore: initialize")
      yield dir
    end
  end

  def assert_release_error(message, &)
    error = assert_raises(Release::Error, &)

    assert_equal message, error.message
  end

  def resume(command = "bin/release 0.2.0 --push")
    "After resolving the problem, rerun #{command}. " \
      "Existing pull requests and tags are inspected before any new action."
  end

  def workflow(version, **)
    configuration = Object.new
    def configuration.verify! = nil
    Release::Workflow.new(version, configuration: configuration, **)
  end

  def released_changelog
    <<~TEXT
      ## [Unreleased]

      ## [0.2.0] - 2026-10-04
      - Readable documentation.

      [Unreleased]: https://github.com/hvpaiva/rich-ri/compare/v0.2.0...HEAD
      [0.2.0]: https://github.com/hvpaiva/rich-ri/releases/tag/v0.2.0
    TEXT
  end

  def workflow_runner(commands, fail_at: nil, repository: "hvpaiva/rich-ri", state: {})
    lambda do |argv, **_options|
      commands << argv
      output = if argv.first == "git"
                 git_answer(argv, state, repository)
               else
                 github_answer(argv, state)
               end
      failed = fail_at && argv.first(fail_at.length) == fail_at
      [output, Struct.new(:success?).new(!failed)]
    end
  end

  def git_answer(argv, state, repository)
    case argv.first(3)
    when %w[git branch --show-current] then "#{state.fetch(:branch, 'main')}\n"
    when %w[git rev-parse HEAD], %w[git rev-parse origin/main],
         %w[git rev-parse origin/hotfix/0.2] then "#{'a' * 40}\n"
    when %w[git remote get-url] then "git@github.com:#{repository}.git\n"
    when %w[git status --porcelain] then state.fetch(:dirty, "")
    when %w[git tag --list] then state[:local_tag] ? "v0.2.0\n" : ""
    when %w[git tag -s]
      state[:local_tag] = true
      ""
    when %w[git cat-file -t] then "tag\n"
    when ["git", "rev-parse", "v0.2.0^{commit}"] then "#{state.fetch(:tag_sha, 'b' * 40)}\n"
    when %w[git ls-remote --tags]
      state[:remote_tag] ? "#{'c' * 40}\trefs/tags/v0.2.0\n#{state[:remote_tag]}\trefs/tags/v0.2.0^{}\n" : ""
    else
      return "" unless argv.first(2) == %w[git show]

      state.fetch(:source, {}).fetch(argv[2]) do
        if argv[2].end_with?("version.rb")
          "VERSION = \"#{state.fetch(:release_version, '0.2.0')}\"\n"
        else
          released_changelog
        end
      end
    end
  end

  def github_answer(argv, state)
    case argv.first(3)
    when %w[gh pr list] then JSON.generate(state.fetch(:prs) { [state[:pr]].compact })
    when %w[gh pr create] then "https://github.com/hvpaiva/rich-ri/pull/1\n"
    when %w[gh pr view] then argv.include?("mergeCommit") ? "#{'b' * 40}\n" : "1\n"
    when %w[gh run list]
      JSON.generate(state.fetch(:runs) do
        [{ databaseId: 123, headSha: "b" * 40, status: state.fetch(:run_status, "completed"),
           conclusion: state.fetch(:conclusion, "success") }]
      end)
    when %w[gh run view]
      data = if argv.include?("jobs")
               { jobs: state.fetch(:jobs, []) }
             else
               { status: "completed", conclusion: state.fetch(:conclusion, "success") }
             end
      JSON.generate(data)
    else ""
    end
  end

  def release_pr(state = "MERGED")
    { "state" => state, "url" => "https://github.com/hvpaiva/rich-ri/pull/1", "isCrossRepository" => false,
      "headRefOid" => "a" * 40, "mergeCommit" => { "oid" => "b" * 40 } }
  end

  def fork_pr(state)
    release_pr(state).merge("url" => "https://github.com/hvpaiva/rich-ri/pull/99", "isCrossRepository" => true,
                            "headRefOid" => "f" * 40)
  end
end
