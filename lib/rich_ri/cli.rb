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
      driver_options[:rich_ri_pager] = options.pager_command
      return dump(driver_options[:dump_path]) if driver_options[:dump_path]

      Driver.new(driver_options).run
    end

    def color?(mode)
      mode == "always" || (mode == "auto" && $stdout.tty? && ENV["TERM"] != "dumb" && ENV.fetch("NO_COLOR", "").empty?)
    end

    def action(name, value = nil, options:)
      case name
      when :help then help(options)
      when :version then puts "rich-ri #{VERSION}"
      when :config_path then puts options.configuration_path
      when :show_config then puts settings_yaml(options.settings)
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

    # Psych leaves controls Unicode calls printable, such as bidi overrides, as they are. Double
    # quotes are the only YAML style where \uXXXX is an escape, so the output loads unchanged.
    def settings_yaml(settings)
      yaml = Psych.safe_dump(settings)
      return yaml if RichRI.printable?(yaml)

      document = Psych.parse_stream(yaml)
      document.grep(Psych::Nodes::Scalar).each do |scalar|
        next if RichRI.printable?(scalar.value)

        scalar.style = Psych::Nodes::Scalar::DOUBLE_QUOTED
        scalar.plain = false
        scalar.quoted = true
      end
      document.to_yaml.gsub(CONTROL) { |char| format(char.ord > 0xFFFF ? "\\U%08X" : "\\u%04X", char.ord) }
    end

    def dump(path)
      raise Error, "RI cache must be a readable regular file: #{path}" unless File.file?(path) && File.readable?(path)

      Driver.dump(path)
      0
    end

    # Only a line ending in a colon is a heading: the notes hold colons mid-sentence.
    def help(options)
      enabled = color?(options.color)
      options.parser.to_s.each_line do |line|
        role = if line.start_with?("Usage:") then :title
               elsif line.match?(/\A\S.*:$/) then :heading
               end
        print role ? options.theme.paint(line, role, enabled:) : line
      end
    end
  end
end
