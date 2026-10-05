# frozen_string_literal: true

require "open3"
require_relative "changelog"

module Release
  ROOT = File.expand_path("..", __dir__)
  VERSION_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  VERSION_FILE = "lib/rich_ri/version.rb"

  # A condition the maintainer can correct; anything else is a defect in this code.
  class Error < StandardError; end

  def self.version(root: ROOT)
    File.read(File.join(root, VERSION_FILE))[/VERSION = "([^"]+)"/, 1]
  end

  def self.verify(tag: ENV.fetch("GITHUB_REF_NAME", nil), changelog: nil, version: self.version)
    changelog ||= File.read(File.join(ROOT, Changelog::PATH))
    validate_version(version)
    raise Error, "release tag must be v#{version}" unless tag == "v#{version}"

    problems = Changelog.problems(changelog)
    problems << %("## [#{version}] - YYYY-MM-DD" is missing) unless Changelog.released?(changelog, version)
    raise Error, problems.map { |problem| "#{Changelog::PATH}: #{problem}" }.join("\n") unless problems.empty?

    version
  end

  def self.validate_version(target)
    raise Error, "use a stable X.Y.Z version" unless target&.match?(VERSION_PATTERN)
  end

  def self.validate_branch(branch, target)
    validate_version(target)
    return branch if ["main", "hotfix/#{target.split('.').first(2).join('.')}"].include?(branch)

    raise Error, "release branch must be main or hotfix/#{target.split('.').first(2).join('.')}"
  end

  def self.verify_ref(sha: ENV.fetch("GITHUB_SHA", nil), version: self.version)
    raise Error, "invalid release commit: set GITHUB_SHA to a full commit ID" unless sha&.match?(/\A[0-9a-f]{40}\z/)

    refs, status = Open3.capture2("git", "for-each-ref", "--contains", sha, "--format=%(refname:short)",
                                  "refs/remotes/origin")
    allowed = ["origin/main", "origin/hotfix/#{version.split('.').first(2).join('.')}"]
    return if status.success? && refs.lines.map(&:strip).intersect?(allowed)

    raise Error, "release commit must belong to main or its matching hotfix branch"
  end

  def self.changes(target, root: ROOT, source: nil, date: Time.now.utc.to_date)
    validate_version(target)
    source ||= clean_source(root)
    current_version = source.fetch(VERSION_FILE)[/VERSION = "([^"]+)"/, 1]
    raise Error, "version cannot go backwards" if Gem::Version.new(target) < Gem::Version.new(current_version)

    changelog = source.fetch(Changelog::PATH)
    raise Error, "version already appears in the changelog" if Changelog.released?(changelog, target)
    raise Error, "add release notes under Unreleased first" unless Changelog.entries?(changelog, "Unreleased")

    updated = Changelog.cut(changelog, target, date)
    verify(tag: "v#{target}", changelog: updated, version: target)
    {
      Changelog::PATH => updated,
      VERSION_FILE => source.fetch(VERSION_FILE).sub(/VERSION = "[^"]+"/, "VERSION = \"#{target}\"")
    }
  end

  def self.clean_source(root)
    status, process = Open3.capture2("git", "status", "--porcelain", chdir: root)
    raise Error, "commit or stash changes before preparing a release" unless process.success? && status.empty?

    [VERSION_FILE, Changelog::PATH].to_h { |path| [path, File.read(File.join(root, path))] }
  end
end
