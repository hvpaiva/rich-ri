# frozen_string_literal: true

require_relative "manual"

module RichRI
  class CLI
    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      if argv.first == "--complete"
        Completion.new.write(argv.drop(1), $stdout)
        return 0
      end

      options = Options.new.parse(argv)
      return action(*options.action, options: options) if options.action

      driver_options = options.driver_options
      driver_options[:rich_ri_color] = color?(options.color)
      driver_options[:rich_ri_theme] = options.theme
      driver_options[:rich_ri_bat_theme] = options.bat_theme
      driver_options[:rich_ri_shell_theme] = options.shell_theme
      with_pager(options.pager_command) do
        if driver_options[:dump_path]
          dump(driver_options[:dump_path])
        else
          Driver.new(driver_options).run
        end
      end
      0
    rescue Errno::EPIPE
      0
    rescue OptionParser::ParseError, ArgumentError, RDoc::Error, TypeError, LoadError, SystemCallError, RegexpError => e
      if (dependency = optional_dependency(e))
        warn "rich-ri: --#{dependency == 'webrick' ? 'server' : 'profile'} requires the optional #{dependency} gem.\n" \
             "Install it for your active Ruby: gem install #{dependency}"
      elsif incompatible_cache?(e)
        warn "rich-ri: incompatible RI cache format for this Ruby and RDoc.\n" \
             "Regenerate the documentation with your current Ruby and RDoc. For gems: gem rdoc GEM_NAME --ri.\n" \
             "For Ruby core documentation, see https://github.com/hvpaiva/rich-ri/blob/main/docs/troubleshooting.md"
      else
        warn "rich-ri: #{RichRI.sanitize(e.message)}\nRun rich-ri --help for usage."
      end
      1
    rescue Interrupt
      130
    end

    private

    def optional_dependency(error)
      error.path if error.is_a?(LoadError) && %w[profile webrick].include?(error.path)
    end

    def incompatible_cache?(error)
      (error.is_a?(TypeError) && error.message.match?(/class RDoc::Markup::\w+ not a struct/)) ||
        (error.is_a?(ArgumentError) &&
          (error.message == "dump format error" || error.message.start_with?("undefined class/module RDoc::")))
    end

    def color?(mode)
      mode == "always" || (mode == "auto" && $stdout.tty? && ENV["TERM"] != "dumb" && ENV.fetch("NO_COLOR", "").empty?)
    end

    def action(name, value = nil, options:)
      case name
      when :help then help(options)
      when :version then puts "rich-ri #{VERSION}"
      when :config_path then puts options.configuration_path
      when :show_config then puts Psych.dump(options.settings)
      when :completion then puts File.read(File.expand_path("../../completions/rich-ri.#{value}", __dir__))
      when :man_path then puts Manual.new.path
      when :man then return Manual.new.show(color: color?(options.color), theme: options.theme)
      when :install_man
        unless options.driver_options[:names].empty?
          raise ArgumentError, "--install-man does not accept lookup names; use --install-man=DIR"
        end

        return Manual.new.install(value)
      end
      0
    end

    def dump(path)
      unless File.file?(path) && File.readable?(path)
        raise ArgumentError, "RI cache must be a readable regular file: #{path}"
      end

      Driver.dump(path)
    end

    def help(options)
      options.parser.to_s.each_line do |line|
        role = line.start_with?("Usage:") ? :title : :heading
        styled = line.match?(/\A\S.*:/) ? options.theme.paint(line, role, enabled: color?(options.color)) : line
        print styled
      end
    end

    def with_pager(command = nil)
      previous_pager = ENV.fetch("RI_PAGER", nil)
      ENV["RI_PAGER"] = command if command
      previous = ENV.fetch("LESS", nil)
      ENV["LESS"] = "-R #{previous || '-Fi'}"
      yield
    ensure
      ENV["LESS"] = previous
      ENV["RI_PAGER"] = previous_pager
    end
  end
end
