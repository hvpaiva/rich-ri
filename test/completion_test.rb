# frozen_string_literal: true

require "test_helper"
require "command_helper"

class CompletionTest < Minitest::Test
  def test_ri_option_terminator_does_not_hide_explicit_sources
    with_environment("RI" => "--no-standard-docs --") do
      out, err, status = cli("--complete", "--no-config", "--no-standard-docs", "--doc-dir", TestSupport::STORE,
                             "RichRIExample#ma", docs: false, env: { "RI" => "--no-standard-docs --" })

      assert_predicate status, :success?, err
      assert_includes out, "RichRIExample#map"
    end
  end

  def values(*words)
    RichRI::Completion.new.answer(words).candidates.map(&:first)
  end

  def test_options_have_descriptions_for_both_boolean_forms
    candidates = RichRI::Completion.new.answer(["--"]).candidates

    assert(candidates.all? { |_value, desc| !desc.empty? })
    %w[--all --no-all --interactive --no-interactive --color= --completion --man
       --config --no-config --config-path --show-config --theme --color-depth --style --bat-theme --shell-theme
       --pager-command].each do |flag|
      assert_includes candidates.map(&:first), flag
    end
  end

  def test_values_match_the_option_context
    assert_equal ["--color=always", "--color=auto"], values("--color=a")
    assert_equal ["--color=never"], values("--color=n")
    assert_equal ["markdown"], values("-f", "mark")
    assert_equal ["--completion=bash"], values("--completion=b")
    assert_empty values("--width", "")
    assert_empty values("--dump", "")
  end

  def test_long_option_prefixes_complete_but_finished_abbreviations_do_not_select_sources
    assert_equal ["--config", "--config-path"], values("--confi")
    defaults = ["--no-standard-docs", "--doc-dir", TestSupport::STORE].shelljoin
    cases = [
      [["--no-conf"], defaults],
      [["--doc-d", TestSupport::STORE], defaults],
      [["--doc-d=#{TestSupport::STORE}"], defaults],
      [[], "#{defaults} --wid=44"]
    ]
    cases.each do |arguments, ri|
      out, err, status = cli("--complete", *arguments, "RichRIExample#ma", docs: false, env: { "RI" => ri })

      assert_predicate status, :success?, err
      assert_equal ":\n", out
      assert_empty err
    end
    assert_includes values("--no-standard-docs", "--doc-dir", TestSupport::STORE,
                           "--pager-command", "--confi=just-a-value", "RichRIExample#ma"), "RichRIExample#map"
  end

  def test_dynamic_classes_and_methods_use_the_selected_store
    args = ["--no-standard-docs", "--doc-dir", TestSupport::STORE]

    assert_includes values(*args, "RichRIExample#ma"), "RichRIExample#map"
    assert_includes values(*args, "RichRIExample.bu"), "RichRIExample.build"
    assert_includes values(*args, "RichRIExample"), "RichRIExample#"
    assert_includes values(*args, "RichRIExample::"), "RichRIExample::Nested"
    assert_empty values(*args, "NoSuchExample123")
    assert_includes values(*args, "--color", "RichRIExample#ma"), "RichRIExample#map"
  end

  def test_names_are_offered_only_where_the_command_line_takes_them
    args = ["--no-standard-docs", "--doc-dir", TestSupport::STORE]

    assert_includes values(*args, "--no-interactive", "RichRIExample#ma"), "RichRIExample#map"
    assert_includes values(*args, "--no-interactive", ""), "RichRIExample"
    assert_includes values(*args, "--list", "Rich"), "RichRIExample"
    assert_raises(RichRI::UsageError) { values(*args, "--interactive", "RichRIExample#ma") }
    assert_raises(RichRI::UsageError) { values(*args, "--man", "--list", "Rich") }
    out, err, status = cli("--complete", *args, "--interactive", "RichRIExample#ma", docs: false)

    assert_predicate status, :success?, err
    assert_equal ":\n", out
    assert_empty err
  end

  def test_ri_source_defaults_match_lookup_and_ignore_actions_during_completion
    defaults = ["--no-standard-docs", "--doc-dir", TestSupport::STORE].shelljoin
    lookup, err, status = cli("RichRIExample#map", docs: false, env: { "RI" => defaults })

    assert_predicate status, :success?, err
    assert_includes lookup, "Return transformed values."
    ["--server --profile", "--dump=/missing", "--man", "--list-doc-dirs"].each do |action|
      out, err, status = cli("--complete", "RichRIExample#ma", docs: false, env: { "RI" => "#{defaults} #{action}" })

      assert_predicate status, :success?, err
      assert_empty err
      assert_equal "RichRIExample#map\t\n:\n", out, action
    end
  end

  def test_explicit_sources_follow_ri_defaults
    environment = TestSupport.gem_environment.merge("RI" => "--no-standard-docs --no-gems")
    out, err, status = cli("--complete", "inkwell-n", docs: false, env: environment)

    assert_predicate status, :success?, err
    assert_equal ":\n", out
    out, err, status = cli("--complete", "--gems", "inkwell-n", docs: false, env: environment)

    assert_predicate status, :success?, err
    assert_equal "inkwell-native:\t\n:nospace\n", out
    with_environment("RI" => "--no-standard-docs --no-gems") do
      assert_includes values("--doc-dir", TestSupport::STORE, "RichRIExample#ma"), "RichRIExample#map"
    end
  end

  def test_names_holding_terminal_controls_are_not_candidates
    with_cached_names(modules: ["RichRIUnsafe\e[31m"], methods: ["ma\ax"], pages: ["GUIDE\u202e.rdoc"]) do |sources|
      instance = RichRI::Driver.new(RichRI::Options.new.parse(sources, defaults: "").driver_options)

      assert_equal %w[RichRIExample], instance.complete("RichRI")
      assert_equal %w[RichRIExample#map], instance.complete("RichRIExample#ma")
      assert_equal ["#{sources.last}:GUIDE.rdoc"], instance.complete("#{sources.last}:GUIDE")
    end
  end

  def test_page_completion_and_missing_sources
    instance = driver
    store = instance.stores.first
    store.type = :system

    assert_includes instance.complete("ruby:G"), "ruby:GUIDE.rdoc"
    assert_includes instance.complete("rub"), "ruby:"
    assert_empty instance.complete("missing:GUIDE")
  end
end

class CompletionProtocolTest < Minitest::Test
  include CommandSupport

  def test_protocol_discards_terminal_controls_in_values_and_descriptions
    completion_class = Class.new(RichRI::Completion) do
      def answer(_words)
        RichRI::Completion::Answer.new([["Valid", "Description"], ["Bad\u009bName", ""], ["Bad\u202eName", ""],
                                        ["Other", "bad\ttext"], ["Two\nlines", ""]], "nospace")
      end
    end
    output = StringIO.new
    completion_class.new.write([], output)

    assert_equal "Valid\tDescription\n:nospace\n", output.string
  end

  def test_the_name_of_a_file_or_directory_is_left_to_the_shell
    { ["--config", ""] => "files", ["--config", "~/.config/ri"] => "files", ["--config=$HOME/"] => "files",
      ["--dump", "cache"] => "files", ["--dump="] => "files", ["-d", "~/"] => "directories",
      ["--doc-dir", "docs [one"] => "directories", ["--doc-dir=do"] => "directories",
      ["-ad", ""] => "directories", ["--install-man=/usr/"] => "directories" }.each do |words, action|
      answer = RichRI::Completion.new.answer(words)

      assert_empty answer.candidates, words.inspect
      assert_equal action, answer.action, words.inspect
    end
    assert_equal ":directories\n", cli("--complete", "--shell=bash", "--doc-dir", "'docs d", docs: false).first
    assert_equal ":files\n", cli("--complete", "--config=", docs: false).first
  end

  def test_only_options_follow_install_man_and_a_plain_value_has_no_candidates
    assert_equal ":\n", cli("--complete", "--no-standard-docs", "--install-man", "/usr/do", docs: false).first
    assert_equal ":\n", cli("--complete", "--doc-dir", TestSupport::STORE, "--install-man", "Rich", docs: false).first
    assert_equal "--no-color\tPlain text with the same page layout.\n:\n",
                 cli("--complete", "--install-man", "--no-col", docs: false).first
    assert_equal ":\n", cli("--complete", "--width", "", docs: false).first
    assert_equal ":\n", cli("--complete", "--pager-command", "RichRIExample", docs: false).first
  end

  def test_a_lone_candidate_that_only_starts_a_word_asks_for_no_space
    sources = ["--no-standard-docs", "--doc-dir", TestSupport::STORE]
    { ["--style", "met"] => "nospace", ["--style=hea"] => "nospace", ["--color="] => nil, ["--color-d"] => nil,
      [*sources, "RichRIExample#rea"] => nil, [*sources, "RichRIExample::N"] => nil, [*sources, "RichRIExample"] => nil,
      [*sources, "RichRIExample.bu"] => nil, [*sources, TestSupport::STORE[0..-3]] => "nospace",
      [*sources, "RichRIEx"] => nil, ["--completion=b"] => nil }.each do |words, action|
      answer = RichRI::Completion.new.answer(words)

      refute_empty answer.candidates, words.inspect
      action ? assert_equal(action, answer.action, words.inspect) : assert_nil(answer.action, words.inspect)
    end
    gems = ["--no-system", "--no-site", "--no-home"]

    { "Inkwell#name=" => "Inkwell#name=\t\n:\n", "Inkwell#[]" => "Inkwell#[]\t\nInkwell#[]=\t\n:\n",
      "Inkwell#=~" => "Inkwell#=~\t\n:\n", "inkwell-2" => "inkwell-2:\t\n:nospace\n" }.each do |name, expected|
      assert_equal expected, cli("--complete", *gems, name, docs: false, env: TestSupport.gem_environment).first
    end
  end

  def test_bash_dequoting_handles_unclosed_quotes_without_evaluating_substitutions
    completion_class = Class.new(RichRI::Completion) do
      def answer(words)
        RichRI::Completion::Answer.new(words.map { |word| [word, ""] }, nil)
      end
    end
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "executed")
      output = StringIO.new
      words = ["--shell=bash", "'open quote", '"double quote"', "path\\ with\\ spaces", "$(touch #{marker})"]
      completion_class.new.write(words, output)

      assert_equal(["open quote", "double quote", "path with spaces", "$(touch #{marker})", ":\n"],
                   output.string.lines.map { |line| line.split("\t").first })
      refute_path_exists marker
    end
  end

  def test_protocol_is_quiet_on_invalid_sources_and_ignores_ri_actions
    out, err, status = cli("--complete", "--doc-dir=/no/such/directory", "X", docs: false)

    assert_predicate status, :success?, err
    assert_equal ":\n", out
    assert_empty err
    hostile_defaults = { "RI" => "--server --dump=/no/such/cache" }
    out, err, status = cli("--complete", "--no-standard-docs", "--", "--h", docs: false, env: hostile_defaults)

    assert_predicate status, :success?, err
    assert_equal ":\n", out
  end

  def test_a_defect_while_reading_the_options_offers_nothing_instead_of_other_candidates
    defect = "require 'optparse'\nclass OptionParser; def permute(*) = nil.size!; end\n"
    words = ["--complete", "--no-standard-docs", "--doc-dir", TestSupport::STORE, "RichRIExample#ma"]
    out, err, status = with_planted(defect) { |env| cli(*words, docs: false, env: env) }

    assert_predicate status, :success?, err
    assert_equal ":\n", out
    assert_empty err
  end

  def test_flag_protocol_includes_descriptions
    out, err, status = cli("--complete", "--no-all", docs: false)

    assert_predicate status, :success?, err
    assert_equal "--no-all\tInclude all methods in a class page.\n:\n", out
  end
