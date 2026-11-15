# frozen_string_literal: true

module FlightByte
  # Watched flights and their webhooks. Reach it as `client.subscriptions`.
  # Every subscription is a billable watched flight.
  class Subscriptions
    # The page size {#list_all} asks for unless told otherwise: the API's largest.
    DEFAULT_PAGE_SIZE = 200

    # @api private
    def initialize(transport)
      @transport = transport
    end

    # Starts watching a flight. The API posts a signed webhook to
    # `webhook_url` each time something about it changes.
    #
    # @param carrier [String] carrier code, for example `TK`
    # @param flight_number [String, Integer] flight number, for example `1848`
    # @param date [String, Date, Time] local departure date at the origin, `YYYY-MM-DD`
    # @param webhook_url [String] where webhooks are posted; a public HTTPS URL
    # @param origin [String, nil] selects a leg, when the flight number flies several that day
    # @param destination [String, nil] narrows the leg further
    # @param flight_id [String, nil] selects a leg by its upstream id
    # @param secret [String, nil] the webhook signing secret. By default the API
    #   generates one, returned once as `secret`. Setting the same secret on
    #   every subscription lets one receiver verify them all.
    # @param events [Array<String>, nil] change types that trigger a webhook; by default every type does
    # @param delay_threshold_minutes [Integer, nil] ignore delay swings smaller than this, 1 to 240
    # @param headers [Hash{String => String}, nil] extra headers sent with every delivery
    # @param metadata [Hash{String => String}, nil] your own data, echoed back in every webhook
    # @param idempotency_key [String, nil] makes retries safe: repeating the
    #   request with the same key within 24 hours returns the original
    #   subscription with `reused` true, instead of creating and billing a
    #   second one. Sent as `Idempotency-Key`.
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [CreatedSubscription]
    # @raise [PaymentRequiredError] when no watched flights are left
    # @raise [BadRequestError] with `legs` set, when the flight number flies
    #   several legs that day and neither `origin:` nor `flight_id:` chose one
    def create(carrier:, flight_number:, date:, webhook_url:, origin: nil, destination: nil, flight_id: nil,
               secret: nil, events: nil, delay_threshold_minutes: nil, headers: nil, metadata: nil,
               idempotency_key: nil, timeout: nil)
      body = {
        "carrier" => Transport.required("carrier", carrier),
        "flightNumber" => Transport.required("flight_number", flight_number),
        "date" => Transport.date("date", date),
        "webhookUrl" => Transport.required("webhook_url", webhook_url),
        "origin" => origin,
        "destination" => destination,
        "flightId" => flight_id,
        "secret" => secret,
        "events" => events&.map(&:to_s),
        "delayThresholdMinutes" => delay_threshold_minutes,
        "headers" => headers,
        "metadata" => metadata
      }.compact
      key = idempotency_key.to_s.strip
      request_headers = key.empty? ? nil : { "idempotency-key" => key }
      created = @transport.request("POST", ["subscriptions"], body: body, headers: request_headers, timeout: timeout)
      if created.is_a?(Hash) && created["secret"].is_a?(String) && !created["secretHint"]
        created = created.merge("secretHint" => FlightByte.mask_secret(created["secret"]))
      end
      CreatedSubscription.from_response(created)
    end

    # One page of your subscriptions, newest first.
    #
    # @param status [String, nil] keeps subscriptions in this status; see {SUBSCRIPTION_STATUSES}
    # @param carrier [String, nil] keeps subscriptions for this carrier
    # @param flight_number [String, Integer, nil] keeps subscriptions for this flight number
    # @param date [String, Date, Time, nil] keeps subscriptions for this date
    # @param limit [Integer, nil] page size; the API clamps it to 1 to 200 and defaults to 25
    # @param offset [Integer, nil] the number of subscriptions to skip
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [SubscriptionPage]
    def list(status: nil, carrier: nil, flight_number: nil, date: nil, limit: nil, offset: nil, timeout: nil)
      date = FlightByte.format_date(date) if date.respond_to?(:strftime)
      query = { status: status, carrier: carrier, flightNumber: flight_number, date: date, limit: limit,
                offset: offset }
      SubscriptionPage.from_response(@transport.request("GET", ["subscriptions"], query: query, timeout: timeout))
    end

    # Every subscription matching the filters, fetched page by page as you
    # iterate. With a block it yields each one; without, it returns an
    # Enumerator, so `first(10)`, `lazy` and `each_slice` fetch only the pages
    # they need. Stop early with `break`; nothing more is fetched.
    #
    #   client.subscriptions.list_all(status: "active") do |subscription|
    #     puts subscription.flight_key
    #   end
    #
    # @param page_size [Integer] page size, 1 to 200
    # @param (see #list)
    # @yieldparam subscription [Subscription]
    # @return [Enumerator<Subscription>, nil]
    def list_all(status: nil, carrier: nil, flight_number: nil, date: nil, offset: nil,
                 page_size: DEFAULT_PAGE_SIZE, timeout: nil, &block)
      filters = { status: status, carrier: carrier, flight_number: flight_number, date: date, timeout: timeout }
      pages = Enumerator.new { |yielder| paginate(filters, offset || 0, page_size) { |item| yielder << item } }
      return pages unless block

      pages.each(&block)
      nil
    end
    alias each list_all

    # One subscription.
    #
    # @param id [String]
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [Subscription]
    # @raise [NotFoundError] when it does not exist or belongs to another key
    def get(id, timeout: nil)
      Subscription.from_response(@transport.request("GET", path(id), timeout: timeout))
    end

    # Changes a subscription. Only the fields you pass change. `headers` and
    # `metadata` replace the existing maps; the API cannot clear them, so an
    # empty map leaves them as they are.
    #
    # @param id [String]
    # @param webhook_url [String, nil] moves deliveries to another URL
    # @param events [Array<String>, nil] replaces the change type filter
    # @param delay_threshold_minutes [Integer, nil] replaces the delay threshold
    # @param headers [Hash{String => String}, nil] replaces the delivery headers
    # @param metadata [Hash{String => String}, nil] replaces the metadata
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [Subscription]
    def update(id, webhook_url: nil, events: nil, delay_threshold_minutes: nil, headers: nil, metadata: nil,
               timeout: nil)
      body = {
        "webhookUrl" => webhook_url,
        "events" => events&.map(&:to_s),
        "delayThresholdMinutes" => delay_threshold_minutes,
        "headers" => headers,
        "metadata" => metadata
      }.compact
      Subscription.from_response(@transport.request("PATCH", path(id), body: body, timeout: timeout))
    end

    # Stops watching the flight and deletes the subscription for good.
    #
    # @param id [String]
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [nil]
    def delete(id, timeout: nil)
      @transport.request("DELETE", path(id), timeout: timeout)
      nil
    end

    # Pauses polling and deliveries; {#resume} picks up where it left off.
    #
    # @param (see #get)
    # @return [Subscription]
    def pause(id, timeout: nil)
      Subscription.from_response(@transport.request("POST", path(id, "pause"), timeout: timeout))
    end

    # Resumes a paused or suspended subscription. A completed one cannot be
    # resumed and gives a {BadRequestError}.
    #
    # @param (see #get)
    # @return [Subscription]
    def resume(id, timeout: nil)
      Subscription.from_response(@transport.request("POST", path(id, "resume"), timeout: timeout))
    end

    # Sends a signed `subscription.test` webhook to the subscription's URL.
    #
    # @param (see #get)
    # @return [String] the event id
    def send_test(id, timeout: nil)
      field(@transport.request("POST", path(id, "test"), timeout: timeout), "eventId")
    end

    # The latest delivery attempts, newest first.
    #
    # @param id [String]
    # @param limit [Integer, nil] how many to return, 1 to 100; the API's default is 25
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [Array<DeliveryRecord>]
    def deliveries(id, limit: nil, timeout: nil)
      response = @transport.request("GET", path(id, "deliveries"), query: { limit: limit }, timeout: timeout)
      DeliveryRecord.list_from_response(response)
    end

    # The latest events, exactly as they were posted, newest first.
    #
    # @param (see #deliveries)
    # @return [Array<WebhookEvent>]
    def events(id, limit: nil, timeout: nil)
      response = @transport.request("GET", path(id, "events"), query: { limit: limit }, timeout: timeout)
      WebhookEvent.list_from_response(response)
    end

    # The full webhook signing secret.
    #
    # @param (see #get)
    # @return [String]
    def secret(id, timeout: nil)
      field(@transport.request("GET", path(id, "secret"), timeout: timeout), "secret")
    end

    # Replaces the webhook signing secret and returns the new one. Deliveries
    # are signed with it from now on, so update your receiver right away.
    #
    # @param (see #get)
    # @return [String]
    def rotate_secret(id, timeout: nil)
      field(@transport.request("POST", path(id, "secret", "rotate"), timeout: timeout), "secret")
    end

    # Never shows the API key.
    def inspect
      "#<#{self.class.name}>"
    end

    private

    def path(id, *rest)
      ["subscriptions", Transport.required("id", id), *rest]
    end

    def paginate(filters, offset, page_size, &block)
      loop do
        page = list(**filters, limit: page_size, offset: offset)
        items = page.data || []
        items.each(&block)
        following = (page.offset || offset) + items.length
        break if items.empty? || !page.total.is_a?(Integer) || following >= page.total

        offset = following
      end
    end

    def field(response, key)
      raise Error, "flightbyte: expected a JSON object with #{key} from the API" unless response.is_a?(Hash)

      response[key]
    end
  end
end
