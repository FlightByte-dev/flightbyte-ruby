<p align="center">
  <a href="https://flightbyte.dev">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
      <img src="assets/logo-light.svg" alt="FlightByte" width="340">
    </picture>
  </a>
</p>

<h3 align="center">FlightByte for Ruby</h3>

<p align="center">
  The official Ruby client for the FlightByte flight status API.<br>
  Look flights up, watch them with signed webhooks and verify every delivery,<br>
  from a Rails app, a background job or a script.
</p>

<p align="center">
  <a href="https://rubygems.org/gems/flightbyte"><img src="https://img.shields.io/gem/v/flightbyte?style=flat-square&color=EF6A1A&label=gem" alt="gem version"></a>
  <img src="https://img.shields.io/badge/Ruby-3.1%2B-121212?style=flat-square&logo=ruby&logoColor=white" alt="Ruby 3.1+">
  <img src="https://img.shields.io/badge/dependencies-none-EF6A1A?style=flat-square" alt="No dependencies">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-121212?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://flightbyte.dev/docs"><b>Docs</b></a> ·
  <a href="https://app.flightbyte.dev/signup?utm_source=rubygems&utm_medium=readme&utm_campaign=ruby-sdk"><b>Get a free key</b></a> ·
  <a href="https://flightbyte.dev/docs/reference"><b>API reference</b></a> ·
  <a href="https://flightbyte.dev/docs/webhooks"><b>Webhook docs</b></a> ·
  <a href="https://t.me/flightbyte"><b>Support</b></a>
</p>

---

## Quick start

