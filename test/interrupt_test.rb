# frozen_string_literal: true

require "test_helper"
require "terminal_helper"

class InterruptTest < Minitest::Test
  include TerminalTestSupport

  EXECUTABLE = File.join(TestSupport::ROOT, "exe/rich-ri")
  SOURCES = ["--no-standard-docs", "--doc-dir", TestSupport::STORE].freeze

  def test_interrupt_while_the_program_loads_ends_quietly
    Dir.mktmpdir("rich-ri-interrupt-") do |dir|
      # Stands in for the library so the signal arrives during its require.
      File.write(File.join(dir, "rich_ri.rb"), "Process.kill('INT', Process.pid)\nsleep\n")
      out, err, status = Open3.capture3(TestSupport::ENVIRONMENT, RbConfig.ruby, "-I#{dir}",
                                        "-I#{TestSupport::ROOT}/lib", EXECUTABLE, "--version")

      assert_equal 130, status.exitstatus, err
      assert_empty out
      assert_empty err
    end
  end

  def test_interrupt_during_a_lookup_ends_quietly
    source = <<~RUBY
      require "rich_ri"
      RichRI::Formatter.prepend(Module.new { def start_accepting = raise(Interrupt) })
      exit RichRI::CLI.run(ARGV)
    RUBY
    out, err, status = Open3.capture3(TestSupport::ENVIRONMENT, RbConfig.ruby, "-I#{TestSupport::ROOT}/lib",
                                      "-e", source, "--", *SOURCES, "RichRIExample#map")

    assert_equal 130, status.exitstatus, err
    assert_empty out
    assert_empty err
  end

  def test_ctrl_c_at_the_interactive_prompt_exits_as_an_interrupt
    Dir.mktmpdir("rich-ri-interrupt-") do |dir|
      environment = { "HOME" => dir, "INPUTRC" => File::NULL, "NO_COLOR" => "1" }
      output, status = terminal(RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", EXECUTABLE, *SOURCES,
                                env: environment, prompt: ">> ", input: "\u0003")

      assert_equal 130, status, output
      refute_match(/Interrupt|from .*\.rb:\d+/, output)
    end
  end
end
