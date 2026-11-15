# frozen_string_literal: true

module FlightByte
  # Country names, emoji and flags. Reach it as `client.countries`.
  class Countries
    # @api private
    def initialize(transport)
      @transport = transport
    end

    # Every country, sorted by name.
    #
    # @param lang [String, nil] the language of the names, for example `tr`; the API's default is `en`
    # @param timeout [Numeric, nil] seconds for this request instead of the client's
    # @return [Array<Country>]
    def list(lang: nil, timeout: nil)
      Country.list_from_response(@transport.request("GET", ["countries"], query: { lang: lang }, timeout: timeout))
    end

    # One country by its ISO 3166-1 alpha-2 code.
    #
    # @param code [String] for example `TR`
    # @param (see #list)
    # @return [Country]
    # @raise [NotFoundError] when there is no such country
    def get(code, lang: nil, timeout: nil)
      path = ["countries", Transport.required("code", code)]
      Country.from_response(@transport.request("GET", path, query: { lang: lang }, timeout: timeout))
    end

    # The URL of a country's SVG flag: 4:3, or 1:1 with `square: true`. Flags
    # need no API key, so the URL can go straight into an `<img>`. Nothing is
    # sent.
    #
    # @param code [String] for example `TR`
    # @param square [Boolean]
    # @return [String]
    def flag_url(code, square: false)
      @transport.url(["flags", "#{Transport.required("code", code).downcase}.svg"], { shape: square ? "1x1" : nil })
    end

    # Never shows the API key.
    def inspect
      "#<#{self.class.name}>"
    end
  end
end
