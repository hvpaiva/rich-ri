# frozen_string_literal: true

require "test_helper"

class DependenciesTest < Minitest::Test
  def test_lookup_highlighting_and_discovery_do_not_require_external_programs
    Dir.mktmpdir("rich-ri-empty-path-") do |path|
      environment = { "PATH" => path, "RI_PAGER" => nil, "PAGER" => nil }
      plain, err, status = cli("--no-pager", "RichRIExample#map", env: environment)

      assert_predicate status, :success?, err
      assert_includes plain, "Return transformed values."
      colored, err, status = cli("--no-pager", "--color=always", "RichRIExample#map", env: environment)

      assert_predicate status, :success?, err
      assert_equal plain, RichRI.plain(colored)
      assert_includes colored, "\e["
      out, err, status = cli("--complete", "--no-standard-docs", "--doc-dir", TestSupport::STORE,
                             "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_includes out, "RichRIExample#map\t"
    end
  end

  def test_completion_scripts_are_available_without_their_shells_installed
    Dir.mktmpdir("rich-ri-empty-path-") do |path|
      %w[bash zsh fish].each do |shell|
        out, err, status = cli("--completion=#{shell}", docs: false, env: { "PATH" => path })

        assert_predicate status, :success?, err
        assert_includes out, "rich-ri --complete"
      end
    end
  end

  def test_manual_installation_does_not_require_the_manual_viewer
    Dir.mktmpdir("rich-ri-empty-path-") do |path|
      target = File.join(path, "manual/man1")
      _out, err, status = cli("--install-man=#{target}", docs: false, env: { "PATH" => path })

      assert_predicate status, :success?, err
      assert File.file?(File.join(target, "rich-ri.1"))
    end
  end
end
