# frozen_string_literal: true

require "fileutils"

# Never install these bundles into the active Ruby: the older rdoc gem replaces the RubyGems
# plugin that documents installed gems, and "gem rdoc" breaks until it is removed.
module Compatibility
  ROOT = File.expand_path("..", __dir__)
  HOME = File.join(ROOT, "tmp/compatibility")
  RUNTIME = %w[bat cli completion configuration configuration_cli configuration_docs corpus dependencies
               document_structure documentation driver highlighter legacy_store manual optional_dependency options
               rendering ruby_highlighting shell terminal theme].freeze

  class Error < StandardError; end

  def self.load_tests = RUNTIME.each { |name| require File.join(ROOT, "test/#{name}_test") }

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
    # Under bundle exec rake, the caller's bundle must not leak into these.
    inherited = defined?(Bundler) ? Bundler.unbundled_env : ENV.to_h
    return if system(inherited.merge(environment), *command, chdir: ROOT, unsetenv_others: true)

    bundle = File.basename(environment.fetch("BUNDLE_GEMFILE"), ".gemfile")
    raise Error, "#{bundle} bundle: #{command.join(' ')} failed"
  end

  private_class_method :environment, :execute
end
