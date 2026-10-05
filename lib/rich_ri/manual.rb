# frozen_string_literal: true

require "fileutils"

module RichRI
  # RubyGems ships manuals inside the gem; installation into man(1)'s search
  # path is an explicit user action so gem installation never changes the shell.
  class Manual
    PAGER_SETTINGS = %w[MANPAGER PAGER MANROFFOPT GROFF_NO_SGR].freeze

    def path
      File.expand_path("../../man/man1/rich-ri.1", __dir__)
    end

    def show(color:, theme: Theme.new)
      result = system(pager_environment(color:, theme:), "man", path)
      raise Error, "man(1) not found; install it or run rich-ri --help" if result.nil?

      result ? 0 : 1
    end

    def install(target = nil)
      directory = install_directory(target)
      destination = File.join(directory, "rich-ri.1")
      raise Error, "refusing to replace a symbolic link: #{destination}" if File.symlink?(destination)
      if File.exist?(destination) && !File.file?(destination)
        raise Error, "manual destination is not a regular file: #{destination}"
      end

      FileUtils.mkdir_p(directory)
      FileUtils.cp(path, destination)
      puts "Installed #{RichRI.sanitize(destination)}"
      puts "If man rich-ri cannot find the page, add the setting for your shell:"
      puts "Bash/Zsh:"
      puts "  export MANPATH=#{Shellwords.escape(File.dirname(directory))}:\"${MANPATH:-}\""
      puts "Fish:"
      puts "  set -gx MANPATH #{Shellwords.escape(File.dirname(directory))} $MANPATH ''"
      puts "Run rich-ri --install-man again after upgrading the gem."
      0
    end

    private

    def install_directory(target)
      raise UsageError, "--install-man=DIR must not be empty" if target && target.strip.empty?

      data = ENV.fetch("XDG_DATA_HOME", nil)
      data = File.join(Dir.home, ".local/share") unless data&.start_with?("/")
      directory = File.expand_path(target || File.join(data, "man/man1"))
      # Without DIR the destination comes from the environment, not from the command line.
      refused = target ? UsageError : ConfigurationError
      if directory.match?(/[[:cntrl:]]/) || RichRI.sanitize(directory) != directory
        raise refused, "manual destination must not contain control characters"
      end
      unless File.basename(directory) == "man1"
        raise refused, "manual destination must be a man1 directory, such as ~/.local/share/man/man1"
      end
      if File.exist?(directory) && !File.directory?(directory)
        raise refused, "manual destination is not a directory: #{directory}"
      end

      directory
    end

    def pager_environment(color:, theme:)
      return {} unless color
      return {} if ENV.any? do |key, value|
        !value.empty? && (PAGER_SETTINGS.include?(key) || key.start_with?("LESS_TERMCAP_"))
      end

      { "GROFF_NO_SGR" => "1", "LESS_TERMCAP_md" => "\e[#{theme.sgr(:heading)}m",
        "LESS_TERMCAP_me" => RESET, "LESS_TERMCAP_us" => "\e[#{theme.sgr(:link)}m", "LESS_TERMCAP_ue" => RESET,
        "LESS_TERMCAP_so" => "\e[7m", "LESS_TERMCAP_se" => RESET }
    end
  end
end
