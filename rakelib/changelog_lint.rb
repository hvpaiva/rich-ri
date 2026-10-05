# frozen_string_literal: true

require "open3"
require_relative "changelog"
require_relative "ci"

module Changelog
  module Lint
    USER_VISIBLE = %r{\A(?:(?:lib|exe|completions|man)/|rich-ri\.gemspec\z)}
    ENTRY_REQUIRED = "Changes to lib/, exe/, completions/, man/ or rich-ri.gemspec need a line under " \
                     '"## [Unreleased]". When users cannot see the change, set SKIP_CHANGELOG=1; ' \
                     "a maintainer adds the skip-changelog label to the pull request."

    class Error < StandardError; end

    def self.problems(root:, base: nil)
      text = read(root)
      problems = Changelog.problems(text)
      return problems unless base && changed_paths(root, base).any? { |path| path.scrub.match?(USER_VISIBLE) }

      entry_added?(fork_point_text(root, base), text) ? problems : problems << ENTRY_REQUIRED
    end

    def self.changed_paths(root, base)
      CI.changed_paths("#{base}...HEAD", root)
    rescue CI::Error => e
      raise Error, "Cannot compare HEAD with #{base}: #{e.message}"
    end

    # Where the branch forked: entries the base released since then are not the branch's own.
    def self.fork_point_text(root, base)
      fork_point, error, status = Open3.capture3("git", "merge-base", "--end-of-options", base, "HEAD", chdir: root)
      raise Error, "Cannot compare HEAD with #{base}: #{error.strip}" unless status.success?

      text, _error, status = Open3.capture3("git", "show", "#{fork_point.strip}:#{Changelog::PATH}", chdir: root)
      status.success? ? text : ""
    end

    # A release moves the entries out of Unreleased into a section of their own.
    def self.entry_added?(before, after)
      entries = ->(text) { Changelog.notes(text, "Unreleased").lines.grep(/^[-*] \S/) }
      versions = ->(text) { Changelog.releases(text).map(&:version) }
      (entries.call(after) - entries.call(before)).any? || (versions.call(after) - versions.call(before)).any?
    end

    def self.read(root)
      File.read(File.join(root, Changelog::PATH))
    rescue SystemCallError => e
      raise Error, "Cannot read #{Changelog::PATH} in #{root}: #{e.message.split(' @ ').first}"
    end
  end
end
