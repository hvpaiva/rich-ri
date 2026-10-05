# frozen_string_literal: true

require "test_helper"

class EncodingTest < Minitest::Test
  LATIN1 = "café".encode(Encoding::ISO_8859_1).freeze
  INVALID = "bad\xFFbyte"

  def test_text_from_outside_is_read_as_utf8
    assert_same "café", RichRI.utf8("café")
    ["café".b, "café".dup.force_encoding(Encoding::US_ASCII), LATIN1, "café".encode(Encoding::UTF_16LE)].each do |text|
      result = RichRI.utf8(text)

      assert_equal Encoding::UTF_8, result.encoding
      assert_equal "café", result
    end
    assert_equal "bad�byte", RichRI.utf8(INVALID)
    assert_equal "bad�byte", RichRI.utf8(INVALID.b)
    assert_equal "", RichRI.utf8(nil)
  end

  def test_text_helpers_accept_binary_and_invalid_strings
    assert_equal "café \\u001b[31m", RichRI.sanitize("café \e[31m".b)
    assert_equal "bad�byte", RichRI.sanitize(INVALID)
    assert_equal "café", RichRI.plain("\e[1mcafé\e[0m".b)
    assert_equal "bad�byte", RichRI.plain(INVALID)
    assert_equal 4, RichRI.width("café".b)
    assert_equal 4, RichRI.width(LATIN1)
    assert_kind_of Integer, RichRI.width(INVALID)
    assert RichRI.printable?("café".b)
    assert RichRI.printable?(INVALID)
    refute RichRI.printable?("café\e[0m".b)
  end

  def test_paths_expand_on_bytes_whatever_the_locale_calls_them
    Dir.mktmpdir("rich-ri-paths-") do |root|
      dir = File.join(root, "josé").tap { |path| Dir.mkdir(path) }
      Dir.chdir(dir) do
        [["doçs", "#{dir}/doçs"], ["doçs".b, "#{dir}/doçs"], ["/tmp/é/../x", "/tmp/x"]].each do |path, expected|
          result = RichRI.expand_path(path)

          assert_equal Encoding::UTF_8, result.encoding
          assert_equal File.realdirpath(expected), File.realdirpath(result)
        end
      end
      with_environment("HOME" => dir) do
        assert_equal "#{dir}/doçs", RichRI.expand_path("~/doçs".b)
        assert_equal dir, RichRI.expand_path("~")
      end
      assert_equal "#{dir}/doçs", RichRI.expand_path("doçs", dir.b)
    end
  end

  def test_store_paths_and_sources_are_utf8_whatever_label_they_arrive_with
    Dir.mktmpdir("rich-ri-paths-") do |root|
      path = File.join(root, "doçs")
      FileUtils.cp_r(TestSupport::STORE, path)
      options = RichRI::Driver.default_options.merge(use_system: false, use_site: false, use_home: false,
                                                     use_gems: false, extra_doc_dirs: [path.b])
      store = RichRI::Driver.new(options).stores.first

      [store.path, store.source, store.friendly_path].each do |text|
        assert_equal Encoding::UTF_8, text.encoding
        assert_equal path, text
      end
      assert_includes store.module_names, "RichRIExample"
    end
  end

  def test_configuration_paths_come_out_as_utf8_from_a_binary_environment
    { { "HOME" => "/home/josé".b } => "/home/josé/.config/rich-ri/config.yml",
      { "HOME" => "/root", "XDG_CONFIG_HOME" => "/xdg/josé".b } => "/xdg/josé/rich-ri/config.yml",
      { "HOME" => "/root", "RICH_RI_CONFIG" => "/etc/josé.yml".b } => "/etc/josé.yml" }.each do |env, expected|
      path = RichRI::Configuration.new(env: env).path

      assert_equal Encoding::UTF_8, path.encoding
      assert_equal expected, path
    end
    path = RichRI::Options.new.command_line(["--config=/tmp/josé.yml".b]).configuration_file

    assert_equal "/tmp/josé.yml", path
    assert_equal Encoding::UTF_8, path.encoding
  end
end

class LocaleTest < Minitest::Test
  POSIX = { "LC_ALL" => "C", "LANG" => "C" }.freeze

  # Output is compared as bytes: this suite may itself run under the C locale.
  def posix(*, env: {})
    cli(*, docs: false, env: POSIX.merge(env)).map { |value| value.is_a?(String) ? value.b : value }
  end

  def in_accented_directory
    Dir.mktmpdir("rich-ri-locale-") do |root|
      yield File.join(root, "josé").tap { |dir| Dir.mkdir(dir) }
    end
  end

  def test_help_version_and_paths_work_with_accented_configuration_directories
    in_accented_directory do |home|
      [{ "XDG_CONFIG_HOME" => home }, { "RICH_RI_CONFIG" => File.join(home, "missing.yml") }].each do |env|
        out, err, status = posix("--version", env: env)

        assert_predicate status, :success?, err
        assert_equal "rich-ri #{RichRI::VERSION}\n", out
        out, err, status = posix("--help", env: env)

        assert_predicate status, :success?, err
        assert_includes out, "Usage: rich-ri"
        out, err, status = posix("--config-path", env: env)

        assert_predicate status, :success?, err
        assert_operator out, :start_with?, home.b
      end
    end
  end

  def test_accented_option_values_are_kept
    in_accented_directory do |dir|
      out, err, status = posix("--no-config", "--pager-command", "pagér", "--bat-theme=Thème",
                               "--style=method=red", "--show-config", env: { "RI_PAGER" => "outro pagér" })

      assert_predicate status, :success?, err
      assert_includes out, "pager: pagér".b
      assert_includes out, "bat_theme: Thème".b
      out, err, status = posix("--no-config", "--show-config", env: { "RI_PAGER" => "pagér", "BAT_THEME" => "Thème" })

      assert_predicate status, :success?, err
      assert_includes out, "pager: pagér\nbat_theme: Thème\n".b
      out, err, status = posix("--install-man=#{dir}/man1")

      assert_predicate status, :success?, err
      assert_includes out, "Installed #{dir}/man1/rich-ri.1".b
      assert File.file?(File.join(dir, "man1/rich-ri.1"))
    end
  end

  def test_documentation_in_an_accented_directory_is_listed_and_read
    in_accented_directory do |dir|
      store = File.join(dir, "doçs")
      FileUtils.cp_r(TestSupport::STORE, store)
      out, err, status = posix("--no-standard-docs", "--doc-dir", store, "--list-doc-dirs")

      assert_predicate status, :success?, err
      assert_equal "#{store}\n".b, out
      # Wide enough that no temporary directory, however long or spaced, wraps the path.
      out, err, status = posix("--no-standard-docs", "--doc-dir", store, "--width=10000", "RichRIExample#map")

      assert_predicate status, :success?, err
      assert_includes out, "Return transformed values."
      assert_includes out, "(from #{store})".b
    end
  end

  def test_failures_naming_accented_text_are_reported
    in_accented_directory do |dir|
      { ["--bógus"] => [2, "invalid option: --bógus"], ["Açaí"] => [1, "Açaí"],
        ["--style=method=vérde"] => [2, "invalid color"], ["--dump=#{dir}/nada.ri"] => [1, "#{dir}/nada.ri"],
        ["--config=#{dir}/nada.yml", "--show-config"] => [1, "#{dir}/nada.yml"] }.each do |args, (code, text)|
        out, err, status = posix(*args)

        assert_equal code, status.exitstatus, args.inspect
        assert_empty out
        assert_includes err, text.b
        refute_match(/from .*\.rb:\d+/, err)
      end
    end
  end
end
