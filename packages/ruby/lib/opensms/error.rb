# frozen_string_literal: true

require "json"

module Opensms
  # Raised for every non-2xx API response, for transport failures that survive
  # all retries (status 0), and for webhook signature failures (status 0, code
  # "invalid_signature" or "expired_signature").
  #
  # Fields map the RFC 9457 problem+json body the API returns. Most OpenSMS
  # errors carry no +code+, so branch on {#status} and show {#detail}.
  # Insufficient scope is 401 on messages and otp, but 403 everywhere else.
  class Error < StandardError
    # @return [Integer] HTTP status (0 when there was no response)
    attr_reader :status
    # @return [String, nil] problem +type+ ("about:blank" or a problems URI)
    attr_reader :type
    # @return [String, nil] problem +title+ ("Bad Request", ...)
    attr_reader :title
    # @return [String, nil] problem +detail+, human readable
    attr_reader :detail
    # @return [String, nil] optional machine code ("invalid_message_id", ...)
    attr_reader :code
    # @return [String, nil] problem +trace_id+
    attr_reader :trace_id
    # @return [Hash{Symbol=>Array<String>}, nil] field validation errors
    attr_reader :errors
    # @return [String, nil] the X-Request-ID response header
    attr_reader :request_id
    # @return [Numeric, nil] Retry-After in seconds
    attr_reader :retry_after
    # @return [Object, nil] raw decoded body (symbol keys), or the raw text if not JSON
    attr_reader :body

    # rubocop:disable Metrics/ParameterLists
    def initialize(status:, message: nil, type: nil, title: nil, detail: nil, code: nil, trace_id: nil,
                   errors: nil, request_id: nil, retry_after: nil, body: nil)
      @status = status
      @type = type
      @title = title
      @detail = detail
      @code = code
      @trace_id = trace_id
      @errors = errors
      @request_id = request_id
      @retry_after = retry_after
      @body = body
      super(message || detail || title || "OpenSMS request failed with status #{status}")
    end
    # rubocop:enable Metrics/ParameterLists

    # Build an error from an HTTP response.
    #
    # @param status [Integer]
    # @param headers [Hash{String=>String}] lower-cased header names
    # @param raw [String, nil] response body text
    # @param retry_after [Numeric, nil]
    # @return [Opensms::Error]
    def self.from_response(status, headers, raw, retry_after: nil)
      parsed = nil
      if raw && !raw.strip.empty?
        begin
          parsed = JSON.parse(raw, symbolize_names: true)
        rescue JSON::ParserError
          parsed = nil
        end
      end
      problem = parsed.is_a?(Hash) ? parsed : {}
      str = ->(v) { v.is_a?(String) ? v : nil }
      new(
        status: status,
        type: str.call(problem[:type]),
        title: str.call(problem[:title]),
        detail: str.call(problem[:detail]),
        code: str.call(problem[:code]),
        trace_id: str.call(problem[:trace_id]),
        errors: problem[:errors].is_a?(Hash) ? problem[:errors] : nil,
        request_id: headers["x-request-id"],
        retry_after: retry_after,
        body: parsed.nil? ? raw : parsed
      )
    end
  end
end
