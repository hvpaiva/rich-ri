# frozen_string_literal: true

require "test_helper"
require "terminal_helper"

class InteractiveTest < Minitest::Test
  include TerminalTestSupport

  def test_session_continues_after_names_that_cannot_be_looked_up
    out, err, status = cli("--interactive", stdin: "RichRIExample[\nNoSuchExample123\nRichRIExample#map\n\n")

    assert_predicate status, :success?, err
    assert_includes err, "rich-ri: Nothing known about RichRIExample[\n"
    assert_includes err, "rich-ri: Nothing known about NoSuchExample123\n"
    refute_match(/from .*\.rb:\d+/, err)
    assert_includes out, "Return transformed values."
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
    _out, err, status = Open3.capture3(TestSupport::ENVIRONMENT, RbConfig.ruby, "-I#{TestSupport::ROOT}/lib",
                                       "-e", source, "--", "--no-standard-docs", "--interactive")

    assert_equal 1, status.exitstatus
    assert_equal ["rich-ri: planted prompt defect\n"] * 3, err.lines
  end
end
