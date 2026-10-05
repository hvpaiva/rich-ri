# frozen_string_literal: true

require "test_helper"
require "program_support"
require "shellwords"
require_relative "../rakelib/release_workflow"
require_relative "release_support"

class ReleaseCommandsTest < Minitest::Test
  include ProgramSupport
  include ReleaseFixtures

  WARNING = "Warning: Permanently added 'github.com' (ED25519) to the list of known hosts."

  def setup
    @out = StringIO.new
    @commands = Release::Commands.new(root: TestSupport::TEMP, out: @out)
  end

  def test_diagnostics_are_shown_but_never_parsed_as_output
    script = "warn #{WARNING.inspect}; puts '[]'"

    assert_equal "[]\n", @commands.call([RbConfig.ruby, "-e", script])
    assert_empty @commands.json([RbConfig.ruby, "-e", script])
    assert_includes @out.string, WARNING
  end

  def test_a_remote_warning_is_not_mistaken_for_an_existing_tag
    Dir.mktmpdir("rich-ri-git-") do |bin|
      write_program(bin, "git", "echo #{WARNING.shellescape} >&2")

      with_environment("PATH" => "#{bin}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}") do
        assert_empty Release::Publication.new("0.2.0", commands: @commands, out: @out).remote_tag
      end
    end
  end

  def test_a_failed_command_reports_its_output_and_diagnostics
    error = assert_raises(Release::Error) do
      @commands.call([RbConfig.ruby, "-e", "puts 'partial'; warn 'fatal: reason'; exit 1"])
    end

    assert_equal "#{RbConfig.ruby} -e puts 'partial'; warn 'fatal: reason'; exit 1 failed.\npartial\nfatal: reason\n",
                 error.message
  end

  def test_unreadable_json_is_a_release_error
    error = assert_raises(Release::Error) { @commands.json([RbConfig.ruby, "-e", "puts 'not JSON'"]) }

    assert_match(/\A#{Regexp.escape(RbConfig.ruby)} -e puts 'not JSON' returned unreadable JSON: /, error.message)
  end

  def test_a_missing_program_is_a_release_error_whether_captured_or_streamed
    [false, true].each do |stream|
      error = assert_raises(Release::Error) { @commands.call(["rich-ri-missing-program"], stream: stream) }

      assert_equal "rich-ri-missing-program is not installed or not on PATH", error.message
    end
  end
end
