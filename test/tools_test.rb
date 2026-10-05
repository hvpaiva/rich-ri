# frozen_string_literal: true

require "test_helper"
require "program_support"
require_relative "../rakelib/tools"

class ToolsTest < Minitest::Test
  include ProgramSupport

  def test_pinned_reads_the_tools_table_and_nothing_else
    path = File.join(TestSupport::TEMP, "mise.toml")
    File.write(path, <<~TOML)
      min_version = "2026.1.0"

      [tools]
      # The version CI runs.
      ruby = "4.0.7"
      typos = "1.50.3" # trailing comment

      [settings]
      experimental = "true"
    TOML

    assert_equal({ "ruby" => "4.0.7", "typos" => "1.50.3" }, Tools.pinned(path))
    assert_equal %w[typos groff man], Tools.required(Tools.pinned(path))
  end

  def test_every_program_a_task_requires_is_pinned_or_a_known_system_program
    sources = [File.join(TestSupport::ROOT, "Rakefile"), *Dir[File.join(TestSupport::ROOT, "rakelib/*.rake")]]
    required = sources.flat_map { |path| File.read(path).scan(/Tools\.require!\("([^"]+)"\)/) }.flatten.uniq

    assert_empty required - Tools.required
    assert_empty Tools.required - required
  end

  def test_advice_distinguishes_pinned_inactive_and_system_programs
    pinned = { "typos" => "1.50.3" }

    assert_equal "typos is not installed; install the version mise.toml pins with: mise install typos",
                 Tools.missing("typos", pinned, installed_by_mise: false)
    assert_equal "typos is installed by mise but not on PATH; activate mise in your shell (mise activate --help)",
                 Tools.missing("typos", pinned, installed_by_mise: true)
    assert_equal "groff is not installed; install it with your package manager", Tools.missing("groff", pinned)
  end

  def test_a_lint_task_without_its_program_explains_how_to_install_it
    Dir.mktmpdir("rich-ri-tools-") do |bin|
      link_ruby(bin)
      link_program(bin, "rake", Gem.bin_path("rake", "rake"))
      { "lint:spelling" => "typos is not installed; install the version mise.toml pins with: mise install typos\n",
        "lint:man" => "groff is not installed; install it with your package manager\n" }.each do |task, advice|
        _out, err, status = Open3.capture3({ "PATH" => bin }, File.join(bin, "bundle"), "exec", "rake", task,
                                           chdir: TestSupport::ROOT)

        assert_equal 1, status.exitstatus
        assert_equal advice, err
      end
    end
  end
end
