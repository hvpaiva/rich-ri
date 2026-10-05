# frozen_string_literal: true

require "tempfile"
require_relative "release"
require_relative "release_commands"
require_relative "release_publication"
require_relative "github_configuration"

module Release
  class Workflow
    FILES = [Release::VERSION_FILE, "CHANGELOG.md", "Gemfile.lock", "man/man1/rich-ri.1"].freeze

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
      origin = command(%w[git remote get-url origin]).strip
      unless origin.match?(%r{\A(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)#{GitHub::REPOSITORY}(?:\.git)?\z}o)
        raise Error, "The origin repository must be #{GitHub::REPOSITORY}"
      end

      @configuration.verify!
      command(%w[git fetch origin --tags])
      @current_branch = command(%w[git branch --show-current]).strip
      raise Error, "Run from #{@base} or #{branch}" unless [@base, branch].include?(@current_branch)
    end

    def find_pull_request
      requests = @commands.json(["gh", "pr", "list", "--state", "all", "--base", @base, "--head", branch,
                                 "--json", "url,state,headRefOid,mergeCommit,isCrossRepository"])
      if requests.any? { |request| request["isCrossRepository"] != false }
        raise Error, "Release pull requests must originate in #{GitHub::REPOSITORY}, not a fork"
      end
      raise Error, "Several pull requests use #{branch}; reconcile them before releasing" if requests.length > 1

      requests.first
    end

    def require_clean
      raise Error, "Commit or stash unrelated work before continuing" unless command(%w[git status --porcelain]).empty?
    end

    def resume_pull_request(request)
      require_clean
      unless request["state"] == "OPEN"
        raise Error, "The release PR #{request['url']} was closed without merging; reopen it before retrying"
      end

      @commit = request.fetch("headRefOid")
      if @current_branch == branch && command(%w[git rev-parse HEAD]).strip != @commit
        raise Error, "Local #{branch} differs from the PR head. Push its reviewed changes before retrying"
      end
      return @out.puts "Existing release PR: #{request.fetch('url')} (dry run)." if @dry_run

      finish_pull_request(request.fetch("url"))
    end

    def prepare_pull_request
      if @current_branch == @base
        require_clean
        head = command(%w[git rev-parse HEAD])
        unless head == command(["git", "rev-parse", "origin/#{@base}"])
          raise Error, "Local #{@base} must match origin/#{@base}; pull first"
        end

        changes = Release.changes(@version, root: @root)
        return @out.puts changes.fetch("CHANGELOG.md"), "Dry run: no working files or GitHub state changed." if @dry_run

        command(["git", "switch", "-c", branch])
      else
        changes = resumed_changes
        return @out.puts "Would resume preparation on #{branch}; no working files or GitHub state changed." if @dry_run
      end
      prepare(changes) if changes
      @commit = command(%w[git rev-parse HEAD]).strip
      command(%w[git verify-commit HEAD])
      command(["git", "push", "-u", "origin", branch], stream: true)
      finish_pull_request(open_pull_request)
    end

    def resumed_changes
      dirty = command(%w[git status --porcelain]).lines.map { |line| line.chomp[3..] }
      raise Error, "Unrelated changes on #{branch}; commit or stash them first" unless (dirty - FILES).empty?

      source = [Release::VERSION_FILE, "CHANGELOG.md"].to_h { |path| [path, command(["git", "show", "HEAD:#{path}"])] }
      if source.fetch("CHANGELOG.md").include?("## [#{@version}]")
        require_clean
        Release.verify(tag: tag, version: source.fetch(Release::VERSION_FILE)[/VERSION = "([^"]+)"/, 1],
                       changelog: source.fetch("CHANGELOG.md"))
        command(%w[bundle exec rake check], stream: true) unless @dry_run
        return
      end

      # A retry may happen on another UTC day. Preserve the preparation date,
      # while still comparing every edit against exactly what we would generate.
      changelog = File.read(File.join(@root, "CHANGELOG.md"))
      dated = changelog[/^## \[#{Regexp.escape(@version)}\] - (\d{4}-\d{2}-\d{2})$/, 1]
      changes = Release.changes(@version, root: @root, source: source, date: preparation_date(dated))
      changes.each do |path, content|
        actual = File.read(File.join(@root, path))
        next if [source.fetch(path), content].include?(actual)

        raise Error, "#{path} has edits beyond release preparation; review them before retrying"
      end
      changes
    end

    def preparation_date(text)
      text ? Date.iso8601(text) : Time.now.utc.to_date
    rescue Date::Error
      raise Error, "CHANGELOG.md has an invalid date for #{@version}: #{text}"
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
                 "--body-file", body.path]).strip
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
      raise Error, "Timed out waiting for checks on #{url}; the existing PR will be reused on retry"
    end
  end
end
