# frozen_string_literal: true

require "pty"

module TerminalTestSupport
  # A real terminal is needed for color detection and shell insertion. Wait for
  # the prompt before typing so the terminal's initial line discipline cannot
  # consume Tab before Readline/ZLE starts.
  #
  # The input is typed at once, or is a list of [text, keys] pairs whose keys
  # are each typed when the text has appeared after the keys before them. A
  # line editor reads every key that is waiting before it draws, so a list of
  # candidates is seen only by waiting for it.
  def terminal(*command, env: {}, prompt: nil, input: nil)
    output = +""
    status = nil
    pid = nil
    Timeout.timeout(15) do
      PTY.spawn(TestSupport::ENVIRONMENT.merge(env), *command) do |reader, writer, child|
        pid = child
        writer.winsize = [30, 120]
        (input.is_a?(Array) ? input : [[prompt, input]]).each do |awaited, keys|
          typed = output.length
          output << reader.readpartial(4096) until !awaited || output[typed..].include?(awaited)
          writer.write(keys) if keys
        end
        begin
          loop { output << reader.readpartial(4096) }
        rescue EOFError, Errno::EIO
          _child, result = Process.wait2(pid)
          status = result.exitstatus
          pid = nil
        end
      end
    end
    [output, status]
  rescue Timeout::Error
    flunk "Terminal timed out: #{command.inspect}\nCaptured output: #{output.inspect}"
  ensure
    if pid
      begin
        Process.kill("KILL", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # The shell can exit between closing its terminal and reaping it.
      end
    end
  end

  # The executable on a terminal, with colors left to its own detection.
  def terminal_cli(*, env: {}, prompt: nil, input: nil)
    coverage = ENV["COVERAGE"] ? ["-r#{TestSupport::ROOT}/test/coverage_helper"] : []
    terminal(RbConfig.ruby, *coverage, "-I#{TestSupport::ROOT}/lib", "#{TestSupport::ROOT}/exe/rich-ri", *,
             env: { "COVERAGE_CHILD" => "1", "NO_COLOR" => nil }.merge(env), prompt: prompt, input: input)
  end
end
