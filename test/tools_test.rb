# frozen_string_literal: true

require "test_helper"
require "yaml"
require_relative "../rakelib/tools"

class ToolsTest < Minitest::Test
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
    required = sources.flat_map { |path| File.read(path).scan(/require_tool\("([^"]+)"\)/) }.flatten.uniq

    assert_empty required - Tools.required
    assert_empty Tools.required - required
  end

  # mise installs the latest release of a tool that mise.toml does not pin, so CI
  # would drift from the local check without failing.
  def test_ci_installs_through_mise_only_the_versions_mise_toml_pins
    jobs = YAML.load_file(File.join(TestSupport::ROOT, ".github/workflows/ci.yml")).fetch("jobs")
    installs = jobs.transform_values do |job|
      mise = job.fetch("steps").select { |step| step["uses"].to_s.start_with?("jdx/mise-action@") }
      mise.flat_map { |step| step.dig("with", "install_args").split }
    end

    assert_equal (Tools.pinned.keys - ["ruby"]).sort, installs.fetch("quality").sort
    assert_empty installs.values.flatten - Tools.pinned.keys
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
    environment = { "PATH" => File.dirname(RbConfig.ruby) }
    { "lint:spelling" => "typos is not installed; install the version mise.toml pins with: mise install typos\n",
      "lint:man" => "groff is not installed; install it with your package manager\n" }.each do |task, advice|
      _out, err, status = Open3.capture3(environment, "bundle", "exec", "rake", task, chdir: TestSupport::ROOT)

      assert_equal 1, status.exitstatus
      assert_equal advice, err
    end
  end
end
