# frozen_string_literal: true

module FlightByte
  # Flight lookups. Reach it as `client.flights`.
  class Flights
    # @api private
    def initialize(transport)
      @transport = transport
    end

    # Looks a flight up. The API upper-cases the carrier and strips leading
    # zeros from the flight number.
    #
    # A flight number can fly several legs on one date. The snapshot lists them
    # all in `alternates`; pass `origin:` (and optionally `destination:`) or a
    # leg's `flight_id:` to choose one.
    #
    # @param carrier [String] IATA or ICAO carrier code, for example `TK`
    # @param flight_number [String, Integer] flight number, for example `1848`
    # @param date [String, Date, Time] local departure date at the origin, `YYYY-MM-DD`
    # @param origin [String, nil] selects a leg by its origin IATA code
    # @param destination [String, nil] narrows the leg further by its destination IATA code
    # @param flight_id [String, nil] selects a leg by its upstream id, from `alternates`
    # @param refresh [Boolean] skips the API's cache and asks upstream
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [FlightSnapshot]
    # @raise [NotFoundError] when the flight did not operate that day
    def get(carrier:, flight_number:, date:, origin: nil, destination: nil, flight_id: nil, refresh: false,
            timeout: nil)
      path = flight_path(carrier, flight_number, date)
      query = { origin: origin, destination: destination, flightId: flight_id, refresh: refresh ? "true" : nil }
      FlightSnapshot.from_response(@transport.request("GET", path, query: query, timeout: timeout))
    end

    # The flight's change history as recorded by the airline, newest first.
    #
    # @param (see #get)
    # @return [FlightTimeline]
    def timeline(carrier:, flight_number:, date:, origin: nil, destination: nil, timeout: nil)
      path = [*flight_path(carrier, flight_number, date), "timeline"]
      query = { origin: origin, destination: destination }
      FlightTimeline.from_response(@transport.request("GET", path, query: query, timeout: timeout))
    end

    # Never shows the API key.
    def inspect
      "#<#{self.class.name}>"
    end

    private

    def flight_path(carrier, flight_number, date)
      [
        "flights",
        Transport.required("carrier", carrier),
        Transport.required("flight_number", flight_number),
        Transport.date("date", date)
      ]
    end
  end
end
