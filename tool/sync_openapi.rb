# frozen_string_literal: true

# Refreshes the vendored OpenAPI document that test/spec_test.rb checks the
# client and its models against.
#
#   rake sync_openapi                  # from https://flightbyte.dev/openapi.json
#   ruby tool/sync_openapi.rb <url>    # from somewhere else
require "json"
require "net/http"
require "uri"

url = URI(ARGV[0] || "https://flightbyte.dev/openapi.json")
target = File.expand_path("../spec/openapi.json", __dir__)

response = Net::HTTP.get_response(url, { "accept" => "application/json" })
abort "GET #{url} answered #{response.code}" unless response.is_a?(Net::HTTPSuccess)

spec = JSON.parse(response.body.force_encoding(Encoding::UTF_8))
abort "#{url} is not an OpenAPI document" unless spec["openapi"].is_a?(String) && spec["paths"].is_a?(Hash)

File.binwrite(target, "#{JSON.pretty_generate(spec)}\n")
operations = spec["paths"].values.flat_map(&:values).count { |op| op.is_a?(Hash) && op["operationId"] }
warn "Wrote spec/openapi.json: #{operations} operations, version #{spec.dig("info", "version")}. " \
     "Run rake test to check the client against it."
