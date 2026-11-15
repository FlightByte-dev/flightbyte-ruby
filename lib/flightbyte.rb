# frozen_string_literal: true

require "date"
require "json"

require_relative "flightbyte/version"
require_relative "flightbyte/values"
require_relative "flightbyte/errors"
require_relative "flightbyte/object"
require_relative "flightbyte/models"
require_relative "flightbyte/rate_limit"
require_relative "flightbyte/transport"
require_relative "flightbyte/resources/flights"
require_relative "flightbyte/resources/subscriptions"
require_relative "flightbyte/resources/countries"
require_relative "flightbyte/client"
require_relative "flightbyte/webhook"
require_relative "flightbyte/webhook/rack_app"

# The official client for the FlightByte flight status API: look flights up,
# watch them with signed webhooks and verify every delivery.
#
#   require "flightbyte"
#
#   client = FlightByte::Client.new(api_key: ENV.fetch("FLIGHTBYTE_API_KEY"))
#   flight = client.flights.get(carrier: "TK", flight_number: "1848", date: "2026-09-08")
#   flight.status.label # => "Scheduled"
#
# Keep API keys on a server you control. A key shipped inside a browser or
# mobile app can be extracted by anyone who has the app.
module FlightByte
  class << self
    # Formats a date as the `YYYY-MM-DD` the API expects for flight dates.
    #
    # Only the calendar fields are used, in the value's own time zone, so pass
    # the local departure date at the origin airport: a `Date`, or a `Time`
    # already in the airport's offset (`time.getlocal("+03:00")`, or
    # `time.in_time_zone("Europe/Istanbul")` with Active Support).
    #
    # @param value [Date, Time, DateTime, #strftime]
    # @return [String]
    # @raise [ArgumentError] when `value` is not a date or a time
    def format_date(value)
      unless value.respond_to?(:strftime)
        raise ArgumentError, "flightbyte: format_date needs a Date or a Time, got #{value.inspect}."
      end

      value.strftime("%Y-%m-%d")
    end

    # Whether the flight is finished: arrived, cancelled, diverted or redirected.
    #
    # @param phase [String, nil] a {FlightStatusInfo#phase}
    # @return [Boolean]
    def terminal_phase?(phase)
      TERMINAL_PHASES.include?(phase.to_s)
    end

    # The best known gate time: actual, else estimated, else scheduled.
    #
    # @param times [EndpointTimes, Hash, nil] a {FlightEndpoint#times}
    # @return [FlightTime, Hash, nil]
    def best_gate_time(times)
      return nil if times.nil?

      times["actualGate"] || times["estimatedGate"] || times["scheduledGate"]
    end

    # Masks a signing secret the way the API does: the first 11 characters,
    # `...`, and the last 4. Short secrets are returned as they are.
    #
    # @param secret [String]
    # @return [String]
    def mask_secret(secret)
      secret = secret.to_s
      secret.length <= 15 ? secret : "#{secret[0, 11]}...#{secret[-4..]}"
    end
  end
end
