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
