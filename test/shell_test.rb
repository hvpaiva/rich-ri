# frozen_string_literal: true

require "test_helper"
require "shell_harness"

class BashCompletionTest < Minitest::Test
  include ShellHarness

  # What the function answers when bash calls it: its replies, each between
  # brackets, then what it asked of compopt. bash breaks a word at each ":"
  # and "=" outside quotes, hands over the pieces in COMP_WORDS and names, as
  # the second argument, the text it is going to replace.
  ANSWER = <<~'BASH'
    [[ -n $1 ]] && source "$1"
    source "$2/completions/rich-ri.bash"
    asked=()
    compopt() { asked+=("$*"); }
    COMP_TYPE=$3 COMP_LINE=$4 COMP_POINT=$5 COMP_CWORD=$6 COLUMNS=100
    typed=$7
    shift 7
    COMP_WORDS=("$@")
    _rich_ri "${COMP_WORDS[0]}" "$typed" "${COMP_WORDS[COMP_CWORD - 1]}"
    for reply in "${COMPREPLY[@]}"; do printf '[%s]\n' "$reply"; done
    printf -- '--\n'
    for option in "${asked[@]}"; do printf '%s\n' "$option"; done
  BASH

  def test_bash_queries_instance_methods
    replies, = bash_answer("rich-ri --no-standard-docs --doc-dir #{TestSupport::STORE} RichRIExample#ma",
                           "--no-standard-docs", "--doc-dir", TestSupport::STORE, "RichRIExample#ma")

    assert_equal ["RichRIExample#map"], replies
  end

  def test_bash_preserves_page_prefixes_split_by_wordbreaks
    store = TestSupport::STORE
    replies, = bash_answer("rich-ri #{store}:G", store, ":", "G")

    assert_equal ["GUIDE.rdoc"], replies
    replies, asked = bash_answer("rich-ri #{store[0..-2]}", store[0..-2])

    assert_equal ["#{store}:"], replies
    assert_includes asked, "-o nospace"
  end

  def test_bash_supports_equals_values_and_aliases
    result = shell("bash", <<~'BASH', bash_completion, TestSupport::ROOT)
      source "$1"
      source "$2/completions/rich-ri.bash"
      alias ri=rich-ri
      complete -F _rich_ri ri
      COMP_WORDS=(ri --color = a)
      COMP_CWORD=3 COMP_LINE='ri --color=a' COMP_POINT=12
      _rich_ri ri a =
      printf '%s\n' "${COMPREPLY[@]}"
    BASH
    assert_equal %w[always auto], result
  end

  def test_bash_leaves_paths_to_readline
    assert_equal [[], ["+o filenames", "-o default"]], bash_answer("rich-ri --config ~/", "--config", "~/")
    assert_equal [[], ["+o filenames", "-o dirnames"]], bash_answer("rich-ri --doc-dir=do", "--doc-dir", "=", "do")
    assert_equal [[], ["+o filenames"]], bash_answer("rich-ri NoSuchExample", "NoSuchExample")
    assert_equal [["method="], ["+o filenames", "-o nospace"]], bash_answer("rich-ri --style met", "--style", "met")
  end

  def test_bash_replaces_only_what_follows_an_equals_sign_in_a_method_name
    assert_equal [[""], ["+o filenames"]], bash_answer("rich-ri Inkwell#name=", "Inkwell#name", "=", typed: "")
    assert_equal ["", "="], bash_answer("rich-ri Inkwell#==", "Inkwell#", "==", typed: "").first
    assert_equal ["\\~"], bash_answer("rich-ri Inkwell#=~", "Inkwell#", "=", "~").first
    assert_equal [""], bash_answer("rich-ri Inkwell#\\[\\]=", "Inkwell#\\[\\]", "=", typed: "").first
    assert_equal [""], bash_answer("rich-ri 'Inkwell#[]'=", "'Inkwell#[]'", "=", typed: "").first
  end

  def test_bash_quotes_its_replies_for_where_the_word_stands
    assert_equal ["Inkwell#fill", "Inkwell#filled\\?"], bash_answer("rich-ri Inkwell#fi", "Inkwell#fi").first
    assert_equal ["Inkwell#\\<\\<", "Inkwell#\\<=", "Inkwell#\\<=\\>"],
                 bash_answer("rich-ri Inkwell#\\<", "Inkwell#\\<").first
    assert_equal ["Inkwell#<=", "Inkwell#<=>"],
                 bash_answer("rich-ri 'Inkwell#<=", "'Inkwell#<=", typed: "Inkwell#<=").first
    assert_equal ["Inkwell#[]", "Inkwell#[]="],
                 bash_answer("rich-ri \"Inkwell#[", "\"Inkwell#[", typed: "Inkwell#[").first
  end

  def test_bash_completes_without_bash_completion
    # What readline replaces: after the "=" it breaks at, inside the open quote.
    typed = { "=" => "", "'Inkwell#<=" => "Inkwell#<=" }

    { ["rich-ri Inkwell#fi", "Inkwell#fi"] => ["Inkwell#fill", "Inkwell#filled\\?"],
      ["rich-ri Inkwell#name=", "Inkwell#name", "="] => [""],
      ["rich-ri 'Inkwell#<=", "'Inkwell#<="] => ["Inkwell#<=", "Inkwell#<=>"],
      ["rich-ri #{TestSupport::STORE}:G", TestSupport::STORE, ":", "G"] => ["GUIDE.rdoc"],
      ["rich-ri --color=a", "--color", "=", "a"] => %w[always auto],
      ["rich-ri --style=met", "--style", "=", "met"] => ["method="],
      ["rich-ri -a  Inkwell#[]=", "-a", "Inkwell#[]", "="] => [""] }.each do |(line, *pieces), replies|
      replaced = typed.fetch(pieces.last, pieces.last)

      assert_equal replies, bash_answer(line, *pieces, typed: replaced, library: nil).first, line
    end
  end

  def test_bash_without_bash_completion_reads_the_word_under_the_cursor
    line = "rich-ri Inkwell#fi --all"
    replies, = bash_answer(line, "Inkwell#fi", "--all", typed: "Inkwell#fi", point: 18, cword: 1, library: nil)

    assert_equal ["Inkwell#fill", "Inkwell#filled\\?"], replies
    replies, = bash_answer("rich-ri --color=always", "--color", "=", "always", typed: "a", point: 17, library: nil)

    assert_equal %w[always auto], replies
    replies, asked = bash_answer("rich-ri Inkwell > pa", "Inkwell", ">", "pa", library: nil)

    assert_empty replies
    assert_equal ["-o default"], asked
  end

  private

  # The replies and the compopt calls for a line whose pieces are the ones bash
  # would break it into, the last being completed unless cword says otherwise.
  # The library is bash-completion, or nil to do without.
  def bash_answer(line, *pieces, typed: pieces.last, library: bash_completion, **at)
    require_bash
    lines = shell("bash", ANSWER, library.to_s, TestSupport::ROOT, at.fetch(:type, 9).to_s, line,
                  at.fetch(:point, line.length).to_s, at.fetch(:cword, pieces.length).to_s, typed, "rich-ri", *pieces)
    replies, asked = lines.slice_after("--").to_a
    [replies[0...-1].map { |reply| reply[1..-2] }, asked.to_a]
  end
