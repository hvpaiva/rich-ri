# frozen_string_literal: true

require "open3"

# Select checks from the complete Git change, then verify the jobs that ran.
module CI
  ROOT = File.expand_path("..", __dir__)
  DOCUMENTS = %w[README.md ARCHITECTURE.md CONTRIBUTING.md CHANGELOG.md CODE_OF_CONDUCT.md SECURITY.md
                 docs/config.example.yml .github/PULL_REQUEST_TEMPLATE.md].freeze
  FULL_JOBS = %w[quality test audit fresh-dependencies compatibility].freeze
  # What can break without a commit: a new advisory, or a dependency release.
  SCHEDULED_JOBS = %w[audit fresh-dependencies].freeze
  JOBS = (%w[changes docs commits] + FULL_JOBS).freeze

  class Error < StandardError; end

  def self.documentation?(path)
    path.valid_encoding? && (DOCUMENTS.include?(path) || path.match?(%r{\Adocs/.+\.md\z}m) ||
      path.match?(%r{\Adocs/images/[^/]+\.png\z}))
  end

  def self.scope(event:, ref:, base:, head:, force_full: false, root: ROOT)
    return "full" if force_full
    return "scheduled" if event == "schedule"

    pull_request = event == "pull_request"
    branch_push = event == "push" && ref.match?(%r{\Arefs/heads/(?:main|hotfix/[^/]+)\z})
    return "full" unless pull_request || branch_push
    return "full" unless [base, head].all? { |sha| sha&.match?(/\A[0-9a-f]{40}\z/) && sha != "0" * 40 }

    paths = changed_paths("#{base}#{pull_request ? '...' : '..'}#{head}", root)
    paths&.any? && paths.all? { |path| documentation?(path) } ? "docs" : "full"
  end

  # Git paths are bytes: the locale must not decide whether they can be split.
  def self.changed_paths(range, root)
    output, _error, status = Open3.capture3("git", "diff", "--name-only", "--no-renames", "-z", "--end-of-options",
                                            range, "--", chdir: root, binmode: true)
    output.split("\0").map { |path| path.force_encoding(Encoding::UTF_8) } if status.success?
  end

  def self.verify!(results, event:, force_full: false)
    raise Error, "Incomplete CI job results" unless results.keys.sort == JOBS.sort
    raise Error, "Change detection did not succeed" unless results.dig("changes", "result") == "success"

    scope = results.dig("changes", "outputs", "scope")
    required = case scope
               when "full" then FULL_JOBS.dup
               when "docs" then ["docs"]
               when "scheduled" then SCHEDULED_JOBS.dup
               else raise Error, "Unknown CI scope: #{scope.inspect}"
               end
    raise Error, "This run requires the full suite" if force_full && scope != "full"
    raise Error, "Only scheduled runs may use scheduled scope" if scope == "scheduled" && event != "schedule"
    if scope == "docs" && !%w[push pull_request].include?(event)
      raise Error, "Only pushes and pull requests may use docs scope"
    end

    required << "commits" if event == "pull_request"
    required << "changes"
    failures = JOBS.filter_map do |name|
      expected = required.include?(name) ? "success" : "skipped"
      actual = results.dig(name, "result")
      "#{name}: expected #{expected}, got #{actual.inspect}" unless actual == expected
    end
    raise Error, failures.join("\n") unless failures.empty?

    scope
  end
end
