# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/release_commands"
require_relative "release_support"

class ReleaseCommandsTest < Minitest::Test
  include ReleaseFixtures

  def setup
    @commands = Release::Commands.new(root: TestSupport::TEMP, out: StringIO.new)
  end

  def test_unreadable_output_and_missing_programs_are_reported_as_release_errors
    assert_release_error(/returned unreadable JSON/) { @commands.json([RbConfig.ruby, "-e", "puts 'not JSON'"]) }
    assert_release_error(/\Arich-ri-missing-program is not installed/) { @commands.call(["rich-ri-missing-program"]) }
    assert_release_error(/\Arich-ri-missing-program is not installed/) do
      @commands.call(["rich-ri-missing-program"], stream: true)
    end
  end
end
