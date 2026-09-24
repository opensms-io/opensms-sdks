# frozen_string_literal: true

require "date"
require "time"

module Opensms
  # One page of a cursor-paginated list: +items+ plus +next_cursor+ (nil on
  # the last page). Items are Hashes with the API's snake_case field names as
  # symbol keys, for example +page.items.first[:traffic_type]+.
  #
  # Page is Enumerable over the items of this page only; use
  # {Opensms::Client#paginate} to walk every page.
  class Page
    include Enumerable

    # @return [Array<Hash>]
    attr_reader :items
    # @return [String, nil]
    attr_reader :next_cursor

    # @param items [Array<Hash>]
    # @param next_cursor [String, nil]
    def initialize(items, next_cursor)
      @items = items || []
      @next_cursor = next_cursor
    end

    # Build a Page from a decoded +{items, next_cursor}+ body.
    #
    # @param body [Hash, nil]
    # @return [Opensms::Page]
    def self.from(body)
      body ||= {}
      new(body[:items], body[:next_cursor])
    end

    def each(&block)
      @items.each(&block)
    end

    # @return [Hash] the page as a Hash (+{items:, next_cursor:}+)
    def to_h
      { items: @items, next_cursor: @next_cursor }
    end
  end

  # A verified webhook delivery envelope, returned by
  # {Opensms::Webhook.construct_event}. Wire fields: id, type, workspace_id,
  # environment, created_at, data.
  WebhookEvent = Struct.new(:id, :type, :workspace_id, :environment, :created_at, :data, keyword_init: true) do
    # @param hash [Hash] decoded envelope with symbol keys
    # @return [Opensms::WebhookEvent]
    def self.from(hash)
      new(
        id: hash[:id],
        type: hash[:type],
        workspace_id: hash[:workspace_id],
        environment: hash[:environment],
        created_at: hash[:created_at],
        data: hash[:data]
      )
    end
  end

  # Request-side model mapping. Response models are plain Hashes (symbol keys,
  # wire names, money kept as decimal strings, timestamps kept as RFC 3339
  # strings, unknown fields preserved). Wire names are already snake_case, so
  # Ruby names are the wire names; this module is the one place that decides
  # which fields a request may carry and how values are serialized.
  module Models
    module_function

    # Select the allowed keys from +params+ (String or Symbol keys), raise on
    # unknown or missing required keys, drop nils and serialize time values.
    #
    # @param params [Hash]
    # @param allowed [Array<Symbol>]
    # @param required [Array<Symbol>]
    # @param times [Array<Symbol>] keys whose values are serialized as RFC 3339
    # @return [Hash]
    def build(params, allowed, required: [], times: [])
      params = symbolize(params || {})
      unknown = params.keys - allowed
      raise ArgumentError, "Opensms: unknown parameter(s): #{unknown.join(', ')}" unless unknown.empty?

      missing = required.select { |k| params[k].nil? }
      raise ArgumentError, "Opensms: missing required parameter(s): #{missing.join(', ')}" unless missing.empty?

      params.each_with_object({}) do |(k, v), out|
        next if v.nil?

        out[k] = times.include?(k) ? time(v) : v
      end
    end

    # Serialize a Time/DateTime as RFC 3339 UTC, a Date as YYYY-MM-DD, and
    # pass strings through.
    #
    # @param value [Time, DateTime, Date, String]
    # @return [String]
    def time(value)
      case value
      when DateTime then value.new_offset(0).iso8601
      when Time then value.getutc.iso8601
      when Date then value.iso8601
      else value.to_s
      end
    end

    # Shallow-symbolize the keys of a Hash.
    def symbolize(hash)
      raise ArgumentError, "Opensms: parameters must be a Hash" unless hash.is_a?(Hash)

      hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
    end
  end
end
