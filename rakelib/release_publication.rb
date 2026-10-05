# frozen_string_literal: true

require_relative "release"

module Release
  # An existing remote tag is observation-only: retries must not move it or
  # trigger another publication when RubyGems may already have accepted the gem.
  class Publication
    def initialize(version, commands:, out: $stdout, sleeper: Kernel, branch: "main")
      @version = version
      @commands = commands
      @out = out
      @sleeper = sleeper
      @base = Release.validate_branch(branch, version)
    end

    def tag = "v#{@version}"

    def remote_tag
      @commands.call(["git", "ls-remote", "--tags", "origin", "refs/tags/#{tag}",
                      "refs/tags/#{tag}^{}"]).lines.to_h do |line|
        sha, ref = line.split
        [ref, sha]
      end
    end

    def run(sha, push:, dry_run: false)
      verify_commit(sha)
      remote = remote_tag
      if remote.any? && remote["refs/tags/#{tag}^{}"] != sha
        raise Error, "Remote #{tag} targets another commit; it will never be moved"
      end

      exists = !@commands.call(["git", "tag", "--list", tag]).strip.empty?
      verify_tag(sha) if exists
      return report_pushed_tag(sha) if dry_run && remote.any?
      return report_ready(sha, exists) if dry_run || (!push && remote.empty?)

      if remote.empty?
        @commands.call(["git", "tag", "-s", tag, "-m", "Release #{@version}", sha]) unless exists
        verify_tag(sha)
        @commands.call(["git", "push", "origin", tag], stream: true)
      end
      watch_release(sha)
    end

    def verify_commit(sha)
      raise Error, "GitHub did not return a valid release merge commit" unless sha&.match?(/\A[0-9a-f]{40}\z/)

      @commands.call(["git", "merge-base", "--is-ancestor", sha, "origin/#{@base}"])
      verify_metadata(sha)
    end

    def verify_metadata(sha)
      source = @commands.call(["git", "show", "#{sha}:#{Release::VERSION_FILE}"])
      version = source[/VERSION = "([^"]+)"/, 1]
      changelog = @commands.call(["git", "show", "#{sha}:CHANGELOG.md"])
      Release.verify(tag: tag, version: version, changelog: changelog)
    end

    private

    def command = "bin/release #{@version}#{" --branch #{@base}" unless @base == 'main'}"

    def report_ready(sha, tagged)
      next_step = tagged ? "push the signed tag" : "sign and push its tag"
      @out.puts "Release merge #{sha} is ready. Run #{command} --push to #{next_step}."
    end

    # A dry run only reads: it reports where the pushed tag stands without waiting for its run.
    def report_pushed_tag(sha)
      run = release_runs.find { |candidate| candidate["headSha"] == sha }
      @out.puts "#{tag} is already on origin at #{sha}: #{run ? run_state(run) : missing_run}."
    end

    def run_state(run)
      name = "Release run #{run.fetch('databaseId')}"
      return "#{name} is #{run['status']}; run #{command} to watch it" unless run["status"] == "completed"
      return "#{name} succeeded; nothing is left to do" if run["conclusion"] == "success"

      "#{name} ended with #{run['conclusion']}; run #{command} for the recovery steps"
    end

    def missing_run = "no Release run was found; inspect Actions before dispatching one"

    def release_runs
      @commands.json(["gh", "run", "list", "--workflow", "release.yml", "--branch", tag, "--event", "push",
                      "--limit", "20", "--json", "databaseId,headSha,status,conclusion"])
    end

    def verify_tag(sha)
      unless @commands.call(["git", "cat-file", "-t", "refs/tags/#{tag}"]).strip == "tag" &&
             @commands.call(["git", "rev-parse", "#{tag}^{commit}"]).strip == sha
        raise Error, "Local #{tag} is not an annotated tag of the release merge; it will never be replaced"
      end

      @commands.call(["git", "verify-tag", tag])
    end

    def watch_release(sha)
      run = nil
      60.times do
        run = release_runs.find { |candidate| candidate["headSha"] == sha }
        break if run

        @sleeper.sleep(5)
      end
      unless run
        raise Error, "#{tag} is already on GitHub. No Release run appeared; inspect Actions before dispatching it. " \
                     "The tag was not changed."
      end

      id = run.fetch("databaseId").to_s
      unless run["status"] == "completed"
        @commands.call(["gh", "run", "watch", id], stream: true)
        run = @commands.json(["gh", "run", "view", id, "--json", "status,conclusion"])
      end
      raise Error, failed_run_message(id) unless run["conclusion"] == "success"

      @out.puts "Released #{tag}; the existing successful run is #{id}."
    end

    def failed_run_message(id)
      jobs = @commands.json(["gh", "run", "view", id, "--json", "jobs"]).fetch("jobs")
      publication = jobs.find { |job| job["name"] == "publish" }
      github_release = jobs.find { |job| job["name"] == "github-release" }
      prefix = "#{tag} is already on GitHub. Release run #{id} failed; no publication was retried."
      if publication && publication["conclusion"] == "success" && github_release
        "#{prefix}\nRubyGems publication succeeded. Retry only GitHub release creation:\n" \
          "gh run rerun #{id} --job #{github_release.fetch('databaseId')} --repo #{GitHub::REPOSITORY}"
      elsif publication.nil? || publication["conclusion"] == "skipped"
        "#{prefix}\nPublication did not run. Fix the failed checks, then: gh run rerun #{id} --failed --repo #{GitHub::REPOSITORY}"
      else
        "#{prefix}\nInspect gh run view #{id} --log-failed --repo #{GitHub::REPOSITORY}. " \
          "Check whether RubyGems accepted #{@version} before retrying any publish job."
      end
    end
  end
end
