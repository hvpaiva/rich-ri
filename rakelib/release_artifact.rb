# frozen_string_literal: true

require "digest"
require "rubygems/package"
require_relative "release"

module Release
  module Artifact
    def self.path(root: ROOT)
      File.join(root, "pkg", "rich-ri-#{Release.version(root: root)}.gem")
    end

    def self.record(root: ROOT)
      gem = path(root: root)
      digest = Digest::SHA256.file(gem).hexdigest
      File.write(File.join(root, "pkg/SHA256SUMS"), "#{digest}  #{File.basename(gem)}\n")
      changelog = File.read(File.join(root, "CHANGELOG.md"))
      section = changelog.include?("## [#{Release.version(root: root)}]") ? Release.version(root: root) : "Unreleased"
      File.write(File.join(root, "pkg/release-notes.md"), "#{Release.notes(changelog, section).strip}\n")
      digest
    end

    def self.verify(root: ROOT, expected: ENV.fetch("RELEASE_SHA256", nil))
      gem = path(root: root)
      digest = Digest::SHA256.file(gem).hexdigest
      manifest = File.read(File.join(root, "pkg/SHA256SUMS"))
      unless manifest == "#{digest}  #{File.basename(gem)}\n" && (expected.nil? || expected == digest)
        raise "Release artifact checksum mismatch"
      end

      package = Gem::Package.new(gem)
      package.verify
      spec = package.spec
      unless spec.name == "rich-ri" && spec.version.to_s == Release.version(root: root)
        raise "Release artifact name/version does not match the checkout"
      end

      gem
    end
  end
end
