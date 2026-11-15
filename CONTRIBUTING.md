# Contributing

Thanks for helping. Bug reports, fixes and docs improvements are all welcome. For a change to the public API, open an issue first so we can agree on the shape before you write it.

## Set up

Using the gem needs Ruby 3.1 or later; so does developing it.

```bash
git clone https://github.com/FlightByte-dev/flightbyte-ruby.git
cd flightbyte-ruby
bundle install
bundle exec rake test
```

The tests never touch the real API and need no key.

## Before you open a pull request

```bash
bundle exec rake    # RuboCop, the signature check and the tests
```

CI runs the tests on Ruby 3.1, 3.2, 3.3, 3.4 and 4.0, runs RuboCop and the RBS check, and builds and installs the gem. A pull request needs all of it green.

- **`lib/` uses the standard library only:** `net/http`, `openssl`, `json`, `uri` and `timeout`. The gemspec has no runtime dependencies, and `test/package_test.rb` fails if it gains one. Keep it that way unless an issue agrees otherwise.
- **The code runs on Ruby 3.1.** RuboCop targets 3.1, so newer syntax fails the lint; newer core methods do not, so check the docs of anything you reach for.
- **Everything public has a YARD comment and an RBS signature** in `sig/flightbyte.rbs`. `bundle exec rake rbs` validates the signatures.
- **Every change has a test.** Requests go to a real HTTP server on 127.0.0.1 (see `FlightByteTest::FakeServer` in `test/test_helper.rb`), never to the network.
- **Add a line to `CHANGELOG.md`** under a `## Unreleased` heading for anything a user would notice.

## How the code maps to the API

The models mirror the API's [OpenAPI document](https://flightbyte.dev/openapi.json), and `test/spec_test.rb` checks them against a copy of it in `spec/openapi.json`. Refresh that copy and see what changed:

```bash
bundle exec rake sync_openapi
bundle exec rake test
```

- **The API adds a field:** add a `field` line, with its YARD comment, to the class in `lib/flightbyte/models.rb`, and the reader to `sig/flightbyte.rbs`. The spec test fails until you do, and fails if a field has no place in the document unless it is listed, with the reason, in `UNDOCUMENTED_FIELDS`. Until then the field still reads as a method and with `[]`, which is why nothing breaks for users in the meantime.
- **The API adds an enum value** (a phase, status, change type or event type): add it to its list in `lib/flightbyte/values.rb`. Until then the value is still a valid string.
- **The API adds a parameter:** add the keyword to the method in `lib/flightbyte/resources/`. The spec test compares every method's keywords, and which are required, with the document's parameters and request bodies.
- **The API adds an error code or status:** map it in `lib/flightbyte/errors.rb` and add a case to `test/errors_test.rb`.
- **The API adds an endpoint:** add a method to the resource in `lib/flightbyte/resources/`, a line to `CALLS` in `test/spec_test.rb`, a test in `test/resources_test.rb`, a signature in `sig/flightbyte.rbs`, and a row to the README's API tables.

## Webhook signatures

`test/fixtures/webhook_vectors.json` holds signatures made with Node's `createHmac`, exactly as the API signs deliveries, so the Ruby verifier is checked against the server and not only against itself. Do not edit those files by hand. To regenerate them, for example after adding a case to the script:

```bash
node tool/webhook_vectors.mjs
```

## Commit messages

One line that says what changed and why it matters, in plain words, for example `Subscriptions can be listed by origin airport`. Add a body when the reason is not obvious from the diff.

## Releasing

Maintainers only.

1. Set `VERSION` in `lib/flightbyte/version.rb`; the gemspec reads it.
2. Rename `## Unreleased` in `CHANGELOG.md` to the new version; a test fails if the version has no section.
3. Push a tag `v<version>`, for example `v1.0.1`.

The release workflow checks that the tag, `FlightByte::VERSION` and the gemspec agree and that the changelog has the section, runs every check, publishes to RubyGems with trusted publishing unless that version is already there, and creates the GitHub release from the version's `CHANGELOG.md` section. To rehearse a release without publishing anything, run the workflow by hand from the Actions tab.

A version on RubyGems can never be pushed again, even after a yank. Fix a bad release with a new version.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
