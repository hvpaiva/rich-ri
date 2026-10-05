# frozen_string_literal: true

require "open3"
require_relative "changelog"
require_relative "ci"
require_relative "system_error"

module Changelog
  module Lint
    # A trailing slash names a directory; anything else names one file.
    USER_VISIBLE = %w[lib/ exe/ completions/ man/ rich-ri.gemspec].freeze
    USER_VISIBLE_NAMES = "#{USER_VISIBLE[...-1].join(', ')} or #{USER_VISIBLE.last}".freeze
    ENTRY_REQUIRED = "changes to #{USER_VISIBLE_NAMES} need a new entry under " \
                     '"## [Unreleased]"; if users cannot see the change, set SKIP_CHANGELOG=1 and ask a ' \
                     "maintainer for the skip-changelog label on the pull request".freeze

    class Error < StandardError; end

    def self.problems(root:, base: nil)
      text = read(root)
      problems = Changelog.problems(text)
      return problems unless base && changed_paths(root, base).any? { |path| user_visible?(path.scrub) }

      entry_added?(fork_point_text(root, base), text) ? problems : problems << ENTRY_REQUIRED
    end

    def self.user_visible?(path)
      USER_VISIBLE.any? { |entry| entry.end_with?("/") ? path.start_with?(entry) : path == entry }
    end

    def self.changed_paths(root, base)
      CI.changed_paths("#{base}...HEAD", root)
    rescue CI::Error => e
      raise Error, "cannot compare HEAD with #{base}: #{e.message}"
    end

    # Where the branch forked: entries the base released since then are not the branch's own.
    # git diff has already read base as a revision, so merge-base never sees it as an option.
    def self.fork_point_text(root, base)
      fork_point = git(root, "cannot compare HEAD with #{base}", "merge-base", base, "HEAD").strip
      git(root, "cannot read #{Changelog::PATH} at #{fork_point}", "show", "#{fork_point}:#{Changelog::PATH}")
    end

    def self.git(root, failure, *)
      output, error, status = Open3.capture3("git", *, chdir: root)
      raise Error, "#{failure}: #{error.strip}" unless status.success?

      output
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
      raise Error, "cannot read #{Changelog::PATH} in #{root}: #{SystemError.reason(e)}"
    end

    private_class_method :user_visible?, :changed_paths, :fork_point_text, :git, :entry_added?, :read
  end
end
