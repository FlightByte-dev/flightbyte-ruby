# frozen_string_literal: true

require_relative "lib/flightbyte/version"

Gem::Specification.new do |spec|
  spec.name = "flightbyte"
  spec.version = FlightByte::VERSION
  spec.authors = ["FlightByte"]
  spec.email = ["support@flightbyte.dev"]

  spec.summary = "Official Ruby client for the FlightByte flight status API."
  spec.description = "Look flights up, watch them with signed webhooks and verify every delivery. " \
                     "Flights, subscriptions, countries and a Rack webhook receiver, " \
                     "with no dependencies outside the standard library."
  spec.homepage = "https://flightbyte.dev"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "documentation_uri" => "https://flightbyte.dev/docs",
    "source_code_uri" => "https://github.com/FlightByte-dev/flightbyte-ruby",
    "bug_tracker_uri" => "https://github.com/FlightByte-dev/flightbyte-ruby/issues",
    "changelog_uri" => "https://github.com/FlightByte-dev/flightbyte-ruby/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = ["lib"]
end
