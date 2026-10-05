# frozen_string_literal: true

require "test_helper"

class EnvironmentFailuresTest < Minitest::Test
  def test_file_failures_name_the_file_before_the_reason
    Dir.mktmpdir("rich-ri-files-") do |dir|
      config = File.join(dir, "config.yml")
      File.write(config, "theme: dark\n")
      File.chmod(0o000, config)
      locked = File.join(dir, "locked")
      Dir.mkdir(locked, 0o555)
      next if File.readable?(config)

      { ["--config", config, "--show-config"] => "rich-ri: #{config}: Permission denied\n",
        ["--install-man=#{locked}/man1"] => "rich-ri: #{locked}/man1: Permission denied\n" }.each do |args, message|
        out, err, status = cli(*args, docs: false)

        assert_equal 1, status.exitstatus, args.inspect
        assert_empty out
        assert_equal message, err
      end
    end
  end

  def test_output_that_cannot_be_written_is_a_failure
    skip "No /dev/full on this system" unless File.chardev?("/dev/full")
    IO.pipe do |reader, writer|
      pid = Process.spawn(TestSupport::ENVIRONMENT, RbConfig.ruby, "-I#{TestSupport::ROOT}/lib",
                          File.join(TestSupport::ROOT, "exe/rich-ri"), "--version", out: "/dev/full", err: writer)
      writer.close
      _pid, status = Process.wait2(pid)

      assert_equal 1, status.exitstatus
      assert_equal "rich-ri: standard output: No space left on device\n", reader.read
    end
  end
end
