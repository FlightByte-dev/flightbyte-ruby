# frozen_string_literal: true

require "test_helper"

class FlightsTest < Minitest::Test
  include FlightByteTest::Helpers

  def flight
    fixture_json("flight.json")
  end

  def test_get_sends_the_identifiers_in_the_path_and_the_rest_in_the_query
    server = serve { json(200, flight) }
    result = client_for(server).flights.get(carrier: "TK", flight_number: "1848", date: "2026-09-08",
                                            origin: "IST", destination: "CDG", flight_id: "1407084032",
                                            refresh: true)

    assert_equal "GET", server.last.verb
    assert_equal "/v1/flights/TK/1848/2026-09-08", server.last.path
    assert_equal({ "origin" => "IST", "destination" => "CDG", "flightId" => "1407084032", "refresh" => "true" },
                 server.last.params)
    assert_instance_of FlightByte::FlightSnapshot, result
    assert_equal flight, result.to_h
  end

  def test_get_sends_no_query_when_nothing_optional_is_set
    server = serve { json(200, flight) }
    client_for(server).flights.get(carrier: "TK", flight_number: "1848", date: "2026-09-08", refresh: false,
                                   origin: "")

    assert_nil server.last.query
  end

  def test_timeline_reads_the_history
    server = serve { json(200, { flightKey: "TK1848:2026-09-08", count: 1, data: flight["timeline"] }) }
    result = client_for(server).flights.timeline(carrier: "TK", flight_number: "1848", date: "2026-09-08",
                                                 origin: "IST")

    assert_equal "/v1/flights/TK/1848/2026-09-08/timeline", server.last.path
    assert_equal "origin=IST", server.last.query
    assert_instance_of FlightByte::FlightTimeline, result
    assert_equal 1, result.count
    assert_equal "Time Adjustment", result.data.first.title
    assert_instance_of FlightByte::TimelineEntry, result.data.first
  end
end

