# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release"

class ProjectTest < Minitest::Test
  USER_GUIDES = %w[docs/compatibility.md docs/configuration.md docs/shell-completion.md docs/troubleshooting.md
                   docs/usage.md].freeze
  # Notes for people working on the project: read in the repository, not shipped.
  REPOSITORY_GUIDES = %w[docs/development.md docs/images/README.md docs/maintenance.md].freeze
  SHIPPED = (USER_GUIDES + %w[docs/config.example.yml exe/rich-ri completions/rich-ri.bash completions/rich-ri.fish
                              completions/rich-ri.zsh man/man1/rich-ri.1 README.md CHANGELOG.md LICENSE.txt
                              SECURITY.md]).freeze

  def test_the_gem_ships_the_runtime_and_the_user_guides_and_nothing_else
    spec = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec"))
    runtime = Dir.glob("lib/**/*.rb", base: TestSupport::ROOT)

    assert_equal ["rich-ri"], spec.executables
    assert_equal RichRI::VERSION, spec.version.to_s
    assert_equal (runtime + SHIPPED).sort, spec.files.sort
  end

  def test_every_guide_is_either_shipped_to_users_or_kept_for_contributors
    guides = Dir.glob("docs/**/*.md", base: TestSupport::ROOT)

    assert_equal guides.sort, (USER_GUIDES + REPOSITORY_GUIDES).sort
  end

  def test_the_minimum_bundle_pins_every_runtime_dependency_at_its_declared_floor
    spec = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec"))
    pins = File.read(File.join(TestSupport::ROOT, "gemfiles/minimum.gemfile")).scan(/^gem "([^"]+)", "([^"]+)"$/).to_h
    floors = spec.runtime_dependencies.to_h do |dependency|
      [dependency.name, dependency.requirement.requirements.map(&:last).min.to_s]
    end

    assert_empty floors.keys - pins.keys
    assert_empty(floors.reject { |name, floor| Gem::Version.new(pins.fetch(name)) == Gem::Version.new(floor) })
    assert(spec.runtime_dependencies.all? { |dependency| dependency.requirement.to_s.start_with?("~> ") })
  end

  def test_release_requires_matching_version_tag_and_dated_changelog
    changelog = <<~TEXT
      ## [Unreleased]
      ## [#{RichRI::VERSION}] - 2026-10-04
      - Add the documentation reader.
      [Unreleased]: https://github.com/hvpaiva/rich-ri/compare/v#{RichRI::VERSION}...HEAD
      [#{RichRI::VERSION}]: https://github.com/hvpaiva/rich-ri/releases/tag/v#{RichRI::VERSION}
    TEXT
    assert_equal RichRI::VERSION, Release.verify(tag: "v#{RichRI::VERSION}", changelog: changelog)
    error = assert_raises(Release::Error) { Release.verify(tag: "v9.9.9", changelog: changelog) }

    assert_equal "Release tag must be v#{RichRI::VERSION}", error.message
    error = assert_raises(Release::Error) do
      Release.verify(tag: "v#{RichRI::VERSION}", changelog: "## [Unreleased]\n")
    end

    assert_includes error.message, %(CHANGELOG.md has no "## [#{RichRI::VERSION}] - YYYY-MM-DD" heading)
  end

  def test_a_failed_release_check_reports_its_reason_without_a_backtrace
    _out, err, status = Open3.capture3({ "GITHUB_REF_NAME" => nil }, "bundle", "exec", "rake", "release:verify",
                                       chdir: TestSupport::ROOT)

    refute_predicate status, :success?
    assert_equal "release:verify: Release tag must be v#{RichRI::VERSION}\n", err
  end

  def test_local_release_is_refused_before_any_publish_action
    _out, err, status = Open3.capture3({ "GITHUB_ACTIONS" => nil }, "bundle", "exec", "rake", "release",
                                       chdir: TestSupport::ROOT)

    refute_predicate status, :success?
    assert_includes err, "Publication runs only in the release workflow"
  end
end
