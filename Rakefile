# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"
require "fileutils"

Rake::TestTask.new(:test) do |task|
  task.libs << "test" << "lib"
  task.pattern = "test/**/*_test.rb"
  task.warning = true
end

RuboCop::RakeTask.new(:rubocop)

desc "Format Ruby source with safe autocorrections"
task :format do
  sh "bundle", "exec", "rubocop", "-a"
end

namespace :test do
  desc "Run all tests with line and branch coverage"
  task :cov do
    FileUtils.rm_f("coverage/.resultset.json")
    sh({ "COVERAGE" => "1" }, "bundle", "exec", "rake", "test")
  end

  desc "Run completion tests in Bash, Zsh and Fish (all required)"
  task :shells do
    sh({ "RICH_RI_REQUIRE_SHELLS" => "1" }, "bundle", "exec", "ruby", "-Ilib", "-Itest", "test/shell_test.rb")
  end
end

desc "Regenerate the manual from the CLI options"
task :generate do
  require_relative "rakelib/manual"
  FileUtils.mkdir_p("man/man1")
  File.write("man/man1/rich-ri.1", Manual.render)
end

namespace :generate do
  desc "Check that generated documentation is current"
  task :check do
    require_relative "rakelib/manual"
    abort "Manual is stale. Run bundle exec rake generate." unless File.read("man/man1/rich-ri.1") == Manual.render
  end
end

namespace :lint do
  desc "Check Bash scripts with ShellCheck"
  task :shell do
    sh "shellcheck", "completions/rich-ri.bash", "bin/setup"
  end

  desc "Check spelling in source and documentation"
  task :spelling do
    sh "typos"
  end

  desc "Check GitHub Actions security (offline)"
  task :workflows do
    sh "zizmor", "--offline", "--no-progress", ".github/workflows"
  end

  desc "Check local documentation links"
  task :links do
    sh "lychee", "--offline", "--include-fragments", "--no-progress", "*.md", "docs/*.md"
  end

  desc "Check the manual with groff"
  task :man do
    require "open3"
    _out, err, status = Open3.capture3("groff", "-ww", "-Tutf8", "-man", "man/man1/rich-ri.1")
    abort err unless status.success? && err.empty?
  end
end

desc "Check dependencies against the latest vulnerability database (network required)"
task :audit do
  sh "bundle", "exec", "bundler-audit", "check", "--update"
end

namespace :audit do
  desc "Check dependencies against the local advisory database without updating it"
  task :local do
    sh "bundle", "exec", "bundler-audit", "check"
  end
end

desc "Run local CI checks (all three shells and security database required)"
task check: %w[rubocop lint:shell lint:spelling lint:workflows lint:links lint:man generate:check test:cov test:shells
               package:check audit]

task default: %w[rubocop test]
