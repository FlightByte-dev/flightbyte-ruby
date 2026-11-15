# frozen_string_literal: true

module FlightByte
  # One quota window, from the `X-RateLimit-*` response headers.
  #
  # @!attribute [r] limit
  #   @return [Integer] Requests the window allows.
  # @!attribute [r] remaining
  #   @return [Integer] Requests left in the window.
  # @!attribute [r] reset_at
  #   @return [Time, nil] When the window resets, in UTC, or `nil` when not reported.
  RateLimitWindow = Struct.new(:limit, :remaining, :reset_at, keyword_init: true)

  # The quota state sent with a response, from {Client#last_rate_limit}. A
  # window the key has no limit on is `nil`; keys without limits get no
  # headers at all. Frozen, so it can be shared and never changes the client.
  #
  # @!attribute [r] minute
  #   @return [RateLimitWindow, nil] The per-minute window.
  # @!attribute [r] day
  #   @return [RateLimitWindow, nil] The per-day window.
  # @!attribute [r] month
  #   @return [RateLimitWindow, nil] The per-month window.
  RateLimit = Struct.new(:minute, :day, :month, keyword_init: true) do
    # @api private
    # Reads the quota headers (lower-case names), or returns `nil` when there are none.
    def self.parse(headers)
      windows = %w[minute day month].to_h { |name| [name.to_sym, parse_window(headers, name)] }
      return nil if windows.values.none?

      new(**windows).freeze
    end

    # @api private
    def self.parse_window(headers, name)
      limit = parse_integer(headers["x-ratelimit-limit-#{name}"])
      remaining = parse_integer(headers["x-ratelimit-remaining-#{name}"])
      return nil if limit.nil? || remaining.nil?

      reset = parse_integer(headers["x-ratelimit-reset-#{name}"])
      reset_at = reset && Time.at(reset).utc.freeze
      RateLimitWindow.new(limit: limit, remaining: remaining, reset_at: reset_at).freeze
    end

    # @api private
    def self.parse_integer(value)
      value = value.to_s.strip
      value.match?(/\A\d+\z/) ? Integer(value, 10) : nil
    end

    private_class_method :parse_window, :parse_integer
  end
end