1. Get a free API key at [app.flightbyte.dev/signup](https://app.flightbyte.dev/signup?utm_source=rubygems&utm_medium=readme&utm_campaign=ruby-sdk).
2. Add the gem:

   | | Command |
   | --- | --- |
   | **Bundler** | `bundle add flightbyte` |
   | **RubyGems** | `gem install flightbyte` |

3. Look a flight up:

   ```ruby
   require "flightbyte"

   client = FlightByte::Client.new(api_key: ENV.fetch("FLIGHTBYTE_API_KEY"))

   flight = client.flights.get(
     carrier: "TK",
     flight_number: "1848",
     date: "2026-09-08" # local departure date at the origin
   )

   puts flight.status.label            # Scheduled
   puts flight.departure.gate          # A11
   puts flight.departure.delay_minutes # 15
   ```

Every field reads as a snake_case method, `flight["departure"]["delayMinutes"]` reads it by the API's own key, and `flight.to_h` is the JSON exactly as received. `date:` takes a `Date` too, and `FlightByte.format_date(time)` gives the `YYYY-MM-DD` the API expects, from a `Time` already in the origin airport's offset. To try it from a terminal, run the example in this repository:

```bash
git clone https://github.com/FlightByte-dev/flightbyte-ruby.git && cd flightbyte-ruby
FLIGHTBYTE_API_KEY=frk_live_... ruby -Ilib examples/lookup.rb TK 1 2026-11-15
```

```text
TK1:2026-11-15@IST-JFK  IST → JFK
Status     Scheduled (scheduled)
Departure  2026-11-15T15:20:00.000 +03, gate D15
Arrival    2026-11-15T18:20:00.000 EST, baggage -
Quota      23 of 30 left this minute
```

## What you can do

| You want to | You call |
| --- | --- |
| *Show a passenger their gate and delay* | `client.flights.get(...)` returns the live snapshot: phase, gate, terminal, baggage belt, scheduled, estimated and actual times, delay, aircraft and codeshares. |
| *Look up TK1 tomorrow, which flies two legs* | Pass `origin: "IST"`. Without it the snapshot lists every leg in `alternates`, and a subscription refuses to guess: the `BadRequestError` carries the `legs` to choose from. |
| *Be told when anything changes* | `client.subscriptions.create(...)` starts the watch and returns the signing secret, shown once. |
| *Find out why webhooks stopped arriving* | `client.subscriptions.get(id)` and `deliveries(id)` show the status and the HTTP code and error of every recent attempt. |
| *Trust a webhook on your server* | `FlightByte::Webhook::RackApp.new(secret) { \|event\| ... }` verifies the signature against the raw body, decodes the event and calls you. |

## API

**Flights**: read-only.

| Method | What it does |
| --- | --- |
| `flights.get` | Live status of one flight leg, and every leg the number flies that day.<br><sub>`GET /v1/flights/{carrier}/{flightNumber}/{date}`</sub> |
| `flights.timeline` | The airline's own change history for a leg, newest first.<br><sub>`GET /v1/flights/{carrier}/{flightNumber}/{date}/timeline`</sub> |

**Subscriptions**

| Method | What it does | Access |
| --- | --- | --- |
| `subscriptions.create` | Watch a flight and get a signed webhook for every change. Counts as a watched flight on your plan; pass `idempotency_key:` so a retry never counts twice.<br><sub>`POST /v1/subscriptions`</sub> | writes |
| `subscriptions.list` | One page of your subscriptions, filtered by status, carrier, number or date.<br><sub>`GET /v1/subscriptions`</sub> | read-only |
| `subscriptions.list_all` | Every matching subscription, fetched page by page as you iterate; without a block it is a lazy `Enumerator`.<br><sub>`GET /v1/subscriptions`</sub> | read-only |
| `subscriptions.get` | One subscription with its status and delivery counters.<br><sub>`GET /v1/subscriptions/{id}`</sub> | read-only |
| `subscriptions.update` | Change the webhook URL, event filter, delay threshold, headers or metadata.<br><sub>`PATCH /v1/subscriptions/{id}`</sub> | writes |
| `subscriptions.pause` | Stop polling and deliveries without losing anything.<br><sub>`POST /v1/subscriptions/{id}/pause`</sub> | writes |
| `subscriptions.resume` | Resume a paused or auto-suspended subscription.<br><sub>`POST /v1/subscriptions/{id}/resume`</sub> | writes |
| `subscriptions.delete` | Delete a subscription for good.<br><sub>`DELETE /v1/subscriptions/{id}`</sub> | **destructive** |
| `subscriptions.send_test` | Send a signed `subscription.test` webhook to the subscription's URL.<br><sub>`POST /v1/subscriptions/{id}/test`</sub> | writes |
| `subscriptions.deliveries` | Recent delivery attempts with HTTP status and errors.<br><sub>`GET /v1/subscriptions/{id}/deliveries`</sub> | read-only |
| `subscriptions.events` | Recent events with the exact payloads that were sent.<br><sub>`GET /v1/subscriptions/{id}/events`</sub> | read-only |
| `subscriptions.secret` | Reveal the signing secret again.<br><sub>`GET /v1/subscriptions/{id}/secret`</sub> | read-only |
| `subscriptions.rotate_secret` | Generate a new signing secret. Previous signatures stop validating.<br><sub>`POST /v1/subscriptions/{id}/secret/rotate`</sub> | writes |

**Countries**: read-only.

| Method | What it does |
| --- | --- |
| `countries.list` | Every country with its name in any language, emoji and flag URLs.<br><sub>`GET /v1/countries`</sub> |
| `countries.get` | One country by its ISO 3166-1 alpha-2 code.<br><sub>`GET /v1/countries/{code}`</sub> |
| `countries.flag_url` | The URL of a country's SVG flag, 4:3 or square. Needs no key, so it can go straight into an `<img>`.<br><sub>`GET /v1/flags/{code}.svg`</sub> |

Every method takes a `timeout:` of its own. Parameters are keywords named after the API's own, in snake_case (`carrier:`, `flight_number:`, `date:`, `origin:`, `webhook_url:`, …), and responses come back exactly as the API sent them, as frozen objects: timestamps are ISO 8601 strings, phases and statuses are strings, and no field is renamed or dropped. Each shape has its class, such as `FlightByte::FlightSnapshot` or `FlightByte::Subscription`, and they match patterns too: `in { status: { phase: "landed" } }`. The full snapshot is documented under [Flights](https://flightbyte.dev/docs/flights).

## Watch a flight

```ruby
created = client.subscriptions.create(
  carrier: "TK",
  flight_number: "1848",
  date: "2026-09-08",
  webhook_url: "https://api.example.com/hooks/flights",
  events: %w[departure.gate.changed delay.increased flight.departed],
  metadata: { bookingId: "BK-1042" },
  idempotency_key: "BK-1042" # safe to retry
)

# Shown in full only now: store it where your webhook receiver can read it.
signing_secret = created.secret
```

FlightByte only delivers to public HTTPS addresses. To receive on your machine, expose the port with a tunnel (`cloudflared tunnel --url http://localhost:3000` or `ngrok http 3000`) and use that URL. `subscriptions.send_test(id)` sends a signed `subscription.test` whenever you want to see the path work.

## Receive webhooks

A receiver has to do four things, in this order: verify the signature against the **raw** body, deduplicate on the event id, answer `2xx` before doing the work, and branch on the event type.

`FlightByte::Webhook::RackApp` does the first and answers for you: `401` for a bad signature, `400` for a body that is not an event, `500` when your block raises (so FlightByte retries) and `200` otherwise, plus `405` to anything but a `POST` and `413` to a body over 1 MiB. What your block raises goes to `warn`, or to the `on_error:` option. An empty secret raises an `ArgumentError` right away, because anyone can sign with an empty key: an unset environment variable fails at boot instead of accepting forged events. It is a plain Rack app that needs no Rack gem, so it mounts in every Ruby web framework:

```ruby
receiver = FlightByte::Webhook::RackApp.new(ENV.fetch("FLIGHTBYTE_WEBHOOK_SECRET")) do |event|
  # A retry carries the same id: answer it, but don't handle it twice.
  next unless mark_handled(event.id)

  # Answer first: FlightByte treats a delivery as failed after 10 seconds.
  FlightEventJob.perform_later(event.to_h)
end
```

<details>
<summary><b>Rails, Sinatra, Roda and a bare config.ru</b></summary>

<br>

```ruby
# Build the receiver once, at boot: in Rails, an initializer that sets
# FLIGHTBYTE_RECEIVER = FlightByte::Webhook::RackApp.new(...) { |event| ... }

# Rails: config/routes.rb
mount FLIGHTBYTE_RECEIVER, at: "/hooks/flightbyte"

# Sinatra, Hanami or any app built with Rack::Builder: config.ru
map("/hooks/flightbyte") { run receiver }
run MyApp

# Roda
route do |r|
  r.on("hooks", "flightbyte") { r.run receiver }
end
```

</details>

In a Rails controller, read the body with `request.raw_post`, not `params`: the signature covers the bytes as sent, and JSON parsed and serialised again no longer matches.

```ruby
class FlightbyteWebhooksController < ActionController::API
  def create
    event = FlightByte::Webhook.construct_event(
      request.raw_post,
      request.headers[FlightByte::Webhook::SIGNATURE_HEADER],
      ENV.fetch("FLIGHTBYTE_WEBHOOK_SECRET")
    )
  rescue FlightByte::WebhookSignatureError
    head :unauthorized
  rescue FlightByte::Error
    head :bad_request
  else
    FlightEventJob.perform_later(event.to_h)
    head :ok
  end
end

class FlightEventJob < ApplicationJob
  def perform(payload)
    event = FlightByte::WebhookEvent.new(payload)
    case event.type
    when "flight.updated"
      event.changes.each { |change| logger.info("#{event.flight_key} #{change.type}: #{change.message}") }
    when "subscription.completed"
      logger.info("#{event.flight_key} finished")
    end
  end
end
```

In a Sinatra route, the raw body is `request.body.read` and the header is `request.env[FlightByte::Webhook::SIGNATURE_ENV_KEY]`. A receiver with no framework, for any Rack server, is in [examples/webhook.ru](examples/webhook.ru).

<details>
<summary><b>How the signature works</b></summary>

<br>

```text
x-flightbyte-signature: t=1789305971,v1=5f1c9a...e3b2
v1 = HMAC-SHA256(secret, "<t>." + <raw body>)
```

`FlightByte::Webhook.verify` computes the HMAC over the body you received, not over JSON you decoded and encoded again, compares it in constant time with `OpenSSL.fixed_length_secure_compare`, accepts any of several `v1` values, and rejects a `t` more than five minutes from now. `Webhook.sign` produces the same header, for testing your receiver. The test suite checks both against signatures made by the API's own signer, and fuzzes the header parser.

The reasons behind each step are in [Verifying webhook signatures](https://flightbyte.dev/guides/verifying-webhook-signatures), and reference receivers in Node.js, Python and Go are in [flightbyte-webhook-examples](https://github.com/FlightByte-dev/flightbyte-webhook-examples).

</details>

## Errors

Every failed request raises a subclass of `FlightByte::Error`, so you `rescue` the ones you can handle and let the rest through.

| Error | Status | When, and what to do |
| --- | --- | --- |
| `BadRequestError` | `400` | Invalid input; `messages` has one line per field. For a number that flies twice, `legs` lists them: pass one's `origin`. |
| `AuthenticationError` | `401` | Missing, invalid, revoked or expired API key. |
| `PaymentRequiredError` | `402` | No watched flights left. `code` says why: `watched_flight_limit`, `overage_cap_reached` (see `resets_at`) or `credits_exhausted` (see `balance` and `expires_at`). |
| `PermissionDeniedError` | `403` | The account is suspended, or a token lacks the scope (`code`). |
| `NotFoundError` | `404` | The flight did not operate that day, or no such subscription. |
| `RateLimitError` | `429` | A minute, day or month quota is used up. Wait `retry_after` seconds. |
| `UpstreamError` | `502` | The flight data provider failed. Retry shortly. It is also a `ServerError`. |
| `ServerError`, `UnexpectedStatusError` | other | Anything else. `request_id` is what support asks for. |
| `ConnectionError` | none | No response at all: refused connection, DNS, TLS or a dropped socket, or `timed_out?` when the timeout ran out. The original exception is its `cause`. |

```ruby
begin
  client.subscriptions.create(**params)
rescue FlightByte::BadRequestError => e
  raise if e.legs.empty?

  puts "Pick a leg: #{e.legs.map(&:origin).join(", ")}"
rescue FlightByte::PaymentRequiredError => e
  puts "No watched flights left (#{e.code}) until #{e.resets_at}"
rescue FlightByte::RateLimitError => e
  sleep(e.retry_after || 5)
  retry
end
```

Arguments that cannot make a valid request, such as an empty id or a blank API key, raise an `ArgumentError` before anything is sent. Every status is explained in the [errors docs](https://flightbyte.dev/docs/errors).

## Built for Ruby apps

- **One client, many threads.** A `FlightByte::Client` is safe to share between Puma threads and Sidekiq workers; create it once, in an initializer for example. Responses are frozen, so they can be cached and handed between threads. CI runs every Ruby from 3.1 to 4.0.
- **No dependencies.** Only the standard library: `net/http`, `openssl` and `json`. Nothing to audit but this gem.
- **Your key stays on your server.** An API key or a signing secret shipped inside a browser or mobile app can be pulled out of it by anyone who has the app. Flag images are the exception: `countries.flag_url` needs no key. On the server, `inspect` never shows the key and shows a signing secret masked, so neither lands in your logs.
- **Your key stays with the API.** The client follows a redirect only for a read, and only on the API's own origin (scheme, host and port), so a misdirected answer cannot carry the key elsewhere and a write is never sent twice.
- **New API values don't break old code.** A phase, status or change type added after this release is still a plain string, and a field added after it reads as a method like the others. The tests check every method, parameter and model against the API's OpenAPI document, so a field the API adds shows up as a failing test here first, not as a missing method in your code.
- **Zero stays apart from unknown.** A field the API left out or sent as `null` reads as `nil`, so a delay of `0` and no delay reading are different things, and `key?` tells the two apart. A misspelt field raises `NoMethodError` instead of passing for a missing value.
- **Errors say what to do next.** A number that flies twice comes back with its legs, a `429` with how long to wait, a `402` with the reason and when the allowance resets.
- **Quotas are visible.** `client.last_rate_limit` holds the minute, day and month windows from the latest response's `X-RateLimit-*` headers.

## Configuration

```ruby
client = FlightByte::Client.new(
  api_key: ENV.fetch("FLIGHTBYTE_API_KEY"),
  base_url: "http://localhost:3000/v1",
  timeout: 10,
  user_agent: "my-app/1.2"
)
```

| Option | Default | Meaning |
| --- | --- | --- |
| `api_key` | required | Your API key, sent as `x-api-key`. |
| `base_url` | `https://api.flightbyte.dev/v1` | API base URL, e.g. `http://localhost:3000/v1` for a local API. |
| `timeout` | `30` | Seconds each request may take, connecting, redirects and response body included. `0` disables it; a call's own `timeout:` overrides it. |
| `user_agent` | none | Put in front of `flightbyte-ruby/<version>` in the `user-agent` header. |

Requests go through `Net::HTTP`, so the usual `HTTPS_PROXY`, `HTTP_PROXY` and `NO_PROXY` environment variables apply.

## Development

```bash
bundle install
bundle exec rake                  # RuboCop, the signature check and the tests
bundle exec rake sync_openapi     # refresh spec/openapi.json, then run the tests against it
node tool/webhook_vectors.mjs
```

The tests never touch the real API and need no key. They cover every method's request mapping, the error class for each status, redirects and timeouts against real local servers, the models against fixtures shaped like the API's JSON and against the API's OpenAPI document, the Rack receiver with `Rack::Lint`, and webhook verification against signatures made with Node's `createHmac` exactly as the API signs them. CI runs them on Ruby 3.1, 3.2, 3.3, 3.4 and 4.0, and builds and installs the gem.

How to add a field, an enum value or an endpoint is in [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues by email, as [SECURITY.md](SECURITY.md) explains, never in a public issue.

<details>
<summary><b>Project layout</b></summary>

```text
lib/
  flightbyte.rb                  entry point, format_date and the helpers
  flightbyte/client.rb           FlightByte::Client and its options
  flightbyte/transport.rb        requests, headers, timeouts, redirects, error mapping
  flightbyte/resources/          flights, subscriptions, countries
  flightbyte/object.rb           FlightByte::Object, the read-only base of every response
  flightbyte/models.rb           a class for each of the API's shapes
  flightbyte/values.rb           the API's value lists
  flightbyte/errors.rb           FlightByte::Error and its subclasses
  flightbyte/webhook.rb          Webhook.verify, construct_event and sign
  flightbyte/webhook/rack_app.rb Webhook::RackApp, the Rack receiver
  flightbyte/rate_limit.rb       X-RateLimit-* headers
sig/flightbyte.rbs               RBS type signatures
spec/openapi.json                the API document the tests check against
test/fixtures/                   API-shaped JSON and signed webhook vectors
examples/                        a lookup from the terminal and a Rack receiver
tool/sync_openapi.rb             refreshes spec/openapi.json
tool/webhook_vectors.mjs         regenerates the signed vectors with Node, as the API signs
tool/release_notes.sh            a version's CHANGELOG.md section, for the GitHub release
```

</details>

<details>
<summary><b>Releasing</b></summary>

1. Set `VERSION` in `lib/flightbyte/version.rb`; the gemspec reads it.
2. Give the version its own `## <version>` section in `CHANGELOG.md`; a test fails without it.
3. Push a tag such as `v1.0.1`.

The release workflow checks that the tag, `FlightByte::VERSION` and the gemspec agree and that the changelog has the section, runs every check, publishes to RubyGems with trusted publishing unless that version is already there, and creates the GitHub release from the changelog section. Run it by hand from the Actions tab to rehearse: it builds the gem and publishes nothing.

</details>

## License

[MIT](LICENSE)

<br>

<p align="center">
  <a href="https://flightbyte.dev"><img src="assets/icon.svg" alt="FlightByte" width="36"></a>
  <br>
  <sub><b>FlightByte</b> · Flight intelligence, byte by byte · <a href="https://flightbyte.dev">flightbyte.dev</a></sub>
</p>
