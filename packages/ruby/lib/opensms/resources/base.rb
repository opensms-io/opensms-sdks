# frozen_string_literal: true

require "securerandom"
require "uri"

require_relative "../models"

module Opensms
  # Resource groups hanging off {Opensms::Client}. Each resource is thin: build
  # the path, query and body, call the transport, decode the model.
  module Resources
    # Shared plumbing for resources. Not part of the public API.
    class Base
      # @param transport [Opensms::Transport]
      def initialize(transport)
        @transport = transport
      end

      private

      # Build a path from literal segments and escaped values:
      # path("/v1/messages", id, "attempts").
      def path(prefix, *segments)
        ([prefix] + segments.map { |s| s.is_a?(Symbol) ? s.to_s : escape(s) }).join("/")
      end

      # Escape a path segment ("a/b" -> "a%2Fb", space -> "%20").
      def escape(value)
        URI.encode_www_form_component(value.to_s).gsub("+", "%20")
      end

      # Validate that an id argument is present.
      def id!(value, name = "id")
        raise ArgumentError, "Opensms: `#{name}` is required." if value.nil? || value.to_s.strip.empty?

        value
      end

      # Idempotency-Key for methods marked req/opt: the caller's key or a new
      # UUIDv4, generated once per call and reused on every retry.
      def idem(key)
        key.nil? ? SecureRandom.uuid : key.to_s
      end

      # Merge a positional Hash with keyword arguments.
      def merge(params, kwargs)
        Models.symbolize(params || {}).merge(kwargs)
      end

      def http_get(p, query = nil)
        @transport.request(:get, p, query: query)
      end

      def http_page(p, query = nil)
        Page.from(http_get(p, query))
      end

      def http_delete(p, idempotency_key: nil)
        @transport.request(:delete, p, idempotency_key: idempotency_key)
        nil
      end
    end
  end
end
