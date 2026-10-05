# frozen_string_literal: true

module RichRI
  # RDoc lets Marshal failures through, so a store from another Ruby or RDoc, or cut short,
  # fails as a TypeError, ArgumentError, EOFError or NoMethodError naming no file.
  class Store < RDoc::RI::Store
    attr_accessor :gem_name

    def page_source
      gem_name || source
    end

    def page_names
      cache[:pages] || []
    end

    def load_cache
      reading { super }
    end

    def load_class_data(klass_name)
      reading { super }
    end

    def load_method(klass_name, method_name)
      reading { super }
    end

    def load_page(page_name)
      reading { super }
    end

    private

    def reading
      yield
    rescue TypeError, ArgumentError, EOFError, NoMethodError
      raise StoreError, path
    end
  end
end
