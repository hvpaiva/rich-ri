# frozen_string_literal: true

require "pty"

module TerminalTestSupport
  # A real terminal is needed for color detection and shell insertion. Wait for
  # the prompt before typing so the terminal's initial line discipline cannot
  # consume Tab before Readline/ZLE starts.
  def terminal(*command, env: {}, prompt: nil, input: nil)
    output = +""
    status = nil
    pid = nil
    Timeout.timeout(15) do
      PTY.spawn(TestSupport::ENVIRONMENT.merge(env), *command) do |reader, writer, child|
        pid = child
        writer.winsize = [30, 120]
        output << reader.readpartial(4096) until !prompt || output.include?(prompt)
        writer.write(input) if input
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
end
