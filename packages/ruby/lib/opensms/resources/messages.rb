# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +messages+ resource: send, list, inspect and cancel SMS. Accessed as
    # +client.messages+.
    class Messages < Base
      SEND_FIELDS = %i[to text sender_id traffic_type scheduled_at callback_url metadata].freeze
      LIST_FIELDS = %i[limit cursor status to country date_from date_to].freeze

      # Send one SMS. POST /v1/messages -> 201 Message.
      #
      # @param params [Hash] :to (E.164, required), :text (required), :sender_id,
      #   :traffic_type, :scheduled_at (Time or RFC 3339), :callback_url, :metadata
      # @param idempotency_key [String, nil] generated when omitted
      # @return [Hash] Message
      def send(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), SEND_FIELDS, required: %i[to text], times: %i[scheduled_at])
        @transport.request(:post, "/v1/messages", body: body, idempotency_key: idem(idempotency_key))
      end

      # List messages, newest first. GET /v1/messages -> Page<Message>.
      #
      # @param params [Hash] :limit (1..100), :cursor, :status, :to, :country,
      #   :date_from, :date_to
      # @return [Opensms::Page]
      def list(params = nil, **kwargs)
        http_page("/v1/messages", Models.build(merge(params, kwargs), LIST_FIELDS, times: %i[date_from date_to]))
      end

      # GET /v1/messages/{id} -> Message.
      # @return [Hash]
      def get(id)
        http_get(path("/v1/messages", id!(id)))
      end

      # Delivery attempts for a message. GET /v1/messages/{id}/attempts.
      # @return [Array<Hash>]
      def attempts(id)
        http_get(path("/v1/messages", id!(id), :attempts))
      end

      # Cancel a queued or scheduled message. Never auto-retried.
      # POST /v1/messages/{id}/cancel -> Message.
      # @return [Hash]
      def cancel(id)
        @transport.request(:post, path("/v1/messages", id!(id), :cancel))
      end
    end
  end
end
