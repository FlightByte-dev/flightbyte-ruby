# Security policy

This gem verifies webhook signatures and carries API keys, so a flaw in it can let a forged webhook through or expose a key. Reports are welcome and taken seriously.

## Supported versions

| Version | Supported |
| --- | --- |
| 1.0.x | Yes |

Fixes land in the latest release. Upgrade to it before reporting, if you can.

## Reporting a vulnerability

**Do not open a public issue.** Email [support@flightbyte.dev](mailto:support@flightbyte.dev) with the subject `Security: flightbyte-ruby`, and include:

- what an attacker can do, and under which conditions
- the gem version, and the output of `ruby --version`
- the smallest code or request that reproduces it

Never put a live API key or a webhook signing secret in a report. Use a test key, or one you revoke right after.

A maintainer answers by email, confirms the issue, and agrees a disclosure date with you once a fix is released. Please give us a reasonable time to fix it before you disclose it anywhere.

## In scope

- `FlightByte::Webhook.verify`, `valid?`, `construct_event`, `sign` and `Webhook::RackApp`: anything that accepts a payload the API did not sign, a replayed one, or leaks timing information about the secret.
- The client: anything that sends the API key somewhere other than the configured base URL, or logs it.

A vulnerability in the FlightByte API itself goes to the same address.
