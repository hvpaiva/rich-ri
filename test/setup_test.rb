# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/tools"

class SetupTest < Minitest::Test
  def setup
    @bin = Dir.mktmpdir("rich-ri-setup-")
    @log = File.join(@bin, "mise.log")
    program("bundle")
    File.symlink(which("dirname"), File.join(@bin, "dirname"))
  end

  def teardown
    FileUtils.remove_entry(@bin)
  end

  def test_a_failed_mise_install_does_not_hide_the_report_of_missing_programs
    program("mise", "echo 'mise ERROR network unreachable' >&2\nexit 1")
    out, err, status = run_setup

    assert_equal 1, status.exitstatus
    assert_includes err, "network unreachable"
    assert_includes out, "mise install failed"
    assert_equal Tools.required, out.scan(/^Missing: (\S+) is not installed/).flatten
    assert_includes err, "Shell integration checks need"
    assert_includes out, "bundle exec rake check"
  end

  def test_pinned_tools_are_installed_by_name_and_a_complete_environment_succeeds
    program("mise", %(echo "$*" >> "#{@log}"))
    (Tools.required + ["docker"]).each { |tool| program(tool) }
    out, err, status = run_setup

    assert_predicate status, :success?, err
    assert_equal "install #{(Tools.pinned.keys - ['ruby']).join(' ')}\n", File.read(@log)
    refute_includes out, "Missing"
    assert_includes out, "Shell integration checks will use docker."
  end

  def test_programs_are_reported_without_mise_and_a_failed_bundle_stops_early
    out, _err, status = run_setup

    assert_equal 1, status.exitstatus
    assert_includes out, "Missing: typos is not installed; install the version mise.toml pins with: mise install typos"
    assert_includes out, "Missing: groff is not installed; install it with your package manager"
    refute_includes out, "mise install failed"
    program("bundle", "exit 7")
    out, _err, status = run_setup

    assert_equal 1, status.exitstatus
    refute_includes out, "Missing"
  end

  private

  def which(name)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, name) }
       .find { |path| File.executable?(path) }
  end

  def program(name, body = "exit 0")
    path = File.join(@bin, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    FileUtils.chmod(0o755, path)
  end

  def run_setup
    path = [@bin, File.dirname(RbConfig.ruby)].join(File::PATH_SEPARATOR)
    Open3.capture3({ "PATH" => path, "RICH_RI_CONTAINER_RUNTIME" => nil }, which("bash"), "bin/setup",
                   chdir: TestSupport::ROOT)
  end
end
