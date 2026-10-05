# frozen_string_literal: true

require_relative "github_configuration"

namespace :github do
  desc "Apply repository protections, security, release and presentation settings (requires admin access)"
  task :setup do
    GitHub.verify_origin!
    GitHub::Configuration.new.setup
  rescue GitHub::Error => e
    abort e.message
  end

  desc "Verify GitHub repository configuration without changing it"
  task :verify do
    GitHub.verify_origin!
    GitHub::Configuration.new.verify!
  rescue GitHub::Error => e
    abort e.message
  end
end
