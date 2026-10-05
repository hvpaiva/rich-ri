# frozen_string_literal: true

require_relative "coverage_helper" if ENV["COVERAGE"]

require "minitest/autorun"
require "rich_ri"
require "tmpdir"
require "fileutils"
require "rdoc/rdoc"

module TestSupport
  ROOT = File.expand_path("..", __dir__)
  TEMP = Dir.mktmpdir("rich-ri-test-")
  STORE = File.join(TEMP, "ri")
  # A contributor's theme file must not change fixture output or option
  # defaults, nor a debugging session add backtraces to expected messages.
  application_variables = RichRI::Configuration::ENVIRONMENT.keys + ["RICH_RI_CONFIG", RichRI::Error::DEBUG_VARIABLE] +
                          ENV.keys.grep(/\ARICH_RI_STYLE_/)
  application_variables.each { |key| ENV.delete(key) }
  ENV["XDG_CONFIG_HOME"] = File.join(TEMP, "config")
  ENVIRONMENT = application_variables.to_h { |key| [key, nil] }.merge(
    "RI" => nil, "RI_PAGER" => nil, "PAGER" => "cat", "NO_COLOR" => "1", "TERM" => "xterm",
    "BAT_THEME" => nil, "XDG_CONFIG_HOME" => File.join(TEMP, "config"), "RICH_RI_CONFIG" => nil
  ).freeze

  Minitest.after_run { FileUtils.remove_entry(TEMP) }
  Dir.chdir(File.join(__dir__, "fixtures")) do
    RDoc::RDoc.new.document(["--ri", "--quiet", "--op", STORE, "example.rb", "GUIDE.rdoc"])
  end

  # Gems as an installation leaves them: a specification and the RI data of
  # the gem's files, in a gem home of their own. Every other store in the suite
  # is a directory given with --doc-dir; these are the ones RubyGems finds and
  # names by gem, version and platform. Each is a directory of fixtures with
  # its version and platform, one of them for another system.
  GEMS = { "inkwell" => %w[1.4.0 ruby], "inkwell-2" => %w[0.3.0 ruby],
           "inkwell-native" => %w[2.0.1 arm64-darwin-23] }.freeze

  # The gem home, generated when a test first asks for it.
  def self.gem_home
    @gem_home ||= File.join(TEMP, "gems").tap do |home|
      FileUtils.mkdir_p(File.join(home, "specifications"))
      GEMS.each { |name, (version, platform)| install_gem(home, name, version, platform) }
    end
  end

  # The RI data of one of those gems, which is a store to give to --doc-dir too.
  def self.gem_store(name)
    version, platform = GEMS.fetch(name)
    File.join(gem_home, "doc", [name, version, *(platform unless platform == "ruby")].join("-"), "ri")
  end

  def self.install_gem(home, name, version, platform)
    source = File.join(__dir__, "fixtures/gems", name)
    files = Dir.glob("**/*.{rb,rdoc}", base: source).sort
    specification = Gem::Specification.new do |gem|
      gem.name = name
      gem.version = version
      gem.platform = platform
      gem.summary = "A documented gem"
      gem.authors = ["rich-ri"]
      gem.files = files
    end
    File.write(File.join(home, "specifications", "#{specification.full_name}.gemspec"), specification.to_ruby)
    RDoc::RDoc.new.document(["--ri", "--quiet", "--root", source, "--op",
                             File.join(home, "doc", specification.full_name, "ri"),
                             *files.map { |file| File.join(source, file) }])
  end
  private_class_method :install_gem

  # The environment of a command that finds the gems of gem_home in place of
  # the installed ones. Bundler would show it the bundle alone, so it runs
  # without, and the libraries rich-ri requires come from this process's load path.
  def self.gem_environment
    libraries = $LOAD_PATH.map(&:to_s).select { |path| File.absolute_path?(path) }
    ENV.keys.grep(/\ABUNDLER?_/).to_h { |key| [key, nil] }.merge(
      "GEM_HOME" => gem_home, "GEM_PATH" => gem_home, "RUBYOPT" => nil,
      "RUBYLIB" => libraries.join(File::PATH_SEPARATOR)
    )
  end

  def cli(*, env: {}, docs: true, stdin: "")
    sources = docs ? ["--no-standard-docs", "--doc-dir", STORE] : []
    coverage = ENV["COVERAGE"] ? ["-r#{ROOT}/test/coverage_helper"] : []
    Open3.capture3(ENVIRONMENT.merge("COVERAGE_CHILD" => "1").merge(env), RbConfig.ruby, *coverage,
                   "-I#{ROOT}/lib", "#{ROOT}/exe/rich-ri", *sources, *,
                   stdin_data: stdin)
  end

  def driver
    options = RichRI::Options.new.parse(["--no-standard-docs", "--doc-dir", STORE], defaults: "")
    RichRI::Driver.new(options.driver_options)
  end

  # A copy of the fixture store whose cache also lists the given names. Yields
  # the options that select it alone.
  def with_cached_names(modules: [], methods: [], pages: [])
    Dir.mktmpdir("rich-ri-names-") do |dir|
      path = File.join(dir, "ri")
      FileUtils.cp_r(STORE, path)
      store = RDoc::RI::Store.new(RDoc::Options.new, path: path, type: :extra)
      store.load_cache
      store.cache[:modules].concat(modules)
      store.cache[:instance_methods]["RichRIExample"].concat(methods)
      store.cache[:pages].concat(pages)
      store.save_cache
      yield ["--no-standard-docs", "--doc-dir", path]
    end
  end

  # A temporary configuration file holding the given YAML text or data.
  def with_config(data)
    Dir.mktmpdir("rich-ri-config-") do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, data.is_a?(String) ? data : Psych.dump(data))
      yield path
    end
  end

  def with_environment(values)
    previous = values.to_h { |key, _value| [key, ENV.fetch(key, nil)] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end

module Minitest
  class Test
    include TestSupport
  end
end
