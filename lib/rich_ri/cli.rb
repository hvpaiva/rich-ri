# frozen_string_literal: true

require_relative "manual"

module RichRI
  class CLI
    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      argv = argv.map { |argument| RichRI.utf8(argument) }
      if argv.first == "--complete"
        Completion.new.write(argv.drop(1), $stdout)
        return 0
      end

      options = Options.new.parse(argv)
      status = options.action ? action(*options.action, options: options) : lookup(options)
      # Buffered output that cannot be written must not pass for success.
      $stdout.flush
      status
    rescue Errno::EPIPE
      0
    rescue Interrupt
      130
    rescue StandardError, ScriptError => e
      Error.report(e)
    end

    private

    def lookup(options)
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
    end

    def color?(mode)
      mode == "always" || (mode == "auto" && $stdout.tty? && ENV["TERM"] != "dumb" && ENV.fetch("NO_COLOR", "").empty?)
    end

    def action(name, value = nil, options:)
      case name
      when :help then help(options)
      when :version then puts "rich-ri #{VERSION}"
      when :config_path then puts options.configuration_path
      when :show_config then puts Psych.safe_dump(options.settings)
      when :completion then puts File.read(File.expand_path("../../completions/rich-ri.#{value}", __dir__))
      when :man_path then puts Manual.new.path
      when :man then return Manual.new.show(color: color?(options.color), theme: options.theme)
      when :install_man
        unless options.driver_options[:names].empty?
          raise UsageError, "--install-man does not accept lookup names; use --install-man=DIR"
        end

        return Manual.new.install(value)
      end
      0
    end

    def dump(path)
      raise Error, "RI cache must be a readable regular file: #{path}" unless File.file?(path) && File.readable?(path)

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
      ENV["LESS"] = "#{previous || '-Fi'} -R"
      yield
    ensure
      ENV["LESS"] = previous
      ENV["RI_PAGER"] = previous_pager
    end
  end
end
