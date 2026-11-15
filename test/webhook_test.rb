# frozen_string_literal: true

require "test_helper"

# Signatures made by tool/webhook_vectors.mjs with Node's createHmac, exactly
# as the API signs deliveries, so the verifier is checked against the server
# and not only against itself.
module Vectors
  DATA = JSON.parse(FlightByteTest.fixture("webhook_vectors.json"))
  SECRET = DATA.fetch("secret")
  AT = DATA.fetch("timestamp")
  CASES = DATA.fetch("cases")
  UPDATED = CASES.fetch(1)
  PAYLOAD = FlightByteTest.fixture(UPDATED.fetch("file"))
  SIGNATURE = UPDATED.fetch("signature")
  SIG = SIGNATURE.split(",v1=").last
end

class WebhookVerifyTest < Minitest::Test
  include FlightByteTest::Helpers
  include Vectors

  CASES.each do |vector|
    define_method("test_verifies_#{vector["file"].delete_suffix(".json")}_signed_by_the_api") do
      body = fixture(vector["file"])

      assert FlightByte::Webhook.verify(body, vector["signature"], SECRET, now: AT)
      assert FlightByte::Webhook.verify(body.b, vector["signature"], SECRET, now: Time.at(AT))
      assert_equal vector["signature"], FlightByte::Webhook.sign(body, SECRET, timestamp: AT)
      assert_equal vector["signature"], FlightByte::Webhook.sign(body, SECRET, timestamp: Time.at(AT))
      event = FlightByte::Webhook.construct_event(body, vector["signature"], SECRET, now: AT)

      assert_instance_of FlightByte::WebhookEvent, event
      assert_equal "sub_1", event.subscription_id
    end
  end

  REJECTS = {
    "the wrong secret" => [PAYLOAD, SIGNATURE, "#{SECRET}x", AT, /does not match/],
    "a changed body" => [PAYLOAD.sub("A22", "A23"), SIGNATURE, SECRET, AT, /does not match/],
    "a re-encoded body" => [JSON.pretty_generate(JSON.parse(PAYLOAD)), SIGNATURE, SECRET, AT, /does not match/],
    "a missing header" => [PAYLOAD, nil, SECRET, AT, /missing/],
    "a blank header" => [PAYLOAD, "  ", SECRET, AT, /missing/],
    "no timestamp" => [PAYLOAD, "v1=#{SIG}", SECRET, AT, /no valid timestamp/],
    "a timestamp that is not a number" => [PAYLOAD, "t=soon,v1=#{SIG}", SECRET, AT, /no valid timestamp/],
    "a negative timestamp" => [PAYLOAD, "t=-1,v1=#{SIG}", SECRET, AT, /no valid timestamp/],
    "a huge timestamp" => [PAYLOAD, "t=9223372036854775807,v1=#{SIG}", SECRET, AT, /no valid timestamp/],
    "no signature" => [PAYLOAD, "t=#{AT}", SECRET, AT, /no v1 signature/],
    "another scheme only" => [PAYLOAD, "t=#{AT},v0=#{SIG}", SECRET, AT, /no v1 signature/],
    "a signature that is not hex" => [PAYLOAD, "t=#{AT},v1=#{"z" * 64}", SECRET, AT, /does not match/],
    "a short signature" => [PAYLOAD, "t=#{AT},v1=#{SIG[0, 10]}", SECRET, AT, /does not match/],
    "a header that is not valid text" => [PAYLOAD, "t=#{AT},v1=\xFF\xFE".b, SECRET, AT, /does not match/],
    "an old signature" => [PAYLOAD, SIGNATURE, SECRET, AT + 301, /tolerance/],
    "a signature from the future" => [PAYLOAD, SIGNATURE, SECRET, AT - 301, /tolerance/]
  }.freeze

  REJECTS.each do |name, (body, signature, secret, now, reason)|
    define_method("test_rejects_#{name.tr(" -", "__")}") do
      error = assert_raises(FlightByte::WebhookSignatureError) do
        FlightByte::Webhook.verify(body, signature, secret, now: now)
      end

      assert_match reason, error.message
      refute FlightByte::Webhook.valid?(body, signature, secret, now: now)
      assert_raises(FlightByte::WebhookSignatureError) do
        FlightByte::Webhook.construct_event(body, signature, secret, now: now)
      end
    end
  end

  def test_rejects_with_a_tighter_tolerance
    error = assert_raises(FlightByte::WebhookSignatureError) do
      FlightByte::Webhook.verify(PAYLOAD, SIGNATURE, SECRET, now: AT + 60, tolerance: 30)
    end

    assert_match(/tolerance/, error.message)
  end

  ACCEPTS = {
    "at the edge of the window" => [SIGNATURE, AT + 300, nil],
    "at the other edge" => [SIGNATURE, AT - 300, nil],
    "any time with the check off" => [SIGNATURE, AT + 86_400, 0],
    "two v1 the second right" => ["t=#{AT},v1=#{"0" * 64},v1=#{SIG}", AT, nil],
    "upper case hex" => ["t=#{AT},v1=#{SIG.upcase}", AT, nil],
    "spaces around parts" => [" t=#{AT} , v1=#{SIG} ", AT, nil],
    "an unknown scheme as well" => ["t=#{AT},v0=abc,v1=#{SIG}", AT, nil],
    "a part without an equal sign" => ["t=#{AT},junk,v1=#{SIG}", AT, nil],
    "a fractional now" => [SIGNATURE, AT + 300.9, nil]
  }.freeze

  ACCEPTS.each do |name, (signature, now, tolerance)|
    define_method("test_accepts_#{name.tr(" ", "_")}") do
      options = tolerance.nil? ? { now: now } : { now: now, tolerance: tolerance }

      assert FlightByte::Webhook.verify(PAYLOAD, signature, SECRET, **options)
      assert FlightByte::Webhook.valid?(PAYLOAD, signature, SECRET, **options)
    end
  end

  def test_accepts_a_fresh_signature_with_the_real_clock
    body = '{"id":"evt_9","type":"subscription.test"}'
    signature = FlightByte::Webhook.sign(body, "whsec_roundtrip")

    assert FlightByte::Webhook.verify(body, signature, "whsec_roundtrip")
  end

  def test_refuses_an_empty_secret_everywhere
    forged = "t=#{AT},v1=#{"0" * 64}"
    ["", "   ", "\n", nil].each do |empty|
      error = assert_raises(ArgumentError) { FlightByte::Webhook.verify(PAYLOAD, forged, empty, now: AT) }

      assert_match(/secret is empty/, error.message)
      assert_raises(ArgumentError) { FlightByte::Webhook.valid?(PAYLOAD, forged, empty, now: AT) }
      assert_raises(ArgumentError) { FlightByte::Webhook.construct_event(PAYLOAD, forged, empty, now: AT) }
      assert_raises(ArgumentError) { FlightByte::Webhook.sign(PAYLOAD, empty) }
    end
  end

  def test_refuses_a_payload_that_is_not_text
    assert_raises(TypeError) { FlightByte::Webhook.verify(StringIO.new(PAYLOAD), SIGNATURE, SECRET, now: AT) }
    assert_raises(TypeError) { FlightByte::Webhook.verify(JSON.parse(PAYLOAD), SIGNATURE, SECRET, now: AT) }
  end

  def test_refuses_a_tolerance_that_is_not_a_number
    assert_raises(ArgumentError) { FlightByte::Webhook.verify(PAYLOAD, SIGNATURE, SECRET, now: AT, tolerance: nil) }
  end

  def test_never_raises_anything_but_a_signature_error_for_any_header
    inputs = ["", ",,,=,t=,v1=", "t=1", "=1", "t==1,v1==", "t=1,v1=a,v1=b", "\u0000", "t=1" * 1000, "\xFF".b]
    random = Random.new(42)
    500.times { inputs << Array.new(20) { (32 + random.rand(95)).chr }.join }
    200.times { inputs << random.bytes(24) }
    inputs.each do |header|
      FlightByte::Webhook.verify(PAYLOAD, header, SECRET, tolerance: 0)

      flunk "accepted #{header.inspect}"
    rescue FlightByte::WebhookSignatureError
      pass
    end
  end

  def test_has_the_header_names
    assert_equal "x-flightbyte-signature", FlightByte::Webhook::SIGNATURE_HEADER
    assert_equal "HTTP_X_FLIGHTBYTE_SIGNATURE", FlightByte::Webhook::SIGNATURE_ENV_KEY
    assert_equal "x-flightbyte-event-id", FlightByte::Webhook::EVENT_ID_HEADER
    assert_equal 300, FlightByte::Webhook::DEFAULT_TOLERANCE
    assert_equal 1_048_576, FlightByte::Webhook::MAX_BODY_BYTES
  end
