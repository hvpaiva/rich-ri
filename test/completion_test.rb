# frozen_string_literal: true

require "test_helper"

class CompletionTest < Minitest::Test
  def values(*words)
    RichRI::Completion.new.candidates(words).map(&:first)
  end

  def test_options_have_descriptions_for_both_boolean_forms
    candidates = RichRI::Completion.new.candidates(["--"])

    assert(candidates.all? { |_value, desc| !desc.empty? })
    %w[--all --no-all --interactive --no-interactive --color= --completion --man].each do |flag|
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

  def test_dynamic_classes_and_methods_use_the_selected_store
    args = ["--no-standard-docs", "--doc-dir", TestSupport::STORE]

    assert_includes values(*args, "RichRIExample#ma"), "RichRIExample#map"
    assert_includes values(*args, "RichRIExample.bu"), "RichRIExample.build"
    assert_includes values(*args, "RichRIExample"), "RichRIExample#"
    assert_includes values(*args, "RichRIExample::"), "RichRIExample::Nested"
    assert_empty values(*args, "NoSuchExample123")
    assert_includes values(*args, "--color", "RichRIExample#ma"), "RichRIExample#map"
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
