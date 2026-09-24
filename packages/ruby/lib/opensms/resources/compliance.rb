# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +compliance+ resource: per-country rules and content rules.
    # Accessed as +client.compliance+.
    class Compliance < Base
      # GET /v1/compliance/countries -> Array<CountryRules>.
      def list_countries
        http_get("/v1/compliance/countries")
      end

      # GET /v1/compliance/countries/{iso2} -> CountryRules.
      def get_country(iso2)
        http_get(path("/v1/compliance/countries", id!(iso2, "iso2")))
      end

      # GET /v1/content-rules -> Array<ContentRule>.
      def list_content_rules
        http_get("/v1/content-rules")
      end
    end
  end
end
