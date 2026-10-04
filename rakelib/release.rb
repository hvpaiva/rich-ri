# frozen_string_literal: true

require "date"
require "open3"

module Release
  ROOT = File.expand_path("..", __dir__)
  VERSION_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  URL = "https://github.com/hvpaiva/rich-ri"
  VERSION_FILE = "lib/rich_ri/version.rb"

  def self.version(root: ROOT)
    File.read(File.join(root, VERSION_FILE))[/VERSION = "([^"]+)"/, 1]
  end

  def self.verify(tag: ENV.fetch("GITHUB_REF_NAME", nil), changelog: nil, version: self.version)
    changelog ||= File.read(File.join(ROOT, "CHANGELOG.md"))
    validate_version(version)
    raise "Release tag must be v#{version}" unless tag == "v#{version}"

    unreleased = changelog.scan(/^## \[Unreleased\]$/).length
    ordered = changelog.index("## [Unreleased]").to_i < changelog.index("## [#{version}]").to_i
    raise "Expected one Unreleased section before the release" unless unreleased == 1 && ordered

    dates = changelog.scan(/^## \[#{Regexp.escape(version)}\] - (\d{4}-\d{2}-\d{2})$/).flatten
    raise "Expected one dated changelog for #{version}" unless dates.length == 1
    raise "Release date cannot be in the future" if Date.iso8601(dates.first) > Time.now.utc.to_date
    raise "Release notes for #{version} are empty" unless notes(changelog, version).match?(/^[-*] \S/)

    expected_links = ["[#{version}]: #{URL}/releases/tag/v#{version}",
                      "[Unreleased]: #{URL}/compare/v#{version}...HEAD"]
    links = changelog.lines.map(&:chomp)
    raise "Missing or incorrect release links" unless expected_links.all? { |link| links.count(link) == 1 }

    version
  rescue Date::Error
    raise "Invalid changelog release date"
  end

  def self.validate_version(target)
    raise "Use a stable X.Y.Z version" unless target&.match?(VERSION_PATTERN)
  end

  def self.validate_branch(branch, target)
    validate_version(target)
    return branch if ["main", "hotfix/#{target.split('.').first(2).join('.')}"].include?(branch)

    raise "Release branch must be main or hotfix/#{target.split('.').first(2).join('.')}"
  end

  def self.verify_ref(sha: ENV.fetch("GITHUB_SHA"), version: self.version)
    raise "Invalid release commit" unless sha.match?(/\A[0-9a-f]{40}\z/)

    refs, status = Open3.capture2("git", "for-each-ref", "--contains", sha, "--format=%(refname:short)",
                                  "refs/remotes/origin")
    allowed = ["origin/main", "origin/hotfix/#{version.split('.').first(2).join('.')}"]
    return if status.success? && refs.lines.map(&:strip).intersect?(allowed)

    raise "Release commit must belong to main or its matching hotfix branch"
  end

  def self.notes(changelog, target)
    changelog.split(/^## \[#{Regexp.escape(target)}\][^\n]*\n/, 2).last.to_s.split(/^## |^\[[^\]]+\]:/, 2).first.to_s
  end

  def self.prepare(target, root: ROOT)
    changes(target, root: root).each { |path, content| File.write(File.join(root, path), content) }
    target
  end

  def self.changes(target, root: ROOT, source: nil, date: Time.now.utc.to_date)
    validate_version(target)
    source ||= clean_source(root)
    current_version = source.fetch(VERSION_FILE)[/VERSION = "([^"]+)"/, 1]
    raise "Version cannot go backwards" if Gem::Version.new(target) < Gem::Version.new(current_version)

    changelog = source.fetch("CHANGELOG.md")
    raise "Version already appears in the changelog" if changelog.include?("## [#{target}]")
    raise "Missing Unreleased section" unless changelog.include?("## [Unreleased]\n")

    raise "Add release notes under Unreleased first" unless notes(changelog, "Unreleased").match?(/^[-*] \S/)

    updated = changelog.sub("## [Unreleased]\n",
                            "## [Unreleased]\n\n## [#{target}] - #{date.iso8601}\n")
    updated = updated.sub(/^\[Unreleased\]:.*$/, "[Unreleased]: #{URL}/compare/v#{target}...HEAD")
    updated << "[#{target}]: #{URL}/releases/tag/v#{target}\n"
    verify(tag: "v#{target}", changelog: updated, version: target)
    {
      "CHANGELOG.md" => updated,
      VERSION_FILE => source.fetch(VERSION_FILE).sub(/VERSION = "[^"]+"/, "VERSION = \"#{target}\"")
    }
  end

  def self.clean_source(root)
    status, process = Open3.capture2("git", "status", "--porcelain", chdir: root)
    raise "Commit or stash changes before preparing a release" unless process.success? && status.empty?

    [VERSION_FILE, "CHANGELOG.md"].to_h { |path| [path, File.read(File.join(root, path))] }
  end
end
