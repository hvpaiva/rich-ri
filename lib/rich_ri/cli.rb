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
      with_pager do
        if driver_options[:dump_path]
          dump(driver_options[:dump_path])
        else
          Driver.new(driver_options).run
        end
      end
      0
    rescue Errno::EPIPE
      0
    rescue OptionParser::ParseError, ArgumentError, RDoc::Error, TypeError, LoadError, SystemCallError => e
      warn "rich-ri: #{RichRI.sanitize(e.message)}\nRun rich-ri --help for usage."
      1
    rescue Interrupt
      130
    end

    private

    def color?(mode)
      mode == "always" || (mode == "auto" && $stdout.tty? && ENV["TERM"] != "dumb" && ENV.fetch("NO_COLOR", "").empty?)
    end

    def action(name, value = nil, options:)
      case name
      when :help then help(options)
      when :version then puts "rich-ri #{VERSION}"
      when :completion then puts File.read(File.expand_path("../../completions/rich-ri.#{value}", __dir__))
      when :man_path then puts Manual.new.path
      when :man then return Manual.new.show(color: color?(options.color))
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
        styled = line.match?(/\A\S.*:/) ? RichRI.paint(line, role, enabled: color?(options.color)) : line
        print styled
      end
    end

    def with_pager
      previous = ENV.fetch("LESS", nil)
      ENV["LESS"] = "#{previous || '-Fi'} -R"
      yield
    ensure
      ENV["LESS"] = previous
    end
  end
end
