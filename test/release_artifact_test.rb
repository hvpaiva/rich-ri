# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release_artifact"
require_relative "release_support"

class ReleaseArtifactTest < Minitest::Test
  include ReleaseFixtures

  def artifact(root, version: "0.1.0")
    FileUtils.mkdir_p(File.join(root, "pkg"))
    spec = Gem::Specification.new do |gem|
      gem.name = "rich-ri"
      gem.version = version
      gem.summary = "Release test"
      gem.authors = ["Test"]
      gem.license = "MIT"
      gem.homepage = "https://example.org"
    end
    capture_io { Gem::Package.build(spec, true, false, gem_path(root)) }
    Release::Artifact.record(root: root)
  end

  def test_a_verified_artifact_is_returned_by_path
    repository do |root|
      digest = artifact(root)

      assert_equal gem_path(root), Release::Artifact.verify(root: root, expected: digest)
    end
  end

  def test_an_artifact_with_another_digest_than_the_one_verified_upstream_is_refused
    repository do |root|
      artifact(root)

      assert_release_error("release artifact checksum mismatch") do
        Release::Artifact.verify(root: root, expected: "0" * 64)
      end
    end
  end

  def test_an_artifact_whose_bytes_differ_from_the_recorded_checksum_is_refused
    repository do |root|
      digest = artifact(root)
      File.binwrite(gem_path(root), "tampered")

      assert_release_error("release artifact checksum mismatch") do
        Release::Artifact.verify(root: root, expected: digest)
      end
    end
  end

  def test_an_artifact_for_another_version_is_refused
    repository do |root|
      artifact(root, version: "9.0.0")

      assert_release_error("release artifact name/version does not match the checkout") do
        Release::Artifact.verify(root: root)
      end
    end
  end

  def test_a_missing_artifact_names_the_missing_files
    repository do |root|
      assert_release_error("release artifact is incomplete: pkg/rich-ri-0.1.0.gem and pkg/SHA256SUMS not found") do
        Release::Artifact.verify(root: root)
      end
    end
  end

  def test_an_artifact_that_is_not_a_gem_is_refused_without_a_backtrace
    repository do |root|
      FileUtils.mkdir_p(File.join(root, "pkg"))
      File.binwrite(gem_path(root), "not a gem")
      Release::Artifact.record(root: root)

      gem = File.join(root, "pkg/rich-ri-0.1.0.gem")

      assert_release_error("release artifact is not a valid gem: package metadata is missing in #{gem}") do
        Release::Artifact.verify(root: root)
      end
    end
  end

  def test_notes_follow_the_artifact_version_and_allow_unreleased_rehearsals
    repository do |root|
      artifact(root)

      assert_includes File.read(File.join(root, "pkg/release-notes.md")), "Readable documentation."
      FileUtils.remove_entry(File.join(root, "pkg"))
      Release.changes("0.2.0", root: root).each { |path, content| File.write(File.join(root, path), content) }
      digest = artifact(root, version: "0.2.0")

      assert_match(/\A[0-9a-f]{64}\z/, digest)
      assert_equal gem_path(root), Release::Artifact.verify(root: root)
    end
  end

  private

  def gem_path(root) = File.join(root, "pkg/rich-ri-#{Release.version(root: root)}.gem")
end
