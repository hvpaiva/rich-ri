# frozen_string_literal: true

module Tools
  MISE_TOML = File.expand_path("../mise.toml", __dir__)
  SYSTEM = %w[groff man].freeze
  TABLE = /\A\[(?<name>[^\]]+)\]\s*\z/
  ENTRY = /\A(?<tool>[a-z][a-z0-9-]*)\s*=\s*"(?<version>[^"]+)"/

  # The standard library has no TOML parser; [tools] holds only quoted versions.
  def self.pinned(path = MISE_TOML)
    table = nil
    File.foreach(path, chomp: true).each_with_object({}) do |line, tools|
      if (header = TABLE.match(line))
        table = header[:name]
      elsif table == "tools" && (entry = ENTRY.match(line))
        tools[entry[:tool]] = entry[:version]
      end
    end
  end

  def self.required(pinned = self.pinned) = (pinned.keys - ["ruby"]) + SYSTEM

  def self.available?(tool)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      path = File.join(directory, tool)
      File.file?(path) && File.executable?(path)
    end
  end

  # A tool mise holds is off PATH until mise is activated, and "mise install" then reports nothing.
  def self.missing(tool, pinned = self.pinned, installed_by_mise: pinned.key?(tool) && mise_holds?(tool))
    if installed_by_mise
      "#{tool} is installed by mise but not on PATH; activate mise in your shell (mise activate --help)"
    elsif pinned.key?(tool)
      "#{tool} is not installed; install the version mise.toml pins with: mise install #{tool}"
    else
      "#{tool} is not installed; install it with your package manager"
    end
  end

  def self.require!(tool)
    abort missing(tool) unless available?(tool)
  end

  def self.mise_holds?(tool) = system("mise", "which", tool, out: File::NULL, err: File::NULL) || false

  def self.report(out = $stdout)
    required.reject { |tool| available?(tool) }.each { |tool| out.puts "Missing: #{missing(tool)}" }
  end
end
