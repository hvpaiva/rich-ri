# frozen_string_literal: true

require "English"
require "json"
require "open3"
require_relative "github"

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
      raise "#{argv.join(' ')} failed.\n#{output}" unless status.success?

      output
    end

    def json(argv)
      JSON.parse(call(argv))
    end

    private

    def execute(argv, stream: false)
      if stream
        system(*argv, chdir: @root)
        return ["", $CHILD_STATUS]
      end

      output, error, status = Open3.capture3(*argv, chdir: @root)
      [status.success? ? output : output + error, status]
    end
  end
end
