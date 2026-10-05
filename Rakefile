# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"
require "fileutils"
require_relative "rakelib/tools"

# The branch checks compare with origin/main. A shallow CI checkout may not have it.
def default_base
  "origin/main" if system("git", "rev-parse", "--verify", "--quiet", "origin/main", out: File::NULL)
end

# A missing program gets one line of advice instead of a failed command and its trace.
def require_tool(name)
  abort Tools.missing(name) unless Tools.available?(name)
end

Rake::TestTask.new(:test) do |task|
  task.libs << "test" << "lib"
  task.pattern = "test/**/*_test.rb"
  task.warning = true
end

Rake::TestTask.new("test:docs") do |task|
  task.libs << "test" << "lib"
  task.pattern = "test/{configuration_docs,documentation}_test.rb"
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

  desc "Run all shell integrations locally, or in Docker/Podman when shells are missing"
  task :shells do
    require_relative "rakelib/shell_tests"
    ShellTests.run
  end

  namespace :shells do
    desc "Run all shell integrations in an isolated Docker/Podman container"
    task :container do
      require_relative "rakelib/shell_tests"
      ShellTests.run(container: true)
    end
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
  desc "Check branch commits and optional PR_TITLE/PR_BODY (range defaults to origin/main..HEAD)"
  task :commits, [:range] do |_task, args|
    sh RbConfig.ruby, "bin/lint-commits", args[:range] || (default_base ? "#{default_base}..HEAD" : "HEAD")
  end

  desc "Check CHANGELOG.md structure and that the branch records user-visible changes (base: origin/main)"
  task :changelog, [:base] do |_task, args|
    sh RbConfig.ruby, "bin/lint-changelog", *(args[:base] || default_base)
  end

  desc "Check Bash scripts with ShellCheck"
  task :shell do
    require_tool("shellcheck")
    sh "shellcheck", "completions/rich-ri.bash", "bin/setup"
  end

  desc "Check spelling in source and documentation"
  task :spelling do
    require_tool("typos")
    sh "typos"
  end

  desc "Check GitHub Actions security (offline)"
  task :workflows do
    require_tool("zizmor")
    sh "zizmor", "--offline", "--no-progress", ".github/workflows"
  end

  desc "Check local documentation links"
  task :links do
    require_tool("lychee")
    sh "lychee", "--offline", "--include-fragments", "--no-progress", *Dir["*.md", "docs/**/*.md", ".github/*.md"]
  end

  desc "Check the manual with groff"
  task :man do
    require_tool("groff")
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

namespace :docs do
  desc "Check documentation links, spelling, generated manual and runnable examples"
  task check: %w[lint:links lint:spelling lint:changelog generate:check test:docs]
end

desc "Run local CI checks (native shells or Docker/Podman, and security database required)"
task check: %w[rubocop lint:commits lint:changelog lint:shell lint:spelling lint:workflows lint:links lint:man
               generate:check test:cov test:shells package:check audit]

task default: %w[rubocop test]