end

class WebhookConstructEventTest < Minitest::Test
  include Vectors

  def test_decodes_the_event
    event = FlightByte::Webhook.construct_event(PAYLOAD, SIGNATURE, SECRET, now: AT)

    assert_equal "flight.updated", event.type
    assert_equal "departure.gate.changed", event.changes.first.type
    assert_equal %w[A11 A22], [event.changes.first.from, event.changes.first.to]
    assert_includes event.changes.first.message, "İstanbul"
    assert_equal Encoding::UTF_8, event.changes.first.message.encoding
    assert_equal({ "booking" => "42" }, event.metadata)
    assert_equal JSON.parse(PAYLOAD), event.to_h
  end

  def test_decodes_a_body_that_is_not_valid_utf8_with_replacement_characters
    body = "{\"id\":\"evt_\xFF\",\"type\":\"subscription.test\"}".b
    event = FlightByte::Webhook.construct_event(body, FlightByte::Webhook.sign(body, "s"), "s")

    assert_equal "evt_�", event.id
    assert_predicate event.id, :valid_encoding?
  end

  {
    "not JSON" => ["not json", /not JSON/],
    "an array" => ["[1,2]", /not a FlightByte event/],
    "an object without an id" => ['{"type":"x"}', /not a FlightByte event/],
    "an object with a number for an id" => ['{"id":1,"type":"x"}', /not a FlightByte event/]
  }.each do |name, (body, message)|
    define_method("test_rejects_a_signed_body_that_is_#{name.tr(" -", "__")}") do
      signature = FlightByte::Webhook.sign(body, "s")
      error = assert_raises(FlightByte::Error) { FlightByte::Webhook.construct_event(body, signature, "s") }

      refute_kind_of FlightByte::WebhookSignatureError, error
      assert_match message, error.message
    end
  end
end
