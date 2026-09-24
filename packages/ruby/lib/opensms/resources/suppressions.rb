# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +suppressions+ resource: numbers that must not receive messages.
    # Accessed as +client.suppressions+.
    class Suppressions < Base
      # GET /v1/compliance/suppressions -> Page<Suppression>.
      def list(params = nil, **kwargs)
        http_page("/v1/compliance/suppressions", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # POST /v1/compliance/suppressions -> 201 Suppression. Not auto-retried.
      # @param params [Hash] :e164, :reason (stop_keyword|manual|complaint|invalid_number)
      def create(params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[e164 reason], required: %i[e164 reason])
        @transport.request(:post, "/v1/compliance/suppressions", body: body)
      end

      # Bulk add. POST /v1/compliance/suppressions/import -> 201 { created:, received: }.
      # Not auto-retried.
      #
      # @param items [Array<Hash>] each { e164:, reason: }
      def import(items)
        raise ArgumentError, "Opensms: `items` must be an Array." unless items.is_a?(Array)

        body = { items: items.map { |i| Models.build(i, %i[e164 reason], required: %i[e164 reason]) } }
        @transport.request(:post, "/v1/compliance/suppressions/import", body: body)
      end

      # DELETE /v1/compliance/suppressions/{id} -> 204.
      # @return [nil]
      def delete(id)
        http_delete(path("/v1/compliance/suppressions", id!(id)))
      end
    end
  end
end
