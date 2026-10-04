# frozen_string_literal: true

require_relative "release"

namespace :release do
  desc "Verify the release version, tag and changelog"
  task :verify do
    puts "Verified rich-ri #{Release.verify}"
  end
end

desc "Publish the tagged gem (GitHub Actions release environment only)"
task :release do
  unless ENV["GITHUB_ACTIONS"] == "true" && ENV["GITHUB_REPOSITORY"] == "hvpaiva/rich-ri" &&
         ENV.fetch("GITHUB_REF", "").start_with?("refs/tags/v")
    abort "Publication runs only in the release workflow. Use bin/release X.Y.Z --push."
  end
  Release.verify
  Rake::Task[:build].invoke
  sh "gem", "push", "pkg/rich-ri-#{Release.version}.gem"
end
