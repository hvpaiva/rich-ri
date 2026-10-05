# frozen_string_literal: true

module RichRI
  # The one action a command asks for instead of a lookup. Within a layer of options --help and
  # --version win and any other two conflict; a later layer (RI, file, command line) replaces it.
  class Actions
    FIRST = %i[help version].freeze
    # Every option that asks for an action, so the manual can list them.
    OPTIONS = { "--help" => :help, "--version" => :version, "--config-path" => :config_path,
                "--show-config" => :show_config, "--completion" => :completion, "--man" => :man,
                "--man-path" => :man_path, "--install-man" => :install_man, "--dump" => :dump, "--list" => :list,
                "--list-doc-dirs" => :list_doc_dirs, "--server" => :server, "--interactive" => :interactive }.freeze

    attr_reader :current

    def initialize
      @current = nil
      @chosen = {}
      @declined = []
    end

    def choose(option, *arguments)
      name = OPTIONS.fetch(option)
      @declined.delete(name)
      @chosen[name] = [option, [name, *arguments]]
    end

    def decline(option)
      name = OPTIONS.fetch(option)
      @declined |= [name]
      @chosen.delete(name)
      @current = nil if @current&.first == name
    end

    def declined?(name)
      @declined.include?(name)
    end

    def settle
      name = FIRST.find { |first| @chosen.key?(first) }
      if name.nil? && @chosen.length > 1
        raise UsageError, "#{@chosen.values.first(2).map(&:first).join(' and ')} cannot be used together"
      end

      name ||= @chosen.keys.first
      @current = @chosen.fetch(name).last if name
      @chosen = {}
      @current
    end
  end
end
