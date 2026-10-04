# frozen_string_literal: true

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
          Driver.dump(driver_options[:dump_path])
        else
          Driver.new(driver_options).run
        end
      end
      0
    rescue OptionParser::ParseError, ArgumentError, RDoc::Error, TypeError, LoadError, Errno::ENOENT, Errno::EACCES => e
      warn "rich-ri: #{RichRI.sanitize(e.message)}\nRun rich-ri --help for usage."
      1
    rescue Errno::EPIPE
      0
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
      when :man_path then puts man_path
      when :man then return system("man", man_path) ? 0 : 1
      end
      0
    end

    def man_path
      File.expand_path("../../man/man1/rich-ri.1", __dir__)
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
