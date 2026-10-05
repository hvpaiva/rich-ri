# frozen_string_literal: true

require "test_helper"

class ActionsTest < Minitest::Test
  def parse(*args, defaults: "")
    RichRI::Options.new.parse(args, defaults: defaults)
  end

  def test_help_then_version_answer_before_any_other_action
    assert_equal [:help], parse("--version", "--help").action
    assert_equal [:help], parse("-h", "-v").action
    assert_equal [:help], parse("--man", "--help", "--list", "--show-config").action
    assert_equal [:version], parse("--man", "-v", "--server").action
    refute parse("--list", "--help").driver_options[:list]
  end

  def test_two_other_actions_cannot_be_combined
    { %w[--man --show-config] => "--man and --show-config",
      %w[--config-path --show-config] => "--config-path and --show-config",
      %w[--completion=bash --man-path] => "--completion and --man-path",
      %w[--install-man --dump=cache.ri] => "--install-man and --dump", %w[-l --server] => "--list and --server",
      %w[--list-doc-dirs -i] => "--list-doc-dirs and --interactive",
      %w[--man -l --server=9000] => "--man and --list" }.each do |args, pair|
      error = assert_raises(RichRI::UsageError, args.inspect) { parse(*args) }

      assert_equal "#{pair} cannot be used together", error.message
    end
  end

  def test_an_action_can_be_repeated_or_taken_back
    assert_equal [:completion, "zsh"], parse("--completion=bash", "--completion=zsh").action
    assert_equal 9000, parse("--server", "--server=9000").driver_options[:server]
    assert_equal [:man], parse("--list", "--no-list", "--man").action
    options = parse("--list", "--no-list", "--list-doc-dirs", "--no-list-doc-dirs", "RichRIExample")

    assert_nil options.action
    refute options.driver_options[:list]
    refute options.driver_options[:list_doc_dirs]
    assert_equal ["RichRIExample"], options.driver_options[:names]
  end

  def test_an_action_on_the_command_line_replaces_the_one_in_ri
    options = parse("--man", defaults: "--list")

    assert_equal [:man], options.action
    refute options.driver_options[:list]
    refute parse("--no-list", "RichRIExample", defaults: "--list").driver_options[:list]
    assert parse("Rich", defaults: "--list").driver_options[:list]
    error = assert_raises(RichRI::ConfigurationError) { parse(defaults: "--list --server") }

    assert_equal "RI: --list and --server cannot be used together", error.message
  end

  def test_interactive_lookup_takes_no_names
    error = assert_raises(RichRI::UsageError) { parse("-i", "RichRIExample") }

    assert_equal "--interactive does not accept lookup names; enter them at its prompt", error.message
    assert_raises(RichRI::UsageError) { parse("RichRIExample", defaults: "--interactive") }
    assert parse("-i").driver_options[:interactive]
    assert parse("--no-interactive", "-i").driver_options[:interactive]
    assert_equal [:help], parse("-i", "RichRIExample", "--help").action
  end

  def test_refusing_interactive_lookup_requires_a_name
    error = assert_raises(RichRI::UsageError) { parse("--no-interactive") }

    assert_equal "--no-interactive requires a name to look up", error.message
    assert_raises(RichRI::UsageError) { parse(defaults: "--no-interactive") }
    assert_raises(RichRI::UsageError) { parse("-i", "--no-interactive") }
    assert parse("--no-interactive", "--list").driver_options[:list]
    [parse("--no-interactive", "RichRIExample"), parse("-i", "--no-interactive", "RichRIExample"),
     parse("--no-interactive", "RichRIExample", defaults: "--interactive")].each do |options|
      refute options.driver_options[:interactive]
      assert_equal ["RichRIExample"], options.driver_options[:names]
    end
  end

  def test_help_and_version_are_printed_whatever_else_is_asked
    out, err, status = cli("--version", "--man", "--help", "-i", "RichRIExample")

    assert_predicate status, :success?, err
    assert_operator out, :start_with?, "Usage: rich-ri"
    out, err, status = cli("--list", "--version", "--show-config")

    assert_predicate status, :success?, err
    assert_equal "rich-ri #{RichRI::VERSION}\n", out
  end

  def test_conflicting_requests_are_usage_errors
    { %w[--man --show-config] => "--man and --show-config cannot be used together",
      %w[--config-path --show-config] => "--config-path and --show-config cannot be used together",
      %w[--list --list-doc-dirs] => "--list and --list-doc-dirs cannot be used together",
      %w[-i RichRIExample] => "--interactive does not accept lookup names; enter them at its prompt",
      %w[--no-interactive] => "--no-interactive requires a name to look up" }.each do |args, message|
      out, err, status = cli(*args, stdin: "RichRIExample#map\n\n")

      assert_equal 2, status.exitstatus, args.inspect
      assert_empty out
      assert_equal "rich-ri: #{message}\nRun rich-ri --help for usage.\n", err
    end
  end

  def test_conflicting_defaults_in_ri_name_the_variable
    out, err, status = cli("RichRIExample", env: { "RI" => "--man --list" })

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_equal "rich-ri: RI: --man and --list cannot be used together\n", err
  end
end
