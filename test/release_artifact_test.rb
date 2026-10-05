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
    capture_io { Gem::Package.build(spec, true, false, Release::Artifact.path(root: root)) }
    Release::Artifact.record(root: root)
  end

  def test_artifact_verification_checks_the_built_bytes_and_version
    repository do |root|
      digest = artifact(root)
      path = Release::Artifact.path(root: root)

      assert_equal path, Release::Artifact.verify(root: root, expected: digest)
      assert_release_error(/checksum mismatch/) { Release::Artifact.verify(root: root, expected: "0" * 64) }
      File.binwrite(path, "tampered")
      assert_release_error(/checksum mismatch/) { Release::Artifact.verify(root: root, expected: digest) }
      artifact(root, version: "9.0.0")
      assert_release_error(%r{name/version does not match}) { Release::Artifact.verify(root: root) }
    end
  end

  def test_a_missing_or_unreadable_artifact_is_reported_without_a_backtrace
    repository do |root|
      assert_release_error(%r{incomplete: pkg/rich-ri-0\.1\.0\.gem and pkg/SHA256SUMS not found}) do
        Release::Artifact.verify(root: root)
      end
      FileUtils.mkdir_p(File.join(root, "pkg"))
      File.binwrite(Release::Artifact.path(root: root), "not a gem")
      Release::Artifact.record(root: root)

      assert_release_error(/not a valid gem/) { Release::Artifact.verify(root: root) }
    end
  end

  def test_notes_follow_the_artifact_version_and_allow_unreleased_rehearsals
    repository do |root|
      artifact(root)

      assert_includes File.read(File.join(root, "pkg/release-notes.md")), "Readable documentation."
      FileUtils.remove_entry(File.join(root, "pkg"))
      Release.prepare("0.2.0", root: root)
      digest = artifact(root, version: "0.2.0")

      assert_match(/\A[0-9a-f]{64}\z/, digest)
      assert_equal Release::Artifact.path(root: root), Release::Artifact.verify(root: root)
    end
  end
end
