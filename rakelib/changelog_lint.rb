# frozen_string_literal: true

require_relative "changelog"
require_relative "ci"

module Changelog
  module Lint
    USER_VISIBLE = %r{\A(?:lib|exe|completions|man)/}
    ENTRY_REQUIRED = 'Changes under lib/, exe/, completions/ or man/ need a line under "## [Unreleased]". ' \
                     "When users cannot see the change, set SKIP_CHANGELOG=1; a maintainer adds the " \
                     "skip-changelog label to the pull request."

    class Error < StandardError; end

    def self.entry_missing?(paths)
      paths.any? { |path| path.scrub.match?(USER_VISIBLE) } && !paths.include?(Changelog::PATH)
    end

    def self.problems(root:, base: nil)
      problems = Changelog.problems(read(root))
      return problems unless base

      entry_missing?(changed_paths(root, base)) ? problems << ENTRY_REQUIRED : problems
    end

    def self.changed_paths(root, base)
      CI.changed_paths("#{base}...HEAD", root)
    rescue CI::Error => e
      raise Error, "Cannot compare HEAD with #{base}: #{e.message}"
    end

    def self.read(root)
      File.read(File.join(root, Changelog::PATH))
    rescue SystemCallError => e
      raise Error, "Cannot read #{Changelog::PATH} in #{root}: #{e.message.split(' @ ').first}"
    end
  end
end
