# frozen_string_literal: true

require "test_helper"

class DriverTest < Minitest::Test
  def test_class_lists_escape_controls_without_changing_stored_names
    options = RichRI::Options.new.parse(["--no-standard-docs", "--doc-dir", TestSupport::STORE, "--list"], defaults: "")
    instance = RichRI::Driver.new(options.driver_options)
    name = "Unsafe\e]52;c;AAAA\a\u202e"
    store = instance.stores.first
    store.cache[:modules] << name
    output, error = capture_io { instance.run }

    assert_empty error
    refute_match(/[\e\a\u202e]/, output)
    assert_includes output, "Unsafe\\u001b]52;c;AAAA\\u0007\\u202e"
    assert_includes store.module_names, name
  end

  def test_names_holding_pattern_characters_are_unknown_names
    ["RichRIExample[", "RichRIExample(", "(", "[", ")", "**", "Rich(?<name>", "R{2,1}", "RichRIExampl?",
     "Rich+", "Rich|RichRIExample"].each do |name|
      out, err, status = cli(name)

      assert_equal 1, status.exitstatus, name
      assert_empty out
      assert_includes err, "Nothing known about #{name}"
      refute_match(/from .*\.rb:\d+|RegexpError|char-class|parenthes/, err)
    end
  end

  def test_abbreviated_and_punctuated_names_are_still_found
    { "RichRIExam" => "= RichRIExample", "RichRIExample::Nes" => "= RichRIExample::Nested",
      "RichRIExample.[]" => "Look up a value by index.", "RichRI#ready?" => "Report whether" }.each do |name, text|
      out, err, status = cli(name)

      assert_predicate status, :success?, "#{name}: #{err}"
      assert_includes out, text
    end
  end

  def test_class_lists_take_names_as_literal_prefixes
    out, err, status = cli("--list", "RichRIExample::")

    assert_predicate status, :success?, err
    assert_equal "RichRIExample::Nested\n", out
    ["(", "Rich[", "Rich.*", "RichRIExampl.", "^Rich"].each do |name|
      out, err, status = cli("--list", name)

      assert_predicate status, :success?, "#{name}: #{err}"
      assert_empty err
      assert_empty out.strip, name
    end
  end

  def test_source_directory_display_escapes_controls_without_changing_lookup_paths
    Dir.mktmpdir("rich-ri-path-") do |dir|
      path = File.join(dir, "docs\e]52;c;AAAA\a")
      FileUtils.cp_r(TestSupport::STORE, path)
      args = ["--no-standard-docs", "--doc-dir", path]
      output, error, status = cli(*args, "--list-doc-dirs", docs: false)

      assert_predicate status, :success?, error
      refute_match(/[\e\a]/, output)
      assert_includes output, "docs\\u001b]52;c;AAAA\\u0007"
      output, error, status = cli(*args, "RichRIExample#map", docs: false)

      assert_predicate status, :success?, error
      assert_includes output, "Return transformed values."
    end
  end
end
