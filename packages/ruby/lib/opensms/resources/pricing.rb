# frozen_string_literal: true

require_relative "base"

module Opensms
  module Resources
    # The +pricing+ resource. Accessed as +client.pricing+.
    class Pricing < Base
      # GET /v1/pricing -> PriceList.
      # @param params [Hash] :product (sms|lookup|number_monthly), :country (ISO2)
      def get(params = nil, **kwargs)
        http_get("/v1/pricing", Models.build(merge(params, kwargs), %i[product country]))
      end
    end
  end
end
