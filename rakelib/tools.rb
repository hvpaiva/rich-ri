# frozen_string_literal: true

module Tools
  MISE_TOML = File.expand_path("../mise.toml", __dir__)
  SYSTEM = %w[groff man].freeze
  TABLE = /\A\[(?<name>[^\]]+)\]\s*\z/
  ENTRY = /\A(?<tool>[a-z][a-z0-9-]*)\s*=\s*"(?<version>[^"]+)"/

  class Error < StandardError; end

  def self.mise_tools = pinned - ["ruby"]

  def self.require!(tool)
    raise Error, missing(tool) unless available?(tool)
  end

  def self.problems = (mise_tools + SYSTEM).reject { |tool| available?(tool) }.map { |tool| missing(tool) }

  # The standard library has no TOML parser; [tools] holds only quoted versions.
  def self.pinned
    table = nil
    File.foreach(MISE_TOML, chomp: true).each_with_object([]) do |line, tools|
      if (header = TABLE.match(line))
        table = header[:name]
      elsif table == "tools" && (entry = ENTRY.match(line))
        tools << entry[:tool]
      end
    end
  end

  def self.available?(tool)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      path = File.join(directory, tool)
      File.file?(path) && File.executable?(path)
    end
  end

  # A tool mise holds is off PATH until mise is activated, and "mise install" then reports nothing.
  def self.missing(tool)
    if !mise_tools.include?(tool)
      "#{tool} is not installed; install it with your package manager"
    elsif system("mise", "which", tool, out: File::NULL, err: File::NULL)
      "#{tool} is installed by mise but not on PATH; activate mise in your shell (mise activate --help)"
    else
      "#{tool} is not installed; install the version mise.toml pins with: mise install #{tool}"
    end
  end

  private_class_method :pinned, :available?
end
