# frozen_string_literal: true

# Looks a flight up and prints its status.
#
#   FLIGHTBYTE_API_KEY=frk_live_... ruby -Ilib examples/lookup.rb TK 1848 2026-09-08
#
# FLIGHTBYTE_BASE_URL points it at another API root, for example a local one.
require "flightbyte"

carrier, flight_number, date = ARGV
unless carrier && flight_number && date
  abort "usage: ruby -Ilib examples/lookup.rb <carrier> <flight number> <YYYY-MM-DD>"
end
abort "Set FLIGHTBYTE_API_KEY to your API key." if ENV["FLIGHTBYTE_API_KEY"].to_s.empty?

client = FlightByte::Client.new(
  api_key: ENV.fetch("FLIGHTBYTE_API_KEY"),
  base_url: ENV.fetch("FLIGHTBYTE_BASE_URL", FlightByte::Client::DEFAULT_BASE_URL)
)

begin
  flight = client.flights.get(carrier: carrier, flight_number: flight_number, date: date)
rescue FlightByte::NotFoundError
  abort "No such flight on that date."
rescue FlightByte::BadRequestError => e
  raise if e.legs.empty?

  warn "This flight number flies several legs that day:"
  e.legs.each { |leg| warn "  #{leg.origin} → #{leg.destination} at #{leg.scheduled_departure_local}" }
  exit 1
rescue FlightByte::Error => e
  abort e.message
end

dash = ->(value) { value || "-" }
puts "#{flight.flight_key}  #{flight.departure.airport.iata} → #{flight.arrival.airport.iata}"
puts "Status     #{flight.status.label} (#{flight.status.phase})"
if (departs = flight.departure.times.best_gate)
  puts "Departure  #{departs.local} #{dash.call(departs.timezone)}, gate #{dash.call(flight.departure.gate)}"
end
if (arrives = flight.arrival.times.best_gate)
  puts "Arrival    #{arrives.local} #{dash.call(arrives.timezone)}, baggage #{dash.call(flight.arrival.baggage)}"
end
delay = flight.departure.delay_minutes
puts "Delay      #{delay} min" if delay&.nonzero?
if (minute = client.last_rate_limit&.minute)
  puts "Quota      #{minute.remaining} of #{minute.limit} left this minute"
end
