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

  def require_bash
    return if ShellSupport.bash?

    flunk "bash is required" if ENV["RICH_RI_REQUIRE_SHELLS"]
    skip "bash 4 or later is not installed; CI runs all shell tests"
  end

  def bash_completion
    completion = ShellSupport.bash_completion
    return completion if completion

    flunk "bash-completion 2.x with a compatible bash is required" if ENV["RICH_RI_REQUIRE_SHELLS"]
    skip "bash-completion 2.x with a compatible bash is unavailable; CI runs all shell tests"
  end
end

# Types a line into an interactive shell, presses Tab and reads the words passed to rich-ri. Its
# home holds a directory and a file with spaces in their names, and directories named like a class.
module ShellInsertion
  include ShellHarness
  include TerminalTestSupport

  # ble.sh, a line editor for bash, where it installs itself.
  BLE = File.join(ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local/share")), "blesh/ble.sh")

  private

  def inserted_arguments(name, line, env: {}, **)
    ["docs spaced", "RichRIExample", "NoSuchExample"].each { |directory| FileUtils.mkdir_p(File.join(@bin, directory)) }
    File.write(File.join(@bin, "settings spaced.yml"), "theme: terminal\n")
    environment = @env.merge("HOME" => @bin, "HISTFILE" => File::NULL, "XDG_CONFIG_HOME" => File.join(@bin, "config"),
                             "XDG_DATA_HOME" => File.join(@bin, "data")).merge(env)
    command = interactive_command(name, environment, **)
    input = [["RICH_READY> ", "#{line}\t\nexit\n"]]
    input.unshift(["RICH_START> ", " source #{File.join(@bin, 'bashrc').shellescape}\n"]) if name == "bash"
    output, status = terminal(*command, env: environment, input: input)
    @terminal_output = output

    assert_equal 0, status, output
    output.scan(/__RICH_ARG__([^\r\n]*)/).flatten
  rescue Errno::ENOENT
    missing(name)
  end

  def interactive_command(name, environment, library: :bash_completion, fpath: nil)
    completion = File.join(TestSupport::ROOT, "completions", "rich-ri.#{name}").shellescape
    capture = "rich-ri() { printf '__RICH_ARG__%s\\n' \"$@\"; }\nalias ri=rich-ri\n"
    return fish_command(completion) if name == "fish"

    script = "PS1='RICH_READY> '\ncd #{@bin.shellescape}\n"
    if name == "bash"
      require_bash
      script += "source #{bash_completion.shellescape}\n" if library
      # The line that 0.1.0 documented for an alias, still in many a ~/.bashrc.
      script += "source #{completion}\n#{capture}complete -o filenames -F _rich_ri ri\n"
      File.write(File.join(@bin, "bashrc"), script)
      # Some systems load bash-completion in the system bashrc, which bash reads before the file it
      # is given; it reads none and is then told to source this one.
      environment["PS1"] = "RICH_START> "
      return [name, "--noprofile", "--norc", "-i"]
    end

    script += "fpath=(#{fpath.shellescape} $fpath)\n" if fpath
    script += "autoload -Uz compinit\ncompinit -D -u\nbindkey '^I' complete-word\n"
    script += "source #{completion}\n" unless fpath
    File.write(File.join(@bin, ".zshrc"), script + capture)
    environment["ZDOTDIR"] = @bin
    # Ubuntu's global zshrc runs compinit before this fixture and may prompt
    # about system directory permissions. Load only our controlled user rc.
    [name, "-d", "-i"]
  end

  # ble.sh drops a completion when a key arrives while it runs, so the key after a Tab waits for
  # what the Tab changed: the text inserted, or the bell for nothing.
  def ble_arguments(*steps, env: {})
    skip "ble.sh is not installed" unless File.file?(BLE)
    require_bash
    directories = { "XDG_RUNTIME_DIR" => "run", "XDG_CACHE_HOME" => "cache", "XDG_STATE_HOME" => "state",
                    "XDG_CONFIG_HOME" => "config" }.transform_values { |name| File.join(@bin, name) }
    directories.each_value { |directory| FileUtils.mkdir_p(directory, mode: 0o700) }
    environment = @env.merge("HOME" => @bin, "HISTFILE" => File::NULL, "INPUTRC" => File::NULL,
                             "PS1" => "RICH_START> ", **directories, **env)
    # Enter is a carriage return: ble.sh runs the line for it, not for a line feed.
    input = [["RICH_START> ", " source #{ble_rc.shellescape}\r"], *steps, ["__RICH_ARG__", "exit\r"]]
    output, status = terminal("bash", "--noprofile", "--norc", "-i", env: environment, input: input)
    @terminal_output = output

    assert_equal 0, status, output
    output.scan(/__RICH_ARG__([^\r\n]*)/).flatten
  end

  def ble_rc
    library = ShellSupport.bash_completion
    File.join(@bin, "blerc").tap do |rc|
      File.write(rc, <<~BASH)
        source -- #{BLE.shellescape} --noattach
        PS1='RICH_READY> '
        cd #{@bin.shellescape}
        #{"source #{library.shellescape}" if library}
        source #{File.join(TestSupport::ROOT, 'completions/rich-ri.bash').shellescape}
        rich-ri() { printf '__RICH_ARG__%s\\n' "$@"; }
        # Without colors a menu shows each name as one piece of text to wait for.
        bleopt complete_auto_complete= highlight_syntax= edit_bell=abell complete_menu_color= complete_menu_color_match=
        ble-attach
      BASH
    end
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
