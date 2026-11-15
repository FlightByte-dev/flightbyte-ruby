# frozen_string_literal: true

require "test_helper"
require "pp"

class ModelsTest < Minitest::Test
  include FlightByteTest::Helpers

  def flight
    FlightByte::FlightSnapshot.new(fixture_json("flight.json"))
  end

  def subscription
    FlightByte::Subscription.new(fixture_json("subscription.json"))
  end

  # Every key of `object`, at any depth, that its model does not declare.
  def undeclared(object, path = object.class.name.split("::").last)
    object.keys.flat_map do |key|
      own = object.class.fields.key?(key) ? [] : ["#{path}.#{key}"]
      value = object[key]
      nested = Array(value.is_a?(Array) ? value : [value]).grep(FlightByte::Object).flat_map do |item|
        undeclared(item, "#{path}.#{key}")
      end
      own + nested
    end
  end

  def test_the_fixtures_fit_the_models
    assert_empty undeclared(flight)
    assert_empty undeclared(subscription)
    %w[webhook_test.json webhook_flight_updated.json].each do |name|
      assert_empty undeclared(FlightByte::WebhookEvent.new(fixture_json(name)))
    end
  end

  def test_flight
    f = flight

    assert_equal "TK1848:2026-09-08", f.flight_key
    assert_equal 15, f.departure.delay_minutes
    assert_equal(-5, f.arrival.delay_minutes)
    assert_nil f.arrival.gate
    assert_nil f.arrival.airport.code
    refute f.arrival.airport.key?("code")
    assert f.arrival.key?("gate")
    assert_nil f.status.arrival_gate_delay_minutes
    assert_predicate f, :cached?
    assert_predicate f.status, :delayed?
    refute_predicate f.status, :cancelled?
    assert_equal "Türkiye", f.departure.airport.country.name
    assert_instance_of FlightByte::CountryRef, f.departure.airport.country
    assert_instance_of FlightByte::FlightLegRef, f.alternates.first
    assert_predicate f.alternates.first, :selected?
    assert_nil f.diverted
    assert_nil f.arrival.times.actual_gate
  end

  def test_subscription_with_a_change_type_newer_than_this_release
    s = subscription

    assert_includes s.events, "some.future.type"
    assert_nil s.last_change_at
    assert_equal({ "booking" => "42" }, s.metadata)
    assert_equal({ "x-team" => "ops" }, s.headers)
    assert_predicate s.metadata, :frozen?
    assert_predicate s, :flight_resolved?
  end

  def test_webhook_events
    types = %w[webhook_test.json webhook_flight_updated.json].map do |name|
      FlightByte::WebhookEvent.new(fixture_json(name)).type
    end

    assert_equal %w[subscription.test flight.updated], types
  end

  def test_terminal_phase
    assert_equal(%w[arrived cancelled diverted redirected], FlightByte::FLIGHT_PHASES.select do |p|
      FlightByte.terminal_phase?(p)
    end)
    refute FlightByte.terminal_phase?("later")
    refute FlightByte.terminal_phase?(nil)
    refute_predicate flight.status, :terminal?
  end

  def test_best_gate_time_prefers_actual_then_estimated_then_scheduled
    assert_equal "2026-09-08T12:25:00.000", FlightByte.best_gate_time(flight.departure.times).local
    assert_equal "CEST", flight.arrival.times.best_gate.timezone
    assert_instance_of FlightByte::FlightTime, flight.arrival.times.best_gate
    assert_nil FlightByte.best_gate_time(FlightByte::EndpointTimes.new({}))
    assert_nil FlightByte.best_gate_time(nil)
    assert_equal({ "utc" => "x" }, FlightByte.best_gate_time({ "estimatedGate" => { "utc" => "x" } }))
  end

  def test_mask_secret
    assert_equal "whsec_AbCdE...wxyz", FlightByte.mask_secret("whsec_AbCdEfGhIjKlMnOpQrStUvwxyz")
    assert_equal "short", FlightByte.mask_secret("short")
  end

  def test_the_value_lists_have_no_duplicates_and_are_frozen
    [FlightByte::FLIGHT_PHASES, FlightByte::TERMINAL_PHASES, FlightByte::SUBSCRIPTION_STATUSES,
     FlightByte::FLIGHT_CHANGE_TYPES, FlightByte::WEBHOOK_EVENT_TYPES, FlightByte::DELIVERY_STATUSES].each do |list|
      assert_equal list.uniq, list
      assert_predicate list, :frozen?
    end
    assert_equal 23, FlightByte::FLIGHT_CHANGE_TYPES.length
    assert_empty FlightByte::TERMINAL_PHASES - FlightByte::FLIGHT_PHASES
  end
end

