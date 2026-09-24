# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +contacts+ resource. Accessed as +client.contacts+.
    class Contacts < Base
      FIELDS = %i[e164 name attributes].freeze

      # GET /v1/contacts -> Page<Contact>.
      # @param params [Hash] :limit, :cursor
      # @return [Opensms::Page]
      def list(params = nil, **kwargs)
        http_page("/v1/contacts", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # POST /v1/contacts -> 201 Contact.
      # @param params [Hash] :e164 (required), :name, :attributes
      def create(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), FIELDS, required: %i[e164])
        @transport.request(:post, "/v1/contacts", body: body, idempotency_key: idem(idempotency_key))
      end

      # GET /v1/contacts/{id} -> Contact.
      def get(id)
        http_get(path("/v1/contacts", id!(id)))
      end

      # Partial update. PATCH /v1/contacts/{id} -> Contact.
      # @param params [Hash] :e164, :name, :attributes
      def update(id, params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), FIELDS)
        @transport.request(:patch, path("/v1/contacts", id!(id)), body: body)
      end

      # DELETE /v1/contacts/{id} -> 204.
      # @return [nil]
      def delete(id)
        http_delete(path("/v1/contacts", id!(id)))
      end
    end
  end
end
