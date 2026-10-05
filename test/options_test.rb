# frozen_string_literal: true

require "test_helper"

class OptionsTest < Minitest::Test
  def parse(*args)
    RichRI::Options.new.parse(args, defaults: "")
  end

  def test_source_switches_and_short_options
    options = parse("--no-standard-docs", "--system", "--no-site", "--no-home", "--gems", "-d", TestSupport::STORE)

    assert options.driver_options[:use_system]
    assert options.driver_options[:use_gems]
    refute options.driver_options[:use_site]
    refute options.driver_options[:use_home]
    assert_equal [TestSupport::STORE], options.driver_options[:extra_doc_dirs]
  end

  def test_lookup_switches_and_stock_format
    options = parse("-i", "-a", "-l", "-T", "--no-expand-refs", "-f", "markdown", "-w", "44")

    %i[interactive show_all list use_stdout].each { |key| assert options.driver_options[key] }
    refute options.driver_options[:expand_refs]
    assert_equal RDoc::Markup::ToMarkdown, options.driver_options[:formatter]
    assert_equal 44, options.driver_options[:width]
  end

  def test_server_default_and_explicit_port
    assert_equal 8214, parse("--server").driver_options[:server]
    assert_equal 9000, parse("--server=9000").driver_options[:server]
    assert_equal 1, parse("--server=1").driver_options[:server]
    assert_equal 65_535, parse("--server=65535").driver_options[:server]
  end

  def test_width_accepts_the_whole_documented_range
    assert_equal 20, parse("--width=20").driver_options[:width]
    assert_equal 10_000, parse("--width=10000").driver_options[:width]
    assert_equal 20, parse("-w", "20").driver_options[:width]
  end

  def test_numbers_must_be_plain_decimal_integers_within_range
    invalid = ["", " 80", "80 ", "+80", "-80", "0x50", "080", "8_0", "80.0", "8e1", "eighty"]
    { "--width" => invalid + %w[0 19 10001 99999999999999999999],
      "--server" => invalid + %w[0 65536 99999 -1 99999999999999999999] }.each do |option, values|
      values.each do |value|
        error = assert_raises(RichRI::UsageError, "#{option}=#{value}") { parse("#{option}=#{value}") }

        assert_match(/\A#{option} must be an integer from \d+ to \d+, not #{Regexp.escape(value.inspect)}\z/,
                     error.message)
      end
    end
  end

  def test_out_of_range_numbers_are_refused_before_anything_runs
    # --list keeps a refused port from ever starting the documentation server.
    { "--width=99999999999999999999" => "--width must be an integer from 20 to 10000",
      "--width=0x20" => "--width must be an integer from 20 to 10000",
      "--server=99999" => "--server must be an integer from 1 to 65535",
      "--server=-1" => "--server must be an integer from 1 to 65535" }.each do |option, message|
      out, err, status = cli(option, "--list")

      assert_equal 2, status.exitstatus, option
      assert_empty out
      assert_includes err, message
      refute_match(/from .*\.rb:\d+/, err)
    end
  end

  def test_only_the_options_listed_in_help_exist
    ["--*-completion-bash=--co", "--*-completion-zsh"].each do |option|
      out, err, status = cli(option, docs: false)

      assert_equal 2, status.exitstatus, option
      assert_empty out
      assert_equal "rich-ri: invalid option: #{option}\n", err.lines.first
      out, err, status = cli("RichRIExample", env: { "RI" => option })

      assert_equal 1, status.exitstatus, option
      assert_empty out
      assert_equal "rich-ri: RI: invalid option: #{option}\n", err
    end
  end

  def test_color_mode_uses_equals_and_bare_flag_preserves_the_subject
    options = parse("--color", "RichRIExample")

    assert_equal ["RichRIExample"], options.driver_options[:names]
    assert_equal "auto", parse("--color=auto").color
    assert_equal "always", parse("--color").color
  end

  def test_utility_actions_do_not_load_stores
    assert_equal [:help], parse("--help").action
    assert_equal [:version], parse("-v").action
    assert_equal [:man], parse("--man").action
    assert_equal [:man_path], parse("--man-path").action
    assert_equal [:completion, "fish"], parse("--completion=fish").action
    assert_equal "cache.ri", parse("--dump=cache.ri").driver_options[:dump_path]
    assert parse("--profile").driver_options[:profile]
    refute parse("--no-profile").driver_options[:profile]
  end

  def test_manual_install_destination_uses_equals
    assert_equal [:install_man, nil], parse("--install-man").action
    assert_equal [:install_man, "/tmp/example/man1"], parse("--install-man=/tmp/example/man1").action
    assert_equal ["subject"], parse("--install-man", "subject").driver_options[:names]
  end
end
