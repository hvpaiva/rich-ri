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
end
