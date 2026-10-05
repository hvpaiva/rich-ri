# frozen_string_literal: true

require "fileutils"

# Programs for a PATH that a test builds itself, so the machine's own programs cannot answer.
module ProgramSupport
  def write_program(directory, name, body = "exit 0")
    path = File.join(directory, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    FileUtils.chmod(0o755, path)
    path
  end

  def link_program(directory, name, target = which(name))
    File.symlink(target, File.join(directory, name))
  end

  def which(name)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, name) }
       .find { |path| File.file?(path) && File.executable?(path) }
  end
end
