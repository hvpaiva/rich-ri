# frozen_string_literal: true

require "test_helper"
require_relative "../rakelib/manual"

class ManualInstallTest < Minitest::Test
  def test_default_installation_can_be_updated_and_found_through_manpath
    Dir.mktmpdir do |home|
      env = { "HOME" => home, "XDG_DATA_HOME" => nil }
      out, err, status = cli("--install-man", docs: false, env: env)
      path = File.join(home, ".local/share/man/man1/rich-ri.1")

      assert_predicate status, :success?, err
      assert_equal File.read(RichRI::Manual.new.path), File.read(path)
      assert_includes out, "export MANPATH=#{File.dirname(path, 2)}:\"${MANPATH:-}\""
      File.write(path, "older version")
      _out, err, status = cli("--install-man", docs: false, env: env)

      assert_predicate status, :success?, err
      assert_equal File.read(RichRI::Manual.new.path), File.read(path)
      out, err, status = Open3.capture3(env.merge("MANPATH" => "#{File.dirname(path, 2)}:"),
                                        "man", "-w", "rich-ri")

      assert_predicate status, :success?, err
      assert_equal File.realpath(path), File.realpath(out.strip)
    end
  end

  def test_explicit_and_xdg_destinations_support_spaces_without_needing_man
    Dir.mktmpdir do |home|
      xdg = File.join(home, "user data")
      explicit = File.join(home, "my manuals/man1")
      [[[], File.join(xdg, "man/man1")], [["--install-man=#{explicit}"], explicit]].each do |args, target|
        args = ["--install-man"] if args.empty?
        out, err, status = cli(*args, docs: false, env: { "HOME" => home, "XDG_DATA_HOME" => xdg, "PATH" => home })

        assert_predicate status, :success?, err
        assert File.file?(File.join(target, "rich-ri.1"))
        assert_includes out, Shellwords.escape(File.dirname(target))
      end
    end
  end

  def test_relative_xdg_uses_the_home_default
    Dir.mktmpdir do |home|
      _out, err, status = cli("--install-man", docs: false, env: { "HOME" => home, "XDG_DATA_HOME" => "relative" })

      assert_predicate status, :success?, err
      assert File.file?(File.join(home, ".local/share/man/man1/rich-ri.1"))
    end
  end

  def test_install_refuses_invalid_destinations_and_extra_names
    Dir.mktmpdir do |directory|
      file = File.join(directory, "man1")
      File.write(file, "keep")
      man1 = "a man1 directory, such as ~/.local/share/man/man1"
      refusals = { "" => man1, " " => man1, directory => man1, file => "a directory",
                   File.join(directory, "\nbad/man1") => "a directory without control characters" }
      refusals.each do |target, accepted|
        out, err, status = cli("--install-man=#{target}", docs: false)

        assert_equal 2, status.exitstatus
        assert_empty out
        assert_equal "rich-ri: --install-man must be #{accepted}, not #{target.inspect}\n" \
                     "Run rich-ri --help for usage.\n", err
      end
      out, err, status = cli("--install-man", "somewhere", docs: false)

      assert_equal 2, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: --install-man does not accept lookup names; use --install-man=DIR\n" \
                   "Run rich-ri --help for usage.\n", err
      assert_equal "keep", File.read(file)
    end
  end

  def test_default_destination_names_the_variable_it_came_from
    Dir.mktmpdir do |data|
      FileUtils.mkdir_p(File.join(data, "man"))
      File.write(File.join(data, "man/man1"), "keep")
      out, err, status = cli("--install-man", docs: false, env: { "XDG_DATA_HOME" => data })

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: XDG_DATA_HOME: the manual directory must be a directory, " \
                   "not #{File.join(data, 'man/man1').inspect}\n", err
    end
  end

  def test_install_refuses_symlink_and_directory_outputs
    Dir.mktmpdir do |directory|
      target = File.join(directory, "man1")
      FileUtils.mkdir_p(target)
      external = File.join(directory, "keep")
      File.write(external, "keep")
      destination = File.join(target, "rich-ri.1")
      File.symlink(external, destination)
      _out, err, status = cli("--install-man=#{target}", docs: false)

      assert_equal 1, status.exitstatus
      assert_includes err, "symbolic link"
      assert_equal "keep", File.read(external)
      File.unlink(destination)
      Dir.mkdir(destination)
      _out, err, status = cli("--install-man=#{target}", docs: false)

      assert_equal 1, status.exitstatus
      assert_includes err, "not a regular file"
      assert_empty Dir.children(destination)
    end
  end

  def test_install_reports_filesystem_failures_without_a_backtrace
    Dir.mktmpdir do |directory|
      loop_path = File.join(directory, "loop")
      File.symlink(loop_path, loop_path)
      _out, err, status = cli("--install-man=#{loop_path}/man1", docs: false)

      assert_equal 1, status.exitstatus
      assert_includes err, "rich-ri:"
      refute_match(/from .*\.rb:\d+/, err)
      refute_path_exists File.join(loop_path, "man1/rich-ri.1")
    end
  end
