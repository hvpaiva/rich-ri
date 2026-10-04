# frozen_string_literal: true

require "test_helper"

class LegacyStoreTest < Minitest::Test
  def test_lookup_and_completion_handle_an_older_rdoc_store
    store = ENV.fetch("LEGACY_RI_STORE", nil)
    skip "Set LEGACY_RI_STORE to an RDoc 6.14 store; CI provides one" unless store
    sources = ["--no-standard-docs", "--doc-dir", store]
    out, err, status = cli(*sources, "--no-pager", "--color=always", "RichRIExample#map", docs: false)

    if RUBY_VERSION.start_with?("4.")
      refute_predicate status, :success?
      assert_includes err, "incompatible RI cache format"
      assert_includes err, "gem rdoc GEM_NAME --ri"
    else
      assert_predicate status, :success?, err
      assert_includes RichRI.plain(out), "Return transformed values."
      assert_includes out, "\e["
      out, err, status = cli("--complete", *sources, "RichRIExample#ma", docs: false)

      assert_predicate status, :success?, err
      assert_includes out, "RichRIExample#map\t"
    end
  end

  def test_cross_version_cache_error_explains_recovery
    skip "Ruby 3 keeps the older Struct representation" unless RUBY_VERSION.start_with?("4.")
    Dir.mktmpdir do |dir|
      cache = File.join(dir, "old.ri")
      source = <<~RUBY
        module RDoc
          module Markup
            Heading = Struct.new(:level, :text)
          end
        end
        File.binwrite(ARGV[0], Marshal.dump(RDoc::Markup::Heading.new(1, "Old documentation")))
      RUBY
      _out, err, status = Open3.capture3(RbConfig.ruby, "-e", source, cache)

      assert_predicate status, :success?, err
      _out, err, status = cli("--dump", cache, docs: false)

      refute_predicate status, :success?
      assert_includes err, "Regenerate the documentation"
      refute_includes err, "from "
    end
  end
end
