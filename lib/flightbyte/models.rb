# frozen_string_literal: true

module FlightByte
  # The shapes the API answers with. Class names follow the API's OpenAPI
  # document. Each reader returns the value exactly as the API sent it:
  # timestamps are ISO 8601 strings, enums are strings, and a field the API
  # left out or sent as `null` is `nil`.

  # A country as it appears inside an airport.
  class CountryRef < Object
    # @!attribute [r] code
    #   @return [String] ISO 3166-1 alpha-2 code, for example `TR`.
    field "code"
    # @!attribute [r] name
    #   @return [String] Country name.
    field "name"
    # @!attribute [r] emoji
    #   @return [String] Flag emoji.
    field "emoji"
    # @!attribute [r] flag_svg
    #   @return [String] Absolute URL of the 4:3 SVG flag.
    field "flagSvg"
    # @!attribute [r] flag_svg_square
    #   @return [String] Absolute URL of the 1:1 SVG flag.
    field "flagSvgSquare"
  end

  # A country from {Countries#list} and {Countries#get}.
  class Country < CountryRef
    # @!attribute [r] alpha2
    #   @return [String] ISO 3166-1 alpha-2 code.
    field "alpha2"
    # @!attribute [r] has_flag
    #   @return [Boolean] Whether a flag image exists for the country. Also `has_flag?`.
    field "hasFlag", predicate: true
  end

  # An airport.
  class AirportRef < Object
    # @!attribute [r] iata
    #   @return [String] IATA code, for example `IST`.
    field "iata"
    # @!attribute [r] icao
    #   @return [String, nil] ICAO code, for example `LTFM`.
    field "icao"
    # @!attribute [r] code
    #   @return [String, nil] The upstream's own airport code; it may differ from `iata`.
    field "code"
    # @!attribute [r] name
    #   @return [String] Airport name.
    field "name"
    # @!attribute [r] city
    #   @return [String, nil] City.
    field "city"
    # @!attribute [r] state
    #   @return [String, nil] State or region.
    field "state"
    # @!attribute [r] country
    #   @return [CountryRef] Country.
    field "country", CountryRef
    # @!attribute [r] timezone
    #   @return [String, nil] IANA time zone, for example `Europe/Istanbul`.
    field "timezone"
  end

  # A point in time, in UTC and in the airport's local time.
  class FlightTime < Object
    # @!attribute [r] utc
    #   @return [String] The instant, ISO 8601 in UTC.
    field "utc"
    # @!attribute [r] local
    #   @return [String, nil] Airport-local wall time without an offset, for
    #     example `2026-09-08T12:10:00.000`. Pair it with the airport's time zone.
    field "local"
    # @!attribute [r] timezone
    #   @return [String, nil] Time zone abbreviation, for example `EEST`.
    field "timezone"
  end

  # The gate and runway times of a departure or an arrival.
  class EndpointTimes < Object
    # @!attribute [r] scheduled_gate
    #   @return [FlightTime, nil] Scheduled gate time.
    field "scheduledGate", FlightTime
    # @!attribute [r] estimated_gate
    #   @return [FlightTime, nil] Estimated gate time.
    field "estimatedGate", FlightTime
    # @!attribute [r] actual_gate
    #   @return [FlightTime, nil] Actual gate time.
    field "actualGate", FlightTime
    # @!attribute [r] scheduled_runway
    #   @return [FlightTime, nil] Scheduled runway time.
    field "scheduledRunway", FlightTime
    # @!attribute [r] estimated_runway
    #   @return [FlightTime, nil] Estimated runway time.
    field "estimatedRunway", FlightTime
    # @!attribute [r] actual_runway
    #   @return [FlightTime, nil] Actual runway time.
    field "actualRunway", FlightTime

    # The best known gate time: actual, else estimated, else scheduled.
    #
    # @return [FlightTime, nil]
    def best_gate
      FlightByte.best_gate_time(self)
    end
  end

  # The departure or arrival side of a flight.
  class FlightEndpoint < Object
    # @!attribute [r] airport
    #   @return [AirportRef] The airport.
    field "airport", AirportRef
    # @!attribute [r] terminal
    #   @return [String, nil] Terminal.
    field "terminal"
    # @!attribute [r] gate
    #   @return [String, nil] Gate.
    field "gate"
    # @!attribute [r] baggage
    #   @return [String, nil] Baggage carousel, on arrival.
    field "baggage"
    # @!attribute [r] times
    #   @return [EndpointTimes] Gate and runway times.
    field "times", EndpointTimes
    # @!attribute [r] best_time_utc
    #   @return [String, nil] Best known time in UTC: actual, else estimated, else scheduled.
    field "bestTimeUtc"
    # @!attribute [r] delay_minutes
    #   @return [Integer, nil] Gate delay in minutes; negative when early.
    field "delayMinutes"
  end

  # The marketing carrier.
  class CarrierRef < Object
    # @!attribute [r] iata
    #   @return [String] IATA code, for example `TK`.
    field "iata"
    # @!attribute [r] icao
    #   @return [String, nil] ICAO code, for example `THY`.
    field "icao"
    # @!attribute [r] name
    #   @return [String] Airline name.
    field "name"
  end

  # A codeshare flight number sold on the same flight.
  class CodeshareRef < Object
    # @!attribute [r] carrier
    #   @return [String] Carrier code.
    field "carrier"
    # @!attribute [r] name
    #   @return [String] Carrier name.
    field "name"
    # @!attribute [r] flight_number
    #   @return [String] Flight number.
    field "flightNumber"
  end

  # The status of a flight.
  class FlightStatusInfo < Object
    # @!attribute [r] code
    #   @return [String] Upstream status code: `S`, `A`, `L`, `C`, `D`, `R`, `U` or `NO`.
    field "code"
    # @!attribute [r] label
    #   @return [String] Human-readable status, for example `Arrived`.
    field "label"
    # @!attribute [r] description
    #   @return [String, nil] Longer description, for example `On time`.
    field "description"
    # @!attribute [r] color
    #   @return [String, nil] Suggested color, for example `green`.
    field "color"
    # @!attribute [r] phase
    #   @return [String] The lifecycle phase; one of {FLIGHT_PHASES}, or a newer one.
    field "phase"
    # @!attribute [r] delayed
    #   @return [Boolean] Whether the flight is delayed. Also `delayed?`.
    field "delayed", predicate: true
    # @!attribute [r] cancelled
    #   @return [Boolean] Whether the flight is cancelled. Also `cancelled?`.
    field "cancelled", predicate: true
    # @!attribute [r] diverted
    #   @return [Boolean] Whether the flight is diverted. Also `diverted?`.
    field "diverted", predicate: true
    # @!attribute [r] departure_gate_delay_minutes
    #   @return [Integer, nil] Departure gate delay in minutes.
    field "departureGateDelayMinutes"
    # @!attribute [r] arrival_gate_delay_minutes
    #   @return [Integer, nil] Arrival gate delay in minutes.
    field "arrivalGateDelayMinutes"

    # Whether the flight is finished: arrived, cancelled, diverted or redirected.
    def terminal?
      FlightByte.terminal_phase?(phase)
    end
  end

  # The aircraft.
  class EquipmentInfo < Object
    # @!attribute [r] tail_number
    #   @return [String, nil] Registration, for example `TC-LTP`.
    field "tailNumber"
    # @!attribute [r] iata
    #   @return [String, nil] IATA aircraft type, for example `32Q`.
    field "iata"
    # @!attribute [r] name
    #   @return [String, nil] Aircraft name, for example `Airbus A321neo`.
    field "name"
    # @!attribute [r] source
    #   @return [String, nil] Where the data came from, for example `Actual`.
    field "source"
  end

  # Block times in minutes.
  class DurationInfo < Object
    # @!attribute [r] scheduled_minutes
    #   @return [Integer, nil] Scheduled duration.
    field "scheduledMinutes"
    # @!attribute [r] estimated_minutes
    #   @return [Integer, nil] Estimated duration.
    field "estimatedMinutes"
    # @!attribute [r] actual_minutes
    #   @return [Integer, nil] Actual duration.
    field "actualMinutes"
  end

  # One entry of a flight's upstream history.
  class TimelineEntry < Object
    # @!attribute [r] occurred_at
    #   @return [String] When it happened, ISO 8601.
    field "occurredAt"
    # @!attribute [r] title
    #   @return [String] Title, for example `Time Adjustment`.
    field "title"
    # @!attribute [r] source
    #   @return [String, nil] Source, for example `Airline`.
    field "source"
    # @!attribute [r] events
    #   @return [Array<String>] What changed, as sentences.
    field "events"
  end

  # A leg flown under the same flight number on the same date. Flight numbers
  # are not unique per day, so the API lists every leg and marks the one the
  # snapshot describes with `selected`.
  class FlightLegRef < Object
    # @!attribute [r] provider_flight_id
    #   @return [String, nil] Upstream flight id; pass it as `flight_id:` to select this leg.
    field "providerFlightId"
    # @!attribute [r] carrier
    #   @return [String, nil] Operating carrier code.
    field "carrier"
    # @!attribute [r] departure_iata
    #   @return [String] Origin IATA code.
    field "departureIata"
    # @!attribute [r] arrival_iata
    #   @return [String] Destination IATA code.
    field "arrivalIata"
    # @!attribute [r] scheduled_departure_local
    #   @return [String, nil] Scheduled local departure, `HH:mm`.
    field "scheduledDepartureLocal"
    # @!attribute [r] scheduled_arrival_local
    #   @return [String, nil] Scheduled local arrival, `HH:mm`.
    field "scheduledArrivalLocal"
    # @!attribute [r] selected
    #   @return [Boolean] Whether this is the leg the snapshot describes. Also `selected?`.
    field "selected", predicate: true
  end

  # Everything known about one flight leg at one moment, from {Flights#get}.
  class FlightSnapshot < Object
    # @!attribute [r] flight_key
    #   @return [String] Stable key, for example `TK1848:2026-09-08` or `TK1:2026-09-08@IST-JFK`.
    field "flightKey"
    # @!attribute [r] carrier_code
    #   @return [String] Carrier code from the request, for example `TK`.
    field "carrierCode"
    # @!attribute [r] flight_number
    #   @return [String] Flight number without leading zeros, for example `1848`.
    field "flightNumber"
    # @!attribute [r] date
    #   @return [String] Local departure date at the origin, `YYYY-MM-DD`.
    field "date"
    # @!attribute [r] provider_flight_id
    #   @return [String, nil] Upstream flight id.
    field "providerFlightId"
    # @!attribute [r] fetched_at
    #   @return [String] When the API fetched this data from upstream, ISO 8601.
    field "fetchedAt"
    # @!attribute [r] carrier
    #   @return [CarrierRef] Marketing carrier.
    field "carrier", CarrierRef
    # @!attribute [r] operated_by
    #   @return [String, nil] Operating carrier name, when different.
    field "operatedBy"
    # @!attribute [r] codeshares
    #   @return [Array<CodeshareRef>] Codeshare flight numbers.
    field "codeshares", [CodeshareRef]
    # @!attribute [r] departure
    #   @return [FlightEndpoint] Departure side.
    field "departure", FlightEndpoint
    # @!attribute [r] arrival
    #   @return [FlightEndpoint] Arrival side.
    field "arrival", FlightEndpoint
    # @!attribute [r] diverted
    #   @return [FlightEndpoint, nil] Where the flight actually went, when diverted.
    field "diverted", FlightEndpoint
    # @!attribute [r] status
    #   @return [FlightStatusInfo] Status.
    field "status", FlightStatusInfo
    # @!attribute [r] equipment
    #   @return [EquipmentInfo] Aircraft.
    field "equipment", EquipmentInfo
    # @!attribute [r] duration
    #   @return [DurationInfo] Block times.
    field "duration", DurationInfo
    # @!attribute [r] timeline
    #   @return [Array<TimelineEntry>] Upstream history, newest first.
    field "timeline", [TimelineEntry]
    # @!attribute [r] alternates
    #   @return [Array<FlightLegRef>] Every leg flown under this flight number on this date.
    field "alternates", [FlightLegRef]
    # @!attribute [r] fingerprint
    #   @return [String] Hash over the change-relevant fields.
    field "fingerprint"
    # @!attribute [r] cached
    #   @return [Boolean, nil] Whether a lookup was answered from the API's cache.
    #     Sent with lookups, not inside webhook events. Also `cached?`.
    field "cached", predicate: true
  end

  # The response of {Flights#timeline}.
  class FlightTimeline < Object
    # @!attribute [r] flight_key
    #   @return [String] The flight's key.
    field "flightKey"
    # @!attribute [r] count
    #   @return [Integer] The number of entries.
    field "count"
    # @!attribute [r] data
    #   @return [Array<TimelineEntry>] History entries, newest first.
    field "data", [TimelineEntry]
  end

  # A watched flight: the API polls it and posts a signed webhook to
  # `webhook_url` whenever something about it changes.
  class Subscription < Object
    # @!attribute [r] id
    #   @return [String] Id, for example `sub_7Kd91mQx0Zb2c3d4e5f6`.
    field "id"
    # @!attribute [r] status
    #   @return [String] Lifecycle status; one of {SUBSCRIPTION_STATUSES}, or a newer one.
    field "status"
    # @!attribute [r] flight_key
    #   @return [String] The watched flight's key, for example `TK1848:2026-09-08`.
    field "flightKey"
    # @!attribute [r] carrier
    #   @return [String] Carrier code.
    field "carrier"
    # @!attribute [r] flight_number
    #   @return [String] Flight number.
    field "flightNumber"
    # @!attribute [r] date
    #   @return [String] Local departure date at the origin, `YYYY-MM-DD`.
    field "date"
    # @!attribute [r] webhook_url
    #   @return [String] Where webhooks are posted.
    field "webhookUrl"
    # @!attribute [r] secret_hint
    #   @return [String, nil] The masked signing secret, for example `whsec_AbCdE...wxyz`.
    field "secretHint"
    # @!attribute [r] secret
    #   @return [String, nil] The full signing secret. Only the creation response
    #     carries it; read it again with {Subscriptions#secret}.
    field "secret"
    # @!attribute [r] headers
    #   @return [Hash{String => String}, nil] Extra headers sent with every delivery.
    field "headers", :map
    # @!attribute [r] events
    #   @return [Array<String>] The change types that trigger a webhook; see {FLIGHT_CHANGE_TYPES}.
    field "events"
    # @!attribute [r] delay_threshold_minutes
    #   @return [Integer] Delay swings smaller than this many minutes are ignored.
    field "delayThresholdMinutes"
    # @!attribute [r] metadata
    #   @return [Hash{String => String}, nil] Your own data, echoed back in every webhook.
    field "metadata", :map
    # @!attribute [r] created_at
    #   @return [String] When it was created, ISO 8601.
    field "createdAt"
    # @!attribute [r] updated_at
    #   @return [String] When it last changed, ISO 8601.
    field "updatedAt"
    # @!attribute [r] last_polled_at
    #   @return [String, nil] When the flight was last polled, ISO 8601.
    field "lastPolledAt"
    # @!attribute [r] last_change_at
    #   @return [String, nil] When a change was last detected, ISO 8601.
    field "lastChangeAt"
    # @!attribute [r] last_delivery_at
    #   @return [String, nil] When a webhook was last delivered, ISO 8601.
    field "lastDeliveryAt"
    # @!attribute [r] delivered_count
    #   @return [Integer] Webhooks delivered.
    field "deliveredCount"
    # @!attribute [r] failed_count
    #   @return [Integer] Webhook attempts that failed.
    field "failedCount"
    # @!attribute [r] flight_resolved
    #   @return [Boolean] `false` while the flight is not found upstream yet. Also `flight_resolved?`.
    field "flightResolved", predicate: true
    # @!attribute [r] status_reason
    #   @return [String, nil] Why the subscription was suspended or completed.
    field "statusReason"
  end

  # The response of {Subscriptions#create}.
  class CreatedSubscription < Subscription
    # @!attribute [r] reused
    #   @return [Boolean] `true` when an earlier request with the same idempotency
    #     key, within 24 hours, was replayed: the original subscription is
    #     returned and nothing new is created or billed. Also `reused?`.
    field "reused", predicate: true
    # @!attribute [r] flight
    #   @return [FlightSnapshot, nil] The flight as first seen, when it was found. Absent when reused.
    field "flight", FlightSnapshot
  end

  # One page of {Subscriptions#list}.
  class SubscriptionPage < Object
    # @!attribute [r] total
    #   @return [Integer] The number of subscriptions matching the filters.
    field "total"
    # @!attribute [r] limit
    #   @return [Integer] The page size used.
    field "limit"
    # @!attribute [r] offset
    #   @return [Integer] The number of subscriptions skipped.
    field "offset"
    # @!attribute [r] data
    #   @return [Array<Subscription>] The subscriptions on this page, newest first.
    field "data", [Subscription]
  end

  # One webhook delivery attempt, from {Subscriptions#deliveries}.
  class DeliveryRecord < Object
    # @!attribute [r] event_id
    #   @return [String] The delivered event's id.
    field "eventId"
    # @!attribute [r] attempt
    #   @return [Integer] Attempt number, starting at 1.
    field "attempt"
    # @!attribute [r] status
    #   @return [String] The outcome; one of {DELIVERY_STATUSES}, or a newer one.
    field "status"
    # @!attribute [r] http_status
    #   @return [Integer, nil] The receiver's HTTP status, when it answered.
    field "httpStatus"
    # @!attribute [r] error
    #   @return [String, nil] What went wrong, when the attempt failed.
    field "error"
    # @!attribute [r] duration_ms
    #   @return [Integer] How long the attempt took, in milliseconds.
    field "durationMs"
    # @!attribute [r] at
    #   @return [String] When the attempt was made, ISO 8601.
    field "at"
    # @!attribute [r] change_types
    #   @return [Array<String>] The change types the event carried.
    field "changeTypes"
  end

  # One change inside a `flight.updated` event.
  class FlightChange < Object
    # @!attribute [r] type
    #   @return [String] What changed; one of {FLIGHT_CHANGE_TYPES}, or a newer one.
    field "type"
    # @!attribute [r] path
    #   @return [String] Dotted path into the snapshot, for example `departure.gate`.
    field "path"
    # @!attribute [r] from
    #   @return [String, Numeric, Boolean, nil] The old value. Times are ISO 8601 UTC strings.
    field "from"
    # @!attribute [r] to
    #   @return [String, Numeric, Boolean, nil] The new value. Times are ISO 8601 UTC strings.
    field "to"
    # @!attribute [r] message
    #   @return [String] A sentence describing the change.
    field "message"
    # @!attribute [r] delta_minutes
    #   @return [Integer, nil] Signed minute delta, for time changes.
    field "deltaMinutes"
  end

  # A webhook event, as posted to your receiver and as listed by
  # {Subscriptions#events}.
  class WebhookEvent < Object
    # @!attribute [r] id
    #   @return [String] Event id, `evt_<uuid>`. The same across delivery retries: deduplicate on it.
    field "id"
    # @!attribute [r] type
    #   @return [String] The event type; one of {WEBHOOK_EVENT_TYPES}, or a newer one.
    field "type"
    # @!attribute [r] created_at
    #   @return [String] When the event was created, ISO 8601.
    field "createdAt"
    # @!attribute [r] subscription_id
    #   @return [String] The subscription it belongs to.
    field "subscriptionId"
    # @!attribute [r] flight_key
    #   @return [String] The flight's key.
    field "flightKey"
    # @!attribute [r] flight
    #   @return [FlightSnapshot, nil] The flight after the change. Missing on some lifecycle events.
    field "flight", FlightSnapshot
    # @!attribute [r] changes
    #   @return [Array<FlightChange>] What changed. Empty except on `flight.updated`.
    field "changes", [FlightChange]
    # @!attribute [r] previous_fetched_at
    #   @return [String, nil] When the previous snapshot was fetched, on `flight.updated`.
    field "previousFetchedAt"
    # @!attribute [r] metadata
    #   @return [Hash{String => String}, nil] The subscription's metadata.
    field "metadata", :map
  end

  # One of the legs listed by an ambiguous-flight {BadRequestError}.
  class AmbiguousLeg < Object
    # @!attribute [r] origin
    #   @return [String] Origin IATA code.
    field "origin"
    # @!attribute [r] destination
    #   @return [String] Destination IATA code.
    field "destination"
    # @!attribute [r] carrier
    #   @return [String, nil] Operating carrier.
    field "carrier"
    # @!attribute [r] scheduled_departure_local
    #   @return [String, nil] Scheduled local departure, `HH:mm`.
    field "scheduledDepartureLocal"
    # @!attribute [r] flight_id
    #   @return [String, nil] Upstream flight id.
    field "flightId"
  end
end
