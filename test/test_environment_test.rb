# frozen_string_literal: true

require "test_helper"
require "json"

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
                                          "--verbose", "--name", "/test_(fish|zsh)_/", chdir: TestSupport::ROOT)
        message = "#{out}\n#{err}"

        assert_equal required ? 1 : 0, status.exitstatus, message
        if required
          assert_includes out, "fish is required"
          assert_includes out, "zsh is required"
          assert_match(/5 failures, 0 errors, 0 skips/, out)
        else
          assert_match(/0 failures, 0 errors, 5 skips/, out)
        end
      end
    end
  end
end
