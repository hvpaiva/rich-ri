# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/manual"
require_relative "../rakelib/release"

class ProjectTest < Minitest::Test
  def test_package_manifest_contains_only_distribution_files
    spec = Gem::Specification.load(File.join(TestSupport::ROOT, "rich-ri.gemspec"))

    assert_equal ["rich-ri"], spec.executables
    assert_equal RichRI::VERSION, spec.version.to_s
    assert_includes spec.files, "completions/rich-ri.bash"
    assert_includes spec.files, "man/man1/rich-ri.1"
    assert(spec.files.all? do |file|
      file.match?(%r{\A(?:lib/|exe/|completions/|man/|docs/|README.md|CHANGELOG.md|LICENSE.txt|SECURITY.md)})
    end)
    refute(spec.files.any? { |file| file.include?("/home/") || file.start_with?("test/", "tmp/", ".") })
  end

  def test_manual_is_current_and_contains_every_option
    actual = File.read(File.join(TestSupport::ROOT, "man/man1/rich-ri.1"))

    assert_equal Manual.render, actual
    RichRI::Options.new.parser.top.list.each do |switch|
      next unless switch.respond_to?(:long)

      switch.long.each { |flag| assert_includes actual, Manual.escape(flag) }
    end
  end

  def test_release_requires_matching_version_tag_and_dated_changelog
    changelog = <<~TEXT
      ## [Unreleased]
      ## [#{RichRI::VERSION}] - 2026-10-04
      - Add the documentation reader.
      [Unreleased]: https://github.com/hvpaiva/rich-ri/compare/v#{RichRI::VERSION}...HEAD
      [#{RichRI::VERSION}]: https://github.com/hvpaiva/rich-ri/releases/tag/v#{RichRI::VERSION}
    TEXT
    assert_equal RichRI::VERSION, Release.verify(tag: "v#{RichRI::VERSION}", changelog: changelog)
    assert_raises(RuntimeError) { Release.verify(tag: "v9.9.9", changelog: changelog) }
    assert_raises(RuntimeError) { Release.verify(tag: "v#{RichRI::VERSION}", changelog: "## [Unreleased]\n") }
  end

  def test_local_release_is_refused_before_any_publish_action
    _out, err, status = Open3.capture3({ "GITHUB_ACTIONS" => nil }, "bundle", "exec", "rake", "release",
                                       chdir: TestSupport::ROOT)

    refute_predicate status, :success?
    assert_includes err, "Publication runs only in the release workflow"
  end

  def test_readme_project_example_runs_as_written_and_matches_its_output
    readme = File.read(File.join(TestSupport::ROOT, "README.md"))
    story = readme.split("### Read your project's documentation\n", 2).last.split("## Configuration", 2).first
    source = story[/```ruby\n(.*?)```/m, 1]
    commands = story[/```sh\n(.*?)```/m, 1].lines
    expected = story[/```text\n(.*?)```/m, 1]
    Dir.mktmpdir("rich-ri-readme-with-a-path-longer-than-sixty-columns-") do |root|
      File.write(File.join(root, "greeter.rb"), source)
      output = nil
      commands.each do |line|
        program, *args = Shellwords.split(line)
        entrypoint = program == "rdoc" ? Gem.bin_path("rdoc", "rdoc") : File.join(TestSupport::ROOT, "exe/rich-ri")
        output, err, status = Open3.capture3(TestSupport::ENVIRONMENT, RbConfig.ruby,
                                             "-I#{TestSupport::ROOT}/lib", entrypoint, *args, chdir: root)

        assert_predicate status, :success?, "#{line.strip}: #{err}"
      end

      # RDoc reports an absolute path, which wraps at the example's width.
      # Verify its provenance before abbreviating it as the README does.
      source = output.match(/\(from\s+(.*?)\)\n/m)

      refute_nil source
      assert_includes [File.realpath(root), root].map { |path| "#{path}/doc/ri" }, source[1].delete("\n")
      assert_equal expected.rstrip, output.sub(source[0], "(from ./doc/ri)\n").rstrip
    end
  end
end
