# frozen_string_literal: true

require_relative "transport"
require_relative "models"
require_relative "pagination"
Dir[File.join(__dir__, "resources", "*.rb")].sort.each { |f| require f }

module Opensms
  # OpenSMS API client. Composes the HTTP transport with the resource groups.
  #
  # @example
  #   client = Opensms::Client.new(api_key: ENV.fetch("OPENSMS_API_KEY"))
  #   msg = client.messages.send(to: "+254700000012", text: "Hello")
  #   puts msg[:id]
  class Client
    include Pagination

    RESOURCES = {
      messages: Resources::Messages,
      batches: Resources::Batches,
      otp: Resources::Otp,
      lookups: Resources::Lookups,
      contacts: Resources::Contacts,
      contact_groups: Resources::ContactGroups,
      templates: Resources::Templates,
      webhooks: Resources::Webhooks,
      inbound: Resources::Inbound,
      numbers: Resources::Numbers,
      sender_ids: Resources::SenderIds,
      suppressions: Resources::Suppressions,
      compliance: Resources::Compliance,
      wallet: Resources::Wallet,
      pricing: Resources::Pricing,
      analytics: Resources::Analytics,
      sandbox: Resources::Sandbox,
      countries: Resources::Countries
    }.freeze

    RESOURCES.each_key { |name| attr_reader name }

    # @return [String] "sandbox" for sk_test_ keys, "live" for sk_live_ keys
    attr_reader :environment
    # @return [String] the base URL with trailing slashes removed
    attr_reader :base_url

    # @param api_key [String] required; "sk_test_..." or "sk_live_..."
    # @param base_url [String] default "https://api.opensms.io"
    # @param timeout [Numeric] per-attempt timeout in seconds, default 30
    # @param max_retries [Integer] retries after the first attempt, default 2
    # @param http_client [#call, nil] replaces the Net::HTTP adapter (see {Opensms::NetHttpClient})
    # @param sleeper [#call, nil] called with the retry delay in seconds
    # @raise [ArgumentError] for a malformed key (no network call is made)
    # rubocop:disable Metrics/ParameterLists
    def initialize(api_key:, base_url: Transport::DEFAULT_BASE_URL, timeout: 30, max_retries: 2,
                   http_client: nil, sleeper: nil, random: nil)
      transport = Transport.new(api_key: api_key, base_url: base_url, timeout: timeout, max_retries: max_retries,
                                http_client: http_client, sleeper: sleeper, random: random)
      @environment = transport.environment
      @base_url = transport.base_url
      RESOURCES.each { |name, klass| instance_variable_set(:"@#{name}", klass.new(transport)) }
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
