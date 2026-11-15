# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "timeout"
require "uri"
require "zlib"

module FlightByte
  # Sends authenticated requests and turns error statuses into errors.
  #
  # @api private Reach the API through {Client}.
  class Transport
    # How many same-origin redirects a GET or HEAD follows.
    MAX_REDIRECTS = 5

    # Every way a request can fail without an HTTP response.
    TRANSPORT_ERRORS = [
      SocketError,
      SystemCallError,
      IOError,
      Timeout::Error,
      OpenSSL::OpenSSLError,
      Net::ProtocolError,
      Net::HTTPBadResponse,
      Net::HTTPHeaderSyntaxError,
      Zlib::Error
    ].freeze

    # A response, as the transport hands it back.
    Response = Struct.new(:status, :reason, :headers, :body, keyword_init: true)
    private_constant :Response

    attr_reader :base_url, :timeout

    def initialize(api_key:, base_url:, timeout:, user_agent:)
      @api_key = api_key
      @base_url = base_url
      @timeout = timeout
      @user_agent = user_agent
      @mutex = Mutex.new
      @last_rate_limit = nil
    end

    # The quota state from the latest response that carried one.
    def last_rate_limit
      @mutex.synchronize { @last_rate_limit }
    end

    # Builds the URL for `path` under the base URL, each segment escaped.
    # `nil` and empty query values are left out.
    def url(path, query = nil)
      url = "#{@base_url}/#{path.map { |segment| Transport.escape(segment) }.join("/")}"
      pairs = (query || {}).filter_map do |key, value|
        [key.to_s, value.to_s] unless value.nil? || value == ""
      end
      pairs.empty? ? url : "#{url}?#{URI.encode_www_form(pairs)}"
    end

    # Sends a request and returns the decoded JSON, or `nil` for an empty body.
    def request(method, path, query: nil, body: nil, headers: nil, timeout: nil)
      timeout = timeout.nil? ? @timeout : Transport.check_timeout(timeout)
      target = url(path, query)
      request_headers = { "x-api-key" => @api_key, "accept" => "application/json", "user-agent" => @user_agent }
      request_headers.merge!(headers) if headers
      payload = nil
      if body.nil?
        request_headers["content-length"] = "0" if %w[POST PUT PATCH].include?(method)
      else
        request_headers["content-type"] = "application/json"
        payload = JSON.generate(body)
      end

      response = perform(method, target, request_headers, payload, timeout)
      handle(method, target, response)
    end

    # Never shows the API key.
    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end

    class << self
      # Escapes one path segment, so an id like `../admin?x=1` stays one segment.
      def escape(segment)
        segment = segment.to_s
        # `.` and `..` would be read as a step up or across the path.
        return segment.gsub(".", "%2E") if segment.match?(/\A\.{1,2}\z/)

        segment.b.gsub(/[^A-Za-z0-9\-._~]/n) { |byte| format("%%%02X", byte.ord) }
      end

      # Rejects an empty path parameter before it turns into a request for the wrong URL.
      def required(name, value)
        value = value.to_s if value.is_a?(Integer) || value.is_a?(Symbol)
        raise ArgumentError, "flightbyte: #{name} is required." unless value.is_a?(String) && !value.strip.empty?

        value
      end

      # A flight date: a `YYYY-MM-DD` string, or a Date or Time to format.
      def date(name, value)
        value.respond_to?(:strftime) ? FlightByte.format_date(value) : required(name, value)
      end

      def check_timeout(value)
        unless value.is_a?(Numeric) && value.real? && value.finite? && value >= 0
          raise ArgumentError, "flightbyte: timeout must be a number of seconds, 0 or more; got #{value.inspect}."
        end

        value
      end
    end

    private

    def perform(method, target, headers, payload, timeout)
      with_deadline(timeout) do
        deadline = timeout.positive? ? clock + timeout : nil
        current = target
        hops = 0
        loop do
          response = exchange(method, URI(current), headers, payload, deadline)
          following = followable_redirect(response, current, method)
          return response if following.nil? || hops >= MAX_REDIRECTS

          hops += 1
          current = following
        end
      end
    rescue Timeout::Error
      raise ConnectionError.new("#{method} #{target} timed out after #{seconds(timeout)}.", timed_out: true)
    rescue *TRANSPORT_ERRORS => e
      raise ConnectionError, "#{method} #{target} failed: #{e.message} (#{e.class})"
    end

    # The overall deadline: it bounds the whole exchange, redirects and the
    # response body included, which the per-read timeouts alone cannot.
    def with_deadline(timeout, &)
      timeout.positive? ? Timeout.timeout(timeout, &) : yield
    end

    def exchange(method, uri, headers, payload, deadline)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      # Net::HTTP retries an idempotent request once on its own; a retry is
      # the caller's call, and it would stretch the timeout.
      http.max_retries = 0
      remaining = deadline && [deadline - clock, 0.001].max
      http.open_timeout = remaining
      http.read_timeout = remaining
      http.write_timeout = remaining

      # Built as a generic request so that one without a payload has no body
      # at all. Before Ruby 4.0, Net::HTTP::Post and friends give a body-less
      # request an empty body and then a form content type, with a warning.
      request = Net::HTTPGenericRequest.new(method, !payload.nil?, method != "HEAD", uri.request_uri, headers)
      http.start do |connection|
        response = connection.request(request, payload)
        Response.new(
          status: response.code.to_i,
          reason: response.message.to_s,
          headers: response.each_header.to_h.freeze,
          # Invalid bytes become U+FFFD, as a browser or Node would decode them.
          body: response.body.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        )
      end
    end

    # Where to go next when `response` is a redirect this client may follow: a
    # GET or HEAD, to the same origin (scheme, host and port). Anything else
    # reaches the caller as an error, so the API key, sent with every request,
    # never reaches another server or travels in the clear, and a write is
    # never replayed.
    def followable_redirect(response, from, method)
      return nil unless (300..399).cover?(response.status) && %w[GET HEAD].include?(method)

      location = response.headers["location"].to_s
      return nil if location.empty?

      target = URI.join(from, location)
      same_origin?(URI(from), target) ? target.to_s : nil
    rescue URI::Error
      nil
    end

    def same_origin?(from, target)
      target.is_a?(URI::HTTP) && !target.host.to_s.empty? &&
        from.scheme.downcase == target.scheme.to_s.downcase &&
        from.host.downcase == target.host.downcase &&
        from.port == target.port
    end

    def handle(method, target, response)
      rate_limit = RateLimit.parse(response.headers)
      @mutex.synchronize { @last_rate_limit = rate_limit } if rate_limit

      unless (200..299).cover?(response.status)
        raise APIError.from(response.status, response.reason, response.body, response.headers)
      end
      return nil if response.status == 204 || response.body.strip.empty?

      begin
        JSON.parse(response.body)
      rescue JSON::ParserError, EncodingError
        text = response.body
        preview = text.length > 200 ? "#{text[0, 200]}..." : text
        raise Error, "Expected JSON from #{method} #{target}, got: #{preview}"
      end
    end

    def clock
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def seconds(value)
      value = value.to_i if value.is_a?(Float) && value == value.to_i
      "#{value} #{value == 1 ? "second" : "seconds"}"
    end
  end
  private_constant :Transport
end
