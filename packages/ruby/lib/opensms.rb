# frozen_string_literal: true

require_relative "opensms/version"
require_relative "opensms/error"
require_relative "opensms/models"
require_relative "opensms/transport"
require_relative "opensms/webhook"
require_relative "opensms/client"

# Ruby SDK for the OpenSMS API (https://opensms.io).
#
# @example
#   require "opensms"
#   client = Opensms::Client.new(api_key: ENV.fetch("OPENSMS_API_KEY"))
#   client.messages.send(to: "+254700000012", text: "Hello from Ruby")
module Opensms
end
