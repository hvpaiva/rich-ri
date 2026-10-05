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
    ["RichRIExample[", "RichRIExample(", "(", "[", ")", "**", "Rich(?<name>", "R{2,1}", "RichRIExamples?",
     "Rich+", "Rich|RichRIExample"].each do |name|
      out, err, status = cli(name)

      assert_equal 1, status.exitstatus, name
      assert_empty out
      assert_equal "rich-ri: #{name} not found\n", err
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
    ["(", "Rich[", "Rich.*", "RichRIExample.", "^Rich"].each do |name|
      out, err, status = cli("--list", name)

      assert_predicate status, :success?, "#{name}: #{err}"
      assert_empty err
      assert_empty out.strip, name
    end
  end

  def test_unknown_name_is_reported_by_rich_ri_without_ending_the_process
    name = "NoSuch\e]52;c;AAAA\aName"
    out, err, status = cli(name)

    assert_equal 1, status.exitstatus
    assert_empty out
    assert_equal "rich-ri: NoSuch\\u001b]52;c;AAAA\\u0007Name not found\n", err
    out, err = capture_io do
      assert_equal 1, RichRI::CLI.run(["--no-standard-docs", "--doc-dir", TestSupport::STORE, "NoSuchExample123"])
    end

    assert_empty out
    assert_equal "rich-ri: NoSuchExample123 not found\n", err
  end

  def test_a_name_answered_with_suggestions_was_not_found
    out, err, status = cli("RichRIExample#ma")

    assert_equal 1, status.exitstatus
    assert_equal "rich-ri: RichRIExample#ma not found\n", err
    assert_equal "RichRIExample#ma not found, maybe you meant:\n\nRichRIExample#map\n", out
    out, err, status = cli("RichRIExample#ma", "RichRIExample.build")

    assert_equal 1, status.exitstatus
    assert_equal "rich-ri: RichRIExample#ma not found\n", err
    assert_includes out, "maybe you meant:"
    assert_includes out, "Create an example."
  end

  def test_a_page_answered_with_the_pages_of_its_source_was_not_found
    source = TestSupport::STORE
    { "#{source}:" => 0, "#{source}:GUIDE.rdoc" => 0, "#{source}:GUIDE" => 0, "#{source}:missing" => 1,
      "#{source}:GUID" => 1 }.each do |name, code|
      out, err, status = cli(name)

      assert_equal code, status.exitstatus, name
      assert_equal code.zero? ? "" : "rich-ri: #{name} not found\n", err
      assert_includes out, code.zero? && !name.end_with?(":") ? "= Example guide" : "GUIDE.rdoc"
    end
  end

  def test_a_page_name_that_matches_several_pages_was_not_found
    with_cached_names(pages: ["GUIDE.md"]) do |sources|
      out, err, status = cli(*sources, "#{sources.last}:GUIDE", docs: false)

      assert_equal 1, status.exitstatus
      assert_equal "rich-ri: #{sources.last}:GUIDE not found\n", err
      assert_includes out, "= GUIDE pages in"
      assert_includes out, "GUIDE.md"
    end
  end

  def test_suggestions_escape_controls_in_stored_names
    with_cached_names(modules: ["Unsafe\a"], methods: ["ma\e[31mx"]) do |sources|
      out, err, status = cli(*sources, "Unsafee", docs: false)

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: Unsafee not found\nDid you mean?  Unsafe\\u0007\n", err
      out, err, status = cli(*sources, "RichRIExample#ma\e", docs: false)

      assert_equal 1, status.exitstatus
      assert_equal "rich-ri: RichRIExample#ma\\u001b not found\n", err
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

  # The names --complete offers over those gems, without the last line of
  # its answer, which says what the shell is to do with them.
  def gem_candidates(word)
    gems(word, complete: true).first.lines(chomp: true)[0...-1].map { |line| line.split("\t").first }
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
      assert_equal "rich-ri: #{source} not found\n", err
      assert_empty gem_candidates("#{source}:"), source
    end
  end

  def test_completion_offers_each_gem_by_name_and_only_its_own_pages
    out, err, status = gems("inkwell", complete: true)

    assert_predicate status, :success?, err
    assert_equal "inkwell-2:\t\ninkwell-native:\t\ninkwell:\t\n:\n", out
    assert_equal %w[inkwell:GLOSSARY.rdoc inkwell:GUIDE.rdoc], gem_candidates("inkwell:")
    assert_equal %w[inkwell-2:UPGRADING.rdoc], gem_candidates("inkwell-2:")
    assert_equal %w[inkwell-native:BUILDING.rdoc], gem_candidates("inkwell-native:B")
    assert_equal %w[inkwell-1.4.0:GUIDE.rdoc], gem_candidates("inkwell-1.4.0:GU")
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
