# frozen_string_literal: true

module RichRI
  # RDoc's own server listens on every interface; the documentation is for this machine only.
  class Server
    ADDRESS = "127.0.0.1"

    def initialize(port:, doc_dirs:)
      @port = port
      @doc_dirs = doc_dirs
    end

    def start
      server = WEBrick::HTTPServer.new(BindAddress: ADDRESS, Port: @port)
      server.mount("/", RDoc::RI::Servlet, nil, @doc_dirs)
      previous = %w[INT TERM].to_h { |signal| [signal, trap(signal) { server.shutdown }] }
      server.start
    ensure
      previous&.each { |signal, handler| trap(signal, handler || "DEFAULT") }
    end
  end
end
