# frozen_string_literal: true

require "test_helper"
require "terminal_helper"

class InteractiveTest < Minitest::Test
  include TerminalTestSupport

  # Runs the command reading from a terminal on which the text is typed, with
  # its output in a pipe. Returns the output and the exit status.
  def typed_into(text, environment, *command)
    PTY.open do |terminal, keyboard|
      terminal.write(text)
      IO.pipe do |reader, writer|
        pid = Process.spawn(environment, *command, in: keyboard, out: writer)
        writer.close
        [reader.read, Process.wait2(pid).last]
      end
    end
  end

  def test_session_continues_after_names_that_cannot_be_looked_up
    names = "RichRIExample[\nNoSuchExample123\nRichRIExample#ma\nRichRIExample#map\n\n"
    out, err, status = cli("--interactive", stdin: names)

    assert_predicate status, :success?, err
    assert_includes out, "RichRIExample#ma not found, maybe you meant:"
    assert_includes err, "rich-ri: Nothing known about RichRIExample[\n"
    assert_includes err, "rich-ri: Nothing known about NoSuchExample123\n"
    refute_match(/from .*\.rb:\d+/, err)
    assert_includes out, "Return transformed values."
  end

  # The session ends at a blank line or at the end of input, whichever comes first.
  PIPED_NAMES = ["RichRIExample#map\nRichRIExample.build\n\nRichRIExample\n",
                 "RichRIExample#map\r\nRichRIExample.build",
                 "RichRIExample#map\nRichRIExample.build\n   \nRichRIExample\n"].freeze

  def test_names_from_a_pipe_are_read_as_plain_lines
    PIPED_NAMES.product([["--interactive"], []]).each do |names, mode|
      out, err, status = cli(*mode, stdin: names, env: { "NO_COLOR" => nil, "TERM" => "xterm-256color" })

      assert_predicate status, :success?, err
      assert_empty err
      refute_match(/\e|>> /, out)
      assert_operator out, :start_with?, "\nEnter the method name you want to look up.\n"
      assert_includes out, "Return transformed values."
      assert_includes out, "Create an example."
      refute_includes out, "= RichRIExample < Object"
    end
  end

  def test_prompt_is_not_drawn_into_redirected_output
    Dir.mktmpdir("rich-ri-interactive-") do |dir|
      environment = TestSupport::ENVIRONMENT.merge("HOME" => dir, "INPUTRC" => File::NULL, "TERM" => "xterm-256color")
      command = [RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", File.join(TestSupport::ROOT, "exe/rich-ri"),
                 "--no-standard-docs", "--doc-dir", TestSupport::STORE]
      out, status = typed_into("RichRIExample#map\n\n", environment, *command)

      assert_predicate status, :success?, out
      refute_match(/\e|>> /, out)
      assert_includes out, "Return transformed values."
    end
  end

  def test_session_continues_after_a_lookup_that_fails
    Dir.mktmpdir("rich-ri-interactive-") do |dir|
      store = File.join(dir, "ri")
      FileUtils.cp_r(TestSupport::STORE, store)
      File.binwrite(File.join(store, "RichRIExample/map-i.ri"), "")
      out, err, status = cli("--no-standard-docs", "--doc-dir", store, "--interactive",
                             docs: false, stdin: "RichRIExample#map\nRichRIExample.build\n\n")

      assert_predicate status, :success?, err
      assert_includes err, "rich-ri: incompatible or damaged RI data in #{store}\n"
      assert_includes out, "Create an example."
    end
  end

  def test_session_continues_after_completion_fails
    source = <<~RUBY
      require "rich_ri"
      RichRI::Driver.prepend(Module.new { def complete(_name) = raise(EncodingError, "planted completion defect") })
      exit RichRI::CLI.run(ARGV)
    RUBY
    Dir.mktmpdir("rich-ri-interactive-") do |dir|
      environment = { "HOME" => dir, "INPUTRC" => File::NULL, "NO_COLOR" => "1" }
      output, status = terminal(RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", "-e", source, "--",
                                "--no-standard-docs", "--doc-dir", TestSupport::STORE,
                                env: environment, prompt: ">> ", input: "Rich\tRichRIExample#map\n\n")

      assert_equal 0, status, output
      assert_includes output, "rich-ri: planted completion defect"
      assert_includes output, "Return transformed values."
    end
  end

  def test_a_prompt_that_keeps_failing_ends_the_session_with_the_failure
    source = <<~RUBY
      require "rich_ri"
      Reline.singleton_class.prepend(Module.new { def readline(*) = raise(EncodingError, "planted prompt defect") })
      exit RichRI::CLI.run(ARGV)
    RUBY
    output, status = terminal(RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", "-e", source, "--",
                              "--no-standard-docs", "--interactive")

    assert_equal 1, status, output
    assert_equal ["rich-ri: planted prompt defect\r\n"] * 3, output.lines.last(3)
    assert_equal 3, output.scan("planted prompt defect").length
  end
end
