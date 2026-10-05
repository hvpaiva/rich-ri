# frozen_string_literal: true

require "test_helper"

class EnvironmentFailuresTest < Minitest::Test
  NO_HOME = { "HOME" => "relative", "XDG_CONFIG_HOME" => nil, "XDG_DATA_HOME" => nil }.freeze

  def without_home(*)
    Dir.mktmpdir("rich-ri-home-") do |dir|
      # A relative HOME must never be resolved against the working directory.
      result = Dir.chdir(dir) { cli(*, docs: false, env: NO_HOME) }

      assert_empty Dir.children(dir)
      result
    end
  end

  def test_file_failures_name_the_file_before_the_reason
    Dir.mktmpdir("rich-ri-files-") do |dir|
      config = File.join(dir, "config.yml")
      File.write(config, "theme: dark\n")
      File.chmod(0o000, config)
      locked = File.join(dir, "locked")
      Dir.mkdir(locked, 0o555)
      skip "File permissions do not apply to this user" if File.readable?(config)

      { ["--config", config, "--show-config"] => "rich-ri: #{config}: Permission denied\n",
        ["--install-man=#{locked}/man1"] => "rich-ri: #{locked}/man1: Permission denied\n" }.each do |args, message|
        out, err, status = cli(*args, docs: false)

        assert_equal 1, status.exitstatus, args.inspect
        assert_empty out
        assert_equal message, err
      end
    end
  end

  def version_written_to(output)
    IO.pipe do |reader, writer|
      pid = Process.spawn(TestSupport::ENVIRONMENT, RbConfig.ruby, "-I#{TestSupport::ROOT}/lib",
                          File.join(TestSupport::ROOT, "exe/rich-ri"), "--version", out: output, err: writer)
      writer.close
      _pid, status = Process.wait2(pid)
      [status.exitstatus, reader.read]
    end
  end

  def test_output_that_cannot_be_written_is_a_failure
    Dir.mktmpdir("rich-ri-output-") do |dir|
      path = File.join(dir, "read-only")
      File.write(path, "")
      # Open for reading only, so every write fails on any system.
      File.open(path) do |read_only|
        outputs = { read_only => "Bad file descriptor" }
        outputs["/dev/full"] = "No space left on device" if File.chardev?("/dev/full")

        outputs.each do |output, reason|
          assert_equal [1, "rich-ri: standard output: #{reason}\n"], version_written_to(output)
        end
      end
    end
  end

  def test_commands_that_need_no_home_directory_work_without_one
    outputs = { ["--version"] => "rich-ri #{RichRI::VERSION}\n", ["--help"] => "Usage: rich-ri",
                ["--show-config"] => "theme: terminal", ["--config-path"] => "\n", ["--completion=bash"] => "_rich_ri",
                ["--man-path"] => RichRI::Manual.new.path,
                ["--dump=#{TestSupport::STORE}/cache.ri"] => 'modules: ["RichRIExample", "RichRIExample::Nested"]' }
    outputs.each do |args, text|
      out, err, status = without_home(*args)

      assert_predicate status, :success?, "#{args.inspect}: #{err}"
      assert_includes out, text
    end
  end

  def test_lookup_without_a_home_directory_says_what_is_missing
    out, err, status = without_home("--no-standard-docs", "--doc-dir", TestSupport::STORE, "RichRIExample")

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_includes err, "rich-ri: cannot find a home directory; set HOME to an absolute path\n"
    refute_includes err, "no implicit conversion"
    refute_includes err, "--help"
  end

  def test_commands_that_read_the_stores_need_a_home_directory
    %w[--list --list-doc-dirs --server].each do |action|
      out, err, status = without_home("--no-standard-docs", "--doc-dir", TestSupport::STORE, action)

      assert_equal 1, status.exitstatus, action
      assert_empty out
      assert_equal "rich-ri: cannot find a home directory; set HOME to an absolute path\n", err
    end
  end

  def test_manual_installation_needs_a_home_directory_only_for_its_default
    out, err, status = without_home("--install-man")

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_includes err, "rich-ri: cannot find a home directory; set HOME to an absolute path\n"
    Dir.mktmpdir("rich-ri-files-") do |dir|
      _out, err, status = cli("--install-man=#{dir}/man1", docs: false, env: NO_HOME)

      assert_predicate status, :success?, err
      assert File.file?(File.join(dir, "man1/rich-ri.1"))
    end
  end
end