end

class ManualDisplayTest < Minitest::Test
  def with_man
    Dir.mktmpdir do |directory|
      program = File.join(directory, "man")
      File.write(program, <<~RUBY)
        #!#{RbConfig.ruby}
        puts ARGV
        ENV.keys.grep(/LESS_TERMCAP|GROFF_NO_SGR|MANPAGER|MANROFFOPT/).sort.each do |key|
          puts "\#{key}=\#{ENV[key].inspect}"
        end
        exit ENV.fetch("MAN_EXIT", "0").to_i
      RUBY
      File.chmod(0o755, program)
      keys = RichRI::Manual::PAGER_SETTINGS + ENV.keys.grep(/^LESS_TERMCAP_/) + %w[NO_COLOR]
      env = keys.to_h { |key| [key, nil] }.merge("PATH" => directory)
      yield env
    end
  end

  def test_man_gets_the_bundled_path_and_conditional_palette
    with_man do |env|
      out, err, status = cli("--color=always", "--man", docs: false, env: env)

      assert_predicate status, :success?, err
      assert_includes out, RichRI::Manual.new.path
      assert_includes out, 'GROFF_NO_SGR="1"'
      assert_includes out, 'LESS_TERMCAP_md="\e[1;34m"'
      out, err, status = cli("--no-color", "--man", docs: false, env: env)

      assert_predicate status, :success?, err
      refute_includes out, "LESS_TERMCAP"
    end
  end

  def test_man_preserves_custom_pager_and_palette_settings
    with_man do |env|
      { "MANPAGER" => "custom-pager", "PAGER" => "cat", "MANROFFOPT" => "-c",
        "GROFF_NO_SGR" => "1", "LESS_TERMCAP_us" => "custom-style" }.each do |key, value|
        out, err, status = cli("--color=always", "--man", docs: false, env: env.merge(key => value))

        assert_predicate status, :success?, err
        refute_includes out, "LESS_TERMCAP_md"
      end
    end
  end

  def test_man_failure_and_absence_are_reported
    with_man do |env|
      _out, _err, status = cli("--man", docs: false, env: env.merge("MAN_EXIT" => "7"))

      assert_equal 1, status.exitstatus
      File.unlink(File.join(env.fetch("PATH"), "man"))
      out, err, status = cli("--man", docs: false, env: env)

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: man(1) not found; install it to read the manual\n", err
    end
  end

  def formatted(source, width)
    out, err, status = Open3.capture3("groff", "-ww", "-Tutf8", "-rLL=#{width}n", "-rLT=#{width}n",
                                      "-man", stdin_data: source)

    assert_predicate status, :success?, err
    assert_empty err
    # -Tutf8 writes UTF-8 whatever the locale says, and Open3 labels the output by the locale.
    out.force_encoding(Encoding::UTF_8).gsub(/\e\[[\d;]*m/, "").gsub(/.\x08/, "")
  end

  def typographic(source)
    typography = TYPOGRAPHY.map { |char, glyph| ".char #{char} \\[#{glyph}]\n" }.join
    source.sub(".SH NAME", "#{typography}.SH NAME")
  end

  def test_generated_options_and_prose_fit_narrow_and_standard_manuals
    [60, 80].each do |width|
      plain = formatted(::Manual.render, width)

      assert(plain.lines.all? { |line| line.chomp.length <= width }, "Manual exceeds #{width} columns")
      assert_includes plain, "--install-man[=DIR]"
      assert_includes plain, "MANUAL INSTALLATION"
      assert_includes plain, 'rich-ri --completion=fish > "$dir/rich-ri.fish"'
    end
  end

  def test_page_says_how_it_is_made_and_when_its_version_was_released
    source = ::Manual.render
    heading = "## [#{RichRI::VERSION}] - "
    released = File.readlines(File.join(TestSupport::ROOT, "CHANGELOG.md"), chomp: true)
                   .find { |line| line.start_with?(heading) }.delete_prefix(heading)

    assert_match(/\A\.\\" Generated by .*rake generate.*\n\.\\" .*Do not edit/, source)
    assert_match(/\A\d{4}-\d{2}-\d{2}\z/, released)
    assert_includes source, %(\n.TH RICH\\-RI 1 "#{released}" "rich\\-ri #{RichRI::VERSION}" "User Commands"\n)
    # The date is left unescaped for the programs that read it, so groff may typeset its hyphens.
    assert_includes formatted(typographic(source), 80).lines.last(3).join, released.tr("-", "\u2010")
  end

  def test_generation_names_the_changelog_without_a_release_heading
    Dir.mktmpdir("rich-ri-manual-") do |root|
      FileUtils.mkdir(File.join(root, "rakelib"))
      FileUtils.cp(File.join(TestSupport::ROOT, "rakelib/manual.rb"), File.join(root, "rakelib"))
      File.symlink(File.join(TestSupport::ROOT, "lib"), File.join(root, "lib"))
      File.write(File.join(root, "CHANGELOG.md"), "# Changelog\n\n## [Unreleased]\n")
      _out, err, status = Open3.capture3(RbConfig.ruby, "-e", "require ARGV[0]; Manual.render",
                                         File.join(root, "rakelib/manual.rb"))

      refute_predicate status, :success?
      assert_includes err, "#{root}/CHANGELOG.md has no \"## [#{RichRI::VERSION}] - YYYY-MM-DD\" heading (Manual::Error)"
    end
  end

  def test_every_section_has_content_and_the_files_are_listed
    source = ::Manual.render

    refute_match(/^\.S[HS] .*\n\.S[HS] /, source)
    refute_includes source, "Style roles"
    assert_equal ["Configuration and themes", "Presentation", "Lookup", "Documentation sources", "Tools"],
                 source[/^\.SH OPTIONS\n.*?^\.SH /m].scan(/^\.SS (.*)$/).flatten
    files = source[/^\.SH FILES\n.*?^\.SH /m]

    assert_includes files, '$XDG_CONFIG_HOME/rich\-ri/config.yml'
    assert_includes files, '$XDG_DATA_HOME/man/man1/rich\-ri.1'
  end

  def test_page_describes_every_variable_and_limit_that_help_names
    help = RichRI::Options.new.parser.to_s
    source = ::Manual.render
    variables = help.scan(/RICH_RI_[A-Z_]+(?:<ROLE>)?/).uniq

    assert_includes variables, "RICH_RI_DEBUG"
    variables.each { |name| assert_includes source, name }
    assert_includes help, "(20 to 10000)"
    assert_equal 2, source.scan("from 20 to 10000").length
    assert_includes help, "(port 1 to 65535,"
    assert_includes source, "\\-\\-server=PORT chooses another port from 1 to 65535."
  end

  def test_page_gives_the_only_address_the_server_listens_on
    assert_includes ::Manual.render, "listening on\n127.0.0.1 only, so other machines cannot connect;"
  end

  def test_page_lists_the_actions_and_pagers_the_code_knows
    source = ::Manual.render
    actions = source[/^No two of (.*) can be combined\.$/, 1]
    pagers = source[/When none is named, (.*)\n/, 1]

    assert_equal (RichRI::Actions::OPTIONS.keys - %w[--help --version]).map { |option| ::Manual.escape(option) },
                 actions.split(/, | and /)
    assert_equal RichRI::Pager::USUAL, pagers.split(/, | and /)
  end

  def test_help_and_page_give_the_exit_statuses_of_the_errors
    statuses = [0, RichRI::Error.new.exit_status, RichRI::UsageError.new.exit_status, 130]
    help = RichRI::Options.new.parser.to_s[/^Exit status: .*$/]
    page = ::Manual.render[/^\.SH EXIT STATUS\n.*?^\.SH /m]

    assert_equal statuses, help.scan(/\d+/).map(&:to_i)
    assert_equal statuses, page.scan(/^\.B (\d+)$/).flatten.map(&:to_i)
  end

  def test_page_says_how_a_name_that_was_not_found_is_reported
    page = ::Manual.render[/^\.SH EXIT STATUS\n.*?^\.SH /m]

    assert_includes page, "reported on standard error as\n\"rich\\-ri: NAME not found\" also when similar names"
  end

  # How groff without a distribution's adjustments typesets these characters.
  TYPOGRAPHY = { "-" => "u2010", "'" => "u2019", "`" => "u2018", "^" => "u02C6", "~" => "u02DC" }.freeze
  LITERALS = ["rich-ri 'Array.[]'", "alias ri='rich-ri'", 'data=${XDG_DATA_HOME:-"$HOME/.local/share"}',
              "--no-pager", "~/.config/rich-ri/config.yml", "^===", "--install-man=DIR",
              "documentation-page"].freeze

  def test_names_and_commands_stay_copyable_whatever_the_formatter_does_with_punctuation
    source = ::Manual.render

    assert_includes source, 'rich\-ri \(aqArray.[]\(aq'
    assert_includes source, 'alias ri=\(aqrich\-ri\(aq'
    [60, 80].each do |width|
      # The footer is dropped: its date is deliberately left unescaped.
      body = formatted(typographic(source), width).rstrip.lines[0...-1].join

      refute_match(/[\u2010\u2018\u2019\u02C6\u02DC]/, body)
      LITERALS.each { |literal| assert_includes body, literal }
    end
  end

  def test_words_are_never_split_across_lines
    [60, 80].each do |width|
      plain = formatted(::Manual.render, width)

      assert_empty plain.lines.map(&:rstrip).grep(/\w[-\u2010]\z/)
      assert_includes plain, "--profile"
      assert_includes plain, "$XDG_CONFIG_HOME/rich-ri/config.yml"
    end
  end
end
