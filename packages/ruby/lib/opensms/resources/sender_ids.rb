# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +sender_ids+ resource: registered sender IDs, availability checks,
    # fee quotes, documents and drafts. Accessed as +client.sender_ids+.
    class SenderIds < Base
      CREATE_FIELDS = %i[value kind countries use_case sample_message documents draft_id draft_version quote_id].freeze
      UPDATE_FIELDS = %i[use_case countries documents sample_message].freeze
      DRAFT_FIELDS = %i[source value kind countries use_case sample_message documents].freeze
      DRAFT_UPDATE_FIELDS = %i[version value kind countries use_case sample_message documents].freeze

      # GET /v1/sender-ids -> Page<SenderId>.
      def list(params = nil, **kwargs)
        http_page("/v1/sender-ids", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # GET /v1/sender-ids/{id} -> SenderId.
      def get(id)
        http_get(path("/v1/sender-ids", id!(id)))
      end

      # Register a sender ID. May charge fees, so it is never auto-retried.
      # POST /v1/sender-ids -> 201 SenderId.
      #
      # @param params [Hash] :value, :kind, :countries, :documents (required),
      #   :use_case, :sample_message, :draft_id, :draft_version, :quote_id
      def create(params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), CREATE_FIELDS, required: %i[value kind countries documents])
        @transport.request(:post, "/v1/sender-ids", body: body)
      end

      # Amend a sender ID. PATCH /v1/sender-ids/{id} -> SenderId.
      # @param params [Hash] :use_case, :countries, :documents (required), :sample_message
      def update(id, params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), UPDATE_FIELDS, required: %i[use_case countries documents])
        @transport.request(:patch, path("/v1/sender-ids", id!(id)), body: body)
      end

      # DELETE /v1/sender-ids/{id} -> 204.
      # @return [nil]
      def delete(id)
        http_delete(path("/v1/sender-ids", id!(id)))
      end

      # GET /v1/sender-ids/check -> { valid:, available:, reserved:, reason: }.
      # @param params [Hash] :value (required), :country
      def check(params = nil, **kwargs)
        http_get("/v1/sender-ids/check", Models.build(merge(params, kwargs), %i[value country], required: %i[value]))
      end

      # Registration fee quote. GET /v1/sender-ids/quote?countries=KE,NG.
      # @param params [Hash] :countries (Array or comma-separated String)
      def quote(params = nil, **kwargs)
        http_get("/v1/sender-ids/quote", Models.build(merge(params, kwargs), %i[countries], required: %i[countries]))
      end

      # Uploaded registration documents. GET /v1/sender-documents.
      # @return [Array<Hash>] the +items+ of the response (no cursor)
      def list_documents
        body = http_get("/v1/sender-documents")
        body.is_a?(Hash) ? (body[:items] || []) : body
      end

      # GET /v1/sender-id-drafts -> Page<Draft>.
      def list_drafts(params = nil, **kwargs)
        http_page("/v1/sender-id-drafts", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # POST /v1/sender-id-drafts -> 201 Draft. Not auto-retried.
      def create_draft(params = nil, **kwargs)
        @transport.request(:post, "/v1/sender-id-drafts", body: Models.build(merge(params, kwargs), DRAFT_FIELDS))
      end

      # GET /v1/sender-id-drafts/{id} -> Draft.
      def get_draft(id)
        http_get(path("/v1/sender-id-drafts", id!(id)))
      end

      # PATCH /v1/sender-id-drafts/{id} -> Draft. Requires the current
      # +version+ (optimistic lock; 409 on mismatch).
      def update_draft(id, params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), DRAFT_UPDATE_FIELDS, required: %i[version])
        @transport.request(:patch, path("/v1/sender-id-drafts", id!(id)), body: body)
      end

      # DELETE /v1/sender-id-drafts/{id} -> 204.
      # @return [nil]
      def delete_draft(id)
        http_delete(path("/v1/sender-id-drafts", id!(id)))
      end
    end
  end
end
