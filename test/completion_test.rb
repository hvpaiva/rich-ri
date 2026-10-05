# frozen_string_literal: true

require "test_helper"

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
    RichRI::Completion.new.candidates(words).map(&:first)
  end

  def test_options_have_descriptions_for_both_boolean_forms
    candidates = RichRI::Completion.new.candidates(["--"])

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
      assert_empty out
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
    assert_empty out
    assert_empty err
  end

  def test_ri_source_defaults_match_lookup_and_ignore_actions_during_completion
    defaults = ["--no-standard-docs", "--doc-dir", TestSupport::STORE].shelljoin
    lookup, err, status = cli("RichRIExample#map", docs: false, env: { "RI" => defaults })

    assert_predicate status, :success?, err
    assert_includes lookup, "Return transformed values."
    environment = { "RI" => "#{defaults} --server --dump=/missing --profile" }
    out, err, status = cli("--complete", "RichRIExample#ma", docs: false, env: environment)

    assert_predicate status, :success?, err
    assert_empty err
    assert_equal "RichRIExample#map\t\n", out
  end

  def test_explicit_sources_follow_ri_defaults
    with_environment("RI" => "--no-standard-docs --no-gems") do
      completion = RichRI::Completion.new
      args = completion.send(:source_arguments, Shellwords.split(ENV.fetch("RI")) + ["--gems"])
      options = RichRI::Options.new.parse(args, defaults: "").driver_options

      assert options[:use_gems]
      refute options[:use_system]
      assert_includes values("--doc-dir", TestSupport::STORE, "RichRIExample#ma"), "RichRIExample#map"
    end
  end

  def test_protocol_discards_terminal_controls_in_values_and_descriptions
    completion_class = Class.new(RichRI::Completion) do
      def candidates(_words)
        [["Valid", "Description"], ["Bad\u009bName", ""], ["Bad\u202eName", ""], ["Other", "bad\ttext"]]
      end
    end
    output = StringIO.new
    completion_class.new.write([], output)

    assert_equal "Valid\tDescription\n", output.string
  end

  def test_page_completion_and_missing_sources
    instance = driver
    store = instance.stores.first
    store.type = :system

    assert_includes instance.complete("ruby:G"), "ruby:GUIDE.rdoc"
    assert_includes instance.complete("rub"), "ruby:"
    assert_empty instance.complete("missing:GUIDE")
  end

  def test_directory_completion_keeps_spaces_and_handles_glob_characters
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "docs [one]"))

      assert_equal ["#{dir}/docs [one]/"], values("-d", "#{dir}/docs [")
      assert_equal ["--doc-dir=#{dir}/docs [one]/"], values("--doc-dir=#{dir}/do")
      assert_equal ["--install-man=#{dir}/docs [one]/"], values("--install-man=#{dir}/do")
      assert_empty values("--no-standard-docs", "--install-man", "#{dir}/do")
      assert_empty values("--doc-dir", TestSupport::STORE, "--install-man", "RichRIExample")
    end
  end

  def test_bash_dequoting_handles_unclosed_quotes_without_evaluating_substitutions
    completion_class = Class.new(RichRI::Completion) do
      def candidates(words)
        words.map { |word| [word, ""] }
      end
    end
    Dir.mktmpdir do |dir|
      marker = File.join(dir, "executed")
      output = StringIO.new
      words = ["--shell=bash", "'open quote", '"double quote"', "path\\ with\\ spaces", "$(touch #{marker})"]
      completion_class.new.write(words, output)

      assert_equal(["open quote", "double quote", "path with spaces", "$(touch #{marker})"],
                   output.string.lines.map { |line| line.split("\t").first })
      refute_path_exists marker
    end
  end

  def test_protocol_is_quiet_on_invalid_sources_and_ignores_ri_actions
    out, err, status = cli("--complete", "--doc-dir=/no/such/directory", "X", docs: false)

    assert_predicate status, :success?, err
    assert_empty out
    assert_empty err
    hostile_defaults = { "RI" => "--server --dump=/no/such/cache" }
    out, err, status = cli("--complete", "--no-standard-docs", "--", "--h", docs: false, env: hostile_defaults)

    assert_predicate status, :success?, err
    assert_empty out
  end

  def test_flag_protocol_includes_descriptions
    out, err, status = cli("--complete", "--no-all", docs: false)

    assert_predicate status, :success?, err
    assert_equal "--no-all\tInclude all methods in a class page.\n", out
  end
end

class ConfigurationCompletionTest < Minitest::Test
  def values(*words)
    RichRI::Completion.new.candidates(words).map(&:first)
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

  def test_config_completion_keeps_spaces_and_handles_glob_characters
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config [one]"))
      config = File.join(dir, "config [one]", "settings spaced.yml")
      File.write(config, "theme: terminal\n")

      assert_equal ["#{dir}/config [one]/"], values("--config", "#{dir}/config [")
      assert_equal [config], values("--config", "#{dir}/config [one]/settings s")
      assert_equal ["--config=#{config}"], values("--config=#{dir}/config [one]/settings s")
      assert_empty values("--doc-dir", "#{dir}/config [one]/settings s")
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
      environment["RI"] = "--server --dump=/missing --profile"
      out, err, status = cli("--complete", "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_empty err
      assert_equal "RichRIExample#map\t\n", out
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
      assert_equal "RichRIExample#map\t\n", out
      out, err, status = cli("--complete", "--pager-command", "--no-home", "RichRIExample#ma",
                             docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_equal "RichRIExample#map\t\n", out
      out, err, status = cli("--complete", "--no-home", "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_empty err
      assert_empty out
    end
  end

  def test_invalid_configuration_is_quiet_and_no_config_bypasses_it
    Dir.mktmpdir do |dir|
      config = File.join(dir, "broken.yml")
      File.write(config, "theme: [\n")
      environment = { "RICH_RI_CONFIG" => config }
      out, err, status = cli("--complete", "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_empty out
      assert_empty err
      out, err, status = cli("--complete", "--no-config", "--no-standard-docs", "--doc-dir", TestSupport::STORE,
                             "RichRIExample#ma", docs: false, env: environment)

      assert_predicate status, :success?, err
      assert_empty err
      assert_equal "RichRIExample#map\t\n", out
    end
  end

  private

  def disabled_sources
    %w[system site home gems].to_h { |source| [source, false] }
  end
end
