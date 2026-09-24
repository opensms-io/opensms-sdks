# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +inbound+ resource: messages received on your numbers. Accessed as
    # +client.inbound+.
    class Inbound < Base
      # GET /v1/inbound -> Page<InboundMessage>.
      def list(params = nil, **kwargs)
        http_page("/v1/inbound", Models.build(merge(params, kwargs), %i[limit cursor]))
      end

      # Reply to an inbound message (live keys only).
      # POST /v1/inbound/{id}/reply -> 201 Message.
      #
      # @param params [Hash] :text (required)
      def reply(id, params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[text], required: %i[text])
        @transport.request(:post, path("/v1/inbound", id!(id), :reply), body: body,
                                                                        idempotency_key: idem(idempotency_key))
      end
    end
  end
end
