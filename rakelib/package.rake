# frozen_string_literal: true

require "open3"
require "tmpdir"
require "rubygems/package"

gem_command = [RbConfig.ruby, "-rrubygems/gem_runner", "-e", "Gem::GemRunner.new.run(ARGV)", "--"]

desc "Build the distributable gem in pkg/"
task :build do
  require_relative "../lib/rich_ri/version"
  FileUtils.mkdir_p("pkg")
  sh(*gem_command, "build", "rich-ri.gemspec", "--output", "pkg/rich-ri-#{RichRI::VERSION}.gem")
end

namespace :package do
  desc "Install the gem into an empty gem home and exercise the installed CLI"
  task :check do
    require_relative "../lib/rich_ri/version"
    Dir.mktmpdir("rich-ri-package-") do |dir|
      package = File.join(dir, "rich-ri.gem")
      home = File.join(dir, "gems")
      # Copy cached dependencies only as installation sources. The child process
      # cannot load the development bundle or the contributor's installed gems.
      Bundler.load.specs.each do |spec|
        next unless File.file?(spec.cache_file)

        FileUtils.cp(spec.cache_file, dir)
      end
      Bundler.with_unbundled_env do
        sh(*gem_command, "build", "rich-ri.gemspec", "--output", package)
        env = { "GEM_HOME" => home, "GEM_PATH" => home, "RUBYOPT" => nil, "RUBYLIB" => nil,
                "RI" => nil, "RI_PAGER" => nil, "PAGER" => "cat", "NO_COLOR" => "1" }
        Dir.chdir(dir) do
          sh(env, *gem_command, "install", "--local", "--no-document",
             "--bindir", File.join(home, "bin"), package)
        end
        command = File.join(home, "bin", "rich-ri")
        store = File.join(dir, "ri")
        fixtures = File.expand_path("../test/fixtures", __dir__)
        sh(env, RbConfig.ruby, "-rrdoc/rdoc", "-e", "RDoc::RDoc.new.document(ARGV)", "--",
           "--ri", "--quiet", "--op", store, "example.rb", "GUIDE.rdoc", chdir: fixtures)
        sources = ["--no-standard-docs", "--doc-dir", store]
        {
          [*sources, "RichRIExample#map"] => "Return transformed values.",
          ["--complete", *sources, "RichRIExample#ma"] => "RichRIExample#map\t\n"
        }.each do |args, expected|
          out, err, status = Open3.capture3(env, command, *args, chdir: dir)
          unless status.success? && out.include?(expected)
            abort "Installed lookup failed: #{args.inspect}\n#{err}\n#{out}"
          end
        end
        [%w[--version], %w[--help], %w[--no-standard-docs --list], %w[--complete --no-all],
         %w[--completion=bash], %w[--completion=zsh], %w[--completion=fish], %w[--man-path]].each do |args|
          out, err, status = Open3.capture3(env, command, *args, chdir: dir)
          abort "Installed CLI failed: #{args.inspect}\n#{err}" unless status.success?
          abort "Wrong package version" if args == ["--version"] && out != "rich-ri #{RichRI::VERSION}\n"
          next unless args == ["--man-path"]

          abort "Manual missing from installed gem" unless out.strip.start_with?(home) && File.file?(out.strip)
        end
        puts "Installed gem: version, help, lookup, completion and manual passed."
      end
    end
  end
end
