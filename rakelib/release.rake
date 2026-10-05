# frozen_string_literal: true

require_relative "release"
require_relative "release_artifact"

namespace :release do
  desc "Verify the release version, tag and changelog"
  task :verify do
    puts "Verified rich-ri #{Release.verify}"
  rescue Release::Error => e
    abort "rake: #{e.message}"
  end

  desc "Check that the release commit belongs to an allowed branch"
  task :verify_ref do
    Release.verify_ref
  rescue Release::Error => e
    abort "rake: #{e.message}"
  end

  desc "Build the release artifact and record its checksum and notes"
  task artifact: :build do
    puts Release::Artifact.record
  end

  desc "Verify the existing release artifact without rebuilding it"
  task :verify_artifact do
    puts Release::Artifact.verify
  rescue Release::Error => e
    abort "rake: #{e.message}"
  end
end

desc "Publish the tagged gem (GitHub Actions release environment only)"
task :release do
  unless ENV["GITHUB_ACTIONS"] == "true" && ENV["GITHUB_REPOSITORY"] == "hvpaiva/rich-ri" &&
         ENV.fetch("GITHUB_REF", "").start_with?("refs/tags/v")
    abort "rake: publication runs only in the release workflow; use bin/release X.Y.Z --push"
  end
  Release.verify
  artifact = Release::Artifact.verify
  sh "gem", "push", "--host", "https://rubygems.org", artifact
rescue Release::Error => e
  abort "rake: #{e.message}"
end
