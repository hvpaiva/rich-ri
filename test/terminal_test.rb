# frozen_string_literal: true

require "test_helper"
require "terminal_helper"

class TerminalTest < Minitest::Test
  include TerminalTestSupport

  def terminal_cli(*, env: {}, prompt: nil, input: nil)
    coverage = ENV["COVERAGE"] ? ["-r#{TestSupport::ROOT}/test/coverage_helper"] : []
    terminal(RbConfig.ruby, *coverage, "-I#{TestSupport::ROOT}/lib", "#{TestSupport::ROOT}/exe/rich-ri", *,
             env: { "COVERAGE_CHILD" => "1", "NO_COLOR" => nil }.merge(env), prompt: prompt, input: input)
  end

  def test_tty_color_policy_and_explicit_override
    [{}, { "NO_COLOR" => "1" }, { "TERM" => "dumb" }].each do |environment|
      output, status = terminal_cli("--help", env: environment)

      assert_equal 0, status, output
      assert_equal environment.empty?, output.include?("\e["), environment.inspect
    end
    output, status = terminal_cli("--color=always", "--help", env: { "NO_COLOR" => "1", "TERM" => "dumb" })

    assert_equal 0, status, output
    assert_includes output, "\e["
  end

  def test_pager_receives_rich_output_and_preserves_less_preferences
    Dir.mktmpdir("rich-ri-pager-") do |dir|
      pager = File.join(dir, "pager.rb")
      capture = File.join(dir, "output")
      File.write(pager, "File.write(ARGV.fetch(0), ENV.fetch('LESS', '') + \"\\n\" + STDIN.read)\n")
      environment = { "RI_PAGER" => [RbConfig.ruby, pager, capture].shelljoin, "LESS" => "-i -Pprompt",
                      "PAGER" => "missing" }
      output, status = terminal_cli("--no-standard-docs", "--doc-dir", TestSupport::STORE, "RichRIExample#map",
                                    env: environment)
      page = File.read(capture)

      assert_equal 0, status, output
      assert_equal "-R -i -Pprompt\n", page.lines.first
      assert_includes page, "\e["
      assert_includes RichRI.plain(page), "Return transformed values."
    end
  end

  def test_interrupt_is_left_to_the_pager_while_a_page_is_open
    Dir.mktmpdir("rich-ri-pager-") do |dir|
      pager = File.join(dir, "pager.rb")
      File.write(pager, <<~RUBY)
        trap("INT", "IGNORE")
        STDIN.read
        print "open"
        File.open("/dev/tty", &:gets)
        print "closed"
      RUBY
      output, status = terminal_cli("--no-standard-docs", "--doc-dir", TestSupport::STORE, "RichRIExample#map",
                                    env: { "RI_PAGER" => [RbConfig.ruby, pager].shelljoin },
                                    prompt: "open", input: "\u0003\n")

      assert_equal 0, status, output
      assert_includes output, "closed"
    end
  end

  def test_missing_pagers_fall_back_to_terminal_output
    environment = { "PATH" => "", "RI_PAGER" => "missing-ri-pager", "PAGER" => "missing-pager" }
    output, status = terminal_cli("--no-standard-docs", "--doc-dir", TestSupport::STORE, "RichRIExample#map",
                                  env: environment)

    assert_equal 0, status, output
    assert_includes RichRI.plain(output), "Return transformed values."
    refute_includes output, "No such file"
  end

  def test_interactive_tab_completes_lookup_and_blank_line_exits_without_external_programs
    Dir.mktmpdir("rich-ri-interactive-") do |dir|
      environment = { "PATH" => "", "HOME" => dir, "INPUTRC" => File::NULL, "NO_COLOR" => "1" }
      output, status = terminal_cli("--no-standard-docs", "--doc-dir", TestSupport::STORE,
                                    env: environment, prompt: ">> ", input: "RichRIExample#ma\t\n\n")

      assert_equal 0, status, output
      assert_includes output, "You can use tab to autocomplete."
      assert_includes output, "Enter a blank line to exit."
      assert_includes output, ">> RichRIExample#map"
      assert_includes output, "Return transformed values."
      refute_includes output, "Nothing known about"
    end
  end

  def test_interactive_lookup_continues_after_a_name_with_pattern_characters
    Dir.mktmpdir("rich-ri-interactive-") do |dir|
      environment = { "PATH" => "", "HOME" => dir, "INPUTRC" => File::NULL, "NO_COLOR" => "1" }
      output, status = terminal_cli("--no-standard-docs", "--doc-dir", TestSupport::STORE,
                                    env: environment, prompt: ">> ", input: "RichRIExample[\nRichRIExample#map\n\n")

      assert_equal 0, status, output
      assert_includes output, "Nothing known about RichRIExample["
      assert_includes output, "Return transformed values."
    end
  end
end
