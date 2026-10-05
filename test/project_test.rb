# frozen_string_literal: true

require "test_helper"
require "program_support"
require_relative "../rakelib/release"

class ProjectTest < Minitest::Test
  include ProgramSupport

  USER_GUIDES = %w[docs/compatibility.md docs/configuration.md docs/shell-completion.md docs/troubleshooting.md
                   docs/usage.md].freeze
  REPOSITORY_GUIDES = %w[docs/development.md docs/images/README.md docs/maintenance.md].freeze
  RELEASED = <<~TEXT.freeze
    ## [Unreleased]
    ## [#{RichRI::VERSION}] - 2026-10-04
    - Add the documentation reader.
    [Unreleased]: https://github.com/hvpaiva/rich-ri/compare/v#{RichRI::VERSION}...HEAD
    [#{RichRI::VERSION}]: https://github.com/hvpaiva/rich-ri/releases/tag/v#{RichRI::VERSION}
  TEXT
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
  end

  def test_every_runtime_dependency_allows_only_compatible_releases
    spec = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec"))

    assert_empty(spec.runtime_dependencies.reject { |dependency| dependency.requirement.to_s.start_with?("~> ") })
  end

  def test_a_release_with_its_tag_and_dated_changelog_is_verified
    assert_equal RichRI::VERSION, Release.verify(tag: "v#{RichRI::VERSION}", changelog: RELEASED)
  end

  def test_a_release_tag_must_name_the_version
    error = assert_raises(Release::Error) { Release.verify(tag: "v9.9.9", changelog: RELEASED) }

    assert_equal "release tag must be v#{RichRI::VERSION}", error.message
  end

  def test_a_release_needs_its_dated_changelog_heading
    error = assert_raises(Release::Error) do
      Release.verify(tag: "v#{RichRI::VERSION}",
                     changelog: "## [Unreleased]\n\n[Unreleased]: https://github.com/hvpaiva/rich-ri/commits/main\n")
    end

    assert_equal %(CHANGELOG.md: "## [#{RichRI::VERSION}] - YYYY-MM-DD" is missing), error.message
  end

  def test_a_failed_release_check_reports_its_reason_without_a_backtrace
    _out, err, status = rake("release:verify", env: { "GITHUB_REF_NAME" => nil })

    assert_equal [1, "rake: release tag must be v#{RichRI::VERSION}\n"], [status.exitstatus, err]
  end

  def test_a_release_commit_check_without_a_commit_reports_its_reason_without_a_backtrace
    _out, err, status = rake("release:verify_ref", env: { "GITHUB_SHA" => nil })

    assert_equal [1, "rake: invalid release commit: set GITHUB_SHA to a full commit ID\n"], [status.exitstatus, err]
  end

  def test_an_artifact_check_reports_its_reason_without_a_backtrace
    Dir.mktmpdir("rich-ri-artifact-") do |root|
      FileUtils.cp_r(File.join(TestSupport::ROOT, "rakelib"), root)
      FileUtils.cp(File.join(TestSupport::ROOT, "Rakefile"), root)
      FileUtils.mkdir_p(File.join(root, "lib/rich_ri"))
      FileUtils.cp(File.join(TestSupport::ROOT, "lib/rich_ri/version.rb"), File.join(root, "lib/rich_ri"))
      _out, err, status = rake("release:verify_artifact", chdir: root, rakefile: File.join(root, "Rakefile"))

      assert_equal [1, "rake: release artifact is incomplete: pkg/rich-ri-#{RichRI::VERSION}.gem and pkg/SHA256SUMS " \
                       "not found\n"], [status.exitstatus, err]
    end
  end

  def test_publication_in_the_release_workflow_reports_its_reason_without_a_backtrace
    workflow = { "GITHUB_ACTIONS" => "true", "GITHUB_REPOSITORY" => "hvpaiva/rich-ri",
                 "GITHUB_REF" => "refs/tags/v9.9.9", "GITHUB_REF_NAME" => "v9.9.9" }
    _out, err, status = rake("release", env: workflow)

    assert_equal [1, "rake: release tag must be v#{RichRI::VERSION}\n"], [status.exitstatus, err]
  end

  def test_a_stale_manual_is_reported_with_the_command_that_regenerates_it
    Dir.mktmpdir("rich-ri-manual-") do |root|
      FileUtils.mkdir_p(File.join(root, "man/man1"))
      File.write(File.join(root, "man/man1/rich-ri.1"), ".TH STALE 1\n")
      _out, err, status = rake("generate:check", chdir: root)

      assert_equal [1, "rake: the manual is stale; run bundle exec rake generate\n"], [status.exitstatus, err]
    end
  end

  def test_every_rake_task_describes_itself
    out, err, status = rake("--all", "--tasks")
    undescribed = out.lines.grep_v(/ # \S/).map { |line| line.split.fetch(1) }

    assert_predicate status, :success?, err
    # RuboCop defines this deprecated alias of rubocop:autocorrect without a description.
    assert_equal ["rubocop:auto_correct"], undescribed
  end

  def test_every_rake_task_a_maintenance_message_names_exists
    out, err, status = rake("--all", "--tasks")
    tasks = out.lines.map { |line| line.split.fetch(1)[/\A[^\[]+/] }
    sources = Dir[File.join(TestSupport::ROOT, "{bin/*,rakelib/*.{rb,rake},Rakefile}")]
    named = sources.flat_map { |path| File.read(path).scan(/bundle exec rake ([a-z][\w:]*)/).flatten }.uniq

    assert_predicate status, :success?, err
    assert_equal %w[check generate github:setup test:compatibility test:shells], named.sort
    assert_empty named - tasks
  end

  def test_local_release_is_refused_before_any_publish_action
    _out, err, status = rake("release", env: { "GITHUB_ACTIONS" => nil })

    assert_equal [1, "rake: publication runs only in the release workflow; use bin/release X.Y.Z --push\n"],
                 [status.exitstatus, err]
  end
end
