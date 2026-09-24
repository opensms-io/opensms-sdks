import Foundation

/// Parameters for ``Batches/create(_:idempotencyKey:)``.
public struct CreateBatchParams {
    public var items: [BatchItemInput]
    /// Drop duplicate destinations. Server default `true`.
    public var dedupe: Bool?

    public init(items: [BatchItemInput], dedupe: Bool? = nil) {
        self.items = items
        self.dedupe = dedupe
    }
}

/// Parameters for ``Batches/listItems(_:_:)``.
public struct ListBatchItemsParams: CursorParams {
    public var status: String?
    public var limit: Int?
    public var cursor: String?

    public init(status: String? = nil, limit: Int? = nil, cursor: String? = nil) {
        self.status = status
        self.limit = limit
        self.cursor = cursor
    }
}

/// The `batches` resource. Accessed as `opensms.batches`.
public final class Batches {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    /// Create a batch in `ready`. Nothing is sent until ``start(_:idempotencyKey:)``.
    public func create(_ params: CreateBatchParams, idempotencyKey: String? = nil) async throws -> Batch {
        let body = RequestBody.json([
            ("items", .array(params.items.map { $0.json })),
            ("dedupe", params.dedupe.json)
        ])
        return try await http.request("POST", "/v1/messages/batch", body: body, idempotencyKey: idempotency(idempotencyKey))
    }

    /// Create a batch from CSV text (header row `to,text[,sender_id,...]`), posted as `text/csv`.
    public func createFromCsv(_ csv: String, dedupe: Bool? = nil, idempotencyKey: String? = nil) async throws -> Batch {
        try await createFromCsv(Data(csv.utf8), dedupe: dedupe, idempotencyKey: idempotencyKey)
    }

    /// Create a batch from CSV bytes, posted as `text/csv`.
    public func createFromCsv(_ csv: Data, dedupe: Bool? = nil, idempotencyKey: String? = nil) async throws -> Batch {
        try await http.request(
            "POST", "/v1/messages/batch",
            query: [("dedupe", dedupe.q)],
            body: .raw(csv, contentType: "text/csv"),
            idempotencyKey: idempotency(idempotencyKey)
        )
    }

    public func get(_ id: String) async throws -> Batch {
        try await http.request("GET", "/v1/batches/\(try idSeg(id))")
    }

    /// Per-row validation report.
    public func validation(_ id: String) async throws -> BatchValidationReport {
        try await http.request("GET", "/v1/batches/\(try idSeg(id))/validation")
    }

    public func start(_ id: String, idempotencyKey: String? = nil) async throws -> Batch {
        try await http.request("POST", "/v1/batches/\(try idSeg(id))/start", idempotencyKey: idempotency(idempotencyKey))
    }

    public func stop(_ id: String, idempotencyKey: String? = nil) async throws -> BatchStopResult {
        try await http.request("POST", "/v1/batches/\(try idSeg(id))/stop", idempotencyKey: idempotency(idempotencyKey))
    }

    /// Messages created by the batch (slimmer than a full ``Message``).
    public func listItems(_ id: String, _ params: ListBatchItemsParams = ListBatchItemsParams()) async throws -> Page<Message> {
        try await http.request("GET", "/v1/batches/\(try idSeg(id))/items", query: [
            ("status", params.status), ("limit", params.limit.q), ("cursor", params.cursor)
        ])
    }
}
