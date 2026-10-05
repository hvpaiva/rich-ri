# frozen_string_literal: true

module RichRI
  # Optional highlighting must not prevent the reader from displaying a page.
  class Bat
    TIMEOUT = 2
    MAX_INPUT = 1_048_576
    MAX_OUTPUT = 8_388_608

    def initialize(timeout: TIMEOUT, max_output: MAX_OUTPUT)
      @timeout = timeout
      @max_output = max_output
      @available = true
    end

    def highlight(text, language:, theme:)
      return unless @available && text.bytesize <= MAX_INPUT

      output = capture(text, language, theme)
      output&.force_encoding(text.encoding)
      output = output.delete_suffix("\n") if output && !text.end_with?("\n") && output.end_with?("\n")
      return output if output&.valid_encoding? && RichRI.plain(output) == text

      @available = false
      nil
    rescue SystemCallError, IOError, Timeout::Error
      @available = false
      nil
    end

    private

    def capture(text, language, theme)
      args = ["bat", "--no-config", "--language=#{language}", "--style=plain", "--color=always",
              "--paging=never", "--wrap=never", "--theme=#{theme}"]
      Open3.popen2(*args, err: File::NULL, pgroup: true) do |input, output, waiter|
        completed = false
        writer = Thread.new { write(input, text) }
        Timeout.timeout(@timeout) do
          result = output.read(@max_output + 1) || +""
          next if result.bytesize > @max_output

          writer.value
          status = waiter.value
          completed = true
          result if status.success?
        end
      ensure
        writer&.kill
        terminate(waiter) unless completed
      end
    end

    def write(input, text)
      input.write(text)
    rescue Errno::EPIPE, IOError
      nil
    ensure
      input.close unless input.closed?
    end

    def terminate(waiter)
      Process.kill("TERM", -waiter.pid)
      waiter.join(0.1)
      # Descendants may still hold pipes open after their parent exits.
      Process.kill("KILL", -waiter.pid)
    rescue Errno::ESRCH
      nil
    ensure
      waiter.join
    end
  end
end
