# frozen_string_literal: true

require "fileutils"
require "open3"

# Run the checkout's rake, or programs on a PATH the test builds so the machine's own cannot answer.
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

  # Ruby's own directory may also hold system programs, so only Ruby and Bundler are linked.
  def link_ruby(directory, bundler: true)
    link_program(directory, "ruby", RbConfig.ruby)
    link_program(directory, "bundle", Gem.bin_path("bundler", "bundle")) if bundler
  end

  def rake(*, env: {}, chdir: TestSupport::ROOT)
    Open3.capture3(env, RbConfig.ruby, Gem.bin_path("rake", "rake"), "-f", File.join(TestSupport::ROOT, "Rakefile"), *,
                   chdir: chdir)
  end

  # rake with nothing on PATH but Ruby, Bundler, rake and what the test puts in the directory.
  def isolated_rake(bin, *)
    link_ruby(bin)
    link_program(bin, "rake", Gem.bin_path("rake", "rake"))
    Open3.capture3({ "PATH" => bin }, File.join(bin, "bundle"), "exec", "rake", *, chdir: TestSupport::ROOT)
  end

  def which(name)
    ENV.fetch("PATH").split(File::PATH_SEPARATOR).map { |directory| File.join(directory, name) }
       .find { |path| File.file?(path) && File.executable?(path) }
  end
end
