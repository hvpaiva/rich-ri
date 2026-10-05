# frozen_string_literal: true

module RichRI
  # RDoc names a gem's store after its directory and takes what precedes "-" and a digit for the
  # gem, so "http" finds http-2 and a native gem has no name. Here a gem answers to its own name.
  class PageSources
    NAME = /\A(?<source>[^:]+):(?!:)(?<page>.*)\z/

    def initialize(stores)
      @stores = stores
    end

    def resolve(name)
      store = @stores.find { |candidate| candidate.source == name } ||
              @stores.find { |candidate| candidate.gem_name == name }
      store&.source
    end

    def complete(name)
      page = NAME.match(name)
      return pages(page[:source], page[:page]) if page
      return [] if name.match?(/[.#:]/)

      holding = @stores.reject { |store| store.page_names.empty? }
      holding.map { |store| "#{store.page_source}:" }.select { |source| source.start_with?(name) }
    end

    private

    def pages(source, prefix)
      named = @stores.select { |store| [store.source, store.gem_name].include?(source) }
      named.flat_map(&:page_names).select { |page| page.start_with?(prefix) }.map { |page| "#{source}:#{page}" }
    end
  end
end
