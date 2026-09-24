# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +otp+ resource: send and verify one-time passcodes. Accessed as
    # +client.otp+.
    class Otp < Base
      # Send a code. POST /v1/otp/send -> 201 { otp_id: }.
      #
      # @param params [Hash] :to (required), :sender_id, :template (must contain
      #   "{{code}}"), :length (4..10), :ttl_seconds (30..86400)
      # @return [Hash] { otp_id: }
      def send(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[to sender_id template length ttl_seconds], required: %i[to])
        @transport.request(:post, "/v1/otp/send", body: body, idempotency_key: idem(idempotency_key))
      end

      # Check a code. A wrong code returns { valid: false } and burns an
      # attempt, so this call is never auto-retried.
      # POST /v1/otp/verify -> { valid:, attempts_left: }.
      #
      # @param params [Hash] :otp_id, :code
      # @return [Hash]
      def verify(params = nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[otp_id code], required: %i[otp_id code])
        @transport.request(:post, "/v1/otp/verify", body: body)
      end
    end
  end
end
