# frozen_string_literal: true

require "test_helper"

class BatTest < Minitest::Test
  def fake_bat(body)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bat")
      File.write(path, "#!#{RbConfig.ruby}\n#{body}\n")
      FileUtils.chmod(0o755, path)
      with_environment("PATH" => dir) { yield dir }
    end
  end

  def test_stalled_process_is_killed_and_reaped
    fake_bat('trap("TERM", "IGNORE"); sleep 30') do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = RichRI::Bat.new(timeout: 0.1).highlight("echo hello\n", language: "bash", theme: "ansi")

      assert_nil result
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 3
      assert_raises(Errno::ECHILD) { Process.waitpid(-1, Process::WNOHANG) }
    end
  end

  def test_invalid_encoding_falls_back_and_disables_bat_for_the_page
    fake_bat('STDOUT.binmode; STDOUT.write([255].pack("C"))') do |dir|
      highlighter = RichRI::Highlighter.new(true)

      assert_equal "echo hello\n", highlighter.highlight("echo hello\n", :bash)
      marker = File.join(dir, "called")
      File.write(File.join(dir, "bat"), "#!#{RbConfig.ruby}\nFile.write(#{marker.inspect}, 'called')\n")

      assert_equal "echo again\n", highlighter.highlight("echo again\n", :bash)
      refute_path_exists marker
    end
  end

  def test_success_without_output_leaves_the_text_to_the_caller
    fake_bat("STDIN.read") do
      assert_nil RichRI::Bat.new.highlight("echo hello\n", language: "bash", theme: "ansi")
    end
  end

  def test_excess_output_is_bounded_even_if_input_is_not_consumed
    fake_bat('loop { STDOUT.write("x" * 4096) }') do
      result = RichRI::Bat.new(timeout: 2, max_output: 1024).highlight("x" * 200_000, language: "bash", theme: "ansi")

      assert_nil result
      assert_raises(Errno::ECHILD) { Process.waitpid(-1, Process::WNOHANG) }
    end
  end

  def test_large_examples_bypass_bat_without_disabling_later_examples
    fake_bat('print "\e[32m", STDIN.read, "\e[0m"') do
      bat = RichRI::Bat.new

      assert_nil bat.highlight("x" * (RichRI::Bat::MAX_INPUT + 1), language: "bash", theme: "ansi")
      assert_equal "\e[32mcat\e[0m", bat.highlight("cat", language: "bash", theme: "ansi")
    end
  end
end
