# frozen_string_literal: true

require_relative "base"
require_relative "../webhook"

module Opensms
  module Resources
    # The +webhooks+ resource: endpoints, deliveries, replays and signature
    # verification. Accessed as +client.webhooks+.
    class Webhooks < Base
      # GET /v1/webhooks -> Page<Endpoint>.
      def list(params = nil, **kwargs)
        http_page("/v1/webhooks", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # POST /v1/webhooks -> 201 Endpoint. The response carries +secret+
      # (whsec_...) exactly once: store it.
      #
      # @param params [Hash] :url (https, required), :events (required), :enabled
      def create(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[url events enabled], required: %i[url events])
        @transport.request(:post, "/v1/webhooks", body: body, idempotency_key: idem(idempotency_key))
      end

      # GET /v1/webhooks/{id} -> Endpoint (no secret).
      def get(id)
        http_get(path("/v1/webhooks", id!(id)))
      end

      # Full replacement. PUT /v1/webhooks/{id} -> Endpoint.
      #
      # @param params [Hash] :url, :events, :enabled (all required)
      def update(id, params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[url events enabled], required: %i[url events enabled])
        @transport.request(:put, path("/v1/webhooks", id!(id)), body: body, idempotency_key: idem(idempotency_key))
      end

      # DELETE /v1/webhooks/{id} -> 204.
      # @return [nil]
      def delete(id, idempotency_key: nil)
        http_delete(path("/v1/webhooks", id!(id)), idempotency_key: idem(idempotency_key))
      end

      # Queue a webhook.test delivery. POST /v1/webhooks/{id}/test -> 202 { status: }.
      def test(id, idempotency_key: nil)
        @transport.request(:post, path("/v1/webhooks", id!(id), :test), idempotency_key: idem(idempotency_key))
      end

      # GET /v1/webhooks/{id}/deliveries -> Page<Delivery>.
      def list_deliveries(id, params = nil, **kwargs)
        http_page(path("/v1/webhooks", id!(id), :deliveries), Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # Replay a delivery.
      # POST /v1/webhooks/{id}/deliveries/{delivery_id}/replay -> 202 { status: }.
      #
      # @param params [Hash] :generation (from the delivery), :reason (5..1000 chars)
      def replay_delivery(id, delivery_id, params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[generation reason], required: %i[generation reason])
        @transport.request(:post, path("/v1/webhooks", id!(id), :deliveries, id!(delivery_id, "delivery_id"), :replay),
                           body: body, idempotency_key: idem(idempotency_key))
      end

      # See {Opensms::Webhook.verify_signature}.
      # @return [Boolean]
      def verify_signature(payload, header, secret, tolerance_seconds: Webhook::DEFAULT_TOLERANCE, now: nil)
        Webhook.verify_signature(payload, header, secret, tolerance_seconds: tolerance_seconds, now: now)
      end

      # See {Opensms::Webhook.construct_event}.
      # @return [Opensms::WebhookEvent]
      def construct_event(payload, header, secret, tolerance_seconds: Webhook::DEFAULT_TOLERANCE, now: nil)
        Webhook.construct_event(payload, header, secret, tolerance_seconds: tolerance_seconds, now: now)
      end
    end
  end
end