class SubscriptionsTest < Minitest::Test
  include FlightByteTest::Helpers

  def subscription
    fixture_json("subscription.json")
  end

  def test_create_posts_the_body_and_the_idempotency_key_and_masks_the_secret
    reply = subscription.except("secretHint").merge("secret" => "whsec_AbCdEfGhIjKlMnOpQrStUvwxyz", "reused" => false,
                                                    "flight" => fixture_json("flight.json"))
    server = serve { json(201, reply) }
    created = client_for(server).subscriptions.create(
      carrier: "TK",
      flight_number: "1848",
      date: "2026-09-08",
      webhook_url: "https://example.com/hooks/flights",
      origin: "IST",
      events: ["flight.departed", "departure.gate.changed"],
      delay_threshold_minutes: 10,
      headers: { "x-team" => "ops" },
      metadata: { booking: "42" },
      idempotency_key: "booking-42"
    )
    request = server.last

    assert_equal "POST", request.verb
    assert_equal "/v1/subscriptions", request.path
    assert_equal "booking-42", request.headers["idempotency-key"]
    assert_equal "application/json", request.headers["content-type"]
    assert_equal({
                   "carrier" => "TK",
                   "flightNumber" => "1848",
                   "date" => "2026-09-08",
                   "webhookUrl" => "https://example.com/hooks/flights",
                   "origin" => "IST",
                   "events" => ["flight.departed", "departure.gate.changed"],
                   "delayThresholdMinutes" => 10,
                   "headers" => { "x-team" => "ops" },
                   "metadata" => { "booking" => "42" }
                 }, JSON.parse(request.body))
    assert_instance_of FlightByte::CreatedSubscription, created
    assert_equal "whsec_AbCdE...wxyz", created.secret_hint
    assert_equal "whsec_AbCdEfGhIjKlMnOpQrStUvwxyz", created.secret
    refute_predicate created, :reused?
    assert_instance_of FlightByte::FlightSnapshot, created.flight
    assert_equal "TK1848:2026-09-08", created.flight.flight_key
  end

  def test_create_keeps_the_hint_the_api_sent
    server = serve { json(201, { id: "sub_1", secret: "whsec_AbCdEfGhIjKlMnOpQrStUvwxyz", secretHint: "from-api" }) }
    created = client_for(server).subscriptions.create(carrier: "TK", flight_number: "1848", date: "2026-09-08",
                                                      webhook_url: "https://example.com/h")

    assert_equal "from-api", created.secret_hint
  end

  def test_create_sends_only_what_was_set_including_a_zero
    server = serve { json(201, { id: "sub_1", secret: "s" }) }
    client_for(server).subscriptions.create(carrier: "TK", flight_number: "1848", date: Date.new(2026, 9, 8),
                                            webhook_url: "https://example.com/h", delay_threshold_minutes: 0,
                                            idempotency_key: " ")

    assert_equal '{"carrier":"TK","flightNumber":"1848","date":"2026-09-08",' \
                 '"webhookUrl":"https://example.com/h","delayThresholdMinutes":0}', server.last.body
    refute server.last.headers.key?("idempotency-key")
  end

  def test_list_sends_the_filters
    server = serve { json(200, { total: 1, limit: 5, offset: 10, data: [subscription] }) }
    page = client_for(server).subscriptions.list(status: "active", carrier: "TK", flight_number: "1848",
                                                 date: "2026-09-08", limit: 5, offset: 10)

    assert_equal({ "status" => "active", "carrier" => "TK", "flightNumber" => "1848", "date" => "2026-09-08",
                   "limit" => "5", "offset" => "10" }, server.last.params)
    assert_instance_of FlightByte::SubscriptionPage, page
    assert_equal 1, page.data.length
    assert_instance_of FlightByte::Subscription, page.data.first
  end

  def pages(total)
    serve do |request|
      limit = Integer(request.params.fetch("limit"))
      offset = Integer(request.params.fetch("offset", "0"))
      data = Array.new((total - offset).clamp(0, limit)) { |i| { id: "sub_#{offset + i}" } }
      json(200, { total: total, limit: limit, offset: offset, data: data })
    end
  end

  def test_list_all_walks_every_page_lazily
    server = pages(5)
    all = client_for(server).subscriptions.list_all(page_size: 2, status: "active")

    assert_kind_of Enumerator, all
    assert_empty server.requests
    assert_equal %w[sub_0 sub_1 sub_2 sub_3 sub_4], all.map(&:id)
    assert_equal 3, server.requests.length
    assert_equal({ "status" => "active", "limit" => "2", "offset" => "4" }, server.last.params)
  end

  def test_list_all_fetches_only_the_pages_it_needs
    server = pages(5)

    assert_equal %w[sub_0 sub_1 sub_2], client_for(server).subscriptions.list_all(page_size: 2).first(3).map(&:id)
    assert_equal 2, server.requests.length
  end

  def test_list_all_stops_fetching_when_the_block_breaks
    server = pages(5)
    client_for(server).subscriptions.each(page_size: 2) { break } # rubocop:disable Lint/UnreachableLoop

    assert_equal 1, server.requests.length
  end

  def test_list_all_yields_to_a_block
    server = pages(3)
    ids = []

    assert_nil(client_for(server).subscriptions.list_all(offset: 1) { |subscription| ids << subscription.id })
    assert_equal %w[sub_1 sub_2], ids
    assert_equal "200", server.last.params["limit"]
  end

  def test_list_all_uses_200_a_page_by_default
    server = pages(0)
    client_for(server).subscriptions.list_all.to_a

    assert_equal "200", server.last.params["limit"]
  end

  def test_list_all_ends_on_an_error
    server = serve { json(500, { statusCode: 500, message: "boom" }) }

    assert_raises(FlightByte::ServerError) { client_for(server).subscriptions.list_all.to_a }
  end

  ACTIONS = [
    { name: "get", call: ->(c) { c.subscriptions.get("sub_1") }, method: "GET", path: "/v1/subscriptions/sub_1",
      result: FlightByte::Subscription },
    { name: "update", call: lambda { |c|
      c.subscriptions.update("sub_1", webhook_url: "https://example.com/new", events: [:"flight.cancelled"],
                                      delay_threshold_minutes: 30)
    }, method: "PATCH", path: "/v1/subscriptions/sub_1",
      body: '{"webhookUrl":"https://example.com/new","events":["flight.cancelled"],"delayThresholdMinutes":30}',
      result: FlightByte::Subscription },
    { name: "update_with_nothing", call: ->(c) { c.subscriptions.update("sub_1") }, method: "PATCH",
      path: "/v1/subscriptions/sub_1", body: "{}" },
    { name: "delete", call: ->(c) { c.subscriptions.delete("sub_1") }, reply: :empty, method: "DELETE",
      path: "/v1/subscriptions/sub_1", result: nil },
    { name: "pause", call: ->(c) { c.subscriptions.pause("sub_1") }, method: "POST",
      path: "/v1/subscriptions/sub_1/pause", result: FlightByte::Subscription },
    { name: "resume", call: ->(c) { c.subscriptions.resume("sub_1") }, method: "POST",
      path: "/v1/subscriptions/sub_1/resume", result: FlightByte::Subscription },
    { name: "send_test", call: ->(c) { c.subscriptions.send_test("sub_1") }, reply: { eventId: "evt_1" },
      method: "POST", path: "/v1/subscriptions/sub_1/test", result: "evt_1" },
    { name: "deliveries", call: ->(c) { c.subscriptions.deliveries("sub_1", limit: 10) },
      reply: { count: 1, data: [{ eventId: "evt_1", attempt: 2, status: "failed", httpStatus: 500, error: "HTTP 500",
                                  durationMs: 120, at: "2026-09-08T09:10:00.000Z",
                                  changeTypes: ["departure.gate.changed"] }] },
      method: "GET", path: "/v1/subscriptions/sub_1/deliveries", query: "limit=10" },
    { name: "events", call: ->(c) { c.subscriptions.events("sub_1") },
      reply: { count: 1, data: [JSON.parse(FlightByteTest.fixture("webhook_flight_updated.json"))] },
      method: "GET", path: "/v1/subscriptions/sub_1/events" },
    { name: "secret", call: ->(c) { c.subscriptions.secret("sub_1") }, reply: { secret: "whsec_x" }, method: "GET",
      path: "/v1/subscriptions/sub_1/secret", result: "whsec_x" },
    { name: "rotate_secret", call: ->(c) { c.subscriptions.rotate_secret("sub_1") }, reply: { secret: "whsec_y" },
      method: "POST", path: "/v1/subscriptions/sub_1/secret/rotate", result: "whsec_y" }
  ].freeze

  ACTIONS.each do |action|
    define_method("test_#{action[:name]}") do
      reply = action.fetch(:reply, subscription)
      server = serve { reply == :empty ? [204, {}, ""] : json(201, reply) }
      value = action[:call].call(client_for(server))
      sent = server.last

      assert_equal action[:method], sent.verb
      assert_equal action[:path], sent.path
      action[:query] ? assert_equal(action[:query], sent.query) : assert_nil(sent.query)
      action[:body] ? assert_equal(action[:body], sent.body) : assert_nil(sent.body)
      case (expected = action.fetch(:result, :unchecked))
      when :unchecked then nil
      when nil then assert_nil value
      when Class then assert_instance_of expected, value

      else assert_equal expected, value
      end
    end
  end

  def test_deliveries_and_events_come_back_as_their_models
    records = ACTIONS.find { |a| a[:name] == "deliveries" }
    server = serve { json(200, records[:reply]) }
    delivery = client_for(server).subscriptions.deliveries("sub_1").first

    assert_instance_of FlightByte::DeliveryRecord, delivery
    assert_equal [500, 120, ["departure.gate.changed"]],
                 [delivery.http_status, delivery.duration_ms, delivery.change_types]

    events = ACTIONS.find { |a| a[:name] == "events" }
    server = serve { json(200, events[:reply]) }
    event = client_for(server).subscriptions.events("sub_1").first

    assert_instance_of FlightByte::WebhookEvent, event
    assert_instance_of FlightByte::FlightChange, event.changes.first
    assert_equal "A22", event.changes.first.to
  end
