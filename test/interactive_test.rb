# frozen_string_literal: true

require "test_helper"
require "terminal_helper"
require "command_helper"

class InteractiveTest < Minitest::Test
  include TerminalTestSupport
  include CommandSupport

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

  def gem_session(keys)
    with_session(TestSupport.gem_environment) do |environment|
      terminal_cli("--no-system", "--no-site", "--no-home", env: environment, prompt: ">> ", input: keys)
    end
  end

  def test_tab_takes_the_whole_line_for_the_name_being_typed
    output, status = gem_session([[">> ", "Inkwell#<\t\t"], ["Inkwell#<=>", "<\n"], [">> ", "Inkwell#=\t\t"],
                                  ["Inkwell#===", "~\n\n"]])

    assert_equal 0, status, output
    assert_match(/Inkwell#<<\s+Inkwell#<=\s+Inkwell#<=>/, output)
    assert_includes output, "Add ink."
    assert_match(/Inkwell#==\s+Inkwell#===\s+Inkwell#=~/, output)
    assert_includes output, "Match the name of the ink."
    refute_includes output, "rich-ri:"
  end

  def test_tab_twice_lists_the_names_that_share_what_was_typed
    output, status = gem_session([[">> ", "  Inkwell#fi\t\t"], ["Inkwell#filled?", "\n\n"]])

    assert_equal 0, status, output
    assert_match(/Inkwell#fill\s+Inkwell#filled\?/, output)
    assert_includes output, "Fill the well."
    refute_includes output, "rich-ri:"
  end

  # RubyGems builds its default directory from RbConfig, whose strings are
  # BINARY in every locale, and the directories of its gems inherit the label.
  def binary_gem_session(keys)
    binary_paths = <<~RUBY
      home = ENV.fetch("GEM_HOME").b
      Gem.paths = { "GEM_HOME" => home, "GEM_PATH" => home }
    RUBY
    with_session(TestSupport.gem_environment) do |environment|
      with_planted(binary_paths, env: environment) do |env|
        terminal_cli("--no-system", "--no-site", "--no-home", env: env, prompt: ">> ", input: keys)
      end
    end
  end

  def test_tab_completes_over_gem_directories_labelled_binary
    output, status = binary_gem_session("inkwell-2\t\nInkwell#filled\t\n\n")

    assert_equal 0, status, output
    assert_includes output, "UPGRADING.rdoc"
    assert_includes output, "Report whether the well is full."
    refute_match(/rich-ri:|incompatible character encodings/, output)
  end

  def test_tab_on_an_empty_line_leaves_the_prompt_working
    output, status = binary_gem_session("\tInkwell#filled?\n\n")

    assert_equal 0, status, output
    assert_includes output, "Report whether the well is full."
    refute_match(/rich-ri:|incompatible character encodings/, output)
  end

  def test_tab_completes_a_gem_and_then_its_page
    output, status = gem_session("inkwell-n\tB\t\n\n")

    assert_equal 0, status, output
    assert_includes output, "inkwell-native:BUILDING.rdoc"
    assert_includes output, "Compile the extension."
    refute_includes output, "rich-ri:"
  end

  def test_each_line_of_a_pasted_block_is_looked_up
    with_session do |environment|
      # Bracketed paste: the editor takes the line breaks inside it for text.
      pasted = "\e[200~RichRIExample#map\n\n  RichRIExample.build\n\e[201~"
      output, status = terminal_cli("--no-standard-docs", "--doc-dir", TestSupport::STORE,
                                    env: environment, prompt: ">> ", input: "#{pasted}\n\n")

      assert_equal 0, status, output
      assert_includes output, "Return transformed values."
      assert_includes output, "Create an example."
      refute_includes output, "rich-ri:"
    end
  end

  def test_tab_offers_no_name_that_holds_a_terminal_control
    names = { modules: ["RichRIUnsafe\e]52;c;AAAA\a", "RichRIUnsafe\e[31m"], methods: ["ma\e[31mx"],
              pages: ["GUIDE\u202e.rdoc"] }
    with_cached_names(**names) do |sources|
      with_session do |environment|
        keys = [[">> ", "RichRIU\t\t"], ["RichRIU", "\u0015RichRIExample#ma\t\t"], ["RichRIExample#map", "\n"],
                [">> ", "#{sources.last}:GUIDE\t\t"], ["GUIDE.rdoc", "\n\n"]]
        output, status = terminal_cli(*sources, env: environment, prompt: ">> ", input: keys)

        assert_equal 0, status, output
        refute_match(/\e\]52|\e\[31m|\a|\u202e|Unsafe/, output.dup.force_encoding(Encoding::UTF_8))
        assert_includes output, "Return transformed values."
        assert_includes output, "= Example guide"
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
    with_session(TestSupport::ENVIRONMENT.merge("COVERAGE_CHILD" => "1", "TERM" => "xterm-256color")) do |environment|
      command = executable("--no-standard-docs", "--doc-dir", TestSupport::STORE)
      out, status = typed_into("RichRIExample#map\n\n", environment, *command)

      assert_predicate status, :success?, out
      refute_match(/\e|>> /, out)
      assert_includes out, "Return transformed values."
    end
  end

  def test_session_continues_after_a_lookup_that_fails
    with_store do |store|
      File.binwrite(File.join(store, "RichRIExample/map-i.ri"), "")
      out, err, status = cli("--no-standard-docs", "--doc-dir", store, "--interactive",
                             docs: false, stdin: "RichRIExample#map\nRichRIExample.build\n\n")

      assert_predicate status, :success?, err
      assert_includes err, "rich-ri: incompatible or damaged RI data in #{store}\n"
      assert_includes out, "Create an example."
    end
  end

  def test_session_continues_after_completion_fails
    defect = <<~RUBY
      require "rich_ri"
      RichRI::Driver.prepend(Module.new { def complete(_name) = raise(EncodingError, "planted completion defect") })
    RUBY
    with_session do |environment|
      output, status = with_planted(defect, env: environment) do |env|
        terminal_cli("--no-standard-docs", "--doc-dir", TestSupport::STORE,
                     env: env, prompt: ">> ", input: "Rich\tRichRIExample#map\n\n")
      end

      assert_equal 0, status, output
      assert_includes output, "rich-ri: planted completion defect"
      assert_includes output, "Return transformed values."
    end
  end

  def test_a_prompt_that_keeps_failing_ends_the_session_with_the_failure
    defect = <<~RUBY
      require "rich_ri"
      Reline.singleton_class.prepend(Module.new { def readline(*) = raise(EncodingError, "planted prompt defect") })
    RUBY
    output, status = with_planted(defect) do |env|
      terminal_cli("--no-standard-docs", "--interactive", env: env.merge("NO_COLOR" => "1"))
    end

    assert_equal 1, status, output
    assert_equal ["rich-ri: planted prompt defect\r\n"] * 3, output.lines.last(3)
    assert_equal 3, output.scan("planted prompt defect").length
  end
end
