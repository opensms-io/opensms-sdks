# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +countries+ resource: the public country catalog. Accessed as
    # +client.countries+.
    class Countries < Base
      # GET /v1/countries -> Array<Country>.
      def list
        http_get("/v1/countries")
      end

      # GET /v1/countries/{iso2}/carriers -> Array<{ id:, name:, mcc_mnc:, prefixes: }>.
      def carriers(iso2)
        http_get(path("/v1/countries", id!(iso2, "iso2"), :carriers))
      end

      # GET /v1/countries/{iso2}/routes -> Array<Route>.
      def routes(iso2)
        http_get(path("/v1/countries", id!(iso2, "iso2"), :routes))
      end

      # GET /v1/countries/{iso2}/compliance -> CountryRules.
      def compliance(iso2)
        http_get(path("/v1/countries", id!(iso2, "iso2"), :compliance))
      end
    end
  end
end
