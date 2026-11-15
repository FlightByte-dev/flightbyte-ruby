# frozen_string_literal: true

require "test_helper"

class ErrorsTest < Minitest::Test
  include FlightByteTest::Helpers

  def fail_with(status, body, headers = {})
    server = serve { json(status, body, headers) }
    error = assert_raises(FlightByte::APIError) { client_for(server).subscriptions.get("sub_1") }
    assert_kind_of FlightByte::Error, error
    error
  end

  {
    400 => FlightByte::BadRequestError,
    401 => FlightByte::AuthenticationError,
    402 => FlightByte::PaymentRequiredError,
    403 => FlightByte::PermissionDeniedError,
    404 => FlightByte::NotFoundError,
    409 => FlightByte::UnexpectedStatusError,
    422 => FlightByte::UnexpectedStatusError,
    429 => FlightByte::RateLimitError,
    500 => FlightByte::ServerError,
    502 => FlightByte::UpstreamError,
    503 => FlightByte::ServerError
  }.each do |status, error_class|
    define_method("test_#{status}_is_a_#{error_class.name.split("::").last}") do
      error = fail_with(status, { statusCode: status, message: "x" })

      assert_instance_of error_class, error
      assert_kind_of StandardError, error
      assert_equal status, error.status
    end
  end

  def test_counts_a_502_as_a_server_error_too
    assert_kind_of FlightByte::ServerError, fail_with(502, {})
  end

  def test_reads_every_message_and_the_request_id
    error = fail_with(400, {
                        statusCode: 400,
                        error: "Bad Request",
                        message: ["carrier must be 2 or 3 characters", "date must be YYYY-MM-DD"],
                        requestId: "req_123"
                      })

    assert_equal ["carrier must be 2 or 3 characters", "date must be YYYY-MM-DD"], error.messages
    assert_equal "req_123", error.request_id
    assert_equal "Bad Request", error.body["error"]
    assert_equal "400 Bad Request: carrier must be 2 or 3 characters; date must be YYYY-MM-DD (request req_123)",
                 error.message
    assert_predicate error.body, :frozen?
    assert_predicate error.messages, :frozen?
  end

  def test_falls_back_to_the_apis_own_phrase_without_a_reason_phrase
    server = serve do |_request, socket|
      body = '{"statusCode":404,"error":"Not Found","message":"No such subscription."}'
      socket.write("HTTP/1.1 404\r\ncontent-type: application/json\r\ncontent-length: #{body.bytesize}\r\n\r\n#{body}")
      :raw
    end
    error = assert_raises(FlightByte::NotFoundError) { client_for(server).subscriptions.get("sub_1") }

    assert_equal "404 Not Found: No such subscription.", error.message
  end

  def test_lists_the_legs_of_an_ambiguous_flight
    error = fail_with(400, {
                        statusCode: 400,
                        message: "TK1 flies 2 legs on 2026-09-08; pass origin to choose one.",
                        legs: [
                          { origin: "IST", destination: "JFK", carrier: "TK", scheduledDepartureLocal: "07:00",
                            flightId: "1" },
                          { origin: "JFK", destination: "IST", scheduledDepartureLocal: "21:00" },
                          "junk"
                        ]
                      })
    legs = error.legs

    assert_equal 2, legs.length
    assert_equal %w[IST JFK], legs.map(&:origin)
    assert_equal "07:00", legs[0].scheduled_departure_local
    assert_equal "1", legs[0].flight_id
    assert_nil legs[1].carrier
    assert_equal({ "origin" => "JFK", "destination" => "IST", "scheduledDepartureLocal" => "21:00" }, legs[1].to_h)
    assert_empty fail_with(400, { message: "bad" }).legs
  end

  def test_reads_the_reason_a_watched_flight_was_refused
    capped = fail_with(402, {
                         statusCode: 402,
                         code: "overage_cap_reached",
                         message: "No watched flights left.",
                         limit: 10,
                         used: 10,
                         resetsAt: "2026-10-01T00:00:00.000Z",
                         capCents: 500
                       })

    assert_equal "overage_cap_reached", capped.code
    assert_equal [10, 10, "2026-10-01T00:00:00.000Z", 500],
                 [capped.limit, capped.used, capped.resets_at, capped.cap_cents]
    assert_nil capped.balance

    credits = fail_with(402, {
                          statusCode: 402,
                          code: "credits_exhausted",
                          message: "No credits left.",
                          balance: 0,
                          expiresAt: "2027-01-01T00:00:00.000Z"
                        })

    assert_equal "credits_exhausted", credits.code
    assert_equal 0, credits.balance
    assert_equal "2027-01-01T00:00:00.000Z", credits.expires_at
    assert_nil credits.limit
  end

  def test_reads_how_long_to_wait_from_the_body_or_the_retry_after_header
    from_body = fail_with(429, { window: "minute", retryAfterSeconds: 12 })

    assert_equal "minute", from_body.window
    assert_equal 12, from_body.retry_after
    assert_equal 30, fail_with(429, { message: "slow down" }, { "retry-after" => "30" }).retry_after
    assert_nil fail_with(429, {}, { "retry-after" => "Wed, 21 Oct 2026 07:28:00 GMT" }).retry_after
    assert_nil fail_with(429, {}).retry_after
  end

  def test_copes_with_a_body_that_is_not_json
    server = serve { [503, { "x-request-id" => "req_from_header" }, "<html>Service Unavailable</html>"] }
    error = assert_raises(FlightByte::ServerError) { client_for(server).countries.list }

    assert_empty error.messages
    assert_empty error.body
    assert_equal "<html>Service Unavailable</html>", error.raw_body
    assert_equal "req_from_header", error.request_id
    assert_equal "503 Service Unavailable (request req_from_header)", error.message
    assert_equal "req_from_header", error.headers["x-request-id"]
  end

  def test_carries_the_code_of_a_suspended_account
    error = fail_with(403, { message: "This account is suspended.", code: "account_suspended" })

    assert_instance_of FlightByte::PermissionDeniedError, error
    assert_equal "account_suspended", error.code
  end

  def test_keeps_the_error_hierarchy
    assert_operator FlightByte::Error, :<, StandardError
    assert_operator FlightByte::ConnectionError, :<, FlightByte::Error
    assert_operator FlightByte::WebhookSignatureError, :<, FlightByte::Error
    assert_operator FlightByte::UpstreamError, :<, FlightByte::ServerError
    [FlightByte::BadRequestError, FlightByte::AuthenticationError, FlightByte::PaymentRequiredError,
     FlightByte::PermissionDeniedError, FlightByte::NotFoundError, FlightByte::RateLimitError,
     FlightByte::ServerError, FlightByte::UnexpectedStatusError].each do |error_class|
      assert_operator error_class, :<, FlightByte::APIError
    end
  end
end
