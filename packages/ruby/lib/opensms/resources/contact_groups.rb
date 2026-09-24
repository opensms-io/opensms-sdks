# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +contact_groups+ resource. Accessed as +client.contact_groups+.
    class ContactGroups < Base
      FIELDS = %i[name contact_ids].freeze
      SEND_FIELDS = %i[text template_id variables sender_id traffic_type callback_url].freeze

      # GET /v1/contact-groups -> Page<Group>.
      # @param params [Hash] :limit, :cursor
      def list(params = nil, **kwargs)
        http_page("/v1/contact-groups", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # POST /v1/contact-groups -> 201 Group.
      # @param params [Hash] :name (required), :contact_ids
      def create(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), FIELDS, required: %i[name])
        @transport.request(:post, "/v1/contact-groups", body: body, idempotency_key: idem(idempotency_key))
      end

      # GET /v1/contact-groups/{id} -> Group.
      def get(id)
        http_get(path("/v1/contact-groups", id!(id)))
      end

      # PATCH /v1/contact-groups/{id} -> Group.
      # @param params [Hash] :name, :contact_ids
      def update(id, params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), FIELDS)
        @transport.request(:patch, path("/v1/contact-groups", id!(id)), body: body)
      end

      # DELETE /v1/contact-groups/{id} -> 204.
      # @return [nil]
      def delete(id)
        http_delete(path("/v1/contact-groups", id!(id)))
      end

      # Send to every contact in the group. POST /v1/contact-groups/{id}/send
      # -> Batch (already "running").
      #
      # @param params [Hash] :text or :template_id, :variables, :sender_id,
      #   :traffic_type, :callback_url
      def send(id, params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), SEND_FIELDS)
        @transport.request(:post, path("/v1/contact-groups", id!(id), :send), body: body,
                                                                             idempotency_key: idem(idempotency_key))
      end
    end
  end
end
