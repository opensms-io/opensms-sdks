# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +numbers+ resource: virtual numbers and their inbound rules.
    # Everything except +list+ and +available+ needs a live key. Accessed as
    # +client.numbers+.
    class Numbers < Base
      RULE_FIELDS = %i[match pattern action target position].freeze

      # GET /v1/numbers -> Page<Number>.
      def list(params = nil, **kwargs)
        http_page("/v1/numbers", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # GET /v1/numbers/available -> Array<Number>.
      # @param params [Hash] :country, :kind
      def available(params = nil, **kwargs)
        http_get("/v1/numbers/available", Models.build(merge(params, kwargs), %i[country kind]))
      end

      # Assign (buy) a number; charges the wallet. POST /v1/numbers -> 201 Number.
      # @param params [Hash] :country (required), :kind (required)
      def assign(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[country kind], required: %i[country kind])
        @transport.request(:post, "/v1/numbers", body: body, idempotency_key: idem(idempotency_key))
      end

      # DELETE /v1/numbers/{id} -> 204.
      # @return [nil]
      def release(id)
        http_delete(path("/v1/numbers", id!(id)))
      end

      # GET /v1/numbers/{id}/rules -> Page<Rule>.
      def list_rules(id, params = nil, **kwargs)
        http_page(path("/v1/numbers", id!(id), :rules), Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # POST /v1/numbers/{id}/rules -> 201 Rule.
      # @param rule [Hash] :match, :pattern, :action, :target, :position
      def create_rule(id, rule = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(rule, kwargs), RULE_FIELDS, required: %i[match action target])
        @transport.request(:post, path("/v1/numbers", id!(id), :rules), body: body,
                                                                        idempotency_key: idem(idempotency_key))
      end

      # PUT /v1/numbers/{id}/rules/{rule_id} -> Rule.
      def update_rule(id, rule_id, rule = nil, **kwargs)
        body = Models.build(merge(rule, kwargs), RULE_FIELDS, required: %i[match action target])
        @transport.request(:put, path("/v1/numbers", id!(id), :rules, id!(rule_id, "rule_id")), body: body)
      end

      # DELETE /v1/numbers/{id}/rules/{rule_id} -> 204.
      # @return [nil]
      def delete_rule(id, rule_id)
        http_delete(path("/v1/numbers", id!(id), :rules, id!(rule_id, "rule_id")))
      end
    end
  end
end
