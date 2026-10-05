# frozen_string_literal: true

require "test_helper"
require "json"

class BenchmarkTest < Minitest::Test
  CASES = %w[startup render completion].freeze

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

  def test_an_unusable_baseline_is_refused_before_anything_is_measured
    missing = File.join(TestSupport::TEMP, "missing-benchmark.json")
    { missing => "Cannot read #{missing}: No such file or directory",
      report("{}") => "is not a benchmark report", report("[1]") => "is not a benchmark report",
      report("not JSON") => "is not a benchmark report",
      report('{"median_ms":{"startup":"fast"}}') => "is not a benchmark report" }.each do |path, reason|
      out, err, status = benchmark("--compare", path)

      assert_equal 1, status.exitstatus
      assert_match(/\Abenchmark: .*#{Regexp.escape(reason)}/, err)
      assert_equal 1, err.lines.length
      assert_empty out
    end
  end

  def test_a_run_saves_its_report_and_names_only_the_cases_slower_than_the_baseline
    saved = File.join(TestSupport::TEMP, "benchmark.json")
    baseline = report(JSON.generate("median_ms" => { "startup" => 60_000, "render" => 0.01, "completion" => 0.01 }))
    out, err, status = benchmark("--iterations=1", "--output", saved, "--compare", baseline)

    assert_equal 1, status.exitstatus
    assert_equal "benchmark: Slower by more than 30% and 50 ms: render, completion\n", err
    assert_equal out, File.read(saved)
    assert_equal CASES, JSON.parse(out).fetch("median_ms").keys
    assert_equal 1, JSON.parse(out).fetch("iterations")
  end

  private

  def report(content)
    @reports = @reports.to_i + 1
    File.join(TestSupport::TEMP, "baseline-#{@reports}.json").tap { |path| File.write(path, content) }
  end

  def benchmark(*)
    Open3.capture3(TestSupport::ENVIRONMENT, RbConfig.ruby, File.join(TestSupport::ROOT, "bin/benchmark"), *)
  end
end
