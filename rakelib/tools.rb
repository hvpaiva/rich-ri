# frozen_string_literal: true

# The programs the checks run besides Ruby and Git. mise.toml pins the lint tools
# at the versions CI uses; the system's package manager provides the rest.
module Tools
  MISE_TOML = File.expand_path("../mise.toml", __dir__)
  SYSTEM = %w[groff man].freeze
  TABLE = /\A\[(?<name>[^\]]+)\]\s*\z/
  ENTRY = /\A(?<tool>[a-z][a-z0-9-]*)\s*=\s*"(?<version>[^"]+)"/

  # The [tools] table as { name => version }. Ruby's standard library has no TOML
  # parser, and the table holds only quoted versions, which is all this reads.
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

  # Everything bundle exec rake check needs on PATH, apart from the shells.
  def self.required(pinned = self.pinned) = (pinned.keys - ["ruby"]) + SYSTEM

  def self.available?(tool)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
      path = File.join(directory, tool)
      File.file?(path) && File.executable?(path)
    end
  end

  # mise can hold a tool that is not on PATH until the shell activates mise, and
  # then "mise install" answers that nothing is missing: that case needs its own advice.
  def self.missing(tool, pinned = self.pinned, installed_by_mise: pinned.key?(tool) && mise_holds?(tool))
    if installed_by_mise
      "#{tool} is installed by mise but not on PATH; activate mise in your shell (mise activate --help)"
    elsif pinned.key?(tool)
      "#{tool} is not installed; install the version mise.toml pins with: mise install #{tool}"
    else
      "#{tool} is not installed; install it with your package manager"
    end
  end

  def self.mise_holds?(tool) = system("mise", "which", tool, out: File::NULL, err: File::NULL) || false

  # Prints one line of advice per missing program and returns their names.
  def self.report(out = $stdout)
    required.reject { |tool| available?(tool) }.each { |tool| out.puts "Missing: #{missing(tool)}" }
  end
end
