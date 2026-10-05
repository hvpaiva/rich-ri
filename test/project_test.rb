# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release"

class ProjectTest < Minitest::Test
  def test_package_manifest_contains_only_distribution_files
    spec = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec"))

    assert_equal ["rich-ri"], spec.executables
    assert_equal RichRI::VERSION, spec.version.to_s
    assert_includes spec.files, "completions/rich-ri.bash"
    assert_includes spec.files, "man/man1/rich-ri.1"
    assert(spec.files.all? do |file|
      file.match?(%r{\A(?:lib/|exe/|completions/|man/|docs/|README.md|CHANGELOG.md|LICENSE.txt|SECURITY.md)})
    end)
    refute(spec.files.any? { |file| file.include?("/home/") || file.start_with?("test/", "tmp/", ".") })
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
