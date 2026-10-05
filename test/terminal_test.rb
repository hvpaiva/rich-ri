# frozen_string_literal: true

require "test_helper"
require "terminal_helper"

class TerminalTest < Minitest::Test
  include TerminalTestSupport

  SOURCES = ["--no-standard-docs", "--doc-dir", TestSupport::STORE].freeze

  # A pager that appends its arguments to the log beside it and shows the page.
  def logging_pager(dir)
    pager = File.join(dir, "pager.rb")
    File.write(pager, "File.write(File.join(__dir__, 'log'), ARGV.inspect + \"\\n\", mode: 'a')\n" \
                      "STDOUT.write(STDIN.read)\n")
    [[RbConfig.ruby, pager].shelljoin, File.join(dir, "log")]
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
      environment = { "RI_PAGER" => [RbConfig.ruby, pager, capture].shelljoin, "PAGER" => "missing" }
      # An option of less that takes a string, such as a prompt, runs to the end of LESS.
      { "-i" => "-R -i", "-Pmyprompt" => "-R -Pmyprompt", "" => "-R ", nil => "-R -Fi" }.each do |less, expected|
        output, status = terminal_cli(*SOURCES, "RichRIExample#map", env: environment.merge("LESS" => less))
        page = File.read(capture)

        assert_equal 0, status, output
        assert_equal "#{expected}\n", page.lines.first
        assert_includes page, "\e["
        assert_includes RichRI.plain(page), "Return transformed values."
      end
    end
  end

  def test_a_class_inside_a_namespace_is_paged_once
    Dir.mktmpdir("rich-ri-pager-") do |dir|
      pager, log = logging_pager(dir)
      output, status = terminal_cli(*SOURCES, "RichRIExample::Nested", env: { "RI_PAGER" => pager })

      assert_equal 0, status, output
      assert_equal "[]\n", File.read(log)
      assert_includes RichRI.plain(output), "A nested example for namespace discovery."
      refute_includes output, "not found"
    end
  end

  def test_without_any_pager_the_page_goes_to_the_terminal
    output, status = terminal_cli(*SOURCES, "RichRIExample#map", env: { "PATH" => "", "PAGER" => nil })

    assert_equal 0, status, output
    assert_includes RichRI.plain(output), "Return transformed values."
    refute_includes output, "rich-ri:"
  end

  def test_a_named_pager_that_cannot_run_is_an_error_whoever_named_it
    Dir.mktmpdir("rich-ri-pager-") do |dir|
      working, log = logging_pager(dir)
      config = File.join(dir, "config.yml")
      File.write(config, "pager: missing-pager --flag\n")
      [[["--pager-command=missing-pager --flag"], { "RI_PAGER" => working }],
       [[], { "RI_PAGER" => "missing-pager --flag", "PAGER" => working }],
       [["--config", config], { "PAGER" => working }], [[], { "PAGER" => "missing-pager --flag" }]].each do |args, env|
        output, status = terminal_cli(*SOURCES, *args, "RichRIExample#map", env: env)

        assert_equal 1, status, output
        assert_equal "rich-ri: cannot run the pager \"missing-pager --flag\": No such file or directory\r\n" \
                     "Use --no-pager to write to the terminal instead.\r\n", output
        refute_path_exists log
      end
      output, status = terminal_cli(*SOURCES, "--pager-command=cat 'unclosed", "RichRIExample#map")

      assert_equal 1, status, output
      assert_includes output, "rich-ri: the pager \"cat 'unclosed\" has an unmatched quote\r\n"
      output, status = terminal_cli(*SOURCES, "--pager-command=missing-pager", "--no-pager", "RichRIExample#map")

      assert_equal 0, status, output
      assert_includes RichRI.plain(output), "Return transformed values."
    end
  end

  def test_pager_named_on_the_command_line_is_used_although_the_file_disables_paging
    Dir.mktmpdir("rich-ri-pager-") do |dir|
      pager, log = logging_pager(dir)
      config = File.join(dir, "config.yml")
      File.write(config, "pager: false\n")
      output, status = terminal_cli(*SOURCES, "--config", config, "RichRIExample#map", env: { "RI_PAGER" => pager })

      assert_equal 0, status, output
      refute_path_exists log
      output, status = terminal_cli(*SOURCES, "--config", config, "--pager-command=#{pager}", "RichRIExample#map")

      assert_equal 0, status, output
      assert_equal "[]\n", File.read(log)
      assert_includes RichRI.plain(output), "Return transformed values."
    end
  end

  def test_a_pager_that_fails_is_reported_instead_of_losing_the_page_quietly
    command = [RbConfig.ruby, "-e", "exit 3"].shelljoin
    output, status = terminal_cli(*SOURCES, "RichRIExample#map", env: { "RI_PAGER" => command })

    assert_equal 1, status, output
    assert_equal "rich-ri: the pager #{command.inspect} exited with status 3\r\n", output
    command = [RbConfig.ruby, "-e", "Process.kill('TERM', Process.pid)"].shelljoin
    output, status = terminal_cli(*SOURCES, "RichRIExample#map", env: { "RI_PAGER" => command })

    assert_equal 1, status, output
    assert_equal "rich-ri: the pager #{command.inspect} was ended by signal 15\r\n", output
  end

  def test_pager_command_is_split_into_words_and_run_without_a_shell
    Dir.mktmpdir("rich-ri-pager-") do |dir|
      working, log = logging_pager(dir)
      command = "#{working} 'two words' | $HOME > #{dir}/redirected"
      output, status = terminal_cli(*SOURCES, "--pager-command=#{command}", "RichRIExample#map")

      assert_equal 0, status, output
      assert_includes RichRI.plain(output), "Return transformed values."
      assert_equal "#{['two words', '|', '$HOME', '>', "#{dir}/redirected"].inspect}\n", File.read(log)
      refute_path_exists File.join(dir, "redirected")
    end
  end

  def test_interactive_lookups_are_paged_with_and_without_the_option
    Dir.mktmpdir("rich-ri-pager-") do |dir|
      pager, log = logging_pager(dir)
      # On a dumb terminal the line editor asks for no cursor reports, which
      # this test terminal would leave it waiting for.
      environment = { "RI_PAGER" => pager, "HOME" => dir, "TERM" => "dumb" }
      { [] => "[]\n[]\n", ["--interactive"] => "[]\n[]\n", ["--no-pager"] => "",
        ["--interactive", "--no-pager"] => "", ["-i", "-T"] => "" }.each do |mode, paged|
        File.write(log, "")
        output, status = terminal_cli(*SOURCES, *mode, env: environment, prompt: ">> ",
                                                       input: "RichRIExample#map\nRichRIExample.build\n\n")

        assert_equal 0, status, output
        assert_equal paged, File.read(log), mode.inspect
        assert_includes RichRI.plain(output), "Return transformed values."
        assert_includes RichRI.plain(output), "Create an example."
      end
    end
  end

  def test_interactive_tab_completes_lookup_and_blank_line_exits_without_external_programs
    Dir.mktmpdir("rich-ri-interactive-") do |dir|
      environment = { "PATH" => "", "PAGER" => nil, "HOME" => dir, "INPUTRC" => File::NULL, "NO_COLOR" => "1" }
      output, status = terminal_cli(*SOURCES, env: environment, prompt: ">> ", input: "RichRIExample#ma\t\n\n")

      assert_equal 0, status, output
      assert_includes output, "You can use tab to autocomplete."
      assert_includes output, "Enter a blank line to exit."
      assert_includes output, ">> RichRIExample#map"
      assert_includes output, "Return transformed values."
      refute_includes output, "Nothing known about"
    end
  end
end
