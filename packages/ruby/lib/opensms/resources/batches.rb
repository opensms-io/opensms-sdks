# frozen_string_literal: true

require "securerandom"

require_relative "base"

module Opensms
  module Resources
    # The +batches+ resource: bulk sends that are validated first and started
    # explicitly. Accessed as +client.batches+.
    class Batches < Base
      ITEM_FIELDS = %i[to text sender_id traffic_type callback_url metadata].freeze
      ITEMS_QUERY = %i[status limit cursor].freeze

      # Create a batch from items. POST /v1/messages/batch -> 202 Batch
      # (status "ready"; nothing is sent until {#start}).
      #
      # @param params [Hash] :items (Array of {to:, text:, sender_id:, ...}), :dedupe
      # @param idempotency_key [String, nil]
      # @return [Hash] Batch
      def create(params = nil, idempotency_key: nil, **kwargs)
        body = Models.build(merge(params, kwargs), %i[items dedupe], required: %i[items])
        body[:items] = Array(body[:items]).map { |item| Models.build(item, ITEM_FIELDS) }
        @transport.request(:post, "/v1/messages/batch", body: body, idempotency_key: idem(idempotency_key))
      end

      # Create a batch from CSV text (header row "to,text[,sender_id,...]").
      # Sent as text/csv. With +dedupe: false+ the CSV is sent as a
      # multipart/form-data upload instead, because that is the only form in
      # which the API accepts a dedupe flag next to CSV.
      #
      # @param csv [String]
      # @param dedupe [Boolean, nil] default true on the server
      # @param idempotency_key [String, nil]
      # @return [Hash] Batch
      def create_from_csv(csv, dedupe: nil, idempotency_key: nil)
        raise ArgumentError, "Opensms: `csv` is required." if csv.nil? || csv.to_s.empty?

        key = idem(idempotency_key)
        if dedupe == false
          boundary = "OpensmsBoundary#{SecureRandom.hex(12)}"
          return @transport.request(:post, "/v1/messages/batch",
                                    raw_body: multipart(boundary, csv.to_s),
                                    content_type: "multipart/form-data; boundary=#{boundary}",
                                    idempotency_key: key)
        end
        @transport.request(:post, "/v1/messages/batch", raw_body: csv.to_s, content_type: "text/csv",
                                                        idempotency_key: key)
      end

      # GET /v1/batches/{id} -> Batch.
      def get(id)
        http_get(path("/v1/batches", id!(id)))
      end

      # Per-row validation report. GET /v1/batches/{id}/validation.
      # @return [Hash] { rows:, total:, valid:, invalid:, duplicates:, suppressed: }
      def validation(id)
        http_get(path("/v1/batches", id!(id), :validation))
      end

      # Start a ready batch. POST /v1/batches/{id}/start -> Batch.
      def start(id, idempotency_key: nil)
        @transport.request(:post, path("/v1/batches", id!(id), :start), idempotency_key: idem(idempotency_key))
      end

      # Stop a batch. POST /v1/batches/{id}/stop -> { id:, status: "stopped", cancelled: }.
      def stop(id, idempotency_key: nil)
        @transport.request(:post, path("/v1/batches", id!(id), :stop), idempotency_key: idem(idempotency_key))
      end

      # Messages created by a batch. GET /v1/batches/{id}/items -> Page<BatchItem>.
      #
      # @param params [Hash] :status, :limit, :cursor
      # @return [Opensms::Page]
      def list_items(id, params = nil, **kwargs)
        http_page(path("/v1/batches", id!(id), :items), Models.build(merge(params, kwargs), ITEMS_QUERY))
      end

      private

      def multipart(boundary, csv)
        [
          "--#{boundary}\r\n",
          %(Content-Disposition: form-data; name="dedupe"\r\n\r\n),
          "false\r\n",
          "--#{boundary}\r\n",
          %(Content-Disposition: form-data; name="file"; filename="batch.csv"\r\n),
          "Content-Type: text/csv\r\n\r\n",
          csv.b,
          "\r\n--#{boundary}--\r\n"
        ].map(&:b).join
      end
    end
  end
end
