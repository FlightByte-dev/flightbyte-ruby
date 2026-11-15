## 1.0.0

- First release.
- `FlightByte::Client` with `flights` (`get`, `timeline`), `subscriptions` (`create`, `list`, `list_all`, `get`, `update`, `delete`, `pause`, `resume`, `send_test`, `deliveries`, `events`, `secret`, `rotate_secret`) and `countries` (`list`, `get`, `flag_url`). Every method takes a `timeout:` of its own.
- A frozen, read-only class for every response, such as `FlightByte::FlightSnapshot` and `FlightByte::Subscription`, checked against the API's OpenAPI document: snake_case readers, `[]` with the API's own keys, pattern matching, and `to_h` with the JSON exactly as received. Fields and enum values added to the API later read as they arrive.
- `FlightByte::Error` and a subclass for each error status, including the `credits_exhausted` reason of a 402 with its `balance` and `expires_at`, and `FlightByte::ConnectionError` for every request that got no response.
- `FlightByte::Webhook.verify`, `valid?`, `construct_event` and `sign` for `x-flightbyte-signature` webhook signatures, and `FlightByte::Webhook::RackApp`, a Rack receiver that needs no Rack gem.
- An empty webhook signing secret is refused with an `ArgumentError`, by `Webhook::RackApp` as soon as it is built, since anyone can sign with an empty key. `Webhook::RackApp` reports what your block raises with `warn`, or to its `on_error:` option.
- `client.last_rate_limit` from the `X-RateLimit-*` headers, frozen.
- A redirect is followed only for a `GET` or `HEAD`, and only on the same scheme, host and port, so the API key stays with the API and a write is never replayed.
- RBS type signatures in `sig/`.
- No dependencies outside the standard library. Runs on Ruby 3.1 and later.
