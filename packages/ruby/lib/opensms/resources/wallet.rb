# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +wallet+ resource: balances, ledger and top-ups. Accessed as
    # +client.wallet+.
    class Wallet < Base
      # GET /v1/wallet -> the +data+ array of balances.
      # @return [Array<Hash>] [{ id:, currency:, balance:, reserved:, environment: }]
      def balances
        unwrap(http_get("/v1/wallet"))
      end

      # Ledger entries, newest first. Pages with +before+ (the smallest id
      # already seen) instead of cursors; stop when fewer than +limit+ rows
      # come back. GET /v1/wallet/ledger.
      #
      # @param params [Hash] :limit (1..200), :before
      # @return [Array<Hash>] LedgerEntry list
      def ledger(params = nil, **kwargs)
        unwrap(http_get("/v1/wallet/ledger", Models.build(merge(params, kwargs), %i[limit before])))
      end

      # Start a payment-provider top-up (live keys only).
      # POST /v1/wallet/topups -> 201 { id:, reference:, authorization_url:, ... }.
      #
      # @param params [Hash] :amount (decimal string), :currency, :channel
      #   (card|mobile_money|bank_transfer), :email
      def create_topup(params = nil, idempotency_key: nil, **kwargs)
        fields = %i[amount currency channel email]
        body = Models.build(merge(params, kwargs), fields, required: fields)
        @transport.request(:post, "/v1/wallet/topups", body: body, idempotency_key: idem(idempotency_key))
      end

      private

      def unwrap(body)
        body.is_a?(Hash) ? (body[:data] || []) : body
      end
    end
  end
end
