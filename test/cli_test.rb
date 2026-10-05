# frozen_string_literal: true

require "test_helper"

class CLITest < Minitest::Test
  def test_version_and_help_are_owned_by_rich_ri
    out, err, status = cli("--version", docs: false)

    assert_predicate status, :success?, err
    assert_equal "rich-ri #{RichRI::VERSION}\n", out
    out, err, status = cli("--help", docs: false)

    assert_predicate status, :success?, err
    assert_includes out, "Usage: rich-ri"
    assert_includes out, "--completion=SHELL"
    assert_includes out, "Exit status: 0 success, 1 failure, 2 usage error, 130 interrupted."
    assert_includes out, "RICH_RI_DEBUG adds the error class and backtrace to a failure."
    refute_includes out, "\e"
    colored, = cli("--color=always", "--help", docs: false)

    assert_equal out, RichRI.plain(colored)
    assert_includes colored, "\e["
  end

  def test_checkout_executable_finds_its_own_library
    paths = $LOAD_PATH.reject { |path| File.expand_path(path) == File.join(TestSupport::ROOT, "lib") }
    environment = TestSupport::ENVIRONMENT.merge("RUBYOPT" => nil, "RUBYLIB" => nil)
    out, err, status = Bundler.with_unbundled_env do
      Open3.capture3(environment, RbConfig.ruby, "--disable-gems", "-I", paths.join(File::PATH_SEPARATOR),
                     File.join(TestSupport::ROOT, "exe/rich-ri"), "--version")
    end

    assert_predicate status, :success?, err
    assert_equal "rich-ri #{RichRI::VERSION}\n", out
  end

  def test_page_color_plain_and_stock_format
    plain, err, status = cli("RichRIExample#map")

    assert_predicate status, :success?, err
    assert_includes plain, "RichRIExample#map"
    assert_equal "= RichRIExample#map\n", plain.lines.first
    assert_equal 2, plain.lines.grep(/\A-{78}\n\z/).length
    refute_includes plain, "\e"
    colored, err, status = cli("--color=always", "RichRIExample#map")

    assert_predicate status, :success?, err
    assert_equal plain, RichRI.plain(colored)
    assert_includes colored, "\e["
    markdown, err, status = cli("-f", "markdown", "RichRIExample#map")

    assert_predicate status, :success?, err
    assert_includes markdown, "# RichRIExample#map"
    refute_includes markdown, "\e"
  end

  def test_errors_have_nonzero_status_and_no_backtrace
    ["NoSuchExample123", "--unknown", "--color=invalid", "--width=0", "--doc-dir=/no/such/directory"].each do |arg|
      _out, err, status = cli(arg)

      refute_predicate status, :success?, arg
      refute_empty err, arg
      refute_match(/from .*\.rb:\d+/, err)
    end
  end

  def test_command_line_mistakes_exit_with_2_and_point_at_help
    ["--unknown", "--color=invalid", "--width=0", "--doc-dir=/no/such/directory", "--style=unknown=red"].each do |arg|
      out, err, status = cli(arg, "RichRIExample")

      assert_equal 2, status.exitstatus, arg
      assert_empty out
      assert_match(/\Arich-ri: \S/, err)
      assert_equal "Run rich-ri --help for usage.\n", err.lines.last
    end
  end

  def test_failures_outside_the_command_line_exit_with_1_and_no_usage_hint
    [%w[NoSuchExample123], %w[--dump=/no/such/cache.ri], %w[--config=/no/such/config.yml RichRIExample]].each do |args|
      out, err, status = cli(*args)

      assert_equal 1, status.exitstatus, args.inspect
      assert_empty out
      refute_empty err
      refute_includes err, "--help"
    end
  end

  def defective_cli(*, env: {})
    source = <<~RUBY
      require "rich_ri"
      RichRI::Formatter.prepend(Module.new { def start_accepting = raise(NoMethodError, "planted defect") })
      exit RichRI::CLI.run(ARGV)
    RUBY
    Open3.capture3(TestSupport::ENVIRONMENT.merge(env), RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", "-e", source,
                   "--", "--no-standard-docs", "--doc-dir", TestSupport::STORE, *)
  end

  def test_a_defect_is_reported_in_one_line
    [{}, { "RICH_RI_DEBUG" => "" }].each do |env|
      out, err, status = defective_cli("RichRIExample#map", env: env)

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: planted defect\n", err
    end
  end

  def test_debug_variable_adds_the_exception_class_and_backtrace
    _out, err, status = defective_cli("RichRIExample#map", env: { "RICH_RI_DEBUG" => "1" })

    assert_equal 1, status.exitstatus
    assert_equal ["rich-ri: planted defect\n", "NoMethodError\n"], err.lines.first(2)
    assert_match(/\A {4}-e:2:in /, err.lines[2])
    assert_includes err, "rich_ri/cli.rb"
    _out, err, status = cli("--dump=#{File.join(TestSupport::ROOT, 'LICENSE.txt')}", env: { "RICH_RI_DEBUG" => "1" })

    assert_equal 1, status.exitstatus
    assert_match(/\Arich-ri: incompatible or damaged RI data in /, err)
    assert_includes err, "\nRichRI::StoreError\n"
    assert_match(/^caused by TypeError: incompatible marshal file format/, err)
  end

  def test_failures_are_reported_even_when_ruby_warnings_are_disabled
    _out, err, status = cli("--unknown", env: { "RUBYOPT" => "-W0" })

    assert_equal 2, status.exitstatus
    assert_includes err, "rich-ri: invalid option: --unknown"
  end

  def test_end_of_options_preserves_names
    _out, err, status = cli("--", "--help")

    refute_predicate status, :success?
    assert_includes err, "Nothing known about"
  end

  def test_pipe_no_color_and_explicit_color_precedence
    %w[auto never].each do |mode|
      out, err, status = cli("--color=#{mode}", "RichRIExample", env: { "NO_COLOR" => nil })

      assert_predicate status, :success?, err
      refute_includes out, "\e"
    end
    out, = cli("--color", "--no-color", "RichRIExample")

    refute_includes out, "\e"
    out, = cli("--no-color", "--color", "RichRIExample")

    assert_includes out, "\e"
  end

  def test_ri_defaults_support_quoted_paths_and_cli_overrides
    out, err, status = cli("--no-color", "RichRIExample", env: { "RI" => "--color=always --width=40" })

    assert_predicate status, :success?, err
    refute_includes out, "\e"
    options = RichRI::Options.new.parse(["--width=60"], defaults: "--width=40")

    assert_equal 60, options.driver_options[:width]
  end

  def test_cli_run_leaves_the_environment_alone
    with_environment("RI" => nil, "LESS" => "-Fi") do
      _out, err = capture_io { assert_equal 0, RichRI::CLI.run(["--no-standard-docs", "--list"]) }

      assert_empty err
      assert_equal "-Fi", ENV.fetch("LESS", nil)
    end
  end

  def test_class_lists_sources_and_all_methods
    out, err, status = cli("--list")

    assert_predicate status, :success?, err
    assert_includes out, "RichRIExample"
    out, = cli("--list-doc-dirs")

    assert_includes out, TestSupport::STORE
    out, err, status = cli("--all", "RichRIExample")

    assert_predicate status, :success?, err
    assert_includes out, "map"
    assert_includes out, "build"
  end

  def test_scripts_and_man_path_ship_in_the_package
    %w[bash zsh fish].each do |shell|
      out, err, status = cli("--completion=#{shell}", docs: false)

      assert_predicate status, :success?, err
      assert_includes out, "rich-ri --complete"
    end
    path, err, status = cli("--man-path", docs: false)

    assert_predicate status, :success?, err
    assert File.file?(path.strip)
  end

  def test_interactive_lookup_can_exit_cleanly
    out, err, status = cli("--interactive", stdin: "RichRIExample#map\n\n")

    assert_predicate status, :success?, err
    assert_empty err
    refute_includes out, "Nothing known about"
  end

  def test_dump_rejects_directories_missing_files_and_unreadable_files
    Dir.mktmpdir do |directory|
      unreadable = File.join(directory, "unreadable.ri")
      File.write(unreadable, "cache")
      File.chmod(0o000, unreadable)
      paths = [directory, File.join(directory, "missing.ri")]
      paths << unreadable unless File.readable?(unreadable)
      paths.each do |path|
        out, err, status = cli("--dump=#{path}", docs: false)

        assert_equal 1, status.exitstatus
        assert_empty out
        assert_includes err, "RI cache must be a readable regular file"
        refute_match(/from .*\.rb:\d+/, err)
      end
    end
  end
end
