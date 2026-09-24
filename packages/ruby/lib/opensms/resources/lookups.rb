# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +lookups+ resource: number lookups (country, carrier, porting).
    # Accessed as +client.lookups+.
    class Lookups < Base
      # POST /v1/lookup -> 200 (completed) or 202 (pending) Lookup.
      #
      # @param params [Hash] :to (E.164, required)
      # @return [Hash] Lookup
      def create(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[to], required: %i[to])
        @transport.request(:post, "/v1/lookup", body: body, idempotency_key: idem(idempotency_key))
      end

      # GET /v1/lookup/{id} -> Lookup.
      def get(id)
        http_get(path("/v1/lookup", id!(id)))
      end
    end
  end
end
