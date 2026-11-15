# frozen_string_literal: true

require "json"
require "openssl"

module FlightByte
  # Verifies and decodes the webhooks FlightByte posts to your receiver.
  #
  # Each delivery carries an `x-flightbyte-signature` header of the form
  # `t=<unix seconds>,v1=<hex>`, where the hex is HMAC-SHA256 of
  # `"<t>.<raw body>"` keyed with the subscription's signing secret.
  #
  #   event = FlightByte::Webhook.construct_event(
  #     request.raw_post,
  #     request.headers["X-FlightByte-Signature"],
  #     ENV.fetch("FLIGHTBYTE_WEBHOOK_SECRET")
  #   )
  #
  # Pass the body exactly as received: JSON parsed and serialized again no
  # longer matches the signature. Keep the signing secret on your server.
  module Webhook
    # Header carrying the signature.
    SIGNATURE_HEADER = "x-flightbyte-signature"
    # Header carrying the signing time, in unix seconds.
    TIMESTAMP_HEADER = "x-flightbyte-timestamp"
    # Header carrying the event id.
    EVENT_ID_HEADER = "x-flightbyte-event-id"
    # Header carrying the event type.
    EVENT_TYPE_HEADER = "x-flightbyte-event-type"
    # Header carrying the subscription id.
    SUBSCRIPTION_ID_HEADER = "x-flightbyte-subscription-id"
    # Header carrying the delivery attempt number, starting at 1.
    DELIVERY_ATTEMPT_HEADER = "x-flightbyte-delivery-attempt"
    # The Rack env key of {SIGNATURE_HEADER}, for `request.env[...]`.
    SIGNATURE_ENV_KEY = "HTTP_X_FLIGHTBYTE_SIGNATURE"
    # How far the signing time may be from now by default, in seconds: 5 minutes.
    DEFAULT_TOLERANCE = 300
    # The largest body {RackApp} reads: 1 MiB.
    MAX_BODY_BYTES = 1024 * 1024

    class << self
      # Checks `signature` (the `x-flightbyte-signature` header) against the
      # raw body `payload` and the subscription's `secret`.
      #
      # @param payload [String] the body exactly as received, for example Rails'
      #   `request.raw_post` or Rack's `env["rack.input"].read`
      # @param signature [String, nil] the `x-flightbyte-signature` header
      # @param secret [String] the subscription's signing secret
      # @param tolerance [Numeric] how far the signing time may be from now, in
      #   seconds; `0` skips the check
      # @param now [Time, Numeric, nil] the time to check against instead of
      #   now, as a Time or unix seconds; useful in tests
      # @return [true]
      # @raise [WebhookSignatureError] when the signature does not verify
      # @raise [ArgumentError] when `secret` is empty: anyone can sign with an
      #   empty key, so it usually means the secret was not configured
      def verify(payload, signature, secret, tolerance: DEFAULT_TOLERANCE, now: nil)
        check_secret(secret)
        unless tolerance.is_a?(Numeric) && tolerance.real?
          raise ArgumentError, "flightbyte: tolerance must be a number of seconds; got #{tolerance.inspect}."
        end

        body = bytes(payload)
        timestamp, signatures = parse_signature(signature)
        if tolerance.positive?
          current = unix(now || Time.now)
          # Compared against both edges, so an extreme timestamp cannot slip through.
          if timestamp.to_i < current - tolerance || timestamp.to_i > current + tolerance
            raise WebhookSignatureError, "The signature timestamp is outside the tolerance window."
          end
        end

        expected = hmac(secret, timestamp, body)
        matched = signatures.any? do |candidate|
          candidate.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(candidate, expected)
        end
        raise WebhookSignatureError, "The signature does not match the payload." unless matched

        true
      end

      # Whether `signature` verifies; see {.verify}.
      #
      # @return [Boolean]
      # @raise [ArgumentError] when `secret` is empty
      def valid?(payload, signature, secret, tolerance: DEFAULT_TOLERANCE, now: nil)
        verify(payload, signature, secret, tolerance: tolerance, now: now)
      rescue WebhookSignatureError
        false
      end

      # Verifies the signature, then decodes the event.
      #
      # @param (see .verify)
      # @return [WebhookEvent]
      # @raise [WebhookSignatureError] when the signature does not verify
      # @raise [Error] when the verified body is not a webhook event
      # @raise [ArgumentError] when `secret` is empty
      def construct_event(payload, signature, secret, tolerance: DEFAULT_TOLERANCE, now: nil)
        verify(payload, signature, secret, tolerance: tolerance, now: now)
        begin
          # As text, invalid bytes replaced, the way the API's other clients decode it.
          event = JSON.parse(bytes(payload).force_encoding(Encoding::UTF_8).scrub)
        rescue JSON::ParserError, EncodingError
          raise Error, "The webhook body is not JSON."
        end
        unless event.is_a?(Hash) && event["id"].is_a?(String) && event["type"].is_a?(String)
          raise Error, "The webhook body is not a FlightByte event."
        end

        WebhookEvent.from_response(event)
      end

      # Signs `payload` the way the API does and returns the
      # `x-flightbyte-signature` header value. Useful for testing your receiver.
      #
      # @param payload [String]
      # @param secret [String]
      # @param timestamp [Time, Numeric, nil] the signing time, as a Time or unix seconds; now by default
      # @return [String]
      # @raise [ArgumentError] when `secret` is empty
      def sign(payload, secret, timestamp: nil)
        check_secret(secret)
        seconds = unix(timestamp || Time.now).to_s
        "t=#{seconds},v1=#{hmac(secret, seconds, bytes(payload))}"
      end

      # @api private
      # Raises ArgumentError for an empty or blank secret.
      def check_secret(secret)
        return if secret.is_a?(String) && !secret.strip.empty?

        raise ArgumentError,
              "flightbyte: the webhook signing secret is empty. Anyone can sign with an empty key; " \
              "set the subscription's secret."
      end

      private

      # Splits `t=<seconds>,v1=<hex>[,v1=<hex>...]`.
      def parse_signature(header)
        # As bytes, so a header that is not valid text cannot raise anything else.
        header = header.to_s.b
        raise WebhookSignatureError, "The signature header is missing." if header.strip.empty?

        timestamp = nil
        signatures = []
        header.split(",").each do |part|
          key, separator, value = part.partition("=")
          next if separator.empty? || key.strip.empty?

          case key.strip
          when "t" then timestamp = value.strip
          when "v1" then signatures << value.strip.downcase
          end
        end
        unless timestamp&.match?(/\A\d{1,15}\z/)
          raise WebhookSignatureError, "The signature header has no valid timestamp."
        end
        raise WebhookSignatureError, "The signature header has no v1 signature." if signatures.empty?

        [timestamp, signatures]
      end

      def hmac(secret, timestamp, body)
        OpenSSL::HMAC.hexdigest("SHA256", secret.b, "#{timestamp}.".b + body)
      end

      def bytes(payload)
        unless payload.respond_to?(:to_str)
          raise TypeError, "flightbyte: the webhook payload must be the raw body as a String, got #{payload.class}."
        end

        payload.to_str.b
      end

      def unix(time)
        case time
        when Time then time.to_i
        when Numeric then time.floor
        else raise ArgumentError, "flightbyte: expected a Time or unix seconds, got #{time.inspect}."
        end
      end
    end
  end
end