end

class CommandLineCompletionTest < Minitest::Test
  def values(*words)
    RichRI::Completion.new.answer(words).candidates.map(&:first)
  end

  def test_names_are_not_offered_for_a_command_line_the_lookup_refuses
    sources = ["--no-standard-docs", "--doc-dir", TestSupport::STORE]
    usage = "\nRun rich-ri --help for usage.\n"
    width = "must be an integer from 20 to 10000, not"
    theme = "--theme must be one of terminal, dark, light, not \"nope\""
    refused = {
      [["-x"], {}] => [2, "invalid option: -x#{usage}"], [["--bogus"], {}] => [2, "invalid option: --bogus#{usage}"],
      [["--width=abc"], {}] => [2, "--width #{width} \"abc\"#{usage}"],
      [["--width", "5"], {}] => [2, "--width #{width} \"5\"#{usage}"],
      [["--theme=nope"], {}] => [2, "#{theme}#{usage}"], [["-ax"], {}] => [2, "invalid option: -x#{usage}"],
      [["--install-man=#{TestSupport::TEMP}/man1"], {}] =>
        [2, "--install-man does not accept lookup names; use --install-man=DIR#{usage}"],
      [[], { "RI" => "-x" }] => [1, "RI: invalid option: -x\n"],
      [[], { "RI" => "--width=abc" }] => [1, "RI: --width #{width} \"abc\"\n"],
      [[], { "RI" => "--theme=nope" }] => [1, "RI: #{theme}\n"],
      [[], { "RI" => "--server --dump=/missing" }] => [1, "RI: --server and --dump cannot be used together\n"],
      [[], { "RICH_RI_WIDTH" => "abc" }] => [1, "RICH_RI_WIDTH #{width} \"abc\"\n"]
    }
    refused.each do |(words, environment), (code, message)|
      _out, err, status = cli(*sources, *words, "RichRIExample#map", docs: false, env: environment)

      assert_equal code, status.exitstatus, [words, environment].inspect
      assert_equal "rich-ri: #{message}", err
      out, err, status = cli("--complete", *sources, *words, "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_equal ":\n", out, [words, environment].inspect
      assert_empty err
    end
    assert_equal "RichRIExample#map\t\n:\n", cli("--complete", *sources, "-a", "RichRIExample#ma", docs: false).first
  end

  def test_the_word_after_an_option_is_its_value_only_where_the_parser_takes_it
    sources = ["--no-standard-docs", "--doc-dir", TestSupport::STORE]

    assert_includes values("--server", "--doc"), "--doc-dir"
    assert_includes values(*sources, "--server", "RichRIExample#ma"), "RichRIExample#map"
    assert_includes values(*sources, "--server=8214", "RichRIExample#ma"), "RichRIExample#map"
    assert_empty values("--server=")
    assert_equal %w[dark light terminal], values("-a", "--theme", "")
    assert_equal %w[markdown], values("-af", "mark")
    assert_includes values(*sources, "--pager-command", "--theme", "RichRIExample#ma"), "RichRIExample#map"
    assert_includes values(*sources, "--", "--theme", "RichRIExample#ma"), "RichRIExample#map"
  end

  def test_an_abbreviated_option_before_the_word_is_refused_as_the_lookup_refuses_it
    error = assert_raises(RichRI::UsageError) { values("--no-standard-docs", "--the", "da") }

    assert_equal "invalid option: --the", error.message
  end
end

class ConfigurationCompletionTest < Minitest::Test
  def values(*words)
    RichRI::Completion.new.answer(words).candidates.map(&:first)
  end

  def test_themes_depths_and_style_roles_are_discoverable
    assert_equal %w[dark light terminal], values("--theme", "")
    assert_equal ["--theme=dark"], values("--theme=d")
    assert_equal %w[256 auto basic truecolor], values("--color-depth", "")
    assert_equal ["--color-depth=truecolor"], values("--color-depth=t")
    assert_equal ["method="], values("--style", "met")
    assert_equal ["--style=heading="], values("--style=hea")
    assert_empty values("--style=method=")
    %w[--bat-theme --shell-theme --pager-command].each do |flag|
      assert_empty values(flag, "RichRIExample")
      assert_empty values("#{flag}=RichRIExample")
    end
  end

  def test_config_sources_match_lookup_and_completion_never_runs_actions
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(TestSupport::STORE, File.join(dir, "docs spaced"))
      marker = File.join(dir, "pager-ran")
      config = File.join(dir, "settings.yml")
      File.write(config, { "sources" => disabled_sources, "doc_dirs" => ["docs spaced"],
                           "pager" => ["touch", marker].shelljoin }.to_yaml)
      environment = { "RICH_RI_CONFIG" => config }
      lookup, err, status = cli("RichRIExample#map", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_includes lookup, "Return transformed values."
      ["--server --profile", "--dump=/missing"].each do |action|
        out, err, status = cli("--complete", "RichRIExample#ma", docs: false, env: environment.merge("RI" => action))

        assert_predicate status, :success?, err
        assert_empty err
        assert_equal "RichRIExample#map\t\n:\n", out
      end
      refute_path_exists marker
    end
  end

  def test_config_sources_override_ri_defaults_and_cli_overrides_config
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(TestSupport::STORE, File.join(dir, ".rdoc"))
      config = File.join(dir, "settings.yml")
      File.write(config, { "sources" => disabled_sources.merge("home" => true) }.to_yaml)
      environment = { "HOME" => dir, "RI" => "--no-home", "RICH_RI_CONFIG" => config }
      out, err, status = cli("--complete", "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_empty err
      assert_equal "RichRIExample#map\t\n:\n", out
      out, err, status = cli("--complete", "--pager-command", "--no-home", "RichRIExample#ma",
                             docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_equal "RichRIExample#map\t\n:\n", out
      out, err, status = cli("--complete", "--no-home", "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_empty err
      assert_equal ":\n", out
    end
  end

  def test_invalid_configuration_is_quiet_and_no_config_bypasses_it
    Dir.mktmpdir do |dir|
      config = File.join(dir, "broken.yml")
      File.write(config, "theme: [\n")
      environment = { "RICH_RI_CONFIG" => config }
      out, err, status = cli("--complete", "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_equal ":\n", out
      assert_empty err
      out, err, status = cli("--complete", "--no-config", "--no-standard-docs", "--doc-dir", TestSupport::STORE,
                             "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_empty err
      assert_equal "RichRIExample#map\t\n:\n", out
    end
  end

  private

  def disabled_sources
    %w[system site home gems].to_h { |source| [source, false] }
  end
end
