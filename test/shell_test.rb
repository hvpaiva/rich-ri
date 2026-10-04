# frozen_string_literal: true

require "test_helper"

class ShellTest < Minitest::Test
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

  private

  def bash_completion
    # Homebrew's profile.d wrapper returns early in noninteractive shells.
    paths = %w[/usr/share/bash-completion/bash_completion /opt/homebrew/share/bash-completion/bash_completion
               /usr/local/share/bash-completion/bash_completion]
    completion = paths.find { |path| File.file?(path) }

    refute_nil completion, "Install bash-completion 2.x"
    completion
  end
end
