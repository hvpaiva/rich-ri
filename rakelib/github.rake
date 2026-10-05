# frozen_string_literal: true

require_relative "github_configuration"

namespace :github do
  desc "Configure repository protections, security and release policies (requires admin access)"
  task :setup do
    GitHub.verify_origin!
    GitHub::Configuration.new.setup
  rescue GitHub::Error => e
    abort "rake: #{e.message}"
  end

  desc "Verify GitHub repository configuration without changing it"
  task :verify do
    GitHub.verify_origin!
    GitHub::Configuration.new.verify!
  rescue GitHub::Error => e
    abort "rake: #{e.message}"
  end
end
