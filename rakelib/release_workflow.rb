# frozen_string_literal: true

require "tempfile"
require "English"
require_relative "release"

module Release
  class Workflow
    FILES = %w[lib/rich_ri/version.rb CHANGELOG.md Gemfile.lock man/man1/rich-ri.1].freeze
    REPOSITORY = "hvpaiva/rich-ri"

    def initialize(version, root: ROOT, runner: nil, out: $stdout, **options)
      @version = version
      @root = root
      @push = options.fetch(:push, false)
      @dry_run = options.fetch(:dry_run, false)
      @runner = runner || method(:execute)
      @out = out
      @sleeper = options.fetch(:sleeper, Kernel)
    end

    def run
      changes = Release.changes(@version, root: @root)
      validate
      if @dry_run
        @out.puts changes.fetch("CHANGELOG.md"), "Dry run: no files written, committed or pushed."
        return
      end

      prepare(changes)
      url = open_pull_request
      if @push
        publish(url)
      else
        @out.puts "Opened #{url}. Review and merge, then sign and push #{tag} from main."
      end
    end

    private

    def tag = "v#{@version}"

    def branch = "release/#{tag}"

    def validate
      origin = command(%w[git remote get-url origin]).strip
      unless origin.match?(%r{\A(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)#{REPOSITORY}(?:\.git)?\z}o)
        raise "The origin repository must be #{REPOSITORY}"
      end

      command(%w[git fetch origin --tags])
      raise "Release from main" unless command(%w[git branch --show-current]).strip == "main"
      unless command(%w[git rev-parse HEAD]) == command(%w[git rev-parse origin/main])
        raise "Local main must match origin/main; pull or push first"
      end
      raise "#{tag} already exists" unless command(["git", "tag", "--list", tag]).strip.empty?
    end

    def prepare(changes)
      command(["git", "switch", "-c", branch])
      changes.each { |path, content| File.write(File.join(@root, path), content) }
      command(%w[bundle lock --local])
      command(%w[bundle exec rake generate], stream: true)
      command(%w[bundle exec rake check], stream: true)
      command(["git", "add", "--", *FILES])
      command(["git", "commit", "-S", "-m", "chore: release #{tag}"])
      command(%w[git log -1 --format=full])
      command(%w[git verify-commit HEAD])
      @commit = command(%w[git rev-parse HEAD]).strip
      command(["git", "push", "-u", "origin", branch], stream: true)
    end

    def open_pull_request
      Tempfile.create(["rich-ri-release", ".md"]) do |body|
        body.write("Release rich-ri #{@version}. The signed tag will target the merge commit.\n\n" \
                   "Validation: `bundle exec rake check`. Release notes are in CHANGELOG.md.\n")
        body.flush
        command(["gh", "pr", "create", "--base", "main", "--head", branch, "--title", "chore: release #{tag}",
                 "--body-file", body.path]).strip
      end
    end

    def publish(url)
      wait_for do
        command(["gh", "pr", "view", url, "--json", "statusCheckRollup", "--jq",
                 ".statusCheckRollup | length"]).to_i.positive?
      end
      command(["gh", "pr", "checks", url, "--watch", "--fail-fast", "--interval", "10"], stream: true)
      command(["gh", "pr", "merge", url, "--merge", "--delete-branch", "--match-head-commit", @commit])
      sha = command(["gh", "pr", "view", url, "--json", "mergeCommit", "--jq", ".mergeCommit.oid"]).strip
      raise "GitHub did not return the release merge commit" unless sha.match?(/\A[0-9a-f]{40}\z/)

      command(%w[git fetch origin --tags])
      command(["git", "merge-base", "--is-ancestor", @commit, sha])
      command(%w[git switch main])
      command(%w[git merge --ff-only origin/main])
      command(["git", "tag", "-s", tag, "-m", "Release #{@version}", sha])
      command(["git", "push", "origin", tag], stream: true)
      watch_release
    end

    def watch_release
      run_id = nil
      wait_for do
        run_id = command(["gh", "run", "list", "--workflow", "release.yml", "--branch", tag, "--event", "push",
                          "--limit", "1", "--json", "databaseId", "--jq", ".[0].databaseId // empty"]).strip
        !run_id.empty?
      end
      command(["gh", "run", "watch", run_id, "--exit-status"], stream: true)
      @out.puts "Released #{tag}."
    end

    def wait_for
      60.times do
        return if yield

        @sleeper.sleep(5)
      end
      raise "Timed out waiting for GitHub; inspect the pull request or Actions run before retrying"
    end

    def command(argv, stream: false)
      argv += ["--repo", REPOSITORY] if argv.first == "gh"
      @out.puts "==> #{argv.join(' ')}"
      output, status = @runner.call(argv, stream: stream)
      unless status.success?
        raise "#{argv.join(' ')} failed. Inspect the current branch and Actions before retrying.\n#{output}"
      end

      output
    end

    def execute(argv, stream: false)
      return Open3.capture2e(*argv, chdir: @root) unless stream

      system(*argv, chdir: @root)
      ["", $CHILD_STATUS]
    end
  end
end
