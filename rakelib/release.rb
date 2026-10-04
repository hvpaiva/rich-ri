# frozen_string_literal: true

require "date"
require "open3"

module Release
  ROOT = File.expand_path("..", __dir__)
  VERSION_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/

  def self.version(root: ROOT)
    File.read(File.join(root, "lib/rich_ri/version.rb"))[/VERSION = "([^"]+)"/, 1]
  end

  def self.verify(tag: ENV.fetch("GITHUB_REF_NAME", nil), changelog: File.read(File.join(ROOT, "CHANGELOG.md")))
    raise "Release tag must be v#{version}" unless tag == "v#{version}"
    raise "Missing Unreleased section" unless changelog.include?("## [Unreleased]\n")
    unless changelog.match?(/^## \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}$/)
      raise "Missing dated changelog for #{version}"
    end
    raise "Missing release link" unless changelog.include?("[#{version}]: https://github.com/hvpaiva/rich-ri/")

    version
  end

  def self.prepare(target, root: ROOT)
    raise "Use a stable X.Y.Z version" unless target&.match?(VERSION_PATTERN)
    raise "Version cannot go backwards" if Gem::Version.new(target) < Gem::Version.new(version(root: root))

    status, process = Open3.capture2("git", "status", "--porcelain", chdir: root)
    raise "Commit or stash changes before preparing a release" unless process.success? && status.empty?

    changelog_path = File.join(root, "CHANGELOG.md")
    changelog = File.read(changelog_path)
    raise "Version already appears in the changelog" if changelog.include?("## [#{target}]")
    raise "Missing Unreleased section" unless changelog.include?("## [Unreleased]\n")

    updated = changelog.sub("## [Unreleased]\n", "## [Unreleased]\n\n## [#{target}] - #{Date.today.iso8601}\n")
    updated = updated.sub(/^\[Unreleased\]:.*$/, "[Unreleased]: https://github.com/hvpaiva/rich-ri/compare/v#{target}...HEAD")
    updated << "[#{target}]: https://github.com/hvpaiva/rich-ri/releases/tag/v#{target}\n"
    File.write(changelog_path, updated)
    path = File.join(root, "lib/rich_ri/version.rb")
    File.write(path, File.read(path).sub(/VERSION = "[^"]+"/, "VERSION = \"#{target}\""))
    target
  end
end
