# frozen_string_literal: true

require "date"
require "tempfile"
require_relative "release"
require_relative "release_commands"
require_relative "release_publication"
require_relative "github_configuration"

module Release
  class Workflow
    FILES = [Release::VERSION_FILE, Changelog::PATH, "Gemfile.lock", "man/man1/rich-ri.1"].freeze

    def initialize(version, root: ROOT, runner: nil, out: $stdout, **options)
      @version = version
      @root = root
      @push = options.fetch(:push, false)
      @dry_run = options.fetch(:dry_run, false)
      @base = Release.validate_branch(options.fetch(:branch, "main"), version)
      @out = out
      @sleeper = options.fetch(:sleeper, Kernel)
      @commands = Commands.new(root: root, runner: runner, out: out)
      @configuration = options.fetch(:configuration) { GitHub::Configuration.new(client: GitHub::Client.new(root: root), out: out) }
      @publication = Publication.new(version, commands: @commands, out: out, sleeper: @sleeper, branch: @base)
    end

    def run
      validate
      pull_request = find_pull_request
      if pull_request&.fetch("state") == "MERGED"
        require_clean
        @publication.run(pull_request.dig("mergeCommit", "oid"), push: @push, dry_run: @dry_run)
      elsif @publication.remote_tag.any?
        raise Error, "#{tag} already exists without a matching merged release PR; inspect it before continuing"
      elsif pull_request
        resume_pull_request(pull_request)
      else
        prepare_pull_request
      end
    rescue Error, GitHub::Error => e
      raise e.class, "#{e.message}\nAfter resolving the problem, rerun #{resume_command}#{' --push' if @push}. " \
                     "Existing pull requests and tags are inspected before any new action."
    end

    private

    def tag = "v#{@version}"

    def branch = "release/#{tag}"

    def resume_command = "bin/release #{@version}#{" --branch #{@base}" unless @base == 'main'}"

    def command(...)
      @commands.call(...)
    end

    def validate
      Release.validate_version(@version)
      unless GitHub.origin?(command(%w[git remote get-url origin]))
        raise Error, "the origin repository must be #{GitHub::REPOSITORY}"
      end

      @configuration.verify!
      command(%w[git fetch origin --tags])
      @current_branch = command(%w[git branch --show-current]).strip
      raise Error, "run from #{@base} or #{branch}" unless [@base, branch].include?(@current_branch)
    end

    # gh matches the head branch by name, in forks too, and a pull request can never be deleted.
    # One opened from a fork or closed without merging must not stop this version forever.
    def find_pull_request
      requests = @commands.json(["gh", "pr", "list", "--state", "all", "--base", @base, "--head", branch,
                                 "--json", "url,state,headRefOid,mergeCommit,isCrossRepository"])
      ignored, candidates = requests.partition { |request| reason_to_ignore(request) }
      ignored.each { |request| @out.puts "Ignoring #{request['url']}: #{reason_to_ignore(request)}." }
      @closed_heads = ignored.select { |request| request["isCrossRepository"] == false }
                             .map { |request| request["headRefOid"] }
      raise Error, "several pull requests use #{branch}; reconcile them before releasing" if candidates.length > 1

      candidates.first
    end

    def reason_to_ignore(request)
      return "it comes from a fork" unless request["isCrossRepository"] == false

      "it was closed without merging" if request["state"] == "CLOSED"
    end

    def require_clean
      raise Error, "commit or stash unrelated work before continuing" unless command(%w[git status --porcelain]).empty?
    end

    def resume_pull_request(request)
      require_clean
      @commit = request.fetch("headRefOid")
      if @current_branch == branch && command(%w[git rev-parse HEAD]).strip != @commit
        raise Error, "local #{branch} differs from the PR head; push its reviewed changes before retrying"
      end
      return @out.puts "Existing release PR: #{request.fetch('url')} (dry run)." if @dry_run

      finish_pull_request(request.fetch("url"))
    end

    def prepare_pull_request
      if @current_branch == @base
        require_clean
        head = command(%w[git rev-parse HEAD])
        unless head == command(["git", "rev-parse", "origin/#{@base}"])
          raise Error, "local #{@base} must match origin/#{@base}; pull first"
        end

        changes = Release.changes(@version, root: @root)
        if @dry_run
          return @out.puts changes.fetch(Changelog::PATH), "Dry run: no working files or GitHub state changed."
        end

        create_branch
      else
        changes = resumed_changes
        return @out.puts "Would resume preparation on #{branch}; no working files or GitHub state changed." if @dry_run
      end
      prepare(changes) if changes
      @commit = command(%w[git rev-parse HEAD]).strip
      command(%w[git verify-commit HEAD])
      push_branch
      finish_pull_request(open_pull_request)
    end

    # A pull request closed without merging leaves its branch behind; only its exact head may be replaced.
    def create_branch
      local = command(["git", "for-each-ref", "--format=%(objectname)", "refs/heads/#{branch}"]).strip
      if local.empty?
        command(["git", "switch", "-c", branch])
      elsif @closed_heads.include?(local)
        command(["git", "switch", "-C", branch])
      else
        raise Error, "local #{branch} has commits outside its closed pull request; delete or rename it, then rerun"
      end
    end

    def push_branch
      remote = command(["git", "ls-remote", "--heads", "origin", "refs/heads/#{branch}"]).split.first
      replace = remote != @commit && @closed_heads.include?(remote)
      lease = ["--force-with-lease=refs/heads/#{branch}:#{remote}"] if replace
      command(["git", "push", *lease, "-u", "origin", branch], stream: true)
    end

    def resumed_changes
      dirty = command(%w[git status --porcelain]).lines.map { |line| line.chomp[3..] }
      raise Error, "unrelated changes on #{branch}; commit or stash them first" unless (dirty - FILES).empty?

      source = [Release::VERSION_FILE, Changelog::PATH].to_h { |path| [path, command(["git", "show", "HEAD:#{path}"])] }
      if Changelog.released?(source.fetch(Changelog::PATH), @version)
        require_clean
        Release.verify(tag: tag, version: Release.version_in(source.fetch(Release::VERSION_FILE)),
                       changelog: source.fetch(Changelog::PATH))
        command(%w[bundle exec rake check], stream: true) unless @dry_run
        return
      end

      # A retry may happen on another UTC day. Preserve the preparation date,
      # while still comparing every edit against exactly what we would generate.
      changelog = File.read(File.join(@root, Changelog::PATH))
      changes = Release.changes(@version, root: @root, source: source, date: preparation_date(changelog))
      changes.each do |path, content|
        actual = File.read(File.join(@root, path))
        next if [source.fetch(path), content].include?(actual)

        raise Error, "#{path} has edits beyond release preparation; review them before retrying"
      end
      changes
    end

    def preparation_date(changelog)
      heading = Changelog.releases(changelog).find { |release| release.version == @version }
      return Time.now.utc.to_date unless heading
      raise Error, "#{Changelog::PATH}: #{Changelog.invalid_date(heading)}" unless heading.dated?

      heading.day
    end

    def prepare(changes)
      changes.each { |path, content| File.write(File.join(@root, path), content) }
      command(%w[bundle lock --local])
      command(%w[bundle exec rake generate], stream: true)
      command(%w[bundle exec rake check], stream: true)
      command(["git", "add", "--", *FILES])
      command(["git", "commit", "-S", "-m", "chore: release #{tag}"])
      command(%w[git log -1 --format=full])
    end

    def open_pull_request
      Tempfile.create(["rich-ri-release", ".md"]) do |body|
        body.write("Release rich-ri #{@version}. The signed tag will target the merge commit.\n\n" \
                   "Validation: `bundle exec rake check`. Release notes are in CHANGELOG.md.\n")
        body.flush
        command(["gh", "pr", "create", "--base", @base, "--head", branch, "--title", "chore: release #{tag}",
                 "--assignee", "@me", "--label", "release", "--body-file", body.path]).strip
      end
    end

    def finish_pull_request(url)
      return @out.puts "Release PR: #{url}. Run #{resume_command} --push to merge, sign and publish." unless @push

      @publication.verify_metadata(@commit)
      command(["git", "verify-commit", @commit])
      wait_for_checks(url)
      command(["gh", "pr", "checks", url, "--watch", "--fail-fast", "--interval", "10"], stream: true)
      command(["gh", "pr", "merge", url, "--merge", "--delete-branch", "--match-head-commit", @commit])
      sha = command(["gh", "pr", "view", url, "--json", "mergeCommit", "--jq", ".mergeCommit.oid"]).strip
      command(%w[git fetch origin --tags])
      command(["git", "merge-base", "--is-ancestor", @commit, sha])
      @publication.run(sha, push: true)
    end

    def wait_for_checks(url)
      60.times do
        count = command(["gh", "pr", "view", url, "--json", "statusCheckRollup", "--jq", ".statusCheckRollup | length"])
        return if count.to_i.positive?

        @sleeper.sleep(5)
      end
      raise Error, "timed out waiting for checks on #{url}; the existing PR will be reused on retry"
    end
  end
end
