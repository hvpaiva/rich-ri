# frozen_string_literal: true

require "test_helper"
require "json"
require "shell_support"

class TestEnvironmentTest < Minitest::Test
  SHELL_TESTS = File.read(File.join(TestSupport::ROOT, "test/shell_test.rb")).scan(/^ +def (test_\w+)/).flatten.freeze
  SUMMARY = /(\d+) runs, \d+ assertions, (\d+) failures, (\d+) errors, (\d+) skips/
  REQUIRED = /^.+ is required$/

  def test_application_settings_are_cleared_without_erasing_suite_controls
    values = { "RICH_RI_REQUIRE_SHELLS" => "1", "RICH_RI_CONFIG" => "/missing/config.yml", "RICH_RI_DEBUG" => "1",
               "RICH_RI_THEME" => "invalid", "RICH_RI_STYLE_COMMENT" => "invalid" }
    source = "puts JSON.generate(ENV.to_h.slice(*ARGV.shift.split(',')))"
    environment = TestSupport::ENVIRONMENT.merge(values).merge("COVERAGE_CHILD" => "1")
    out, err, status = Open3.capture3(environment, RbConfig.ruby,
                                      "-Ilib", "-Itest", "-rtest_helper", "-rjson", "-e", source,
                                      values.keys.join(","), "--", "--name", "/no_tests/", chdir: TestSupport::ROOT)

    assert_predicate status, :success?, err
    assert_equal({ "RICH_RI_REQUIRE_SHELLS" => "1" }, JSON.parse(out.lines.first))
  end

  def test_missing_shells_fail_in_required_mode_and_skip_in_optional_mode
    required, status = without_shells("1")

    assert_equal 1, status.exitstatus, required
    assert_includes required, "fish is required"
    assert_includes required, "zsh is required"
    assert_includes required, "bash-completion 2.x with a compatible bash is required"
    runs, failures, errors, skips = counts(required)
    # ble.sh is optional: its tests are skipped where it is missing, in either mode.
    ble = required.scan(/^ble\.sh is not installed$/).length

    assert_equal [SHELL_TESTS.length, required.scan(REQUIRED).length, 0, ble], [runs, failures, errors, skips]
    optional, status = without_shells(nil)

    assert_equal 0, status.exitstatus, optional
    assert_equal [SHELL_TESTS.length, 0, 0, failures + skips], counts(optional)
  end

  def test_missing_bash_completion_fails_only_in_required_mode
    required, status = without_bash_completion("1")

    assert_equal 1, status.exitstatus, required
    assert_includes required, "bash-completion 2.x with a compatible bash is required"
    runs, failures, errors, skips = counts(required)

    assert_equal [SHELL_TESTS.grep(/test_bash_/).length, required.scan(REQUIRED).length, 0, 0],
                 [runs, failures, errors, skips]
    optional, status = without_bash_completion(nil)

    assert_equal 0, status.exitstatus, optional
    assert_equal [runs, 0, 0, failures], counts(optional)
  end

  def test_completion_probe_checks_loading_version_functions_and_ignores_user_startup
    Dir.mktmpdir do |dir|
      valid = File.join(dir, "valid")
      File.write(valid, <<~BASH)
        [[ -z ${BASH_COMPLETION_COMPAT_DIR-} ]] || return 1
        BASH_COMPLETION_VERSINFO=(2 0)
        _init_completion() { :; }
      BASH
      skip "Bash 4+ is needed to test the completion probe" unless ShellSupport.bash_completion(paths: [valid])

      rejected = ["return 0\n", "BASH_COMPLETION_VERSINFO=(1 0)\n_init_completion() { :; }\n", "return 1\n"]
      paths = rejected.each_with_index.map do |content, index|
        path = File.join(dir, "invalid#{index}")
        File.write(path, content)
        path
      end
      startup = File.join(dir, "startup")
      marker = File.join(dir, "marker")
      File.write(startup, ": > #{marker.shellescape}\n")
      with_environment("BASH_ENV" => startup, "ENV" => startup, "BASH_COMPLETION_USER_FILE" => startup,
                       "BASH_COMPLETION_COMPAT_DIR" => dir) do
        assert_nil ShellSupport.bash_completion(paths: paths)
        assert_equal valid, ShellSupport.bash_completion(paths: paths + [valid])
        refute_path_exists marker
      end
      with_environment("PATH" => dir) { refute_predicate ShellSupport, :available? }
    end
  end

  private

  def without_shells(required)
    Dir.mktmpdir do |empty_path|
      environment = TestSupport::ENVIRONMENT.merge("PATH" => empty_path, "RICH_RI_REQUIRE_SHELLS" => required,
                                                   "XDG_DATA_HOME" => empty_path, "COVERAGE_CHILD" => "1")
      out, err, status = Open3.capture3(environment, RbConfig.ruby, "-Ilib", "-Itest", "test/shell_test.rb",
                                        "--verbose", chdir: TestSupport::ROOT)
      ["#{out}\n#{err}", status]
    end
  end

  def without_bash_completion(required)
    source = <<~RUBY
      require "shell_support"
      def ShellSupport.bash_completion = nil
      require_relative "test/shell_test"
    RUBY
    environment = TestSupport::ENVIRONMENT.merge("RICH_RI_REQUIRE_SHELLS" => required, "COVERAGE_CHILD" => "1")
    out, err, status = Open3.capture3(environment, RbConfig.ruby, "-Ilib", "-Itest", "-e", source,
                                      "--", "--name", "/test_bash_/", chdir: TestSupport::ROOT)
    ["#{out}\n#{err}", status]
  end

  # Runs, failures, errors and skips, as Minitest counts them.
  def counts(output)
    output.match(SUMMARY).captures.map(&:to_i)
  end
end
