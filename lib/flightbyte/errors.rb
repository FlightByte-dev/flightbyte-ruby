# frozen_string_literal: true

require "json"

module FlightByte
  # Base class of every error this gem raises. Invalid arguments raise
  # `ArgumentError` instead, before anything is sent.
  class Error < StandardError; end

  # A request got no HTTP response: a refused connection, a DNS failure, a TLS
  # failure, a dropped socket, or the timeout ran out. The original exception
  # is in `cause`.
  class ConnectionError < Error
    # @api private
    def initialize(message, timed_out: false)
      super(message)
      @timed_out = timed_out
    end

    # Whether the client's own timeout ran out.
    def timed_out?
      @timed_out
    end
  end

  # The API answered with a non-2xx status. The readers mirror the API's error
  # body. Rescue the subclass you can handle:
  #
  #   begin
  #     client.flights.get(carrier: "TK", flight_number: "1", date: "2026-09-08")
  #   rescue FlightByte::NotFoundError
  #     puts "No such flight that day"
  #   rescue FlightByte::RateLimitError => e
  #     sleep(e.retry_after || 5)
  #     retry
  #   end
  class APIError < Error
    # @return [Integer] The HTTP status.
    attr_reader :status
    # @return [Array<String>] Every message the API sent. Validation errors send one per field.
    attr_reader :messages
    # @return [Hash{String => Object}] The decoded error body; empty when it was not a JSON object.
    attr_reader :body
    # @return [String] The body exactly as received.
    attr_reader :raw_body
    # @return [Hash{String => String}] The response headers, with lower-case names.
    attr_reader :headers

    # @api private
    # Builds the subclass for `status`.
    def self.from(status, reason, raw_body, headers)
      error_class_for(status).new(status, reason, raw_body, headers)
    end

    # @api private
    def self.error_class_for(status)
      case status
      when 400 then BadRequestError
      when 401 then AuthenticationError
      when 402 then PaymentRequiredError
      when 403 then PermissionDeniedError
      when 404 then NotFoundError
      when 429 then RateLimitError
      when 502 then UpstreamError
      when 500..599 then ServerError
      else UnexpectedStatusError
      end
    end

    # @api private
    def initialize(status, reason, raw_body, headers)
      @status = status
      @raw_body = raw_body.to_s.dup.freeze
      @headers = headers.dup.freeze
      @body = decode(@raw_body).freeze
      @messages = read_messages(@body).freeze
      super(build_message(reason.to_s.strip))
    end

    # A machine-readable reason, when the API sends one, for example
    # `watched_flight_limit` or `account_suspended`.
    #
    # @return [String, nil]
    def code
      string_field("code")
    end

    # Identifies the request; quote it when contacting support.
    #
    # @return [String, nil]
    def request_id
      string_field("requestId") || headers["x-request-id"]
    end

    private

    def build_message(reason)
      # HTTP/2 and some proxies send no reason phrase; the API's own fills in.
      phrase = reason.empty? ? string_field("error").to_s : reason
      label = [status, phrase].reject { |part| part.to_s.empty? }.join(" ")
      message = messages.empty? ? label : "#{label}: #{messages.join("; ")}"
      message += " (request #{request_id})" if request_id
      message
    end

    def decode(raw)
      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError, EncodingError
      {}
    end

    def read_messages(body)
      case (message = body["message"])
      when String then [message]
      when Array then message.map(&:to_s)
      else []
      end
    end

    def string_field(key)
      value = body[key]
      value.is_a?(String) ? value : nil
    end

    def number_field(key)
      value = body[key]
      value.is_a?(Numeric) && value.finite? ? value : nil
    end
  end

  # 400: the request was invalid. When a flight number flies several legs that
  # day and no `origin:` chose one, {#legs} lists them.
  class BadRequestError < APIError
    # The legs to choose from; pass one's `origin` or `flight_id` and try again.
    #
    # @return [Array<AmbiguousLeg>]
    def legs
      legs = body["legs"]
      return [] unless legs.is_a?(Array)

      legs.grep(Hash).map { |leg| AmbiguousLeg.new(leg) }
    end
  end

  # 401: the API key is missing, invalid, revoked or expired.
  class AuthenticationError < APIError; end

  # 402: no watched flights are left. {#code} says why:
  # `watched_flight_limit` (the plan's cap), `overage_cap_reached` (the
  # account's overage cap) or `credits_exhausted` (prepaid credits used up).
  class PaymentRequiredError < APIError
    # Watched flights the usage period allows. Not with `credits_exhausted`.
    # @return [Numeric, nil]
    def limit = number_field("limit")

    # Watched flights created this usage period. Not with `credits_exhausted`.
    # @return [Numeric, nil]
    def used = number_field("used")

    # When the usage period, and so the count, resets, ISO 8601.
    # @return [String, nil]
    def resets_at = string_field("resetsAt")

    # The overage cap in US cents; only with `overage_cap_reached`.
    # @return [Numeric, nil]
    def cap_cents = number_field("capCents")

    # Prepaid credits left; only with `credits_exhausted`.
    # @return [Numeric, nil]
    def balance = number_field("balance")

    # When the credits expire or expired, ISO 8601; only with `credits_exhausted`.
    # @return [String, nil]
    def expires_at = string_field("expiresAt")
  end

  # 403: the account is suspended (`code` `account_suspended`) or a token
  # lacks the scope (`code` `insufficient_scope`).
  class PermissionDeniedError < APIError; end

  # 404: the flight did not operate that day, or no such subscription.
  class NotFoundError < APIError; end

  # 429: a minute, day or month quota is used up.
  class RateLimitError < APIError
    # The window that ran out: `minute`, `day` or `month`.
    #
    # @return [String, nil]
    def window
      string_field("window")
    end

    # How many seconds to wait before retrying, from the body's
    # `retryAfterSeconds` or the `Retry-After` header.
    #
    # @return [Numeric, nil]
    def retry_after
      from_body = number_field("retryAfterSeconds")
      return from_body if from_body

      header = headers["retry-after"].to_s.strip
      header.match?(/\A\d+\z/) ? Integer(header, 10) : nil
    end
  end

  # 5xx: the API failed. {#request_id} is what support asks for.
  class ServerError < APIError; end

  # 502: the upstream flight data provider failed. Safe to retry after a short
  # wait. It is also a {ServerError}.
  class UpstreamError < ServerError; end

  # Any other non-2xx status, including a redirect this client does not
  # follow: one to another origin, or one for a request other than GET or
  # HEAD. The target is in {#location}.
  class UnexpectedStatusError < APIError
    # Where a 3xx pointed, when it did.
    #
    # @return [String, nil]
    def location
      headers["location"]
    end
  end

  # The webhook signature did not verify.
  class WebhookSignatureError < Error; end
end
