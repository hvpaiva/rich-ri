# frozen_string_literal: true

require "json"
require "open3"

module GitHub
  REPOSITORY = "hvpaiva/rich-ri"
  ROOT = File.expand_path("..", __dir__)
  ORIGIN = %r{\A(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)#{Regexp.escape(REPOSITORY)}(?:\.git)?\z}

  class Error < StandardError; end

  Response = Data.define(:status, :body)
  Change = Data.define(:description, :verb, :path, :body)

  # Keep HTTP errors distinct from disabled features. In particular, a forbidden
  # request must never be interpreted as a missing setting that needs creating.
  class Client
    def initialize(root: ROOT, runner: nil)
      @root = root
      @runner = runner || method(:execute)
    end

    def request(path, method: "GET", body: nil, missing: false)
      argv = ["gh", "api", "--include", "--method", method, "repos/#{REPOSITORY}#{path}"]
      argv += ["--input", "-"] if body
      output, status = @runner.call(argv, stdin_data: body && JSON.generate(body))
      header, content = output.split(/\r?\n\r?\n/, 2)
      code = header[%r{\AHTTP/[\d.]+ (\d+)}, 1].to_i
      parsed = content.to_s.empty? ? {} : JSON.parse(content)
      unless status.success? || (missing && code == 404)
        raise Error, "GitHub #{method} #{path}: #{code.zero? ? output.strip : "HTTP #{code}: #{parsed['message']}"}"
      end

      Response.new(code, parsed)
    rescue JSON::ParserError
      raise Error, "GitHub #{method} #{path}: unreadable response (#{output.strip})"
    end

    private

    def execute(argv, stdin_data: nil)
      output, error, status = Open3.capture3(*argv, stdin_data: stdin_data, chdir: @root)
      [output.empty? ? error : output, status]
    end
  end

  def self.origin?(url) = url.strip.match?(ORIGIN)

  def self.verify_origin!(root: ROOT)
    origin, status = Open3.capture2("git", "remote", "get-url", "origin", chdir: root)
    return if status.success? && origin?(origin)

    raise Error, "The origin repository must be #{REPOSITORY}"
  end
end
