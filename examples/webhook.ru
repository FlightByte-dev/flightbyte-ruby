# frozen_string_literal: true

# Receives FlightByte webhooks with FlightByte::Webhook::RackApp and logs each
# change. Any Rack server runs it:
#
#   gem install rack rackup puma
#   FLIGHTBYTE_WEBHOOK_SECRET=whsec_... rackup -I lib -p 8080 examples/webhook.ru
#
# It listens at POST /hooks/flightbyte. Point a subscription's webhook_url
# there, through a tunnel when running locally.
require "flightbyte"

secret = ENV.fetch("FLIGHTBYTE_WEBHOOK_SECRET") do
  abort "Set FLIGHTBYTE_WEBHOOK_SECRET to the subscription's signing secret."
end

# Retries carry the same event id. A real receiver keeps these in its database.
seen = {}
seen_lock = Mutex.new

receiver = FlightByte::Webhook::RackApp.new(secret) do |event|
  next if seen_lock.synchronize { seen.key?(event.id).tap { seen[event.id] = true } }

  if event.type == "flight.updated"
    event.changes.each { |change| puts "#{event.flight_key} #{change.type}: #{change.message}" }
  else
    puts "#{event.flight_key} #{event.type}"
  end
end

map("/hooks/flightbyte") { run receiver }
