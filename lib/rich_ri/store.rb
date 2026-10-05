# frozen_string_literal: true

module RichRI
  # RDoc reads a store with Marshal and lets whatever that raises through. A
  # store written by another Ruby or RDoc, or cut short on disk, then fails as
  # a TypeError, ArgumentError, EOFError or NoMethodError that names no file.
  # This store reports all of them as a StoreError carrying its own path.
  class Store < RDoc::RI::Store
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

    # A missing file is an answer RDoc handles, and a failed system call
    # already says what is wrong with which file.
    def reading
      yield
    rescue Error, RDoc::Error, SystemCallError
      raise
    rescue StandardError
      raise StoreError, path
    end
  end
end
