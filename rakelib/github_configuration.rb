# frozen_string_literal: true

require_relative "github"

module GitHub
  # These are repository policy, not release credentials. RubyGems trust remains
  # the maintainer's separate setup; this task cannot publish a gem.
  class Configuration
    REQUIRED_CHECKS = ["ci"].freeze
    ACTIONS_APP_ID = 15_368
    MERGE_SETTINGS = {
      "allow_merge_commit" => true, "allow_squash_merge" => false, "allow_rebase_merge" => false,
      "merge_commit_title" => "PR_TITLE", "merge_commit_message" => "BLANK", "delete_branch_on_merge" => true
    }.freeze
    ENVIRONMENT_POLICY = { "protected_branches" => false, "custom_branch_policies" => true }.freeze
    TAG_POLICY = { "name" => "v*", "type" => "tag" }.freeze
    REPOSITORY_SETTINGS = { "homepage" => "https://rubygems.org/gems/rich-ri", "has_issues" => true,
                            "has_wiki" => false, "has_projects" => false }.freeze
    TOPICS = %w[cli documentation rdoc ri ruby shell-completion syntax-highlighting terminal].freeze
    # CI reads skip-changelog and bin/release applies release; the issue forms apply the others.
    RELEASE_LABELS = %w[skip-changelog release].freeze
    LABELS = [
      { "name" => "skip-changelog", "color" => "ededed",
        "description" => "No CHANGELOG.md entry: no user-visible change" },
      { "name" => "release", "color" => "0e8a16", "description" => "Prepares a release" },
      { "name" => "bug", "color" => "d73a4a", "description" => "Something isn't working" },
      { "name" => "enhancement", "color" => "a2eeef", "description" => "New feature or request" },
      { "name" => "documentation", "color" => "0075ca",
        "description" => "Improvements or additions to documentation" }
    ].freeze

    def self.main_ruleset
      {
        "name" => "main", "target" => "branch", "enforcement" => "active", "bypass_actors" => [],
        "conditions" => { "ref_name" => { "include" => ["refs/heads/main", "refs/heads/hotfix/*"], "exclude" => [] } },
        "rules" => [
          { "type" => "pull_request", "parameters" => {
            "required_approving_review_count" => 0, "dismiss_stale_reviews_on_push" => false,
            "require_code_owner_review" => false, "require_last_push_approval" => false,
            "required_review_thread_resolution" => true, "allowed_merge_methods" => ["merge"]
          } },
          { "type" => "required_status_checks", "parameters" => {
            "strict_required_status_checks_policy" => true, "do_not_enforce_on_create" => false,
            "required_status_checks" => REQUIRED_CHECKS.map do |name|
              { "context" => name, "integration_id" => ACTIONS_APP_ID }
            end
          } },
          { "type" => "required_signatures" }, { "type" => "non_fast_forward" }, { "type" => "deletion" }
        ]
      }
    end

    def self.tags_ruleset
      {
        "name" => "tags", "target" => "tag", "enforcement" => "active",
        "bypass_actors" => [{ "actor_id" => 5, "actor_type" => "RepositoryRole", "bypass_mode" => "always" }],
        "conditions" => { "ref_name" => { "include" => ["refs/tags/v*"], "exclude" => [] } },
        "rules" => %w[creation update deletion].map { |type| { "type" => type } }
      }
    end

    def initialize(client: Client.new, out: $stdout)
      @client = client
      @out = out
    end

    # A missing topic or homepage must not hold up a release.
    def verify!(release: false)
      pending = release ? changes.select(&:release) : changes
      unless pending.empty?
        descriptions = pending.map { |change| "- #{change.description}" }.join("\n")
        raise Error, "Repository configuration needs attention:\n#{descriptions}\n" \
                     "Run bundle exec rake github:setup, then github:verify."
      end

      @out.puts "GitHub repository protections, release environment and security settings verified."
    end

    def setup
      pending = changes # Read every setting successfully before making the first write.
      pending.each do |change|
        @client.request(change.path, method: change.verb, body: change.body)
        @out.puts "Configured #{change.description}."
      end
      verify!
    end

    def changes
      @changes = []
      repository_settings
      rulesets
      environment
      security_features
      labels
      @changes
    end

    private

    def matches?(actual, expected)
      case expected
      when Hash then actual.is_a?(Hash) && expected.all? { |key, value| matches?(actual[key], value) }
      when Array
        actual.is_a?(Array) && actual.length == expected.length && expected.all? do |value|
          actual.any? { |item| matches?(item, value) }
        end
      else actual == expected
      end
    end

    def plan(description, method, path, body = nil, release: true)
      @changes << Change.new(description, method, path, body, release)
    end

    def get(path, **)
      @client.request(path, **)
    end

    def repository_settings
      current = get("").body
      raise Error, "Repository administrator access is required" unless current.dig("permissions", "admin")

      plan("merge settings", "PATCH", "", MERGE_SETTINGS) unless matches?(current, MERGE_SETTINGS)
      presentation(current)
      scanning = %w[secret_scanning secret_scanning_push_protection].to_h { |key| [key, { "status" => "enabled" }] }
      return if matches?(current["security_and_analysis"], scanning)

      plan("secret scanning and push protection", "PATCH", "", { "security_and_analysis" => scanning })
    end

    def presentation(current)
      unless matches?(current, REPOSITORY_SETTINGS)
        plan("homepage, issues, wiki and projects", "PATCH", "", REPOSITORY_SETTINGS, release: false)
      end
      return if current["topics"]&.sort == TOPICS

      plan("topics", "PUT", "/topics", { "names" => TOPICS }, release: false)
    end

    def rulesets
      existing = get("/rulesets").body
      [self.class.main_ruleset, self.class.tags_ruleset].each do |desired|
        found = existing.select { |ruleset| ruleset["name"] == desired["name"] }
        raise Error, "Duplicate #{desired['name']} rulesets; reconcile them in GitHub first" if found.length > 1

        path = found.empty? ? "/rulesets" : "/rulesets/#{found.first.fetch('id')}"
        next if found.any? && matches?(get(path).body, desired)

        plan("#{desired['name']} ruleset", found.empty? ? "POST" : "PUT", path, desired)
      end
    end

    def environment
      path = "/environments/release"
      current = get(path, missing: true)
      unless matches?(current.body["deployment_branch_policy"], ENVIRONMENT_POLICY)
        plan("release environment", "PUT", path, { "deployment_branch_policy" => ENVIRONMENT_POLICY })
      end
      policies = current.status == 404 ? [] : get("#{path}/deployment-branch-policies").body.fetch("branch_policies")
      policies.reject { |policy| matches?(policy, TAG_POLICY) }.each do |policy|
        plan("remove extra release deployment policy #{policy.fetch('name')}", "DELETE",
             "#{path}/deployment-branch-policies/#{policy.fetch('id')}")
      end
      return if policies.any? { |policy| matches?(policy, TAG_POLICY) }

      plan("release deployments restricted to v* tags", "POST", "#{path}/deployment-branch-policies", TAG_POLICY)
    end

    def security_features
      alerts = get("/vulnerability-alerts", missing: true)
      plan("vulnerability alerts", "PUT", "/vulnerability-alerts") if alerts.status == 404
      %w[automated-security-fixes private-vulnerability-reporting immutable-releases].each do |feature|
        plan(feature.tr("-", " "), "PUT", "/#{feature}") unless get("/#{feature}").body.fetch("enabled")
      end
    end

    def labels
      LABELS.each do |label|
        name = label.fetch("name")
        next unless get("/labels/#{name}", missing: true).status == 404

        plan("#{name} label", "POST", "/labels", label, release: RELEASE_LABELS.include?(name))
      end
    end
  end
end
