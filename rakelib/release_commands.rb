# frozen_string_literal: true

require "English"
require "json"
require "open3"
require_relative "github"
require_relative "release"

module Release
  class Commands
    def initialize(root:, runner: nil, out: $stdout)
      @root = root
      @runner = runner || method(:execute)
      @out = out
    end

    def call(argv, stream: false)
      argv += ["--repo", GitHub::REPOSITORY] if argv.first == "gh"
      @out.puts "==> #{argv.join(' ')}"
      output, status = @runner.call(argv, stream: stream)
      raise Error, "#{argv.join(' ')} failed.\n#{output}" unless status.success?

      output
    end

    def json(argv)
      JSON.parse(call(argv))
    rescue JSON::ParserError => e
      raise Error, "#{argv.join(' ')} returned unreadable JSON: #{e.message}"
    end

    private

    def execute(argv, stream: false)
      return start(argv) if stream

      output, diagnostics, status = Open3.capture3(*argv, chdir: @root)
      # Only standard output is data: a warning from ssh or gh must not read as a tag or as JSON.
      return ["#{output}#{diagnostics}", status] unless status.success?

      @out.print diagnostics
      [output, status]
    rescue Errno::ENOENT
      raise Error, "#{argv.first} is not installed or not on PATH"
    end

    def start(argv)
      # system answers nil, without raising, when the program cannot be started.
      raise Errno::ENOENT, argv.first if system(*argv, chdir: @root).nil?

      ["", $CHILD_STATUS]
    end
  end
end
