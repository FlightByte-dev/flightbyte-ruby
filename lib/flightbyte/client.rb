# frozen_string_literal: true

require "uri"

module FlightByte
  # A client for the FlightByte API. Create one and share it: it is safe to use
  # from many threads at once.
  #
  #   client = FlightByte::Client.new(api_key: ENV.fetch("FLIGHTBYTE_API_KEY"))
  #   flight = client.flights.get(carrier: "TK", flight_number: "1848", date: "2026-09-08")
  #   puts flight.status.label
  #
  # Keep API keys on a server you control. A key shipped inside a browser or
  # mobile app can be extracted by anyone who has the app.
  class Client
    # The production API root.
    DEFAULT_BASE_URL = "https://api.flightbyte.dev/v1"

    # Seconds each request may take, response body included, unless told otherwise.
    DEFAULT_TIMEOUT = 30

    # @return [Flights] flight lookups
    attr_reader :flights
    # @return [Subscriptions] watched flights and their webhooks
    attr_reader :subscriptions
    # @return [Countries] countries and flags
    attr_reader :countries
    # @return [String] the API root this client talks to
    attr_reader :base_url
    # @return [Numeric] seconds each request may take; `0` means no limit
    attr_reader :timeout
    # @return [String] the `User-Agent` header sent with every request
    attr_reader :user_agent

    # @param api_key [String] your API key, sent as `x-api-key`. Keep it on a server you control.
    # @param base_url [String] the API root, for example `http://localhost:3000/v1` for a local API
    # @param timeout [Numeric] seconds each request may take, connecting,
    #   redirects and the response body included; `0` disables the limit
    # @param user_agent [String, nil] put in front of this gem's own user
    #   agent, for example `my-app/1.2`
    # @raise [ArgumentError] when the key is empty, the base URL is not an
    #   http or https URL, or the timeout is negative
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: DEFAULT_TIMEOUT, user_agent: nil)
      api_key = api_key.is_a?(String) ? api_key.strip : ""
      raise ArgumentError, "flightbyte: api_key is required." if api_key.empty?

      @base_url = Client.check_base_url(base_url)
      @timeout = Transport.check_timeout(timeout)
      own = "flightbyte-ruby/#{VERSION}"
      prefix = user_agent.to_s.strip
      @user_agent = (prefix.empty? ? own : "#{prefix} #{own}").freeze

      @transport = Transport.new(api_key: api_key.freeze, base_url: @base_url, timeout: @timeout,
                                 user_agent: @user_agent)
      @flights = Flights.new(@transport)
      @subscriptions = Subscriptions.new(@transport)
      @countries = Countries.new(@transport)
    end

    # The quota state from the latest response that reported one, or `nil`
    # before any did. It is frozen, so reading it never changes the client.
    #
    # @return [RateLimit, nil]
    def last_rate_limit
      @transport.last_rate_limit
    end

    # Never shows the API key.
    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end

    # @api private
    def self.check_base_url(value)
      uri = begin
        URI.parse(value.to_s)
      rescue URI::Error
        nil
      end
      raise ArgumentError, "flightbyte: base_url #{value.inspect} is not a URL." unless uri

      unless uri.is_a?(URI::HTTP) && !uri.host.to_s.empty?
        raise ArgumentError, "flightbyte: base_url #{value.inspect} must be an http or https URL."
      end
      if uri.query || uri.fragment
        raise ArgumentError, "flightbyte: base_url #{value.inspect} must not have a query or fragment."
      end

      uri.to_s.sub(%r{/+\z}, "").freeze
    end
  end
end
