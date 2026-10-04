# frozen_string_literal: true

require "test_helper"
require "terminal_helper"

class ShellTest < Minitest::Test
  include TerminalTestSupport

  def setup
    @bin = Dir.mktmpdir("rich-ri-bin-")
    File.write(File.join(@bin, "rich-ri"), <<~RUBY)
      #!#{RbConfig.ruby}
      $LOAD_PATH.unshift(#{File.join(TestSupport::ROOT, 'lib').inspect})
      require "rich_ri"
      exit RichRI::CLI.run(ARGV)
    RUBY
    FileUtils.chmod(0o755, File.join(@bin, "rich-ri"))
    @env = TestSupport::ENVIRONMENT.merge("PATH" => "#{@bin}:#{ENV.fetch('PATH')}")
  end

  def teardown
    FileUtils.remove_entry(@bin)
  end

  def shell(name, script, *)
    out, err, status = Open3.capture3(@env, name, "-c", script, "harness", *)

    assert_predicate status, :success?, err
    assert_empty err
    out.lines.map(&:chomp)
  rescue Errno::ENOENT
    flunk "#{name} is required" if ENV["RICH_RI_REQUIRE_SHELLS"]
    skip "#{name} is not installed; CI runs all shell tests"
  end

  def test_bash_queries_instance_methods
    result = shell("bash", <<~'BASH', bash_completion, TestSupport::ROOT, TestSupport::STORE)
      source "$1"
      source "$2/completions/rich-ri.bash"
      COMP_WORDS=(rich-ri --no-standard-docs --doc-dir "$3" RichRIExample#ma)
      COMP_CWORD=4 COMP_LINE="rich-ri --no-standard-docs --doc-dir $3 RichRIExample#ma"
      COMP_POINT=${#COMP_LINE}
      _rich_ri
      printf '%s\n' "${COMPREPLY[@]}"
    BASH
    assert_equal ["RichRIExample#map"], result
  end

  def test_bash_preserves_page_prefixes_split_by_wordbreaks
    result = shell("bash", <<~'BASH', bash_completion, TestSupport::ROOT, TestSupport::STORE)
      source "$1"
      source "$2/completions/rich-ri.bash"
      COMP_WORDS=(rich-ri --no-standard-docs --doc-dir "$3" "$3" : G)
      COMP_CWORD=6 COMP_LINE="rich-ri --no-standard-docs --doc-dir $3 $3:G"
      COMP_POINT=${#COMP_LINE}
      _rich_ri
      printf '%s\n' "${COMPREPLY[@]}"
    BASH
    assert_equal ["GUIDE.rdoc"], result
  end

  def test_bash_supports_equals_values_and_aliases
    result = shell("bash", <<~'BASH', bash_completion, TestSupport::ROOT)
      source "$1"
      source "$2/completions/rich-ri.bash"
      alias ri=rich-ri
      complete -F _rich_ri ri
      COMP_WORDS=(ri --color = a)
      COMP_CWORD=3 COMP_LINE='ri --color=a' COMP_POINT=12
      _rich_ri
      printf '%s\n' "${COMPREPLY[@]}"
    BASH
    assert_equal %w[always auto], result
  end

  def test_zsh_handles_method_names_and_descriptions
    result = shell("zsh", <<~'ZSH', TestSupport::ROOT, TestSupport::STORE)
      compdef() { :; }
      source "$1/completions/rich-ri.zsh"
      compadd() { local arg; while [[ $1 != -- ]]; do shift; done; shift; printf '%s\n' "$@"; }
      words=(rich-ri --no-standard-docs --doc-dir "$2" RichRIExample#ma)
      CURRENT=5
      _rich_ri
    ZSH
    assert_equal ["RichRIExample#map"], result
  end

  def test_fish_runs_actual_completion_with_descriptions
    result = shell("fish", <<~FISH, TestSupport::ROOT)
      source "$argv[2]/completions/rich-ri.fish"
      complete -C 'rich-ri --color=a'
    FISH
    assert_equal ["--color=always\tColor mode", "--color=auto\tColor mode"], result
  end

  def test_fish_falls_back_when_expanded_tokens_are_unavailable
    result = shell("fish", <<~FISH, TestSupport::ROOT, TestSupport::STORE)
      function commandline
        if contains -- -xpc $argv
          return 2
        end
        builtin commandline $argv
      end
      source "$argv[2]/completions/rich-ri.fish"
      complete -C "rich-ri --no-standard-docs --doc-dir '$argv[3]' 'RichRIExample#["
    FISH
    assert_equal ["RichRIExample#[]"], result
  end

  def test_bash_inserts_completed_alias_method_and_quoted_directory
    check_insertion("bash")
  end

  def test_zsh_inserts_completed_alias_method_and_quoted_directory
    check_insertion("zsh")
  end

  def test_fish_inserts_completed_alias_method_and_quoted_directory
    check_insertion("fish")
  end

  private

  def check_insertion(name)
    result = inserted_arguments(name, "ri RichRIExample#rea")

    assert_equal ["RichRIExample#ready?"], result, @terminal_output
    result = inserted_arguments(name, "ri 'RichRIExample#[")

    assert_equal ["RichRIExample#[]"], result, @terminal_output
    directory = File.join(@bin, "docs spaced")
    FileUtils.mkdir_p(directory)

    result = inserted_arguments(name, "rich-ri --doc-dir '#{@bin}/docs s'")

    assert_equal ["--doc-dir", "#{directory}/"], result, @terminal_output
    FileUtils.cp_r(Dir["#{TestSupport::STORE}/*"], directory)
    result = inserted_arguments(name, "ri --no-standard-docs --doc-dir '#{directory}' RichRIExample#rea")

    assert_equal ["--no-standard-docs", "--doc-dir", directory, "RichRIExample#ready?"], result, @terminal_output
  end

  def inserted_arguments(name, line)
    environment = @env.merge("RI" => ["--no-standard-docs", "--doc-dir", TestSupport::STORE].shelljoin,
                             "HOME" => @bin, "HISTFILE" => File::NULL,
                             "XDG_CONFIG_HOME" => File.join(@bin, "config"),
                             "XDG_DATA_HOME" => File.join(@bin, "data"))
    command = interactive_command(name, environment)
    input = "#{line}\t\nexit\n"
    output, status = terminal(*command, env: environment, prompt: "RICH_READY> ", input: input)
    @terminal_output = output

    assert_equal 0, status, output
    output.scan(/__RICH_ARG__([^\r\n]*)/).flatten
  rescue Errno::ENOENT
    flunk "#{name} is required" if ENV["RICH_RI_REQUIRE_SHELLS"]
    skip "#{name} is not installed; CI runs all shell tests"
  end

  def interactive_command(name, environment)
    completion = File.join(TestSupport::ROOT, "completions", "rich-ri.#{name}").shellescape
    setup = File.join(@bin, name == "zsh" ? ".zshrc" : "#{name}rc")
    if name == "fish"
      script = <<~FISH
        function fish_prompt; printf 'RICH_READY> '; end
        function fish_greeting; end
        source #{completion}
        function rich-ri; printf '__RICH_ARG__%s\\n' $argv; end
        alias ri rich-ri
      FISH
      return [name, "--private", "--no-config", "--interactive", "--init-command", script]
    end

    script = +"PS1='RICH_READY> '\n"
    script << if name == "bash"
                "source #{bash_completion.shellescape}\n"
              else
                "autoload -Uz compinit\ncompinit -D -u\nbindkey '^I' complete-word\n"
              end
    script << "source #{completion}\nrich-ri() { printf '__RICH_ARG__%s\\n' \"$@\"; }\nalias ri=rich-ri\n"
    script << "complete -o filenames -F _rich_ri ri\n" if name == "bash"
    File.write(setup, script)
    return [name, "--noprofile", "--rcfile", setup, "-i"] if name == "bash"

    environment["ZDOTDIR"] = @bin
    [name, "-i"]
  end

  def bash_completion
    # Homebrew's profile.d wrapper returns early in noninteractive shells.
    paths = %w[/usr/share/bash-completion/bash_completion /opt/homebrew/share/bash-completion/bash_completion
               /usr/local/share/bash-completion/bash_completion]
    completion = paths.find { |path| File.file?(path) }

    refute_nil completion, "Install bash-completion 2.x"
    completion
  end
end
