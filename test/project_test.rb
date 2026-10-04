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
      file.match?(%r{\A(?:lib/|exe/|completions/|man/|README.md|CHANGELOG.md|LICENSE.txt|SECURITY.md)})
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

  def test_readme_lookup_commands_are_valid_with_fixture_subjects
    readme = File.read(File.join(TestSupport::ROOT, "README.md"))
    commands = readme.scan(/```(?:sh|bash|zsh|fish)\n(.*?)```/m).join.lines.grep(/^rich-ri /)
    commands.each do |line|
      args = Shellwords.split(line).drop(1).take_while { |arg| !%w[| >].include?(arg) }
      args.map! do |arg|
        if arg == "doc/ri"
          TestSupport::STORE
        elsif arg.match?(/\A(?:Array|Hash|String|MyClass|ruby:)/)
          "RichRIExample#map"
        else
          arg
        end
      end
      _out, err, status = cli(*args)

      assert_predicate status, :success?, "#{line.strip}: #{err}"
    end
  end
end