end

# ble.sh runs a completion function shaped like the ones cobra generates in a
# way of its own (patch:cobraV2 in its core-complete.sh): it calls words[0]
# through a function of its own that it can cancel, takes the lines with a
# description for its menu and hands the others back in out. It breaks the
# word at ":" and "=" itself, says in progcomp_prefix what comes before the
# piece being completed, puts it back before every reply and quotes the reply.
# ble.sh does not run in CI, so ANSWER does the same in plain bash.
class BleCompletionTest < Minitest::Test
  include ShellInsertion

  ANSWER = <<~'BASH'
    source "$1/completions/rich-ri.bash"
    marker=$2
    BLE_ATTACHED=1 COMP_TYPE=9 COMP_LINE=$3 COMP_POINT=${#3} progcomp_prefix=$4
    shift 4
    COMP_WORDS=("$@") COMP_CWORD=$(( $# - 1 ))
    asked=() yielded=()
    compopt() { asked+=("$*"); }
    invoke() { : >"$marker"; "${orig_words[0]}" "$@"; }

    eval "ble_original_$(declare -f __rich_ri_get_completion_results)"
    __rich_ri_get_completion_results() {
        local -a orig_words=("${words[@]}")
        local -a words=(invoke "${orig_words[@]:1}")
        ble_original___rich_ri_get_completion_results
    }
    eval "ble_original_$(declare -f __rich_ri_handle_completion_types)"
    __rich_ri_handle_completion_types() {
        local lines line unprocessed=()
        for lines in "${out[@]}"; do
            while IFS= read -r line; do
                if [[ $line == *$'\t'* ]]; then
                    [[ ${line%%$'\t'*} == "$cur"* ]] && yielded+=("${line%%$'\t'*}")
                elif [[ -n $line ]]; then
                    unprocessed+=("$line")
                fi
            done <<<"$lines"
        done
        if (( ${#unprocessed[@]} )); then
            out=("${unprocessed[@]}")
            ble_original___rich_ri_handle_completion_types
        fi
    }

    __start_rich_ri "${COMP_WORDS[0]}" "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD - 1]}"
    if [[ -e $marker ]]; then echo invoked; else echo direct; fi
    for line in "${yielded[@]}"; do printf '%s\n' "$line"; done
    echo --
    for line in "${COMPREPLY[@]}"; do printf '%s\n' "$line"; done
    echo --
    for line in "${asked[@]}"; do printf '%s\n' "$line"; done
  BASH

  NO_FALLBACK = ["+o filenames", "-o ble/no-default -o ble/no-mark-directories"].freeze

  def test_the_script_has_the_shape_ble_sh_patches
    script = File.read(File.join(TestSupport::ROOT, "completions/rich-ri.bash"))

    assert_includes script, "complete -F __start_rich_ri rich-ri"
    assert_includes script, "__rich_ri_get_completion_results() {"
    assert_includes script, "__rich_ri_handle_completion_types() {"
    refute_includes script, "_extract_activeHelp"
  end

  def test_ble_sh_runs_the_command_and_lists_the_described_candidates_itself
    assert_equal ["invoked", %w[--color=always --color=auto], [], NO_FALLBACK],
                 ble_answer("rich-ri --color=a", "--color=", "--color", "=", "a")
  end

  def test_names_come_back_without_what_ble_sh_puts_before_them
    assert_equal ["invoked", [], ["GUIDE.rdoc"], NO_FALLBACK],
                 ble_answer("rich-ri #{TestSupport::STORE}:G", "#{TestSupport::STORE}:", TestSupport::STORE, ":", "G")
    assert_equal ["invoked", [], ["Inkwell#fill", "Inkwell#filled?"], NO_FALLBACK],
                 ble_answer("rich-ri Inkwell#fi", "", "Inkwell#fi")
  end

  def test_an_answer_without_candidates_turns_off_the_file_names_of_ble_sh
    assert_equal ["invoked", [], [], NO_FALLBACK], ble_answer("rich-ri NoSuchExample", "", "NoSuchExample")
  end

  def test_ble_sh_inserts_a_page_of_a_gem_given_in_two_steps
    environment = TestSupport.gem_environment.merge("RI" => "--no-system --no-site --no-home")
    result = ble_arguments(["RICH_READY> ", "rich-ri inkwell-n\t"], ["native:", "B\t"], ["UILDING.rdoc", "\r"],
                           env: environment)

    assert_equal ["inkwell-native:BUILDING.rdoc"], result, @terminal_output
  end

  def test_ble_sh_inserts_a_name_as_it_is_and_not_as_a_directory
    FileUtils.mkdir_p(File.join(@bin, "RichRIExample"))

    assert_equal ["Inkwell#filled?"], ble_arguments(["RICH_READY> ", "rich-ri Inkwell#fille\t"], ["d\\? ", "\r"]),
                 @terminal_output
    assert_equal ["RichRIExample"], ble_arguments(["RICH_READY> ", "rich-ri RichRIExam\t"], ["ple ", "\r"]),
                 @terminal_output
  end

  def test_ble_sh_inserts_no_file_name_for_a_name_it_does_not_know
    FileUtils.mkdir_p(File.join(@bin, "NoSuchExample"))
    result = ble_arguments(["RICH_READY> ", "rich-ri NoSuchExam"], %W[NoSuchExam \t], %W[\a \r])

    assert_equal ["NoSuchExam"], result, @terminal_output
  end

  private

  # How the command was reached, the candidates ble.sh took, the replies and
  # the compopt calls.
  def ble_answer(line, prefix, *pieces)
    require_bash
    marker = File.join(@bin, "invoked")
    FileUtils.rm_f(marker)
    reached, *rest = shell("bash", ANSWER, TestSupport::ROOT, marker, line, prefix, "rich-ri", *pieces)
    [reached, *["--", *rest].slice_before("--").map { |part| part.drop(1) }]
  end
end

class ZshCompletionTest < Minitest::Test
  include ShellHarness

  # What the function hands to the completion system of zsh.
  ANSWER = <<~ZSH
    compdef() { :; }
    source "$1/completions/rich-ri.zsh"
    compadd() { print -r -- "compadd ${(j: :)${(@q-)@}}" }
    compset() { print -r -- "compset ${(j: :)${(@q-)@}}" }
    _files() { print -r -- "_files $*" }
    shift
    words=(rich-ri "$@")
    CURRENT=${#words}
    _rich_ri
  ZSH

  def test_zsh_handles_method_names_and_descriptions
    assert_equal ["compadd -d descriptions -- 'RichRIExample#map'"], zsh_answer("RichRIExample#ma")
    assert_equal ["compadd -d descriptions -- 'Inkwell#name='"], zsh_answer("Inkwell#name=")
    assert_equal ["compadd -d descriptions -- 'Inkwell#<=' 'Inkwell#<=>'"], zsh_answer("'Inkwell#<=")
    assert_equal ["compadd -d descriptions -- --color=always --color=auto"], zsh_answer("--color=a")
    assert_equal ["compadd -d descriptions --"], zsh_answer("NoSuchExample")
  end

  def test_zsh_adds_no_space_to_a_word_to_be_continued_and_leaves_paths_to_the_shell
    assert_equal ["compadd -S '' -d descriptions -- method="], zsh_answer("--style", "met")
    assert_equal ["compadd -S '' -d descriptions -- #{TestSupport::STORE}:"], zsh_answer(TestSupport::STORE[0..-2])
    assert_equal ["compset -P '--[^=]#='", "_files "], zsh_answer("--config", "~/")
    assert_equal ["compset -P '--[^=]#='", "_files -/"], zsh_answer("--doc-dir=do")
  end

  private

  def zsh_answer(*)
    shell("zsh", ANSWER, TestSupport::ROOT, *)
  end
end

class FishCompletionTest < Minitest::Test
  include ShellHarness

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

  def test_fish_completes_paths_by_itself_and_offers_nothing_for_an_unknown_name
    FileUtils.mkdir_p(File.join(@bin, "docs spaced"))
    File.write(File.join(@bin, "settings.yml"), "theme: terminal\n")
    result = shell("fish", <<~FISH, TestSupport::ROOT, @bin)
      source "$argv[2]/completions/rich-ri.fish"
      cd $argv[3]
      complete -C 'rich-ri --doc-dir do'
      complete -C 'rich-ri --doc-dir=do'
      complete -C 'rich-ri --config se'
      complete -C 'rich-ri --doc-dir se'
      complete -C 'rich-ri NoSuchExample'
      complete -C 'rich-ri setti'
    FISH
    assert_equal(["docs spaced/", "--doc-dir=docs spaced/", "settings.yml"],
                 result.map { |line| line.split("\t").first })
  end
end

class ShellInsertionTest < Minitest::Test
  include ShellInsertion

  def test_bash_inserts_completed_alias_method_and_quoted_directory
    check_insertion("bash")
  end

  def test_zsh_inserts_completed_alias_method_and_quoted_directory
    check_insertion("zsh")
  end

  def test_fish_inserts_completed_alias_method_and_quoted_directory
    check_insertion("fish")
  end

  def test_bash_inserts_names_that_no_shell_takes_unquoted
    check_names("bash")
  end

  def test_bash_inserts_without_bash_completion
    check_names("bash", library: nil)

    assert_equal ["--theme=dark"], inserted_arguments("bash", "rich-ri --theme=da", library: nil), @terminal_output
    assert_equal ["--doc-dir", "#{@bin}/docs spaced/"],
                 inserted_arguments("bash", "rich-ri --doc-dir ~/doc", library: nil), @terminal_output
  end

  def test_zsh_inserts_names_that_no_shell_takes_unquoted
    check_names("zsh")
  end

  def test_fish_inserts_names_that_no_shell_takes_unquoted
    check_names("fish")
  end

  private

  def check_insertion(name)
    assert_equal ["RichRIExample#ready?"], inserted_arguments(name, "ri RichRIExample#rea"), @terminal_output
    assert_equal ["RichRIExample#[]"], inserted_arguments(name, "ri 'RichRIExample#["), @terminal_output
    directory = File.join(@bin, "docs spaced")

    ["rich-ri --doc-dir '#{@bin}/docs s'", "rich-ri --doc-dir ~/doc"].each do |line|
      assert_equal ["--doc-dir", directory], inserted_arguments(name, line).map { |word| word.delete_suffix("/") },
                   @terminal_output
    end
    FileUtils.cp_r(Dir["#{TestSupport::STORE}/*"], directory)
    result = inserted_arguments(name, "ri --no-standard-docs --doc-dir '#{directory}' RichRIExample#rea")

    assert_equal ["--no-standard-docs", "--doc-dir", directory, "RichRIExample#ready?"], result, @terminal_output
    result = inserted_arguments(name, "rich-ri --config '#{@bin}/settings s'")

    assert_equal ["--config", File.join(@bin, "settings spaced.yml")], result, @terminal_output
    { "rich-ri --theme=da" => ["--theme=dark"], "rich-ri --style met" => ["--style", "method="],
      "rich-ri --style=met" => ["--style=method="] }.each do |line, arguments|
      assert_equal arguments, inserted_arguments(name, line), @terminal_output
    end
  end

  # Operators end in characters at which a shell breaks words or that it reads
  # as its own; a class can have the name of a directory, and a gem be given in
  # two steps, before and after its colon.
  def check_names(name, **)
    { "rich-ri Inkwell#name=" => "Inkwell#name=", "rich-ri 'Inkwell#name=" => "Inkwell#name=",
      "rich-ri Inkwell#=~" => "Inkwell#=~", "rich-ri 'Inkwell#<=>" => "Inkwell#<=>",
      "rich-ri Inkwell#fil" => "Inkwell#fill", "rich-ri RichRIExam" => "RichRIExample",
      "rich-ri #{TestSupport::STORE[0..-2]}\tG" => "#{TestSupport::STORE}:GUIDE.rdoc",
      "rich-ri NoSuchExam" => "NoSuchExam" }.each do |line, argument|
      assert_equal [argument], inserted_arguments(name, line, **), "#{line.inspect}\n#{@terminal_output}"
    end
    environment = TestSupport.gem_environment.merge("RI" => "--no-system --no-site --no-home")
    result = inserted_arguments(name, "rich-ri inkwell-n\tB", env: environment, **)

    assert_equal ["inkwell-native:BUILDING.rdoc"], result, @terminal_output
  end
end
