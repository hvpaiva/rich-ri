# frozen_string_literal: true

require "tmpdir"
require "rbconfig"
require_relative "../test/shell_support"

module ShellTests
  ROOT = File.expand_path("..", __dir__)
  ENGINES = %w[docker podman].freeze
  IMAGE = "localhost/rich-ri-shell-tests:ruby-4.0"
  TEST = "test/shell_test.rb"

  class Error < StandardError; end

  def self.runtime
    selected = ENV.fetch("RICH_RI_CONTAINER_RUNTIME", nil)
    raise Error, "RICH_RI_CONTAINER_RUNTIME must be docker or podman" if selected && !ENGINES.include?(selected)

    candidates = selected ? [selected] : ENGINES
    engine = candidates.find { |name| system(name, "info", out: File::NULL, err: File::NULL) }
    return engine if engine

    raise Error, "shell integration checks need Bash, Zsh, Fish and bash-completion 2.x, " \
                 "or a running #{selected || 'Docker or Podman'} engine. " \
                 "Start the engine and rerun bundle exec rake test:shells."
  end

  def self.verify_environment!
    target = ShellSupport.available? ? "native Bash, Zsh and Fish" : runtime
    puts "Shell integration checks will use #{target}."
  end

  def self.run(container: false)
    if !container && ShellSupport.available?
      puts "Shell integration checks: native Bash, Zsh and Fish."
      success = system({ "RICH_RI_REQUIRE_SHELLS" => "1" }, RbConfig.ruby, "-Ilib", "-Itest", TEST, chdir: ROOT)
      raise Error, "native shell integration tests failed" unless success

      return
    end

    run_container(runtime)
  end

  def self.run_container(engine)
    puts "Shell integration checks: isolated environment with #{engine}."
    Dir.mktmpdir("rich-ri-shell-image-") do |directory|
      image_file = File.join(directory, "id")
      built = system(engine, "build", "--file", "test/containers/Dockerfile", "--tag", IMAGE,
                     "--iidfile", image_file, ".", chdir: ROOT)
      raise Error, "shell test image build failed" unless built

      image = File.file?(image_file) ? File.read(image_file).strip : ""
      raise Error, "container build did not return an image ID" unless image.match?(/\A(?:sha256:)?[0-9a-f]{64}\z/)

      success = system(engine, "run", "--rm", "--network=none", "--read-only", "--cap-drop=ALL",
                       "--security-opt=no-new-privileges", "--tmpfs", "/tmp:rw,exec,nosuid,nodev,size=256m,mode=1777",
                       image, chdir: ROOT)
      raise Error, "container shell integration tests failed" unless success
    end
  end
end