end

class CountriesTest < Minitest::Test
  include FlightByteTest::Helpers

  TR = {
    "code" => "TR",
    "alpha2" => "TR",
    "name" => "Türkiye",
    "emoji" => "🇹🇷",
    "hasFlag" => true,
    "flagSvg" => "https://api.flightbyte.dev/v1/flags/tr.svg",
    "flagSvgSquare" => "https://api.flightbyte.dev/v1/flags/tr.svg?shape=1x1"
  }.freeze

  def test_list_unwraps_the_data
    server = serve { json(200, { count: 1, data: [TR] }) }
    countries = client_for(server).countries.list(lang: "tr")

    assert_equal [TR], countries.map(&:to_h)
    assert_instance_of FlightByte::Country, countries.first
    assert_predicate countries.first, :has_flag?
    assert_equal "/v1/countries", server.last.path
    assert_equal "lang=tr", server.last.query
  end

  def test_get_reads_one_country
    server = serve { json(200, TR) }
    country = client_for(server).countries.get("TR")

    assert_equal "Türkiye", country.name
    assert_equal "/v1/countries/TR", server.last.path
    assert_nil server.last.query
  end

  def test_flag_url_builds_the_url_without_a_request
    server = serve { json(200, {}) }
    client = client_for(server)

    assert_equal "#{server.url}/v1/flags/tr.svg", client.countries.flag_url("TR")
    assert_equal "#{server.url}/v1/flags/tr.svg?shape=1x1", client.countries.flag_url("TR", square: true)
    assert_equal "https://api.flightbyte.dev/v1/flags/tr.svg",
                 FlightByte::Client.new(api_key: "k").countries.flag_url("tr")
    assert_empty server.requests
  end
end