class ObjectTest < Minitest::Test
  include FlightByteTest::Helpers

  def test_to_h_is_the_json_as_received_and_a_copy
    json = fixture_json("flight.json")
    f = FlightByte::FlightSnapshot.new(json)

    assert_equal json, f.to_h
    copy = f.to_h
    copy["departure"]["gate"] = "Z9"
    copy["codeshares"] << 1

    assert_equal "A11", f.departure.gate
    assert_equal 1, f.codeshares.length
    json["departure"]["gate"] = "Z8"

    assert_equal "A11", f.departure.gate
    assert_equal JSON.parse(fixture("flight.json")), JSON.parse(f.to_json)
    assert_equal f.to_h, f.as_json
  end

  def test_is_frozen_all_the_way_down
    f = FlightByte::FlightSnapshot.new(fixture_json("flight.json"))

    assert_predicate f, :frozen?
    assert_predicate f.codeshares, :frozen?
    assert_predicate f.departure.gate, :frozen?
    assert_predicate f.timeline.first.events, :frozen?
    assert_raises(FrozenError) { f.departure.gate << "x" }
  end

  def test_reads_a_field_newer_than_this_release
    f = FlightByte::FlightSnapshot.new(fixture_json("flight.json").merge("boardingAt" => "12:40",
                                                                         "gateInfo" => { "walkMinutes" => 7 }))

    assert_equal "12:40", f.boarding_at
    assert_respond_to f, :boarding_at
    assert_equal 7, f.gate_info.walk_minutes
    assert_instance_of FlightByte::Object, f.gate_info
    assert_equal "12:40", f["boardingAt"]
    assert_equal "12:40", f[:boardingAt]
  end

  def test_a_name_that_is_neither_known_nor_sent_raises
    f = FlightByte::FlightSnapshot.new(fixture_json("flight.json"))

    assert_raises(NoMethodError) { f.stauts }
    refute_respond_to f, :stauts
    assert_raises(NoMethodError) { f.boarding_at }
    assert_nil f["boardingAt"]
  end

  def test_digs_and_matches_patterns
    f = FlightByte::FlightSnapshot.new(fixture_json("flight.json"))

    assert_equal "A11", f.dig("departure", "gate")
    assert_equal "A3", f.dig("codeshares", 0, "carrier")
    assert_nil f.dig("diverted", "gate")
    matched = case f
              in { status: { phase: "scheduled" }, departure: { gate: String => gate } } then gate
              end

    assert_equal "A11", matched
  end

  def test_takes_symbol_keys_and_shows_them_as_strings
    country = FlightByte::Country.new(code: "TR", hasFlag: false)

    assert_equal "TR", country.code
    refute_predicate country, :has_flag?
    assert_equal({ "code" => "TR", "hasFlag" => false }, country.to_h)
    assert_raises(TypeError) { FlightByte::Country.new([1]) }
  end

  def test_compares_by_class_and_json
    a = FlightByte::Country.new("code" => "TR")

    assert_equal a, FlightByte::Country.new("code" => "TR")
    assert_equal a.hash, FlightByte::Country.new("code" => "TR").hash
    refute_equal a, FlightByte::CountryRef.new("code" => "TR")
    refute_equal a, FlightByte::Country.new("code" => "FR")
    assert_equal 1, [a, FlightByte::Country.new("code" => "TR")].uniq.length
  end

  def test_keeps_a_value_whose_shape_changed_as_received
    f = FlightByte::FlightSnapshot.new("departure" => "IST", "codeshares" => "none", "timeline" => [1, "x"])

    assert_equal "IST", f.departure
    assert_equal "none", f.codeshares
    assert_equal [1, "x"], f.timeline
  end

  def test_shows_a_secret_masked
    created = FlightByte::CreatedSubscription.new("id" => "sub_1", "secret" => "whsec_AbCdEfGhIjKlMnOpQrStUvwxyz")

    refute_includes created.inspect, "whsec_AbCdEfGhIjKlMnOpQrStUvwxyz"
    assert_includes created.inspect, "whsec_AbCdE...wxyz"
    refute_includes created.pretty_inspect, "whsec_AbCdEfGhIjKlMnOpQrStUvwxyz"
    assert_equal "whsec_AbCdEfGhIjKlMnOpQrStUvwxyz", created.secret
  end

  def test_names_fields_in_snake_case
    {
      "delayMinutes" => "delay_minutes", "flagSvgSquare" => "flag_svg_square", "alpha2" => "alpha2",
      "bestTimeUtc" => "best_time_utc", "providerFlightId" => "provider_flight_id", "x-team" => "x_team",
      "HTTPStatus" => "http_status", "id" => "id"
    }.each do |key, name|
      assert_equal name, FlightByte::Object.method_name(key)
    end
  end
end
