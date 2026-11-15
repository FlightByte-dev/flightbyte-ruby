# frozen_string_literal: true

module FlightByte
  # The values the API's string enums take, as this version knows them. The
  # API may add more: a value added after this release still arrives as a
  # plain `String`, so nothing breaks. Compare with strings, or check
  # `FLIGHT_PHASES.include?(phase)` to see whether this version knows a value.

  # Every flight phase this version knows, in the API's order.
  FLIGHT_PHASES = %w[
    scheduled boarding departed en_route landed arrived cancelled diverted redirected unknown
  ].freeze

  # The phases after which nothing about the flight changes any more.
  TERMINAL_PHASES = %w[arrived cancelled diverted redirected].freeze

  # Every subscription status this version knows.
  #
  # `active` polls and delivers, `pending` waits for the flight to be
  # published upstream, `paused` was paused by you, `completed` finished after
  # the flight did, `suspended` was disabled by the API, for example after
  # repeated delivery failures.
  SUBSCRIPTION_STATUSES = %w[active pending paused completed suspended].freeze

  # Every flight change type this version knows, in the API's order: the kind
  # of change a `flight.updated` webhook reports, and what a subscription's
  # `events` filter is made of.
  FLIGHT_CHANGE_TYPES = %w[
    status.changed
    flight.departed
    flight.arrived
    flight.cancelled
    flight.diverted
    flight.reinstated
    departure.gate.changed
    departure.terminal.changed
    arrival.gate.changed
    arrival.terminal.changed
    arrival.baggage.changed
    departure.scheduled.changed
    departure.estimated.changed
    departure.actual.changed
    arrival.scheduled.changed
    arrival.estimated.changed
    arrival.actual.changed
    delay.increased
    delay.decreased
    aircraft.changed
    aircraft.tail.changed
    route.changed
    codeshares.changed
  ].freeze

  # Every webhook event type this version knows.
  WEBHOOK_EVENT_TYPES = %w[
    subscription.created
    subscription.activated
    subscription.test
    subscription.completed
    subscription.suspended
    flight.updated
  ].freeze

  # Every delivery status this version knows: the outcome of one webhook
  # delivery attempt.
  DELIVERY_STATUSES = %w[delivered failed].freeze
end
