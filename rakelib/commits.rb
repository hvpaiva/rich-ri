# frozen_string_literal: true

require "open3"

module CommitPolicy
  SUBJECT = /\A(?:feat|fix|docs|test|refactor|perf|build|ci|chore|revert)(?:\([\w.-]+\))?!?: \S/
  GENERATED = /^(?:Generated-(?:by|with)|Assisted-by|Claude-Session):|^\W*Generated with \[?(?:Claude|Codex|ChatGPT)\b/i
  BOT_ADDRESS = /\A(?:noreply@anthropic\.com|cursoragent@cursor\.com|(?:aider|noreply)@aider\.chat|
                    \d+\+(?:Copilot|[\w-]+\[bot\])@users\.noreply\.github\.com)\z/ix

  class Error < StandardError; end

  def self.git(*)
    output, error, status = Open3.capture3("git", *)
    raise Error, "Cannot read commits: #{error.strip}" unless status.success?

    output.force_encoding(Encoding::UTF_8).scrub
  end

  def self.attribution?(text)
    text.match?(GENERATED) || text.scan(/^Co-Authored-By:[^<\n]*<([^>\n]+)>/i).flatten.any? do |address|
      address.strip.match?(BOT_ADDRESS)
    end
  end

  def self.problems(range, title: nil, body: nil)
    errors = git("rev-list", "--reverse", range, "--").lines.flat_map do |line|
      sha = line.strip
      # Read stored parents: shallow checkouts hide them from git log --no-merges.
      headers, message = git("cat-file", "commit", sha).split("\n\n", 2)
      check(message, subject: headers.scan(/^parent /).length < 2).map { |error| "#{sha[0, 8]}: #{error}" }
    end
    errors.concat(check(title, subject: true).map { |error| "PR title: #{error}" }) if title
    errors.concat(check(body, subject: false).map { |error| "PR body: #{error}" }) if body
    errors
  end

  def self.check(message, subject:)
    errors = []
    if subject && !message.to_s.lines.first.to_s.match?(SUBJECT)
      errors << "Use a Conventional Commit subject: #{message.to_s.lines.first.to_s.strip}"
    end
    errors << "Remove generated attribution trailers" if attribution?(message.to_s)
    errors
  end
end
