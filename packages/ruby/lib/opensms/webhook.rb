# frozen_string_literal: true

require "json"
require "openssl"

require_relative "error"
require_relative "models"

module Opensms
  # Webhook signature verification. Works without an API key, so a receiver
  # only needs the endpoint secret.
  #
  # The API sends +X-OpenSMS-Signature: t=<unix seconds>,v1=<hex>+ where
  # v1 = hex(HMAC-SHA256(secret, "<t>.<raw body>")). The secret is the full
  # +whsec_...+ string returned once by +webhooks.create+, used verbatim.
  #
  # @example
  #   event = Opensms::Webhook.construct_event(request.body.read,
  #                                            request.get_header("HTTP_X_OPENSMS_SIGNATURE"),
  #                                            ENV.fetch("OPENSMS_WEBHOOK_SECRET"))
  module Webhook
    HEADER = "X-OpenSMS-Signature"
    DEFAULT_TOLERANCE = 300

    module_function

    # @param payload [String] the exact raw request body
    # @param header [String, nil] the X-OpenSMS-Signature header value
    # @param secret [String] the endpoint secret (whsec_...)
    # @param tolerance_seconds [Integer] max clock skew, default 300
    # @param now [Integer, Time, nil] current time, injectable for tests
    # @return [Boolean]
    def verify_signature(payload, header, secret, tolerance_seconds: DEFAULT_TOLERANCE, now: nil)
      check(payload, header, secret, tolerance_seconds, now).nil?
    end

    # Verify the signature, then parse the body.
    #
    # @return [Opensms::WebhookEvent]
    # @raise [Opensms::Error] status 0, code "invalid_signature" or "expired_signature"
    def construct_event(payload, header, secret, tolerance_seconds: DEFAULT_TOLERANCE, now: nil)
      failure = check(payload, header, secret, tolerance_seconds, now)
      unless failure.nil?
        message = failure == "expired_signature" ? "webhook signature timestamp is outside the tolerance" : "webhook signature is invalid"
        raise Error.new(status: 0, code: failure, message: message)
      end

      begin
        data = JSON.parse(payload.to_s, symbolize_names: true)
      rescue JSON::ParserError
        raise Error.new(status: 0, code: "invalid_payload", message: "webhook payload is not valid JSON", body: payload)
      end
      WebhookEvent.from(data.is_a?(Hash) ? data : {})
    end

    # Returns nil when valid, else "invalid_signature" or "expired_signature".
    def check(payload, header, secret, tolerance, now)
      return "invalid_signature" if secret.nil? || secret.strip.empty? || header.nil? || tolerance.negative?

      parts = parse_header(header.to_s)
      return "invalid_signature" if parts.nil?

      t = parts["t"]
      return "invalid_signature" unless t.match?(/\A[+-]?\d+\z/)

      v1 = parts["v1"]
      return "invalid_signature" unless v1.match?(/\A[0-9a-fA-F]{64}\z/)

      now_s = now.nil? ? Time.now.to_i : now.to_i
      return "expired_signature" if (now_s - t.to_i).abs > tolerance

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret.b, "#{t}.".b + payload.to_s.b)
      secure_compare(expected, v1.downcase) ? nil : "invalid_signature"
    end

    # Mirror the server parser: exactly the keys t and v1, no duplicates, no
    # empty keys or values.
    def parse_header(header)
      out = {}
      header.split(",", -1).each do |part|
        key, value = part.strip.split("=", 2)
        return nil if key.nil? || key.empty? || value.nil? || value.empty?
        return nil if out.key?(key)

        out[key] = value
      end
      out.keys.sort == %w[t v1] ? out : nil
    end

    def secure_compare(a, b)
      return false unless a.bytesize == b.bytesize

      OpenSSL.fixed_length_secure_compare(a, b)
    end
  end
end
