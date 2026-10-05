# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  root File.expand_path("..", __dir__)
  command_name "rich-ri-#{Process.pid}"
  enable_coverage :branch
  cover "lib/**/*.rb"
  minimum_coverage line: 90, branch: 80 unless ENV["COVERAGE_CHILD"]
  formatter SimpleCov::Formatter::HTMLFormatter unless ENV["COVERAGE_CHILD"]
end

SimpleCov.at_exit { SimpleCov.result } if ENV["COVERAGE_CHILD"]
# A command that fails exits nonzero on purpose, and SimpleCov would add a line to its stderr.
SimpleCov.print_error_status = false if ENV["COVERAGE_CHILD"]
