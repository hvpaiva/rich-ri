# frozen_string_literal: true

require "terminal_helper"
require "shell_support"

# Runs the completion scripts in the shells themselves. The rich-ri found on
# PATH runs this checkout and reads the fixture store and the store of a gem.
module ShellHarness
  def setup
    @bin = Dir.mktmpdir("rich-ri-bin-")
    File.write(File.join(@bin, "rich-ri"), <<~RUBY)
      #!#{RbConfig.ruby}
      $LOAD_PATH.unshift(#{File.join(TestSupport::ROOT, 'lib').inspect})
      require "rich_ri"
      exit RichRI::CLI.run(ARGV)
    RUBY
    FileUtils.chmod(0o755, File.join(@bin, "rich-ri"))
    sources = ["--no-standard-docs", "--doc-dir", TestSupport::STORE, "--doc-dir", TestSupport.gem_store("inkwell")]
    @env = TestSupport::ENVIRONMENT.merge(ShellSupport::ENVIRONMENT)
                                   .merge("PATH" => "#{@bin}:#{ENV.fetch('PATH', '')}", "RI" => sources.shelljoin)
  end

  def teardown
    FileUtils.remove_entry(@bin)
  end

  private

  def shell(name, script, *)
    flags = { "bash" => %w[--noprofile --norc], "zsh" => ["-f"], "fish" => ["--no-config"] }.fetch(name)
    out, err, status = Open3.capture3(@env, name, *flags, "-c", script, "harness", *)

    assert_predicate status, :success?, err
    assert_empty err
    out.lines.map(&:chomp)
  rescue Errno::ENOENT
    missing(name)
  end

  def missing(name)
    flunk "#{name} is required" if ENV["RICH_RI_REQUIRE_SHELLS"]
    skip "#{name} is not installed; CI runs all shell tests"
  end

  def bash_completion
    completion = ShellSupport.bash_completion
    return completion if completion

    flunk "bash-completion 2.x with a compatible bash is required" if ENV["RICH_RI_REQUIRE_SHELLS"]
    skip "bash-completion 2.x with a compatible bash is unavailable; CI runs all shell tests"
  end
end

# Types a line into an interactive shell, presses Tab at its end and reads the
# words the shell then passes to rich-ri. The working and home directory hold
# a directory and a file with a space in their names and directories named
# like a class.
module ShellInsertion
  include ShellHarness
  include TerminalTestSupport

  private

  def inserted_arguments(name, line, env: {})
    ["docs spaced", "RichRIExample", "NoSuchExample"].each { |directory| FileUtils.mkdir_p(File.join(@bin, directory)) }
    File.write(File.join(@bin, "settings spaced.yml"), "theme: terminal\n")
    environment = @env.merge("HOME" => @bin, "HISTFILE" => File::NULL, "XDG_CONFIG_HOME" => File.join(@bin, "config"),
                             "XDG_DATA_HOME" => File.join(@bin, "data")).merge(env)
    command = interactive_command(name, environment)
    output, status = terminal(*command, env: environment, prompt: "RICH_READY> ", input: "#{line}\t\nexit\n")
    @terminal_output = output

    assert_equal 0, status, output
    output.scan(/__RICH_ARG__([^\r\n]*)/).flatten
  rescue Errno::ENOENT
    missing(name)
  end

  def interactive_command(name, environment)
    completion = File.join(TestSupport::ROOT, "completions", "rich-ri.#{name}").shellescape
    capture = "rich-ri() { printf '__RICH_ARG__%s\\n' \"$@\"; }\nalias ri=rich-ri\n"
    return fish_command(completion) if name == "fish"

    script = "PS1='RICH_READY> '\ncd #{@bin.shellescape}\n"
    if name == "bash"
      script += "source #{bash_completion.shellescape}\n"
      # The line that 0.1.0 documented for an alias, still in many a ~/.bashrc.
      rc = File.join(@bin, "bashrc")
      File.write(rc, "#{script}source #{completion}\n#{capture}complete -o filenames -F _rich_ri ri\n")
      return [name, "--noprofile", "--rcfile", rc, "-i"]
    end

    script += "autoload -Uz compinit\ncompinit -D -u\nbindkey '^I' complete-word\nsource #{completion}\n"
    File.write(File.join(@bin, ".zshrc"), script + capture)
    environment["ZDOTDIR"] = @bin
    # Ubuntu's global zshrc runs compinit before this fixture and may prompt
    # about system directory permissions. Load only our controlled user rc.
    [name, "-d", "-i"]
  end

  def fish_command(completion)
    script = <<~FISH
      function fish_prompt; printf 'RICH_READY> '; end
      function fish_greeting; end
      cd #{@bin.shellescape}
      source #{completion}
      function rich-ri; printf '__RICH_ARG__%s\\n' $argv; end
      alias ri rich-ri
    FISH
    ["fish", "--private", "--no-config", "--interactive", "--init-command", script]
  end
end
