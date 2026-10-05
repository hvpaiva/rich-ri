# frozen_string_literal: true

module RichRI
  # The names that the stores holding pages answer to. A page is asked for as
  # "source:page" and RDoc knows each store by one source: "ruby", "site",
  # "home", the directory given to --doc-dir or, for a gem, the name of the
  # gem's directory, which runs name, version and platform together. RDoc
  # takes for the gem's name whatever precedes "-" and a digit there, so that
  # "http" finds the gem http-2 and a native gem has no usable name. Here a gem
  # answers to its own name, and every store to its source in full.
  class PageSources
    # "source:page", or "source:" for the list of its pages.
    NAME = /\A(?<source>[^:]+):(?!:)(?<page>.*)\z/

    def initialize(stores)
      @stores = stores
    end

    # The source, as RDoc knows it, of the store the name stands for, or nil.
    def resolve(name)
      store = @stores.find { |candidate| candidate.source == name } ||
              @stores.find { |candidate| candidate.gem_name == name }
      store&.source
    end

    # What completes a name being typed: the pages of the source it names, or
    # the sources it may yet come to name, each ready for its page.
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
