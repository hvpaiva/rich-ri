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
      refute_includes out, "not found"
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

  # A copy of the fixture store whose cache also lists the given names.
  def with_cached_names(modules: [], methods: [])
    Dir.mktmpdir("rich-ri-names-") do |dir|
      path = File.join(dir, "ri")
      FileUtils.cp_r(TestSupport::STORE, path)
      store = RDoc::RI::Store.new(RDoc::Options.new, path: path, type: :extra)
      store.load_cache
      store.cache[:modules].concat(modules)
      store.cache[:instance_methods]["RichRIExample"].concat(methods)
      store.save_cache
      yield ["--no-standard-docs", "--doc-dir", path]
    end
  end

  def test_unknown_name_is_reported_by_rich_ri_without_ending_the_process
    name = "NoSuch\e]52;c;AAAA\aName"
    out, err, status = cli(name)

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_equal "rich-ri: Nothing known about NoSuch\\u001b]52;c;AAAA\\u0007Name\n", err
    out, err = capture_io do
      assert_equal 1, RichRI::CLI.run(["--no-standard-docs", "--doc-dir", TestSupport::STORE, "NoSuchExample123"])
    end

    assert_empty out
    assert_equal "rich-ri: Nothing known about NoSuchExample123\n", err
  end

  def test_a_name_answered_with_suggestions_was_not_found
    out, err, status = cli("RichRIExample#ma")

    assert_equal 1, status.exitstatus
    assert_empty err
    assert_equal "RichRIExample#ma not found, maybe you meant:\n\nRichRIExample#map\n", out
    out, err, status = cli("RichRIExample#ma", "RichRIExample.build")

    assert_equal 1, status.exitstatus
    assert_empty err
    assert_includes out, "maybe you meant:"
    assert_includes out, "Create an example."
  end

  def test_a_page_answered_with_the_pages_of_its_source_was_not_found
    source = TestSupport::STORE
    { "#{source}:" => 0, "#{source}:GUIDE.rdoc" => 0, "#{source}:GUIDE" => 0, "#{source}:missing" => 1,
      "#{source}:GUID" => 1 }.each do |name, code|
      out, err, status = cli(name)

      assert_equal code, status.exitstatus, name
      assert_empty err
      assert_includes out, code.zero? && !name.end_with?(":") ? "= Example guide" : "GUIDE.rdoc"
    end
  end

  def test_a_page_name_that_matches_several_pages_was_not_found
    Dir.mktmpdir("rich-ri-pages-") do |dir|
      path = File.join(dir, "ri")
      FileUtils.cp_r(TestSupport::STORE, path)
      store = RDoc::RI::Store.new(RDoc::Options.new, path: path, type: :extra)
      store.load_cache
      store.cache[:pages] << "GUIDE.md"
      store.save_cache
      out, err, status = cli("--no-standard-docs", "--doc-dir", path, "#{path}:GUIDE", docs: false)

      assert_equal 1, status.exitstatus
      assert_empty err
      assert_includes out, "= GUIDE pages in"
      assert_includes out, "GUIDE.md"
    end
  end

  def test_suggestions_escape_controls_in_stored_names
    with_cached_names(modules: ["Unsafe\a"], methods: ["ma\e[31mx"]) do |sources|
      out, err, status = cli(*sources, "Unsafee", docs: false)

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: Nothing known about Unsafee\nDid you mean?  Unsafe\\u0007\n", err
      out, _err, status = cli(*sources, "RichRIExample#ma\e", docs: false)

      assert_equal 1, status.exitstatus
      refute_match(/[\e\a]/, out)
      assert_includes out, "RichRIExample#ma\\u001b not found, maybe you meant:"
      assert_includes out, "RichRIExample#ma\\u001b[31mx\n"
    end
  end

  # The command over the gems of the suite alone.
  def gems(*words, complete: false)
    sources = ["--no-system", "--no-site", "--no-home"]
    cli(*(complete ? ["--complete", *sources] : sources), *words, docs: false, env: TestSupport.gem_environment)
  end

  def test_a_gem_is_asked_for_by_its_name_whatever_its_version_and_platform
    { "inkwell-native:BUILDING" => "Compile the extension.", "inkwell-native:" => "BUILDING.rdoc",
      "inkwell-2:UPGRADING" => "Move from the first inkwell.", "inkwell:GUIDE" => "Keep the well full." }
      .each do |name, text|
      out, err, status = gems(name)

      assert_predicate status, :success?, "#{name}: #{err}"
      assert_includes out, text
    end
    out, err, status = gems("inkwell:")

    assert_predicate status, :success?, err
    assert_includes out, "GUIDE.rdoc"
    refute_includes out, "UPGRADING.rdoc"
  end

  def test_a_source_is_also_known_by_the_whole_name_of_its_directory
    { "inkwell-1.4.0:GUIDE" => "Keep the well full.", "inkwell-1.4.0:" => "GLOSSARY.rdoc",
      "inkwell-native-2.0.1-arm64-darwin-23:" => "BUILDING.rdoc",
      "inkwell-native-2.0.1-arm64-darwin-23:BUILDING.rdoc" => "Compile the extension." }.each do |name, text|
      out, err, status = gems(name)

      assert_predicate status, :success?, "#{name}: #{err}"
      assert_includes out, text
    end
  end

  def test_part_of_a_gem_name_or_of_its_directory_names_no_gem
    ["inkwell-native-2.0.1-arm64-darwin", "inkwell-native-2.0.1", "inkwell-nat"].each do |source|
      out, err, status = gems("#{source}:BUILDING")

      assert_equal 1, status.exitstatus, source
      assert_empty out
      assert_equal "rich-ri: Nothing known about #{source}\n", err
      out, = gems("#{source}:", complete: true)

      assert_empty out, source
    end
  end

  def test_completion_offers_each_gem_by_name_and_only_its_own_pages
    out, err, status = gems("inkwell", complete: true)

    assert_predicate status, :success?, err
    assert_equal %w[inkwell-2: inkwell-native: inkwell:], out.split
    assert_equal %w[inkwell:GLOSSARY.rdoc inkwell:GUIDE.rdoc], gems("inkwell:", complete: true).first.split
    assert_equal %w[inkwell-2:UPGRADING.rdoc], gems("inkwell-2:", complete: true).first.split
    assert_equal %w[inkwell-native:BUILDING.rdoc], gems("inkwell-native:B", complete: true).first.split
    assert_equal %w[inkwell-1.4.0:GUIDE.rdoc], gems("inkwell-1.4.0:GU", complete: true).first.split
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
