# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "flightbyte"
require "json"
require "socket"
require "stringio"
require "uri"
require "minitest/autorun"

module FlightByteTest
  ROOT = File.expand_path("..", __dir__)

  # A fixture file's text, byte for byte as stored, read as UTF-8 whatever the
  # locale says.
  def self.fixture(name)
    File.binread(File.join(ROOT, "test", "fixtures", name)).force_encoding(Encoding::UTF_8)
  end

  # The vendored OpenAPI document.
  def self.spec
    @spec ||= JSON.parse(File.binread(File.join(ROOT, "spec", "openapi.json")).force_encoding(Encoding::UTF_8))
  end

  # A real HTTP/1.1 server on 127.0.0.1, so requests go through Net::HTTP,
  # sockets and all, and never reach the network. Each request is recorded
  # and answered by the handler, which returns `[status, headers, body]`, or
  # `:raw` after writing to the socket itself.
  class FakeServer
    Request = Struct.new(:verb, :path, :query, :headers, :body, keyword_init: true) do
      def params
        URI.decode_www_form(query.to_s).to_h
      end
    end

    REASONS = {
      200 => "OK", 201 => "Created", 204 => "No Content", 301 => "Moved Permanently", 302 => "Found",
      307 => "Temporary Redirect", 308 => "Permanent Redirect", 400 => "Bad Request", 401 => "Unauthorized",
      402 => "Payment Required", 403 => "Forbidden", 404 => "Not Found", 409 => "Conflict",
      422 => "Unprocessable Entity", 429 => "Too Many Requests", 500 => "Internal Server Error",
      502 => "Bad Gateway", 503 => "Service Unavailable"
    }.freeze

    attr_reader :url

    def initialize(&handler)
      @handler = handler || proc { [200, { "content-type" => "application/json" }, "{}"] }
      @server = TCPServer.new("127.0.0.1", 0)
      @url = "http://127.0.0.1:#{@server.addr[1]}"
      @requests = []
      @threads = []
      @mutex = Mutex.new
      @acceptor = Thread.new { accept_loop }
    end

    # Every request received so far.
    def requests
      @mutex.synchronize { @requests.dup }
    end

    def last
      requests.last or raise "no request was sent"
    end

    def close
      @acceptor.kill
      @mutex.synchronize { @threads.each(&:kill) }
      @server.close
    rescue IOError
      nil
    end

    private

    def accept_loop
      loop do
        socket = @server.accept
        @mutex.synchronize { @threads << Thread.new(socket) { |s| serve(s) } }
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def serve(socket)
      request = read_request(socket)
      return if request.nil?

      @mutex.synchronize { @requests << request }
      reply = @handler.call(request, socket)
      write_reply(socket, *reply) unless reply == :raw
    rescue IOError, SystemCallError
      nil
    ensure
      socket.close unless socket.closed?
    end

    def read_request(socket)
      line = socket.gets or return nil
      method, target, = line.split
      headers = {}
      while (header = socket.gets) && header != "\r\n"
        name, value = header.split(":", 2)
        headers[name.strip.downcase] = value.to_s.strip
      end
      length = headers["content-length"].to_i
      body = length.positive? ? socket.read(length) : nil
      path, query = target.split("?", 2)
      Request.new(verb: method, path: path, query: query, headers: headers, body: body&.force_encoding("UTF-8"))
    end

    def write_reply(socket, status, headers = {}, body = "")
      body = body.to_s.b
      lines = ["HTTP/1.1 #{status} #{REASONS.fetch(status, "Status")}"]
      headers.each { |name, value| lines << "#{name}: #{value}" }
      lines << "content-length: #{body.bytesize}" unless headers.key?("content-length")
      lines << "connection: close"
      socket.write("#{lines.join("\r\n")}\r\n\r\n")
      socket.write(body)
    end
  end

  # Helpers for tests that talk to a FakeServer.
  module Helpers
    def teardown
      super
      (@servers || []).each(&:close)
    end

    # Starts a FakeServer that answers with the block, closed after the test.
    def serve(&)
      server = FakeServer.new(&)
      (@servers ||= []) << server
      server
    end

    # A client for `server`'s /v1.
    def client_for(server, **options)
      FlightByte::Client.new(api_key: "frk_test_key", base_url: "#{server.url}/v1", **options)
    end

    # A JSON reply.
    def json(status, body, headers = {})
      [status, { "content-type" => "application/json" }.merge(headers), body.is_a?(String) ? body : JSON.generate(body)]
    end

    def fixture(name)
      FlightByteTest.fixture(name)
    end

    def fixture_json(name)
      JSON.parse(fixture(name))
    end
  end
end
