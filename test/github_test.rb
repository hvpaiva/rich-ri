# frozen_string_literal: true

require "test_helper"
require "git_support"
require "program_support"
require_relative "../rakelib/github_configuration"

class GitHubTest < Minitest::Test
  include GitSupport
  include ProgramSupport

  class MemoryClient
    attr_reader :calls, :state
    attr_accessor :fail_path

    def initialize
      @calls = []
      scanning = %w[secret_scanning secret_scanning_push_protection].to_h { |key| [key, { "status" => "enabled" }] }
      policies = { "branch_policies" => [GitHub::Configuration::TAG_POLICY.merge("id" => 1)] }
      @state = {
        "" => GitHub::Configuration::MERGE_SETTINGS.merge(
          "permissions" => { "admin" => true }, "security_and_analysis" => scanning
        ),
        "/rulesets" => [{ "id" => 1, "name" => "main" }, { "id" => 2, "name" => "tags" }],
        "/rulesets/1" => GitHub::Configuration.main_ruleset,
        "/rulesets/2" => GitHub::Configuration.tags_ruleset,
        "/environments/release" => { "deployment_branch_policy" => GitHub::Configuration::ENVIRONMENT_POLICY },
        "/environments/release/deployment-branch-policies" => policies,
        "/vulnerability-alerts" => {}, "/automated-security-fixes" => { "enabled" => true },
        "/private-vulnerability-reporting" => { "enabled" => true }, "/immutable-releases" => { "enabled" => true }
      }
      GitHub::Configuration::LABELS.each do |label|
        @state["/labels/#{label.fetch('name')}"] = label.merge("color" => "123456")
      end
    end

    def request(path, method: "GET", body: nil, missing: false)
      @calls << [method, path, body]
      raise GitHub::Error, "HTTP 403" if path == fail_path

      if method == "GET"
        return GitHub::Response.new(404, {}) if !state.key?(path) && missing

        return GitHub::Response.new(200, state.fetch(path))
      end
      apply(path, method, body)
      GitHub::Response.new(200, {})
    end

    def apply(path, method, body)
      case path
      when "" then state[""] = state[""].merge(body)
      when "/rulesets"
        id = state[path].length + 1
        state[path] << body.slice("name").merge("id" => id)
        state["#{path}/#{id}"] = body
      when "/environments/release/deployment-branch-policies"
        state[path] ||= { "branch_policies" => [] }
        state[path]["branch_policies"] << body.merge("id" => 1)
      when %r{/deployment-branch-policies/\d+\z}
        state[path.sub(%r{/\d+\z}, "")]["branch_policies"].reject! { |entry| entry["id"].to_s == path.split("/").last }
      when "/labels" then state["/labels/#{body.fetch('name')}"] = body
      else state[path] = method == "DELETE" ? nil : body || { "enabled" => true }
      end
    end
  end

  def test_verify_is_read_only_and_accepts_server_defaults_and_existing_label_style
    client = MemoryClient.new
    client.state["/rulesets/1"]["rules"].reverse!
    client.state["/rulesets/1"]["created_at"] = "2026-10-04"
    GitHub::Configuration.new(client: client, out: StringIO.new).verify!

    assert(client.calls.all? { |method, *_| method == "GET" })
  end

  def test_setup_reconciles_policies_and_is_idempotent
    client = MemoryClient.new
    client.state[""]["allow_squash_merge"] = true
    client.state["/rulesets"] = []
    %w[/environments/release /vulnerability-alerts /labels/skip-changelog].each { |path| client.state.delete(path) }
    %w[/automated-security-fixes /private-vulnerability-reporting /immutable-releases].each do |path|
      client.state[path] = { "enabled" => false }
    end
    config = GitHub::Configuration.new(client: client, out: StringIO.new)
    config.setup
    writes = client.calls.reject { |method, *_| method == "GET" }

    assert_equal 10, writes.length
    client.calls.clear
    config.setup

    assert(client.calls.all? { |method, *_| method == "GET" })
    assert_empty config.changes
  end

  def test_setup_reads_every_setting_before_writing_and_fails_on_access_errors
    client = MemoryClient.new
    client.state[""]["allow_squash_merge"] = true
    client.fail_path = "/immutable-releases"
    error = assert_raises(GitHub::Error) do
      GitHub::Configuration.new(client: client, out: StringIO.new).setup
    end

    assert_equal "HTTP 403", error.message
    assert(client.calls.all? { |method, *_| method == "GET" })
  end

  def test_verify_detects_wrong_check_app_bypass_and_extra_deployment_policy
    client = MemoryClient.new
    rules = client.state["/rulesets/1"]
    rules["bypass_actors"] = [{ "actor_id" => 5 }]
    checks = rules["rules"].find { |rule| rule["type"] == "required_status_checks" }
    checks["parameters"]["required_status_checks"].first["integration_id"] = 42
    policies = client.state["/environments/release/deployment-branch-policies"]["branch_policies"]
    policies << { "id" => 2, "type" => "branch", "name" => "*" }
    config = GitHub::Configuration.new(client: client, out: StringIO.new)
    error = assert_raises(GitHub::Error) { config.verify! }

    assert_equal "repository configuration needs attention; run bundle exec rake github:setup to apply:\n" \
                 "- main ruleset\n- remove extra release deployment policy *", error.message
    config.setup

    assert_empty config.changes
  end

  def test_a_missing_label_that_ci_or_releases_use_needs_attention
    GitHub::Configuration::LABELS.each do |label|
      client = MemoryClient.new
      client.state.delete("/labels/#{label.fetch('name')}")
      error = assert_raises(GitHub::Error) { GitHub::Configuration.new(client: client, out: StringIO.new).verify! }

      assert_equal "repository configuration needs attention; run bundle exec rake github:setup to apply:\n" \
                   "- #{label.fetch('name')} label", error.message
    end
  end

  def test_configuration_needs_an_administrator
    client = MemoryClient.new
    client.state[""]["permissions"]["admin"] = false
    error = assert_raises(GitHub::Error) { GitHub::Configuration.new(client: client, out: StringIO.new).verify! }

    assert_equal "repository administrator access is required", error.message
  end

  def test_two_rulesets_with_one_name_are_left_for_a_person_to_reconcile
    client = MemoryClient.new
    client.state["/rulesets"] << { "id" => 3, "name" => "main" }
    error = assert_raises(GitHub::Error) { GitHub::Configuration.new(client: client, out: StringIO.new).setup }

    assert_equal "duplicate main rulesets; reconcile them in GitHub first", error.message
    assert(client.calls.all? { |method, *_| method == "GET" })
  end

  def test_repository_tasks_refuse_another_origin
    %w[github:verify github:setup].each do |task|
      github_origin("https://github.com/someone/rich-ri.git") do |environment|
        Dir.mktmpdir("rich-ri-origin-") do |bin|
          link_program(bin, "git")
          out, err, status = isolated_rake(bin, task, env: environment)

          assert_equal [1, "", "rake: the origin repository must be hvpaiva/rich-ri\n"],
                       [status.exitstatus, out, err], task
        end
      end
    end
  end

  def test_client_distinguishes_disabled_endpoint_from_forbidden_access
    status = Struct.new(:success?).new(false)
    response = lambda do |code|
      GitHub::Client.new(runner: lambda do |_argv, **_options|
        ["HTTP/2.0 #{code} Error\r\nContent-Type: application/json\r\n\r\n{\"message\":\"Denied\"}", status]
      end)
    end

    assert_equal 404, response.call(404).request("/vulnerability-alerts", missing: true).status
    assert_raises(GitHub::Error) { response.call(403).request("/vulnerability-alerts", missing: true) }
    assert_raises(GitHub::Error) { response.call(500).request("/immutable-releases") }
  end

  def test_repository_tasks_without_gh_say_how_to_install_it
    %w[github:verify github:setup].each do |task|
      github_origin do |environment|
        Dir.mktmpdir("rich-ri-no-gh-") do |bin|
          link_program(bin, "git")
          out, err, status = isolated_rake(bin, task, env: environment)

          assert_equal [1, "", "rake: gh is not installed; install it with your package manager\n"],
                       [status.exitstatus, out, err], task
        end
      end
    end
  end

  def test_origin_accepts_only_this_repository_on_github
    accepted = %w[https://github.com/hvpaiva/rich-ri https://github.com/hvpaiva/rich-ri.git
                  git@github.com:hvpaiva/rich-ri.git ssh://git@github.com/hvpaiva/rich-ri]
    rejected = %w[https://github.com/someone/rich-ri.git https://github.com/hvpaiva/rich-ri-fork
                  https://github.com/hvpaiva/rich_ri https://example.org/hvpaiva/rich-ri.git
                  https://github.com/hvpaiva/rich-ri.git/extra]

    assert_equal(accepted, (accepted + rejected).select { |url| GitHub.origin?("#{url}\n") })
  end
end
