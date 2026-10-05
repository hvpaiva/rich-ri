# frozen_string_literal: true

require "test_helper"

class StoreTest < Minitest::Test
  DAMAGED = { "empty" => "", "truncated" => Marshal.dump({ modules: %w[One Two] })[0, 9],
              "nil" => Marshal.dump(nil), "text" => Marshal.dump("cache") }.freeze

  def with_store
    Dir.mktmpdir("rich-ri-store-") do |dir|
      store = File.join(dir, "ri")
      FileUtils.cp_r(TestSupport::STORE, store)
      yield store
    end
  end

  def lookup(store, *)
    cli("--no-standard-docs", "--doc-dir", store, *, docs: false)
  end

  # As written by another RDoc version: Marshal names a class this one lacks.
  def retired_class_data
    RDoc.const_set(:RetiredMethod, Class.new)
    Marshal.dump(RDoc::RetiredMethod.new)
  ensure
    RDoc.send(:remove_const, :RetiredMethod)
  end

  def test_damaged_cache_names_the_store_for_lookups_and_class_lists
    commands = [["RichRIExample"], ["--list"]]
    DAMAGED.each do |kind, content|
      with_store do |store|
        File.binwrite(File.join(store, "cache.ri"), content)
        commands.each do |args|
          out, err, status = lookup(store, *args)

          assert_equal 1, status.exitstatus, kind
          assert_empty out
          assert_equal "rich-ri: incompatible or damaged RI data in #{store}\n", err.lines.first, kind
          assert_includes err, "Regenerate the documentation with your current Ruby and RDoc."
          refute_includes err, "--help"
          refute_match(/from .*\.rb:\d+/, err)
        end
      end
    end
  end

  def test_searched_directories_are_listed_without_reading_a_damaged_cache
    with_store do |store|
      File.binwrite(File.join(store, "cache.ri"), "")
      out, err, status = lookup(store, "--list-doc-dirs")

      assert_predicate status, :success?, err
      assert_empty err
      assert_equal "#{store}\n", out
    end
  end

  def test_method_data_from_another_rdoc_names_the_store
    with_store do |store|
      File.binwrite(File.join(store, "RichRIExample/map-i.ri"), retired_class_data)
      out, err, status = lookup(store, "RichRIExample#map")

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: incompatible or damaged RI data in #{store}\n", err.lines.first
      assert_includes err, "gem rdoc GEM_NAME --ri"
      refute_includes err, "--help"
      out, err, status = lookup(store, "RichRIExample.build")

      assert_predicate status, :success?, err
      assert_includes out, "Create an example."
    end
  end

  def test_class_data_from_another_rdoc_names_the_store
    with_store do |store|
      File.binwrite(File.join(store, "RichRIExample/cdesc-RichRIExample.ri"), retired_class_data)
      out, err, status = lookup(store, "RichRIExample")

      assert_equal 1, status.exitstatus
      assert_empty out
      assert_equal "rich-ri: incompatible or damaged RI data in #{store}\n", err.lines.first
    end
  end

  def test_page_data_from_another_rdoc_names_the_store_while_missing_pages_stay_missing
    with_store do |path|
      File.binwrite(File.join(path, "page-GUIDE_rdoc.ri"), retired_class_data)
      options = RichRI::Options.new.parse(["--no-standard-docs", "--doc-dir", path], defaults: "")
      store = RichRI::Driver.new(options.driver_options).stores.first
      error = assert_raises(RichRI::StoreError) { store.load_page("GUIDE.rdoc") }

      assert_equal "incompatible or damaged RI data in #{path}", error.message
      assert_kind_of ArgumentError, error.cause
      assert_raises(RDoc::Store::MissingFileError) { store.load_page("MISSING.rdoc") }
    end
  end

  def test_all_keeps_the_class_page_when_one_method_cannot_be_read
    with_store do |store|
      File.binwrite(File.join(store, "RichRIExample/map-i.ri"), retired_class_data)
      out, err, status = lookup(store, "--all", "RichRIExample")

      assert_predicate status, :success?, err
      assert_empty err
      assert_includes out, "Create an example."
      assert_includes out, "Report whether this example is ready."
      refute_includes out, "Return transformed values."
      assert_includes out, "= RichRIExample#map"
      assert_match(/\(not shown: incompatible or damaged RI data in\s/, out)
    end
  end

  def test_dump_of_unreadable_data_names_the_file
    Dir.mktmpdir("rich-ri-store-") do |dir|
      { "retired.ri" => retired_class_data, "empty.ri" => "", "text.ri" => "not marshal data" }.each do |name, content|
        path = File.join(dir, name)
        File.binwrite(path, content)
        out, err, status = cli("--dump=#{path}", docs: false)

        assert_equal 1, status.exitstatus, name
        assert_empty out
        assert_equal "rich-ri: incompatible or damaged RI data in #{path}\n", err.lines.first
        assert_includes err, "Regenerate the documentation"
      end
    end
  end
end
