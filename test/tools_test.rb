# frozen_string_literal: true

require "test_helper"
require "program_support"
require_relative "../rakelib/tools"

class ToolsTest < Minitest::Test
  include ProgramSupport

  def test_only_the_tools_table_of_mise_toml_is_read_and_ruby_is_left_out
    Dir.mktmpdir("rich-ri-tools-") do |root|
      FileUtils.mkdir_p(File.join(root, "rakelib"))
      FileUtils.cp(File.join(TestSupport::ROOT, "rakelib/tools.rb"), File.join(root, "rakelib"))
      File.write(File.join(root, "mise.toml"), <<~TOML)
        min_version = "2026.1.0"

        [tools]
        # The version CI runs.
        ruby = "4.0.7"
        typos = "1.50.3" # trailing comment

        [settings]
        experimental = "true"
      TOML
      out, err, status = Open3.capture3(RbConfig.ruby, "-r./rakelib/tools", "-e", "puts Tools.mise_tools", chdir: root)

      assert_predicate status, :success?, err
      assert_equal "typos\n", out
    end
  end

  def test_every_program_a_task_requires_is_pinned_or_a_known_system_program
    sources = [File.join(TestSupport::ROOT, "Rakefile"), *Dir[File.join(TestSupport::ROOT, "rakelib/*.rake")]]
    required = sources.flat_map { |path| File.read(path).scan(/Tools\.require!\("([^"]+)"\)/) }.flatten.uniq

    assert_equal (Tools.mise_tools + Tools::SYSTEM).sort, required.sort
  end

  def test_a_tool_mise_installed_but_left_off_path_asks_to_activate_mise
    Dir.mktmpdir("rich-ri-tools-") do |bin|
      write_program(bin, "mise", '[ "$1" = which ]')
      _out, err, status = isolated_rake(bin, "lint:spelling")

      assert_equal [1, "rake: typos is installed by mise but not on PATH; activate mise in your shell " \
                       "(mise activate --help)\n"], [status.exitstatus, err]
    end
  end

  def test_a_lint_task_without_its_program_explains_how_to_install_it
    { "lint:spelling" => "rake: typos is not installed; install the version mise.toml pins with: " \
                         "mise install typos\n",
      "lint:man" => "rake: groff is not installed; install it with your package manager\n" }.each do |task, advice|
      Dir.mktmpdir("rich-ri-tools-") do |bin|
        _out, err, status = isolated_rake(bin, task)

        assert_equal [1, advice], [status.exitstatus, err]
      end
    end
  end

  def test_groff_warnings_about_the_manual_are_reported_with_the_file
    Dir.mktmpdir("rich-ri-tools-") do |bin|
      write_program(bin, "groff", "echo 'troff: <standard input>:7: warning: macro not defined' >&2")
      out, err, status = isolated_rake(bin, "lint:man")

      assert_equal [1, "", "rake: groff reported problems in man/man1/rich-ri.1:\n" \
                           "troff: <standard input>:7: warning: macro not defined\n"], [status.exitstatus, out, err]
    end
  end

  def test_a_silent_groff_failure_reports_its_exit_status
    Dir.mktmpdir("rich-ri-tools-") do |bin|
      write_program(bin, "groff", "exit 3")
      out, err, status = isolated_rake(bin, "lint:man")

      assert_equal [1, "", "rake: groff failed on man/man1/rich-ri.1 with exit status 3\n"],
                   [status.exitstatus, out, err]
    end
  end

  def test_package_check_needs_groff_to_render_the_installed_manual
    Dir.mktmpdir("rich-ri-tools-") do |bin|
      write_program(bin, "man")
      _out, err, status = isolated_rake(bin, "package:check")

      assert_equal [1, "rake: groff is not installed; install it with your package manager\n"], [status.exitstatus, err]
    end
  end
end
