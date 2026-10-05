# frozen_string_literal: true

require "test_helper"
require "json"
require "shell_support"

class TestEnvironmentTest < Minitest::Test
  def test_application_settings_are_cleared_without_erasing_suite_controls
    values = { "RICH_RI_REQUIRE_SHELLS" => "1", "RICH_RI_CONFIG" => "/missing/config.yml",
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
    Dir.mktmpdir do |empty_path|
      ["1", nil].each do |required|
        environment = TestSupport::ENVIRONMENT.merge("PATH" => empty_path, "RICH_RI_REQUIRE_SHELLS" => required,
                                                     "COVERAGE_CHILD" => "1")
        out, err, status = Open3.capture3(environment, RbConfig.ruby, "-Ilib", "-Itest", "test/shell_test.rb",
                                          "--verbose", chdir: TestSupport::ROOT)
        message = "#{out}\n#{err}"

        assert_equal required ? 1 : 0, status.exitstatus, message
        if required
          assert_includes out, "fish is required"
          assert_includes out, "zsh is required"
          assert_includes out, "bash-completion 2.x with a compatible bash is required"
          assert_match(/9 failures, 0 errors, 0 skips/, out)
        else
          assert_match(/0 failures, 0 errors, 9 skips/, out)
        end
      end
    end
  end

  def test_missing_bash_completion_fails_only_in_required_mode
    source = <<~RUBY
      require "shell_support"
      def ShellSupport.bash_completion = nil
      require_relative "test/shell_test"
    RUBY
    ["1", nil].each do |required|
      environment = TestSupport::ENVIRONMENT.merge("RICH_RI_REQUIRE_SHELLS" => required, "COVERAGE_CHILD" => "1")
      out, err, status = Open3.capture3(environment, RbConfig.ruby, "-Ilib", "-Itest", "-e", source,
                                        "--", "--name", "/test_bash_/", chdir: TestSupport::ROOT)
      message = "#{out}\n#{err}"

      assert_equal required ? 1 : 0, status.exitstatus, message
      assert_match(required ? /4 failures, 0 errors, 0 skips/ : /0 failures, 0 errors, 4 skips/, out)
    end
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
end
