# frozen_string_literal: true

require "test_helper"

# Redirects, against real local servers: the API key is sent with every
# request, so a redirect this client followed to another origin would hand
# the key to that origin.
class RedirectTest < Minitest::Test
  include FlightByteTest::Helpers

  def redirect(location, status = 302)
    [status, { "location" => location }, ""]
  end

  def ok
    json(200, { count: 1, data: [{ code: "TR" }] })
  end

  # Same host, another port.
  def test_does_not_follow_one_to_another_origin_so_the_key_stays_home
    other = serve { ok }
    api = serve { redirect("#{other.url}/steal") }
    error = assert_raises(FlightByte::UnexpectedStatusError) { client_for(api).countries.list }

    assert_empty other.requests
    assert_equal 302, error.status
    assert_equal "#{other.url}/steal", error.location
  end

  def test_does_not_follow_one_to_another_host_name_for_the_same_address
    api = serve do |request|
      request.path == "/v1/countries" ? redirect("#{api.url.sub("127.0.0.1", "localhost")}/v1/moved") : ok
    end

    assert_raises(FlightByte::UnexpectedStatusError) { client_for(api).countries.list }
    assert_equal 1, api.requests.length
  end

  def test_follows_one_within_the_origin_key_and_all
    api = serve { |request| request.path == "/v1/countries" ? redirect("/v1/moved", 301) : ok }

    assert_equal [{ "code" => "TR" }], client_for(api).countries.list.map(&:to_h)
    assert_equal([["GET", "/v1/countries", "frk_test_key"], ["GET", "/v1/moved", "frk_test_key"]],
                 api.requests.map { |r| [r.verb, r.path, r.headers["x-api-key"]] })
  end

  def test_follows_an_absolute_location_on_the_same_origin
    api = serve { |request| request.path == "/v1/countries" ? redirect("#{api.url}/v1/moved", 308) : ok }

    assert_equal 1, client_for(api).countries.list.length
    assert_equal 2, api.requests.length
  end

  def test_does_not_follow_one_for_a_request_other_than_get_or_head
    api = serve { redirect("/v1/elsewhere", 307) }
    client = client_for(api)

    assert_raises(FlightByte::UnexpectedStatusError) { client.subscriptions.pause("sub_1") }
    assert_raises(FlightByte::UnexpectedStatusError) do
      client.subscriptions.create(carrier: "TK", flight_number: "1", date: "2026-09-08", webhook_url: "https://e/h")
    end
    assert_raises(FlightByte::UnexpectedStatusError) { client.subscriptions.delete("sub_1") }
    assert_equal %w[POST POST DELETE], api.requests.map(&:verb)
  end

  def test_gives_up_on_a_loop_after_five_hops
    api = serve { |request| redirect(request.path) }
    error = assert_raises(FlightByte::UnexpectedStatusError) { client_for(api).countries.list }

    assert_equal 302, error.status
    assert_equal 6, api.requests.length
  end

  def test_does_not_follow_one_without_a_location_or_with_a_broken_one
    api = serve { |request| request.path == "/v1/countries" ? [302, {}, ""] : redirect("http://[broken") }

    assert_raises(FlightByte::UnexpectedStatusError) { client_for(api).countries.list }
    assert_raises(FlightByte::UnexpectedStatusError) { client_for(api).countries.get("TR") }
    assert_equal 2, api.requests.length
  end

  def test_does_not_follow_https_to_http_on_the_same_host
    # A TLS test server would need a certificate the client trusts, so this
    # checks the rule itself: scheme, host and port must all match.
    transport = FlightByte::Client.new(api_key: "k").instance_variable_get(:@transport)
    same_origin = ->(from, to) { transport.send(:same_origin?, URI(from), URI(to)) }

    refute same_origin.call("https://api.test/v1/countries", "http://api.test/v1/countries")
    refute same_origin.call("https://api.test/v1/countries", "https://api.test:8443/v1/countries")
    refute same_origin.call("https://api.test/v1/countries", "https://evil.test/v1/countries")
    refute same_origin.call("https://api.test/v1/countries", "mailto:someone@api.test")
    assert same_origin.call("https://api.test/v1/countries", "https://API.test:443/v1/other")
  end
end
