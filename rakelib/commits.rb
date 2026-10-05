# frozen_string_literal: true

require "open3"

module CommitPolicy
  TYPES = %w[feat fix docs test refactor perf build ci chore revert].freeze
  SUBJECT = /\A(?:#{TYPES.join('|')})(?:\([\w.-]+\))?!?: \S/
  UNFINISHED = /\A(?:(?:fixup|squash|amend)!|wip\b)|\A\w+(?:\([\w.-]+\))?!?:\s*wip\b/i
  # git revert writes Reapply when the reverted commit was itself a revert.
  REVERT = /\A(?:Revert|Reapply) "(?<subject>.+)"\z/

  ASSISTANTS = %w[Aider aider Amp ChatGPT Claude Codex Copilot Cursor Devin Gemini Jules opencode Windsurf].freeze
  TOOL_TRAILER = /\A(?:Generated-(?:by|with)|Assisted-by|Claude-Session|Amp-Thread-ID):/i
  # Product names stay case-sensitive: "generated with cursor movements" is ordinary prose.
  GENERATED = /\A\W*(?i:Generated (?:by|with)) \[?(?:#{ASSISTANTS.join('|')})\b/
  SESSION = %r{https://(?:claude\.ai/code/session_|chatgpt\.com/codex/tasks/|ampcode\.com/threads/|
               app\.devin\.ai/sessions/|jules\.google\.com/task/|cursor\.com/(?:agents|background-agent)\b)}ix
  # People share assistants' names (Claude Monet), so a signature counts as a tool's only by
  # a tool's address or by a name that is nothing but a product.
  SIGNATURE = /\A(?:Co-authored-by|Signed-off-by):\s*(?<name>[^<\n]*?)\s*<(?<address>[^>\n]+)>/i
  TOOL_ADDRESS = /\A(?:noreply@anthropic\.com|(?:codex|noreply)@openai\.com|cursoragent@cursor\.com|
                    (?:aider|noreply)@aider\.chat|copilot@github\.com|noreply@opencode\.ai|amp@ampcode\.com|
                    \d+\+(?:Copilot|gemini-cli|[\w-]+\[bot\])@users\.noreply\.github\.com)\z/ix
  TOOL_NAME = /\A(?:ChatGPT|Claude\ Code|Codex|(?:GitHub\ )?Copilot|Cursor\ Agent|Gemini(?:[ -]CLI)?|opencode)
               (?:\ \(.*\))?\z/ix

  class Error < StandardError; end

  def self.git(*)
    output, error, status = Open3.capture3("git", *)
    raise Error, "Cannot read commits: #{error.strip}" unless status.success?

    output.force_encoding(Encoding::UTF_8).scrub
  end

  def self.attribution(text)
    text.each_line.map(&:strip).find do |line|
      signature = SIGNATURE.match(line)
      next signature[:address].strip.match?(TOOL_ADDRESS) || signature[:name].match?(TOOL_NAME) if signature

      line.match?(TOOL_TRAILER) || line.match?(GENERATED) || line.match?(SESSION)
    end
  end

  def self.subject_problems(subject)
    reverted = REVERT.match(subject)
    return subject_problems(reverted[:subject]) if reverted

    if UNFINISHED.match?(subject)
      ["Finish this commit first; fixup!, squash!, amend! and WIP subjects are not accepted: #{subject}"]
    elsif SUBJECT.match?(subject)
      []
    else
      [%(Use a Conventional Commit subject, "type(scope): summary" with one of #{TYPES.join(', ')}: #{subject})]
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
    errors = subject ? subject_problems(message.to_s.lines.first.to_s.strip) : []
    credited = attribution(message.to_s)
    errors << "Remove generated attribution: #{credited}" if credited
    errors
  end
end
