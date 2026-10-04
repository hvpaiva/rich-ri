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
      ["", directory, file, File.join(directory, "\nbad/man1")].each do |target|
        _out, err, status = cli("--install-man=#{target}", docs: false)

        assert_equal 1, status.exitstatus
        refute_empty err
        refute_match(/from .*\.rb:\d+/, err)
      end
      _out, err, status = cli("--install-man", "somewhere", docs: false)

      assert_equal 1, status.exitstatus
      assert_includes err, "use --install-man=DIR"
      assert_equal "keep", File.read(file)
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
      _out, err, status = cli("--man", docs: false, env: env)

      assert_equal 1, status.exitstatus
      assert_includes err, "man(1) not found"
      assert_includes err, "rich-ri --help"
    end
  end

  def test_generated_options_and_prose_fit_narrow_and_standard_manuals
    [60, 80].each do |width|
      out, err, status = Open3.capture3("groff", "-ww", "-Tutf8", "-rLL=#{width}n", "-rLT=#{width}n",
                                        "-man", stdin_data: ::Manual.render)
      plain = out.gsub(/\e\[[\d;]*m/, "").gsub(/.\x08/, "")

      assert_predicate status, :success?, err
      assert_empty err
      assert(plain.lines.all? { |line| line.chomp.length <= width }, "Manual exceeds #{width} columns")
      assert_includes plain, "--install-man[=DIR]"
      assert_includes plain, "MANUAL INSTALLATION"
      assert_includes plain, 'rich-ri --completion=fish > "$dir/rich-ri.fish"'
    end
  end

  def test_code_blocks_preserve_copyable_commands_with_typographic_formatter_glyphs
    source = ::Manual.render

    assert_includes source, 'rich\-ri \(aqArray.[]\(aq'
    assert_includes source, 'alias ri=\(aqrich\-ri\(aq'
    # Older groff versions use these glyphs for ordinary source punctuation.
    source = source.sub(".SH NAME", ".char - \\[u2010]\n.char ' \\[u2019]\n.SH NAME")
    out, err, status = Open3.capture3("groff", "-ww", "-Tutf8", "-man", stdin_data: source)
    plain = out.gsub(/\e\[[\d;]*m/, "").gsub(/.\x08/, "")

    assert_predicate status, :success?, err
    assert_empty err
    assert_includes plain, "rich\u2010ri"
    assert_includes plain, "rich-ri 'Array.[]'"
    assert_includes plain, "alias ri='rich-ri'"
    assert_includes plain, 'data=${XDG_DATA_HOME:-"$HOME/.local/share"}'
    assert_includes plain, 'rich-ri --completion=fish > "$dir/rich-ri.fish"'
  end
end
