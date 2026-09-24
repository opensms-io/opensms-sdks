# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"
require "time"
require "uri"

require_relative "version"
require_relative "error"

module Opensms
  # Default HTTP client: a thin Net::HTTP adapter. Any object that responds to
  # +call(method, url, headers, body, timeout)+ and returns
  # +[status, headers, body]+ (headers with lower-cased names, body a String or
  # nil) can replace it through +Opensms::Client.new(http_client: ...)+.
  class NetHttpClient
    METHODS = {
      get: Net::HTTP::Get,
      post: Net::HTTP::Post,
      put: Net::HTTP::Put,
      patch: Net::HTTP::Patch,
      delete: Net::HTTP::Delete
    }.freeze

    # @return [Array(Integer, Hash{String=>String}, String)]
    def call(method, url, headers, body, timeout)
      uri = URI.parse(url)
      req = METHODS.fetch(method).new(uri)
      headers.each { |k, v| req[k] = v }
      req.body = body unless body.nil?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout if http.respond_to?(:write_timeout=)
      res = http.request(req)

      out = {}
      res.each_header { |k, v| out[k.downcase] = v }
      [res.code.to_i, out, res.body]
    end
  end

  # HTTP transport: the single place that talks to the network. Owns bearer
  # authentication, headers, JSON encode/decode, Idempotency-Key reuse,
  # timeouts, retries with backoff, and turning non-2xx responses into
  # {Opensms::Error}. Resources depend on this, never on Net::HTTP directly.
  class Transport
    DEFAULT_BASE_URL = "https://opensms.io"
    USER_AGENT = "opensms-ruby/#{VERSION}"
    RETRY_STATUSES = [429, 500, 502, 503, 504].freeze
    MAX_RETRY_AFTER = 60
    KEY_PATTERN = /\Ask_(test|live)_.{13,}\z/m.freeze

    attr_reader :base_url, :environment

    # @param api_key [String] "sk_test_..." or "sk_live_..."
    # @param base_url [String]
    # @param timeout [Numeric] seconds, per attempt
    # @param max_retries [Integer] retries after the first attempt
    # @param http_client [#call] see {NetHttpClient}
    # @param sleeper [#call] receives the delay in seconds (tests inject a no-op)
    # @param random [#call] returns a Float in [0, 1) for backoff jitter
    # rubocop:disable Metrics/ParameterLists
    def initialize(api_key:, base_url: DEFAULT_BASE_URL, timeout: 30, max_retries: 2,
                   http_client: nil, sleeper: nil, random: nil)
      unless api_key.is_a?(String) && KEY_PATTERN.match?(api_key)
        raise ArgumentError,
              "Opensms: `api_key` must start with sk_test_ or sk_live_ followed by more than 12 characters."
      end
      raise ArgumentError, "Opensms: `max_retries` must be >= 0." unless max_retries.is_a?(Integer) && max_retries >= 0

      @api_key = api_key
      @environment = api_key.start_with?("sk_live_") ? "live" : "sandbox"
      @base_url = (base_url || DEFAULT_BASE_URL).to_s.sub(%r{/+\z}, "")
      @timeout = timeout
      @max_retries = max_retries
      @http_client = http_client || NetHttpClient.new
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @random = random || -> { Random.rand }
    end
    # rubocop:enable Metrics/ParameterLists

    # Perform a request and return the decoded JSON body (symbol keys), or nil
    # for 204 / empty bodies.
    #
    # @param method [Symbol] :get, :post, :put, :patch, :delete
    # @param path [String] path beginning with "/" (segments already escaped)
    # @param query [Hash, nil] nil values are dropped, arrays joined with ","
    # @param body [Hash, Array, nil] JSON body
    # @param raw_body [String, nil] raw body sent with +content_type+ instead of JSON
    # @param content_type [String, nil]
    # @param idempotency_key [String, nil] sent verbatim and reused on every retry
    # @return [Hash, Array, nil]
    # rubocop:disable Metrics/ParameterLists
    def request(method, path, query: nil, body: nil, raw_body: nil, content_type: nil, idempotency_key: nil)
      url = build_url(path, query)
      headers = base_headers
      payload = nil
      if !raw_body.nil?
        payload = raw_body
        headers["Content-Type"] = content_type || "application/octet-stream"
      elsif !body.nil?
        payload = JSON.generate(body)
        headers["Content-Type"] = "application/json"
      end
      headers["Idempotency-Key"] = idempotency_key unless idempotency_key.nil?
      can_retry = method != :post || !idempotency_key.nil?

      perform(method, url, headers, payload, can_retry)
    end
    # rubocop:enable Metrics/ParameterLists

    private

    def perform(method, url, headers, payload, can_retry)
      attempt = 0
      loop do
        attempt += 1
        retries_left = can_retry && attempt <= @max_retries
        begin
          status, res_headers, raw = @http_client.call(method, url, headers, payload, @timeout)
        rescue StandardError => e
          raise Error.new(status: 0, message: "OpenSMS request failed: #{e.class}: #{e.message}") unless retries_left

          @sleeper.call(backoff(attempt))
          next
        end

        res_headers = normalize_headers(res_headers)
        return decode(raw) if status.between?(200, 299)

        retry_after = parse_retry_after(res_headers["retry-after"])
        error = Error.from_response(status, res_headers, raw, retry_after: retry_after)
        raise error unless retries_left && RETRY_STATUSES.include?(status)
        raise error if retry_after && retry_after > MAX_RETRY_AFTER

        @sleeper.call(retry_after || backoff(attempt))
      end
    end

    def base_headers
      {
        "Authorization" => "Bearer #{@api_key}",
        "Accept" => "application/json",
        "User-Agent" => USER_AGENT
      }
    end

    def build_url(path, query)
      url = "#{@base_url}#{path}"
      return url if query.nil?

      pairs = query.each_with_object([]) do |(k, v), acc|
        next if v.nil?

        acc << [k.to_s, v.is_a?(Array) ? v.join(",") : v.to_s]
      end
      return url if pairs.empty?

      # Commas are legal in a query (RFC 3986 sub-delims); keep them literal so
      # list values read as countries=KE,NG on the wire.
      "#{url}?#{URI.encode_www_form(pairs).gsub('%2C', ',')}"
    end

    def normalize_headers(headers)
      (headers || {}).each_with_object({}) do |(k, v), acc|
        acc[k.to_s.downcase] = v.is_a?(Array) ? v.first : v
      end
    end

    def decode(raw)
      return nil if raw.nil? || raw.strip.empty?

      JSON.parse(raw, symbolize_names: true)
    rescue JSON::ParserError
      raise Error.new(status: 0, message: "OpenSMS returned a response that is not valid JSON", body: raw)
    end

    # Full-jitter exponential backoff: random(0, min(8, 0.5 * 2^(n-1))).
    def backoff(attempt)
      cap = [8.0, 0.5 * (2**(attempt - 1))].min
      @random.call * cap
    end

    # Retry-After is integer seconds or an HTTP date.
    def parse_retry_after(value)
      return nil if value.nil? || value.to_s.strip.empty?

      text = value.to_s.strip
      return text.to_i if text.match?(/\A\d+\z/)

      [Time.httpdate(text) - Time.now, 0].max.ceil
    rescue ArgumentError
      nil
    end
  end
end
