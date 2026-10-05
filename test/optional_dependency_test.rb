# frozen_string_literal: true

require "test_helper"
require "socket"

class OptionalDependencyTest < Minitest::Test
  def test_missing_optional_gems_have_actionable_errors
    { "server" => "webrick", "profile" => "profile" }.each do |option, dependency|
      out, err, status = without_optional_gems("--#{option}", "RichRIExample#map")

      assert_equal 1, status.exitstatus, err
      assert_empty out
      assert_includes err, "--#{option} requires the optional #{dependency} gem"
      assert_includes err, "gem install #{dependency}"
      refute_match(/from .*\.rb:\d+/, err)
    end
  end

  def test_lookup_completion_and_disabled_profile_work_without_optional_gems
    {
      ["--no-profile", "RichRIExample#map"] => "Return transformed values.",
      ["--complete", "RichRIExample#ma"] => "RichRIExample#map\t\n",
      ["--server", "--list"] => "RichRIExample"
    }.each do |args, expected|
      out, err, status = without_optional_gems(*args)

      assert_predicate status, :success?, err
      assert_empty err
      assert_includes out, expected
    end
  end

  def test_profile_prints_real_timing_information
    require_optional_gem("profile")
    out, err, status = cli("--profile", "RichRIExample#map")

    assert_predicate status, :success?, err
    assert_includes out, "Return transformed values."
    assert_includes err, "ms/call"
    assert_match(/RichRI::(?:Driver|Formatter)#/, err)
  end

  def test_server_serves_real_documentation_on_loopback
    require_optional_gem("webrick")
    source = <<~RUBY
      require "webrick"
      require "rich_ri"
      module LoopbackServer
        def initialize(config, &block)
          super(config.merge(BindAddress: "127.0.0.1", AccessLog: [],
            Logger: WEBrick::Log.new($stderr, WEBrick::Log::FATAL),
            StartCallback: -> { puts listeners.first.addr[1]; $stdout.flush }), &block)
        end
      end
      WEBrick::HTTPServer.prepend(LoopbackServer)
      exit RichRI::CLI.run(ARGV)
    RUBY
    with_server(source) do |port|
      response = http_get(port, "/")

      assert_match(%r{\AHTTP/1.1 200 }, response)
      assert_includes response, "RDoc"
      assert_includes response, "extra-1/"
      page = http_get(port, "/extra-1/RichRIExample.html")

      assert_match(%r{\AHTTP/1.1 200 }, page)
      assert_includes page, "Return transformed values."
    end
  end

  private

  def require_optional_gem(name)
    return if Gem::Specification.find_all_by_name(name).any?

    # The minimum runtime bundle deliberately excludes these development gems.
    skip "#{name} is absent from this bundle; main CI exercises the optional mode"
  end

  def without_optional_gems(*args)
    optional_paths = %w[profile webrick].flat_map do |name|
      Gem::Specification.find_all_by_name(name).flat_map(&:full_require_paths)
    end
    paths = ($LOAD_PATH - optional_paths) + [File.join(TestSupport::ROOT, "lib")]
    source = <<~RUBY
      require "rubygems"
      abort "Optional gems leaked into the isolated test" if
        %w[profile webrick].any? { |name| Gem::Specification.find_all_by_name(name).any? }
      require "rich_ri"
      exit RichRI::CLI.run(ARGV)
    RUBY
    sources = ["--no-standard-docs", "--doc-dir", TestSupport::STORE]
    args = args.first == "--complete" ? [args.first, *sources, *args.drop(1)] : [*sources, *args]
    Dir.mktmpdir do |home|
      env = TestSupport::ENVIRONMENT.merge("GEM_HOME" => home, "GEM_PATH" => home,
                                           "RUBYOPT" => nil, "RUBYLIB" => nil)
      Bundler.with_unbundled_env do
        Open3.capture3(env, RbConfig.ruby, "--disable-gems", "-I", paths.join(File::PATH_SEPARATOR), "-e", source,
                       "--", *args)
      end
    end
  end

  def with_server(source)
    command = [RbConfig.ruby, "-I#{TestSupport::ROOT}/lib", "-e", source, "--",
               "--no-standard-docs", "--doc-dir", TestSupport::STORE, "--server=0"]
    Open3.popen3(TestSupport::ENVIRONMENT, *command) do |input, output, errors, process|
      input.close
      begin
        Timeout.timeout(15) do
          line = output.gets

          assert_match(/\A\d+\n\z/, line.to_s, line || errors.read)
          yield Integer(line)
          Process.kill("TERM", process.pid)

          assert_predicate process.value, :success?, errors.read
        end
      ensure
        if process.alive?
          Process.kill("KILL", process.pid)
          process.join
        end
      end
    end
  end

  def http_get(port, path)
    TCPSocket.open("127.0.0.1", port) do |socket|
      socket.write("GET #{path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
      socket.read
    end
  end
end
