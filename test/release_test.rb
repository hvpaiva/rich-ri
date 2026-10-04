# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release"

class ReleaseTest < Minitest::Test
  def repository
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "lib/rich_ri"))
      File.write(File.join(dir, "lib/rich_ri/version.rb"), "VERSION = \"0.1.0\"\n")
      File.write(File.join(dir, "CHANGELOG.md"), <<~TEXT)
        # Changelog
        ## [Unreleased]

        ### Added
        - Readable documentation.

        [Unreleased]: https://github.com/hvpaiva/rich-ri/commits/main
      TEXT
      [%w[init -q], %w[add .], ["-c", "user.name=Test", "-c", "user.email=test@example.org",
                                "-c", "commit.gpgsign=false", "commit", "-qm", "chore: initialize"]].each do |args|
        _out, err, status = Open3.capture3("git", *args, chdir: dir)

        assert_predicate status, :success?, err
      end
      yield dir
    end
  end

  def test_preparation_updates_version_and_preserves_unreleased_for_next_changes
    repository do |root|
      assert_equal "0.2.0", Release.prepare("0.2.0", root: root)
      assert_equal "0.2.0", Release.version(root: root)
      changelog = File.read(File.join(root, "CHANGELOG.md"))

      assert_includes changelog, "## [Unreleased]\n\n## [0.2.0] - #{Date.today.iso8601}"
      assert_includes changelog, "- Readable documentation."
      assert_includes changelog, "compare/v0.2.0...HEAD"
    end
  end

  def test_preparation_refuses_dirty_tree_and_invalid_versions_without_writing
    repository do |root|
      original = File.read(File.join(root, "CHANGELOG.md"))
      assert_raises(RuntimeError) { Release.prepare("0.0.1", root: root) }
      assert_raises(RuntimeError) { Release.prepare("01.2.3", root: root) }
      assert_raises(RuntimeError) { Release.prepare("invalid", root: root) }
      File.write(File.join(root, "unfinished"), "work")
      assert_raises(RuntimeError) { Release.prepare("0.2.0", root: root) }
      assert_equal original, File.read(File.join(root, "CHANGELOG.md"))
    end
  end
end
