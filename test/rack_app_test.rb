# frozen_string_literal: true

require "test_helper"
require "rack"
require "rack/lint"
require "rack/mock"

class RackAppTest < Minitest::Test
  include FlightByteTest::Helpers

  SECRET = "whsec_handler"

  def payload
    fixture("webhook_flight_updated.json")
  end

  def env_for(body: payload, method: "POST", signature: nil, length: true)
    input = body.is_a?(String) ? StringIO.new(body.b) : body
    env = { "REQUEST_METHOD" => method, "rack.input" => input }
    env["CONTENT_LENGTH"] = body.bytesize.to_s if length && body.is_a?(String)
    env["HTTP_X_FLIGHTBYTE_SIGNATURE"] = signature if signature
    env
  end

  # Delivers one request and returns what the app answered and saw.
  def deliver(env, app_options: {}, &handle)
    received = nil
    reported = nil
    app = FlightByte::Webhook::RackApp.new(SECRET, on_error: lambda { |error, *|
      reported = error
    }, **app_options) do |event, rack_env|
      received = event
      handle&.call(event, rack_env)
    end
    status, headers, body = app.call(env)
    { status: status, headers: headers, text: body.join, received: received, reported: reported }
  end

  def test_answers_200_and_hands_over_the_event_and_the_env
    seen_env = nil
    result = deliver(env_for(signature: FlightByte::Webhook.sign(payload, SECRET))) { |_event, env| seen_env = env }

    assert_equal 200, result[:status]
    assert_equal "ok", result[:text]
    assert_instance_of FlightByte::WebhookEvent, result[:received]
    assert_equal "evt_2", result[:received].id
    assert_equal "POST", seen_env["REQUEST_METHOD"]
  end

  def test_answers_500_when_the_block_raises_so_the_api_retries
    result = deliver(env_for(signature: FlightByte::Webhook.sign(payload, SECRET))) { raise "db down" }

    assert_equal 500, result[:status]
    assert_equal "db down", result[:reported].message
  end

  def test_reports_what_the_block_raises_with_warn_by_default
    app = FlightByte::Webhook::RackApp.new(SECRET) { raise ArgumentError, "db down" }
    status = nil
    _out, err = capture_io do
      status, = app.call(env_for(signature: FlightByte::Webhook.sign(payload, SECRET)))
    end

    assert_equal 500, status
    assert_includes err, "evt_2"
    assert_includes err, "flight.updated"
    assert_includes err, "db down"
  end

  def test_still_answers_500_when_on_error_raises
    app = FlightByte::Webhook::RackApp.new(SECRET, on_error: ->(*) { raise "reporter down" }) { raise "db down" }
    status, = app.call(env_for(signature: FlightByte::Webhook.sign(payload, SECRET)))

    assert_equal 500, status
  end

  def test_refuses_an_empty_secret_when_it_is_built
    ["", "  ", nil].each do |empty|
      error = assert_raises(ArgumentError) { FlightByte::Webhook::RackApp.new(empty) { nil } }

      assert_match(/secret is empty/, error.message)
    end
    assert_raises(ArgumentError) { FlightByte::Webhook::RackApp.new(SECRET) }
    assert_raises(ArgumentError) { FlightByte::Webhook::RackApp.new(SECRET, on_error: "warn") { nil } }
  end

  {
    "a bad signature" => lambda {
      FlightByte::Webhook.sign(FlightByteTest.fixture("webhook_flight_updated.json"), "other")
    },
    "no signature" => -> {},
    "a stale signature" => lambda {
      FlightByte::Webhook.sign(FlightByteTest.fixture("webhook_flight_updated.json"), SECRET,
                               timestamp: Time.now - 3600)
    }
  }.each do |name, sign|
    define_method("test_answers_401_for_#{name.tr(" ", "_")}_without_calling_the_block") do
      result = deliver(env_for(signature: sign.call))

      assert_equal 401, result[:status]
      assert_nil result[:received]
    end
  end

  def test_answers_400_for_a_signed_body_that_is_not_an_event
    result = deliver(env_for(body: "[1,2]", signature: FlightByte::Webhook.sign("[1,2]", SECRET)))

    assert_equal 400, result[:status]
    assert_nil result[:received]
  end

  def test_answers_405_to_anything_but_post
    result = deliver(env_for(method: "GET"))

    assert_equal 405, result[:status]
    assert_equal "POST", result[:headers]["allow"]
  end

  def test_answers_413_to_a_body_over_the_limit_declared_or_streamed
    big = "a" * (FlightByte::Webhook::MAX_BODY_BYTES + 1)

    assert_equal 413, deliver(env_for(body: big, signature: "t=1,v1=00"))[:status]
    assert_equal 413, deliver(env_for(body: big, signature: "t=1,v1=00", length: false))[:status]
  end

  def test_reads_a_body_right_at_the_limit
    body = JSON.generate({ id: "evt_1", type: "subscription.test",
                           pad: "a" * (FlightByte::Webhook::MAX_BODY_BYTES - 60) })
    body += " " * (FlightByte::Webhook::MAX_BODY_BYTES - body.bytesize)

    assert_equal 200, deliver(env_for(body: body, signature: FlightByte::Webhook.sign(body, SECRET)))[:status]
  end

  def test_takes_the_tolerance_and_the_clock
    signature = FlightByte::Webhook.sign(payload, SECRET, timestamp: 1_000)

    assert_equal 200, deliver(env_for(signature: signature), app_options: { now: 1_100 })[:status]
    assert_equal 401, deliver(env_for(signature: signature), app_options: { now: 1_100, tolerance: 60 })[:status]
    assert_equal 200, deliver(env_for(signature: signature), app_options: { tolerance: 0 })[:status]
  end

  def test_passes_rack_lint_for_every_answer
    calls = 0
    app = Rack::Lint.new(FlightByte::Webhook::RackApp.new(SECRET) do |event|
      calls += 1
      raise "fail" if event.id == "evt_fail"
    end)
    request = Rack::MockRequest.new(app)
    signed = ->(body) { { :input => body, "HTTP_X_FLIGHTBYTE_SIGNATURE" => FlightByte::Webhook.sign(body, SECRET) } }
    responses = nil
    capture_io do
      responses = {
        200 => request.post("/", signed.call(payload)),
        500 => request.post("/", signed.call('{"id":"evt_fail","type":"subscription.test"}')),
        401 => request.post("/", input: payload),
        400 => request.post("/", signed.call("[]")),
        405 => request.get("/")
      }
    end

    responses.each { |status, response| assert_equal status, response.status }
    assert_equal 2, calls
  end

  def test_never_shows_the_secret
    refute_includes FlightByte::Webhook::RackApp.new(SECRET) { nil }.inspect, SECRET
  end
end
