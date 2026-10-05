# frozen_string_literal: true

require "date"
require_relative "github"

# CHANGELOG.md follows Keep a Changelog: Unreleased first, then releases newest
# first, then one link reference per heading in the same order.
module Changelog
  PATH = "CHANGELOG.md"
  URL = "https://github.com/#{GitHub::REPOSITORY}".freeze
  SECTIONS = %w[Added Changed Deprecated Removed Fixed Security].freeze
  UNRELEASED = "[Unreleased]"
  # A withdrawn release keeps its heading and gains the marker.
  RELEASE = /\A\[(?<version>\d+\.\d+\.\d+)\] - (?<date>\d{4}-\d{2}-\d{2})(?: \[YANKED\])?\z/
  REFERENCE = /^\[(?:Unreleased|\d+\.\d+\.\d+)\]: .*$/
  SECTION_END = /^## |#{REFERENCE}/
  # A change under these paths reaches users, so it needs an entry.
  USER_VISIBLE = %r{\A(?:lib|exe|completions|man)/}

  Heading = Data.define(:version, :date) do
    def day = Date.strptime(date, "%Y-%m-%d")
    def dated? = Date.valid_date?(*date.split("-").map(&:to_i))
  end

  def self.headings(text) = text.scan(/^## (.*)$/).flatten

  def self.releases(text)
    headings(text).filter_map do |heading|
      match = RELEASE.match(heading)
      Heading.new(match[:version], match[:date]) if match
    end
  end

  def self.released?(text, version) = releases(text).any? { |release| release.version == version }

  # The text between a heading and the next one, or the link references.
  def self.notes(text, name)
    _before, heading, body = text.partition(/^## \[#{Regexp.escape(name)}\][^\n]*\n/)
    heading.empty? ? "" : body.split(SECTION_END, 2).first.strip
  end

  def self.entries?(text, name) = notes(text, name).match?(/^[-*] \S/)

  def self.references(text)
    versions = releases(text).map(&:version)
    unreleased = versions.empty? ? "#{URL}/commits/main" : "#{URL}/compare/v#{versions.first}...HEAD"
    ["[Unreleased]: #{unreleased}"] + versions.map { |version| "[#{version}]: #{URL}/releases/tag/v#{version}" }
  end

  # Moves the Unreleased entries under a dated heading and lists its link first.
  def self.cut(text, version, date)
    released = text.sub(/^## \[Unreleased\]\n/) { "## #{UNRELEASED}\n\n## [#{version}] - #{date.iso8601}\n" }
    released.sub(/^\[Unreleased\]: .*\n/) do
      "[Unreleased]: #{URL}/compare/v#{version}...HEAD\n[#{version}]: #{URL}/releases/tag/v#{version}\n"
    end
  end

  def self.entry_missing?(paths) = paths.any?(USER_VISIBLE) && !paths.include?(PATH)

  def self.problems(text, today: Time.now.utc.to_date)
    heading_problems(text) + release_problems(text, today) + section_problems(text) + reference_problems(text)
  end

  def self.heading_problems(text)
    headings = headings(text)
    problems = headings.reject { |heading| heading == UNRELEASED || RELEASE.match?(heading) }.map do |heading|
      %(Heading "## #{heading}" must be "## #{UNRELEASED}" or "## [X.Y.Z] - YYYY-MM-DD")
    end
    return problems if headings.first == UNRELEASED && headings.one?(UNRELEASED)

    problems << %("## #{UNRELEASED}" must appear once, before every release)
  end

  def self.release_problems(text, today)
    releases = releases(text)
    undated, dated = releases.partition { |release| !release.dated? }
    repeated = releases.map(&:version).tally.select { |_version, count| count > 1 }.keys
    problems = undated.map { |release| "[#{release.version}] has an invalid date: #{release.date}" }
    problems += dated.select { |release| release.day > today }.map do |release|
      "[#{release.version}] is dated in the future: #{release.date}"
    end
    problems += repeated.map { |version| "[#{version}] appears more than once" }
    problems << "Releases must be listed newest first" unless newest_first?(dated)
    problems + empty_releases(text).map { |version| %([#{version}] has no entries; add at least one "- " line) }
  end

  def self.empty_releases(text) = releases(text).map(&:version).uniq.reject { |version| entries?(text, version) }

  def self.newest_first?(releases)
    keys = releases.map { |release| [release.day, Gem::Version.new(release.version)] }
    keys.each_cons(2).all? { |above, below| (above <=> below) >= 0 }
  end

  def self.section_problems(text)
    (text.scan(/^### (.*)$/).flatten.uniq - SECTIONS).map do |section|
      %(Section "### #{section}" must be one of #{SECTIONS.join(', ')})
    end
  end

  def self.reference_problems(text)
    expected = references(text)
    text.scan(REFERENCE) == expected ? [] : ["Link references must be, in this order:\n#{expected.join("\n")}"]
  end
end
