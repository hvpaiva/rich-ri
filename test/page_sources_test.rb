# frozen_string_literal: true

require "test_helper"

class PageSourcesTest < Minitest::Test
  Store = Struct.new(:source, :gem_name, :page_names) do
    def page_source = gem_name || source
  end

  def sources
    RichRI::PageSources.new([Store.new("ruby", nil, %w[NEWS.md syntax/literals.rdoc syntax/methods.rdoc]),
                             Store.new("http-2-1.0.0", "http-2", %w[README.md]),
                             Store.new("nokogiri-1.18.9-x86_64-linux", "nokogiri", %w[README.md ROADMAP.md]),
                             Store.new("site", nil, []), Store.new("/srv/docs/ri", nil, %w[GUIDE.rdoc])])
  end

  def test_a_gem_answers_to_its_name_and_every_store_to_its_whole_source
    { "ruby" => "ruby", "http-2" => "http-2-1.0.0", "http-2-1.0.0" => "http-2-1.0.0",
      "nokogiri" => "nokogiri-1.18.9-x86_64-linux", "site" => "site", "/srv/docs/ri" => "/srv/docs/ri" }
      .each { |name, source| assert_equal source, sources.resolve(name) }
  end

  def test_the_start_of_a_name_or_of_a_directory_stands_for_no_store
    ["http", "http-2-1", "nokogiri-1.18.9", "nokogiri-1.18.9-x86_64", "rub", "", "home"].each do |name|
      assert_nil sources.resolve(name), name
    end
  end

  def test_a_name_without_a_colon_completes_to_the_sources_that_hold_pages
    assert_equal %w[/srv/docs/ri: http-2: nokogiri: ruby:], sources.complete("").sort
    assert_equal %w[http-2:], sources.complete("h")
    assert_equal %w[nokogiri:], sources.complete("nokogiri")
    assert_empty sources.complete("s")
    assert_empty sources.complete("Http")
  end

  def test_a_source_completes_to_its_pages_under_the_name_it_was_given
    assert_equal %w[ruby:syntax/literals.rdoc ruby:syntax/methods.rdoc], sources.complete("ruby:syn")
    assert_equal %w[nokogiri:README.md nokogiri:ROADMAP.md], sources.complete("nokogiri:R")
    assert_equal %w[http-2-1.0.0:README.md], sources.complete("http-2-1.0.0:")
    assert_empty sources.complete("http:")
    assert_empty sources.complete("site:")
  end

  def test_a_class_or_method_name_is_no_source
    ["Net::HTTP", "ruby::", "Array#map", "File.open", "ruby.", "::ruby"].each do |name|
      refute_match RichRI::PageSources::NAME, name
      assert_empty sources.complete(name), name
    end
  end
end
