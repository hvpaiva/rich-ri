# frozen_string_literal: true

require "test_helper"
require "json"

class BenchmarkTest < Minitest::Test
  CASES = %w[startup render completion].freeze

  def setup
    @tree = Dir.mktmpdir("rich-ri-benchmark-tree-")
    @calls = File.join(@tree, "calls.log")
    FileUtils.mkdir_p(File.join(@tree, "bin"))
    FileUtils.cp(File.join(TestSupport::ROOT, "bin/benchmark"), File.join(@tree, "bin"))
    FileUtils.mkdir_p(File.join(@tree, "test/fixtures"))
    FileUtils.cp(File.join(TestSupport::ROOT, "test/fixtures/example.rb"), File.join(@tree, "test/fixtures"))
    rich_ri("File.write(#{@calls.dump}, \"\#{ARGV.join(' ')}\\n\", mode: 'a')")
  end

  def teardown
    FileUtils.remove_entry(@tree)
  end

  def test_invalid_arguments_print_usage_instead_of_a_backtrace
    { ["--bogus"] => "invalid option: --bogus",
      ["--iterations", "0"] => "invalid argument: --iterations=0 (use 1 to 50)",
      ["--iterations=51"] => "invalid argument: --iterations=51 (use 1 to 50)",
      ["--iterations", "many"] => "invalid argument: --iterations many",
      ["unexpected"] => "needless argument: unexpected" }.each do |arguments, reason|
      out, err, status = benchmark(*arguments)

      assert_equal 2, status.exitstatus, arguments.inspect
      assert_equal "benchmark: #{reason}", err.lines.first.chomp
      assert_includes err, "Usage: ruby bin/benchmark"
      assert_empty out
    end
  end

  def test_a_missing_baseline_is_refused_before_rich_ri_runs
    missing = File.join(@tree, "missing.json")
    out, err, status = benchmark("--compare", missing)

    assert_equal [1, "", "benchmark: Cannot read #{missing}: No such file or directory\n"],
                 [status.exitstatus, out, err]
    refute_path_exists @calls
  end

  def test_a_baseline_that_is_not_a_report_is_refused_before_rich_ri_runs
    ["{}", "[1]", "not JSON", '{"median_ms":{"startup":"fast"}}'].each do |content|
      path = report(content)
      out, err, status = benchmark("--compare", path)

      assert_equal [1, "", "benchmark: #{path} is not a benchmark report\n"], [status.exitstatus, out, err]
    end
    refute_path_exists @calls
  end

  def test_a_run_prints_and_saves_one_median_per_case
    saved = File.join(@tree, "benchmark.json")
    out, err, status = benchmark("--iterations=1", "--output", saved)

    assert_predicate status, :success?, err
    assert_equal out, File.read(saved)
    assert_equal CASES, JSON.parse(out).fetch("median_ms").keys
    assert_equal 1, JSON.parse(out).fetch("iterations")
  end

  def test_only_the_cases_slower_than_the_baseline_are_named
    baseline = report(JSON.generate("median_ms" => { "startup" => 1e9, "render" => -1000, "completion" => -1000 }))
    _out, err, status = benchmark("--iterations=1", "--compare", baseline)

    assert_equal [1, "benchmark: Slower by more than 30% and 50 ms: render, completion\n"], [status.exitstatus, err]
  end

  def test_an_unwritable_report_is_named_in_one_line
    saved = File.join(@tree, "missing/benchmark.json")
    out, err, status = benchmark("--iterations=1", "--output", saved)

    assert_equal [1, "", "benchmark: Cannot write #{saved}: No such file or directory\n"],
                 [status.exitstatus, out, err]
  end

  def test_a_failing_rich_ri_is_named_with_its_error
    rich_ri("warn 'rich-ri: broken'; exit 3")
    out, err, status = benchmark("--iterations=1")

    assert_equal [1, "", "benchmark: rich-ri --no-config --version failed:\nrich-ri: broken\n"],
                 [status.exitstatus, out, err]
  end

  private

  def rich_ri(source)
    FileUtils.mkdir_p(File.join(@tree, "exe"))
    File.write(File.join(@tree, "exe/rich-ri"), "#{source}\n")
  end

  def report(content)
    @reports = @reports.to_i + 1
    File.join(@tree, "baseline-#{@reports}.json").tap { |path| File.write(path, content) }
  end

  def benchmark(*)
    Open3.capture3(TestSupport::ENVIRONMENT, RbConfig.ruby, File.join(@tree, "bin/benchmark"), *)
  end
end
