# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +sandbox+ resource: the rendered text of sandbox sends, including
    # OTP codes. Accessed as +client.sandbox+.
    class Sandbox < Base
      # GET /v1/sandbox/messages -> Page<SandboxMessage>.
      def list_messages(params = nil, **kwargs)
        http_page("/v1/sandbox/messages", Models.build(merge(params, kwargs), %i[limit cursor]))
      end
    end
  end
end
