# frozen_string_literal: true

require "test_helper"
require "terminal_helper"

class InterruptTest < Minitest::Test
  include TerminalTestSupport

  EXECUTABLE = File.join(TestSupport::ROOT, "exe/rich-ri")
  SOURCES = ["--no-standard-docs", "--doc-dir", TestSupport::STORE].freeze

  # What the program below does on Ctrl-C: carry on as less does, leave with
  # a failure as less -K does, or be ended by the signal.
  ON_INTERRUPT = { handles: 'trap("INT") { File.write(log, "interrupted\n", mode: "a") }',
                   leaves: 'trap("INT") { exit 2 }', dies: "" }.freeze

  # A program that takes over the terminal the way a pager does: it announces
  # itself, then waits for a line.
  def terminal_program(path, on_interrupt)
    File.write(path, <<~RUBY)
      #!#{RbConfig.ruby}
      log = File.join(__dir__, "log")
      #{ON_INTERRUPT.fetch(on_interrupt)}
      STDIN.read unless STDIN.tty?
      File.open("/dev/tty", "r+") do |tty|
        tty.puts "PROGRAM READY"
        tty.gets
      end
      File.write(log, "finished\n", mode: "a")
    RUBY
    File.chmod(0o755, path)
    path
  end

  def paged_lookup(pager, input)
    terminal(RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", EXECUTABLE, *SOURCES, "RichRIExample#map",
             env: { "RI_PAGER" => pager, "NO_COLOR" => nil }, prompt: "PROGRAM READY", input: input)
  end

  def test_ctrl_c_is_left_to_a_pager_that_handles_it
    Dir.mktmpdir("rich-ri-interrupt-") do |dir|
      pager = terminal_program(File.join(dir, "pager"), :handles)
      output, status = paged_lookup(pager, "\u0003q\n")

      assert_equal 0, status, output
      assert_equal "interrupted\nfinished\n", File.read(File.join(dir, "log"))
    end
  end

  def test_ctrl_c_that_ends_the_pager_ends_the_lookup_as_an_interrupt
    Dir.mktmpdir("rich-ri-interrupt-") do |dir|
      pager = terminal_program(File.join(dir, "pager"), :dies)
      output, status = paged_lookup(pager, "\u0003")

      assert_equal 130, status, output
      refute_path_exists File.join(dir, "log")
    end
  end

  def test_ctrl_c_that_makes_the_pager_leave_is_an_interrupt_not_a_pager_failure
    Dir.mktmpdir("rich-ri-interrupt-") do |dir|
      pager = terminal_program(File.join(dir, "pager"), :leaves)
      output, status = paged_lookup(pager, "\u0003")

      assert_equal 130, status, output
      refute_includes output, "rich-ri:"
      refute_path_exists File.join(dir, "log")
    end
  end

  def test_ctrl_c_is_left_to_the_manual_viewer
    Dir.mktmpdir("rich-ri-interrupt-") do |dir|
      terminal_program(File.join(dir, "man"), :handles)
      output, status = terminal(RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", EXECUTABLE, "--man",
                                env: { "PATH" => dir }, prompt: "PROGRAM READY", input: "\u0003q\n")

      assert_equal 0, status, output
      assert_equal "interrupted\nfinished\n", File.read(File.join(dir, "log"))
    end
  end

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
