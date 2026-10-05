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
      changelog = File.read(File.join(root, Changelog::PATH))
      version = Release.version(root: root)
      section = Changelog.released?(changelog, version) ? version : "Unreleased"
      File.write(File.join(root, "pkg/release-notes.md"), "#{Changelog.notes(changelog, section)}\n")
      digest
    end

    def self.verify(root: ROOT, expected: ENV.fetch("RELEASE_SHA256", nil))
      gem = path(root: root)
      manifest = File.join(root, "pkg/SHA256SUMS")
      missing = [gem, manifest].reject { |file| File.file?(file) }.map { |file| file.delete_prefix("#{root}/") }
      raise Error, "release artifact is incomplete: #{missing.join(' and ')} not found" unless missing.empty?

      digest = Digest::SHA256.file(gem).hexdigest
      unless File.read(manifest) == "#{digest}  #{File.basename(gem)}\n" && (expected.nil? || expected == digest)
        raise Error, "release artifact checksum mismatch"
      end

      verify_package(gem, Release.version(root: root))
      gem
    end

    def self.verify_package(gem, version)
      package = Gem::Package.new(gem)
      package.verify
      return if package.spec.name == "rich-ri" && package.spec.version.to_s == version

      raise Error, "release artifact name/version does not match the checkout"
    rescue Gem::Package::Error => e
      raise Error, "release artifact is not a valid gem: #{e.message}"
    end
  end
end
