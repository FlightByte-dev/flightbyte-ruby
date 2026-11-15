# frozen_string_literal: true

module FlightByte
  module Webhook
    # A Rack app that receives FlightByte webhooks. It needs no Rack gem, so
    # it runs under anything that speaks Rack: Rails, Sinatra, Hanami, Roda,
    # or a bare `config.ru` on Puma.
    #
    #   # config/routes.rb
    #   mount FlightByte::Webhook::RackApp.new(ENV.fetch("FLIGHTBYTE_WEBHOOK_SECRET")) { |event|
    #     FlightEventJob.perform_later(event.to_h)
    #   }, at: "/hooks/flightbyte"
    #
    # It reads up to {MAX_BODY_BYTES}, verifies the signature, decodes the
    # event and calls the block with it and the Rack env. It answers 405 to
    # anything but POST, 413 to a larger body, 401 when the signature does not
    # verify, 400 when the body is not an event, 500 when the block raises (so
    # FlightByte retries) and 200 otherwise. Retries carry the same event id:
    # deduplicate on `event.id`.
    class RackApp
      # @param secret [String] the subscription's signing secret
      # @param tolerance [Numeric] how far the signing time may be from now, in seconds; `0` skips the check
      # @param now [Time, Numeric, nil] the time to check against instead of now; useful in tests
      # @param on_error [#call, nil] called with the error, the event and the
      #   Rack env when the block raises, after the 500 is decided. Defaults to
      #   `warn`. Whatever it raises is ignored, so the answer stays 500.
      # @yieldparam event [WebhookEvent]
      # @yieldparam env [Hash] the Rack env
      # @raise [ArgumentError] right away when `secret` is empty, so an unset
      #   environment variable fails at boot instead of accepting forged events,
      #   or when no block is given
      def initialize(secret, tolerance: DEFAULT_TOLERANCE, now: nil, on_error: nil, &handler)
        Webhook.check_secret(secret)
        raise ArgumentError, "flightbyte: RackApp needs a block to handle each event." unless handler
        unless on_error.nil? || on_error.respond_to?(:call)
          raise ArgumentError, "flightbyte: on_error must respond to call."
        end

        @secret = secret.dup.freeze
        @tolerance = tolerance
        @now = now
        @on_error = on_error || method(:report)
        @handler = handler
        freeze
      end

      # Handles one Rack request.
      #
      # @param env [Hash] the Rack env
      # @return [Array(Integer, Hash, Array<String>)]
      def call(env)
        return reply(405, "method not allowed", "allow" => "POST") unless env["REQUEST_METHOD"] == "POST"

        payload = read_body(env)
        return reply(413, "body too large") if payload.nil?

        begin
          event = Webhook.construct_event(payload, env[SIGNATURE_ENV_KEY], @secret, tolerance: @tolerance, now: @now)
        rescue WebhookSignatureError
          return reply(401, "invalid signature")
        rescue Error
          return reply(400, "invalid event")
        end

        begin
          @handler.call(event, env)
        rescue StandardError => e
          notify(e, event, env)
          return reply(500, "handler failed")
        end
        reply(200, "ok")
      end

      # Never shows the signing secret.
      def inspect
        "#<#{self.class.name}>"
      end

      private

      # The body, or nil when it is larger than MAX_BODY_BYTES.
      def read_body(env)
        declared = env["CONTENT_LENGTH"].to_s
        return nil if declared.match?(/\A\d+\z/) && declared.to_i > MAX_BODY_BYTES

        input = env["rack.input"]
        return +"" if input.nil?

        body = +"".b
        while (chunk = input.read(16 * 1024))
          body << chunk
          return nil if body.bytesize > MAX_BODY_BYTES
        end
        body
      end

      def notify(error, event, env)
        @on_error.call(error, event, env)
      rescue StandardError
        # A failing reporter must not change the answer.
        nil
      end

      def report(error, event, _env)
        warn "flightbyte: the webhook handler failed for event #{event.id} (#{event.type}): " \
             "#{error.full_message(highlight: false)}"
      end

      def reply(status, text, headers = {})
        [status, { "content-type" => "text/plain; charset=utf-8" }.merge(headers), [text]]
      end
    end
  end
end
