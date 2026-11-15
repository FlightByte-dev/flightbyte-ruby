# frozen_string_literal: true

require "test_helper"

# Drift check: the client and its models must line up with the vendored
# OpenAPI document (spec/openapi.json). Refresh the copy with
# `rake sync_openapi`; if the API added, renamed or moved anything, these
# tests say what.
class SpecTest < Minitest::Test
  include FlightByteTest::Helpers

  SPEC = FlightByteTest.spec
  SCHEMAS = SPEC.dig("components", "schemas")

  OPERATIONS = SPEC["paths"].each_with_object({}) do |(path, methods), operations|
    methods.each do |method, operation|
      next unless operation.is_a?(Hash) && operation["operationId"]

      operations[operation["operationId"]] = { method: method.upcase, path: path, operation: operation }
    end
  end.freeze

  # Operations without a method of their own, and why.
  NOT_EXPOSED = {
    "search-flights" => "the same lookup as get-flight, with the identifiers in the query string",
    "get-flag" => "returns an SVG image; countries.flag_url builds its URL"
  }.freeze

  LEG = { carrier: "TK", flight_number: "1848", date: "2026-09-08" }.freeze

  # Each operation, the method that sends it, and a call of that method.
  CALLS = {
    "list-countries" => [FlightByte::Countries, :list, ->(c) { c.countries.list }],
    "get-country" => [FlightByte::Countries, :get, ->(c) { c.countries.get("TR") }],
    "get-flight" => [FlightByte::Flights, :get, ->(c) { c.flights.get(**LEG) }],
    "flight-timeline" => [FlightByte::Flights, :timeline, ->(c) { c.flights.timeline(**LEG) }],
    "create-subscription" => [FlightByte::Subscriptions, :create, lambda { |c|
      c.subscriptions.create(**LEG, webhook_url: "https://example.com/h")
    }],
    "list-subscriptions" => [FlightByte::Subscriptions, :list, ->(c) { c.subscriptions.list }],
    "get-subscription" => [FlightByte::Subscriptions, :get, ->(c) { c.subscriptions.get("sub_1") }],
    "update-subscription" => [FlightByte::Subscriptions, :update, ->(c) { c.subscriptions.update("sub_1") }],
    "delete-subscription" => [FlightByte::Subscriptions, :delete, ->(c) { c.subscriptions.delete("sub_1") }],
    "pause-subscription" => [FlightByte::Subscriptions, :pause, ->(c) { c.subscriptions.pause("sub_1") }],
    "resume-subscription" => [FlightByte::Subscriptions, :resume, ->(c) { c.subscriptions.resume("sub_1") }],
    "send-test-event" => [FlightByte::Subscriptions, :send_test, ->(c) { c.subscriptions.send_test("sub_1") }],
    "list-deliveries" => [FlightByte::Subscriptions, :deliveries, ->(c) { c.subscriptions.deliveries("sub_1") }],
    "list-events" => [FlightByte::Subscriptions, :events, ->(c) { c.subscriptions.events("sub_1") }],
    "reveal-secret" => [FlightByte::Subscriptions, :secret, ->(c) { c.subscriptions.secret("sub_1") }],
    "rotate-secret" => [FlightByte::Subscriptions, :rotate_secret, ->(c) { c.subscriptions.rotate_secret("sub_1") }]
  }.freeze

  # Keywords every method takes that are not the API's.
  OWN_KEYWORDS = %i[timeout].freeze

  def snake(name)
    FlightByte::Object.method_name(name).to_sym
  end

  def path_pattern(template)
    Regexp.new("\\A#{template.gsub(/\{[^}]+\}/, "[^/]+")}\\z")
  end

  def test_every_operation_has_a_method_and_nothing_is_left_unaccounted_for
    covered = CALLS.keys + NOT_EXPOSED.keys

    assert_empty OPERATIONS.keys - covered, "operations without a method"
    assert_empty covered - OPERATIONS.keys, "methods for operations the document does not have"
  end

  CALLS.each do |operation_id, (_resource, _method, call)|
    define_method("test_#{operation_id.tr("-", "_")}_sends_the_documented_method_and_path") do
      expected = OPERATIONS.fetch(operation_id)
      server = serve { json(200, { data: [], secret: "s", eventId: "e" }) }
      call.call(client_for(server))

      assert_equal expected[:method], server.last.verb
      assert_match path_pattern(expected[:path]), server.last.path
    end

    define_method("test_#{operation_id.tr("-", "_")}_takes_every_documented_parameter") do
      _resource, method_name, = CALLS.fetch(operation_id)
      operation = OPERATIONS.fetch(operation_id)[:operation]
      documented = (operation["parameters"] || []).to_h { |p| [snake(p["name"]), p["required"] == true] }
      body = operation.dig("requestBody", "content", "application/json", "schema", "$ref")
      if body
        schema = SCHEMAS.fetch(body.split("/").last)
        schema["properties"].each_key { |name| documented[snake(name)] = schema.fetch("required", []).include?(name) }
      end
      parameters = CALLS.fetch(operation_id)[0].instance_method(method_name).parameters
      taken = parameters.reject { |_kind, name| OWN_KEYWORDS.include?(name) }
                        .to_h { |kind, name| [name, %i[req keyreq].include?(kind)] }

      assert_equal documented.sort.to_h, taken.sort.to_h, "#{operation_id}: parameters, and whether each is required"
    end
  end

  def test_list_all_takes_the_list_filters
    list = FlightByte::Subscriptions.instance_method(:list).parameters.map(&:last) - %i[limit]
    list_all = FlightByte::Subscriptions.instance_method(:list_all).parameters.map(&:last) - %i[page_size block]

    assert_equal list.sort, list_all.sort
  end

  def test_get_flag_through_flag_url
    url = URI(FlightByte::Client.new(api_key: "k").countries.flag_url("TR"))

    assert_match path_pattern(OPERATIONS.fetch("get-flag")[:path]), url.path
  end

  # Schemas that are a request body, checked above as keywords, or an error
  # body, checked below.
  NOT_MODELS = %w[CreateSubscriptionDto UpdateSubscriptionDto WatchedFlightsUsedUp].freeze

  # Fields the API sends that the document leaves out, and why the models have them.
  UNDOCUMENTED_FIELDS = {
    "FlightSnapshot.cached" => "lookups say whether the cache answered; the document leaves it out",
    "Subscription.secretHint" => "every response but the creation one carries the masked secret"
  }.freeze

  (SCHEMAS.keys - NOT_MODELS).each do |schema_name|
    define_method("test_#{schema_name}_has_a_model_with_every_documented_field") do
      assert FlightByte.const_defined?(schema_name, false), "lib/flightbyte/models.rb has no class #{schema_name}"
      model = FlightByte.const_get(schema_name, false)

      assert_operator model, :<, FlightByte::Object
      documented = SCHEMAS.fetch(schema_name).fetch("properties", {}).keys
      declared = model.fields.keys

      assert_empty documented - declared, "#{schema_name} lacks fields the API documents"
      extra = declared - documented - UNDOCUMENTED_FIELDS.keys.filter_map do |f|
        f.split(".").last if f.start_with?("#{schema_name}.")
      end

      assert_empty extra, "#{schema_name} has fields the document does not list"
    end
  end

  def test_the_402_body_through_payment_required_error
    base = %w[statusCode error message code]
    fields = SCHEMAS.fetch("WatchedFlightsUsedUp").fetch("properties").keys - base
    missing = fields.reject { |field| FlightByte::PaymentRequiredError.method_defined?(snake(field)) }

    assert_empty missing
  end

  def test_the_value_lists_match_the_document
    assert_equal SCHEMAS.dig("FlightStatusInfo", "properties", "phase", "enum"), FlightByte::FLIGHT_PHASES
    assert_equal SCHEMAS.dig("Subscription", "properties", "status", "enum"), FlightByte::SUBSCRIPTION_STATUSES
    assert_equal SCHEMAS.dig("CreateSubscriptionDto", "properties", "events", "items", "enum"),
                 FlightByte::FLIGHT_CHANGE_TYPES
    assert_equal SCHEMAS.dig("UpdateSubscriptionDto", "properties", "events", "items", "enum"),
                 FlightByte::FLIGHT_CHANGE_TYPES
    assert_equal %w[watched_flight_limit overage_cap_reached credits_exhausted],
                 SCHEMAS.dig("WatchedFlightsUsedUp", "properties", "code", "enum")
  end

  def test_no_field_hides_behind_a_method_every_object_has
    models = ObjectSpace.each_object(Class).select { |klass| klass < FlightByte::Object }
    taken = FlightByte::Object.instance_methods + FlightByte::Object.private_instance_methods
    clashes = models.flat_map do |model|
      model.fields.keys.map { |key| FlightByte::Object.method_name(key).to_sym }
           .select { |name| taken.include?(name) }.map { |name| "#{model}##{name}" }
    end

    assert_operator models.length, :>=, 20
    assert_empty clashes
  end

  def test_no_documented_field_would_hide_behind_one_either
    taken = FlightByte::Object.instance_methods + FlightByte::Object.private_instance_methods
    names = SCHEMAS.values.flat_map { |schema| schema.fetch("properties", {}).keys }.uniq

    assert_empty(names.select { |name| taken.include?(snake(name)) })
  end
end
