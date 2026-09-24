# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +templates+ resource: reusable message bodies with {{placeholders}}.
    # Accessed as +client.templates+.
    class Templates < Base
      FIELDS = %i[name body traffic_type].freeze

      # GET /v1/templates -> Page<Template>.
      def list(params = nil, **kwargs)
        http_page("/v1/templates", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # POST /v1/templates -> 201 Template.
      # @param params [Hash] :name (required), :body (required), :traffic_type
      def create(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), FIELDS, required: %i[name body])
        @transport.request(:post, "/v1/templates", body: body, idempotency_key: idem(idempotency_key))
      end

      # GET /v1/templates/{id} -> Template.
      def get(id)
        http_get(path("/v1/templates", id!(id)))
      end

      # PATCH /v1/templates/{id} -> Template.
      def update(id, params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), FIELDS)
        @transport.request(:patch, path("/v1/templates", id!(id)), body: body)
      end

      # DELETE /v1/templates/{id} -> 204.
      # @return [nil]
      def delete(id)
        http_delete(path("/v1/templates", id!(id)))
      end
    end
  end
end
