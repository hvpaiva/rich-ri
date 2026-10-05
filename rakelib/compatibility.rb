# frozen_string_literal: true

require "fileutils"

# Runs the runtime tests with the lowest supported dependencies against an RI store written by
# RDoc 6.14. Both bundles are installed under tmp/compatibility, never into the active Ruby:
# there, the older rdoc gem replaces the RubyGems plugin that documents every gem installed
# afterwards, and "gem rdoc" stops working until that gem is removed again.
module Compatibility
  ROOT = File.expand_path("..", __dir__)
  HOME = File.join(ROOT, "tmp/compatibility")
  # Release, CI and repository tooling is tested with the development bundle only.
  MAINTENANCE = %w[benchmark changelog commit_policy compatibility github project setup shell_runner
                   test_environment tools].freeze

  class Error < StandardError; end

  def self.maintenance?(name) = MAINTENANCE.include?(name) || name.match?(/\A(?:ci|release)(?:_|\z)/)

  def self.runtime_tests
    Dir[File.join(ROOT, "test/*_test.rb")].reject { |path| maintenance?(File.basename(path, "_test.rb")) }
  end

  def self.load_tests = runtime_tests.each { |path| require path }

  def self.environment(bundle, home: HOME)
    { "BUNDLE_GEMFILE" => File.join(ROOT, "gemfiles/#{bundle}.gemfile"), "BUNDLE_PATH" => File.join(home, bundle) }
  end

  def self.run(home: HOME, runner: method(:execute))
    store = File.join(home, "legacy-ri")
    FileUtils.rm_rf(store)
    legacy = environment("legacy", home: home)
    runner.call(legacy, "bundle", "install")
    runner.call(legacy, "bundle", "exec", "ruby", "-rrdoc/rdoc", "-e", "RDoc::RDoc.new.document(ARGV)", "--",
                "--ri", "--quiet", "--op", store, "test/fixtures/example.rb")
    minimum = environment("minimum", home: home).merge("LEGACY_RI_STORE" => store)
    runner.call(minimum, "bundle", "install")
    runner.call(minimum, "bundle", "exec", "ruby", "-Ilib", "-Itest", "-r./rakelib/compatibility",
                "-e", "Compatibility.load_tests")
  end

  def self.execute(environment, *command)
    # Started from bundle exec rake, the caller's bundle must not leak into these two.
    inherited = defined?(Bundler) ? Bundler.unbundled_env : ENV.to_h
    return if system(inherited.merge(environment), *command, chdir: ROOT, unsetenv_others: true)

    bundle = File.basename(environment.fetch("BUNDLE_GEMFILE"), ".gemfile")
    raise Error, "#{bundle} bundle: #{command.join(' ')} failed"
  end
end
