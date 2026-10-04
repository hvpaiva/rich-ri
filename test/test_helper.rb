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
  ENVIRONMENT = { "RI" => nil, "RI_PAGER" => nil, "PAGER" => "cat", "NO_COLOR" => "1", "TERM" => "xterm" }.freeze

  Minitest.after_run { FileUtils.remove_entry(TEMP) }
  Dir.chdir(File.join(__dir__, "fixtures")) do
    RDoc::RDoc.new.document(["--ri", "--quiet", "--op", STORE, "example.rb", "GUIDE.rdoc"])
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
