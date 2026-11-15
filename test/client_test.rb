# frozen_string_literal: true

require "test_helper"
require "openssl"

class ClientTest < Minitest::Test
  include FlightByteTest::Helpers

  INVALID_OPTIONS = {
    "an empty key" => { api_key: "" },
    "a blank key" => { api_key: "   " },
    "a nil key" => { api_key: nil },
    "a relative base URL" => { api_key: "k", base_url: "/v1" },
    "an ftp base URL" => { api_key: "k", base_url: "ftp://api.flightbyte.dev/v1" },
    "a base URL with a query" => { api_key: "k", base_url: "https://api.flightbyte.dev/v1?x=1" },
    "a base URL with a fragment" => { api_key: "k", base_url: "https://api.flightbyte.dev/v1#top" },
    "a base URL that is not a URL" => { api_key: "k", base_url: "http://exa mple.com" },
    "a negative timeout" => { api_key: "k", timeout: -1 },
    "a timeout that is not a number" => { api_key: "k", timeout: "30" },
    "an infinite timeout" => { api_key: "k", timeout: Float::INFINITY },
    "a nil timeout" => { api_key: "k", timeout: nil }
  }.freeze

  INVALID_OPTIONS.each do |name, options|
    define_method("test_rejects_#{name.tr(" ", "_")}") do
      assert_raises(ArgumentError) { FlightByte::Client.new(**options) }
    end
  end

  def test_defaults_to_the_production_api_and_trims_what_it_is_given
    assert_equal "https://api.flightbyte.dev/v1", FlightByte::Client.new(api_key: "k").base_url
    assert_equal "http://localhost:3000/v1",
                 FlightByte::Client.new(api_key: "k", base_url: "http://localhost:3000/v1//").base_url
    assert_equal 30, FlightByte::Client.new(api_key: "k").timeout
  end

  def test_never_shows_the_key
    client = FlightByte::Client.new(api_key: "frk_live_secret")

    [client, client.flights, client.subscriptions, client.countries].each do |object|
      refute_includes object.inspect, "frk_live_secret"
    end
  end

  def test_sends_the_key_accept_and_user_agent
    server = serve { json(200, { count: 0, data: [] }) }
    client_for(server, api_key: "  frk_test_key  ", user_agent: " my-app/1.2 ").countries.list
    request = server.last

    assert_equal "GET", request.verb
    assert_equal "/v1/countries", request.path
    assert_nil request.query
    assert_equal "frk_test_key", request.headers["x-api-key"]
    assert_equal "application/json", request.headers["accept"]
    assert_equal "my-app/1.2 flightbyte-ruby/#{FlightByte::VERSION}", request.headers["user-agent"]
    refute request.headers.key?("content-type")
    assert_nil request.body
  end

  def test_uses_its_own_user_agent_alone
    server = serve { json(200, { count: 0, data: [] }) }
    client_for(server).countries.list

    assert_equal "flightbyte-ruby/#{FlightByte::VERSION}", server.last.headers["user-agent"]
  end

  def test_sends_json_with_a_content_type_and_an_empty_post_with_a_zero_length
    server = serve { json(200, {}) }
    client = client_for(server)
    client.subscriptions.update("sub_1", events: ["flight.departed"])

    assert_equal "application/json", server.last.headers["content-type"]
    assert_equal '{"events":["flight.departed"]}', server.last.body

    client.subscriptions.pause("sub_1")

    assert_equal "0", server.last.headers["content-length"]
    refute server.last.headers.key?("content-type")
  end

  def test_escapes_every_path_segment
    server = serve { json(200, {}) }
    client = client_for(server)
    client.subscriptions.get("sub/../../admin?x=1")

    assert_equal "/v1/subscriptions/sub%2F..%2F..%2Fadmin%3Fx%3D1", server.last.path
    assert_nil server.last.query

    client.subscriptions.get("..")

    assert_equal "/v1/subscriptions/%2E%2E", server.last.path

    client.subscriptions.get("İstanbul 1")

    assert_equal "/v1/subscriptions/%C4%B0stanbul%201", server.last.path
  end

  def test_rejects_an_empty_path_parameter_without_sending_anything
    server = serve { json(200, {}) }
    client = client_for(server)
    [
      [/carrier is required/, -> { client.flights.get(carrier: "", flight_number: "1", date: "2026-09-08") }],
      [/flight_number is required/, -> { client.flights.get(carrier: "TK", flight_number: nil, date: "2026-09-08") }],
      [/date is required/, -> { client.flights.timeline(carrier: "TK", flight_number: "1", date: " ") }],
      [/webhook_url is required/, lambda {
        client.subscriptions.create(carrier: "TK", flight_number: "1", date: "2026-09-08", webhook_url: "")
      }],
      [/id is required/, -> { client.subscriptions.get("") }],
      [/id is required/, -> { client.subscriptions.delete(" ") }],
      [/id is required/, -> { client.subscriptions.send_test("\t") }],
      [/code is required/, -> { client.countries.get("") }],
      [/code is required/, -> { client.countries.flag_url(nil) }]
    ].each do |message, call|
      error = assert_raises(ArgumentError, &call)

      assert_match message, error.message
    end
    assert_empty server.requests
  end

  def test_takes_dates_and_integers_where_the_path_needs_text
    server = serve { json(200, {}) }
    client_for(server).flights.get(carrier: :TK, flight_number: 1848, date: Date.new(2026, 9, 8))

    assert_equal "/v1/flights/TK/1848/2026-09-08", server.last.path
  end

  def test_treats_an_empty_2xx_body_as_no_value
    server = serve { [201, {}, ""] }

    assert_nil client_for(server).subscriptions.delete("sub_1")
  end

  def test_says_so_when_a_2xx_body_is_not_json
    server = serve { [200, { "content-type" => "text/html" }, "<html>maintenance</html>"] }
    error = assert_raises(FlightByte::Error) { client_for(server).countries.list }

    assert_match %r{\AExpected JSON from GET http://127\.0\.0\.1:\d+/v1/countries, got: <html>}, error.message
  end

  def test_says_so_when_a_2xx_body_is_not_the_expected_shape
    server = serve { json(200, [1, 2]) }

    assert_raises(FlightByte::Error) { client_for(server).subscriptions.get("sub_1") }
  end

  QUOTA = {
    "x-ratelimit-limit-minute" => "60",
    "x-ratelimit-remaining-minute" => "59",
    "x-ratelimit-reset-minute" => "1788858660",
    "x-ratelimit-limit-month" => "120",
    "x-ratelimit-remaining-month" => "bad"
  }.freeze

  def test_reads_the_windows_the_headers_report
    server = serve { json(200, { count: 0, data: [] }, QUOTA) }
    client = client_for(server)

    assert_nil client.last_rate_limit

    client.countries.list
    limit = client.last_rate_limit

    assert_equal FlightByte::RateLimitWindow.new(limit: 60, remaining: 59, reset_at: Time.at(1_788_858_660).utc),
                 limit.minute
    assert_predicate limit.minute.reset_at, :utc?
    assert_nil limit.day
    assert_nil limit.month
  end

  def test_keeps_the_last_state_when_a_response_carries_no_headers
    first = true
    server = serve do
      headers = first ? QUOTA : {}
      first = false
      json(200, { data: [] }, headers)
    end
    client = client_for(server)
    client.countries.list
    client.countries.list

    assert_equal 59, client.last_rate_limit.minute.remaining
  end

  def test_hands_out_a_state_that_cannot_change_the_client
    server = serve { json(200, { count: 0, data: [] }, QUOTA) }
    client = client_for(server)
    client.countries.list
    limit = client.last_rate_limit

    assert_predicate limit, :frozen?
    assert_predicate limit.minute, :frozen?
    assert_predicate limit.minute.reset_at, :frozen?
    assert_raises(FrozenError) { limit.minute.remaining = 0 }
    assert_raises(FrozenError) { limit.minute = nil }
    assert_equal 59, client.last_rate_limit.minute.remaining
  end

  def test_is_safe_to_share_between_threads
    server = serve { |request| json(200, { id: request.path.split("/").last }, QUOTA) }
    client = client_for(server)
    ids = Array.new(8) { |thread| Array.new(5) { |i| "sub_#{thread}_#{i}" } }
    results = ids.map { |batch| Thread.new { batch.map { |id| client.subscriptions.get(id).id } } }.map(&:value)

    assert_equal ids, results
    assert_equal 40, server.requests.length
    assert_equal 59, client.last_rate_limit.minute.remaining
  end

  # A server that accepts the connection and never answers.
  def hang
    serve do
      sleep 5
      :raw
    end
  end

  def test_times_out_with_a_connection_error
    error = assert_raises(FlightByte::ConnectionError) { client_for(hang, timeout: 0.2).countries.list }

    assert_predicate error, :timed_out?
    assert_match %r{GET http://127\.0\.0\.1:\d+/v1/countries timed out after 0\.2 seconds}, error.message
  end

  def test_lets_one_request_override_the_timeout
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(FlightByte::ConnectionError) { client_for(hang, timeout: 60).countries.list(timeout: 0.2) }

    assert_predicate error, :timed_out?
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 2
  end

  def test_rejects_a_bad_timeout_for_one_request
    assert_raises(ArgumentError) { client_for(hang).countries.list(timeout: -1) }
  end

  def test_bounds_the_whole_response_body_not_only_each_read
    # Every byte arrives well within the timeout, but the body as a whole does not.
    server = serve do |_request, socket|
      socket.write("HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: 20\r\n\r\n")
      20.times do
        socket.write(" ")
        socket.flush
        sleep 0.1
      end
      :raw
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(FlightByte::ConnectionError) { client_for(server, timeout: 0.5).countries.list }
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_predicate error, :timed_out?
    assert_operator elapsed, :<, 1.5
  end

  def test_waits_as_long_as_it_takes_with_the_timeout_off
    server = serve do
      sleep 0.3
      json(200, { count: 0, data: [] })
    end

    assert_empty client_for(server, timeout: 0).countries.list
  end

  def test_reaches_a_refused_port_as_a_connection_error
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] }
    client = FlightByte::Client.new(api_key: "k", base_url: "http://127.0.0.1:#{port}/v1")
    error = assert_raises(FlightByte::ConnectionError) { client.countries.list }

    refute_predicate error, :timed_out?
    assert_kind_of SystemCallError, error.cause
  end

  def test_reaches_a_dropped_connection_as_a_connection_error
    server = serve { :raw }
    error = assert_raises(FlightByte::ConnectionError) { client_for(server).countries.list }

    refute_predicate error, :timed_out?
  end

  def test_reaches_a_tls_failure_as_a_connection_error
    # A server that speaks plain HTTP the moment a client connects, so the
    # TLS handshake reads an HTTP status line instead of a ServerHello.
    plain = TCPServer.new("127.0.0.1", 0)
    thread = Thread.new do
      socket = plain.accept
      socket.write("HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n")
      sleep 0.2
      socket.close
    end
    client = FlightByte::Client.new(api_key: "k", base_url: "https://127.0.0.1:#{plain.addr[1]}/v1", timeout: 5)
    error = assert_raises(FlightByte::ConnectionError) { client.countries.list }

    refute_predicate error, :timed_out?
    assert_kind_of OpenSSL::OpenSSLError, error.cause
  ensure
    thread&.kill
    plain&.close
  end

  def test_reaches_a_dns_failure_as_a_connection_error
    # .invalid never resolves (RFC 6761).
    client = FlightByte::Client.new(api_key: "k", base_url: "http://flightbyte-test.invalid/v1", timeout: 10)
    error = assert_raises(FlightByte::ConnectionError) { client.countries.list }

    refute_predicate error, :timed_out?
  end

  def test_format_date_uses_the_calendar_date_of_the_value
    instant = Time.utc(2026, 9, 7, 22, 30)

    assert_equal "2026-09-08", FlightByte.format_date(instant.getlocal("+03:00"))
    assert_equal "2026-09-07", FlightByte.format_date(instant.getlocal("-04:00"))
    assert_equal "2026-09-07", FlightByte.format_date(instant)
    assert_equal "2026-09-08", FlightByte.format_date(Date.new(2026, 9, 8))
    assert_equal "0999-01-02", FlightByte.format_date(Date.new(999, 1, 2))
    assert_raises(ArgumentError) { FlightByte.format_date("2026-09-08") }
  end
end
