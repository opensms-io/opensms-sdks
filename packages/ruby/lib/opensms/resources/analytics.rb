# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +analytics+ resource: delivery and spend metrics. Every method takes
    # the same optional query: :currency, :range ("30d"), or :from / :to
    # (Time, Date or string; not combined with :range), and :bucket
    # (day|hour). Accessed as +client.analytics+.
    class Analytics < Base
      QUERY = %i[currency range from to bucket].freeze

      # GET /v1/analytics/overview -> Metrics + { from:, to:, currency:, environment: }.
      def overview(params = nil, **kwargs)
        fetch("overview", params, kwargs)
      end

      # GET /v1/analytics/by-country -> Array<Metrics + { key:, name: }>.
      def by_country(params = nil, **kwargs)
        fetch("by-country", params, kwargs)
      end

      # GET /v1/analytics/by-carrier -> Array<Metrics + { key:, name: }>.
      def by_carrier(params = nil, **kwargs)
        fetch("by-carrier", params, kwargs)
      end

      # GET /v1/analytics/by-sender-id -> Array<Metrics + { key:, name: }>.
      def by_sender_id(params = nil, **kwargs)
        fetch("by-sender-id", params, kwargs)
      end

      # GET /v1/analytics/timeseries -> Array<Metrics + { bucket: }>.
      def timeseries(params = nil, **kwargs)
        fetch("timeseries", params, kwargs)
      end

      private

      def fetch(name, params, kwargs)
        http_get("/v1/analytics/#{name}", Models.build(merge(params, kwargs), QUERY, times: %i[from to]))
      end
    end
  end
end
