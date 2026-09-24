import Foundation

/// One row for ``Suppressions/import(_:)``.
public struct SuppressionInput: Equatable {
    public var e164: String
    /// `stop_keyword|manual|complaint|invalid_number`
    public var reason: String

    public init(e164: String, reason: String) {
        self.e164 = e164
        self.reason = reason
    }
}

/// The `suppressions` resource. Accessed as `opensms.suppressions`.
public final class Suppressions {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<Suppression> {
        try await http.request("GET", "/v1/compliance/suppressions", query: params.query)
    }

    /// Suppress one number. Never retried.
    public func create(e164: String, reason: String) async throws -> Suppression {
        let body = RequestBody.json([("e164", .string(e164)), ("reason", .string(reason))])
        return try await http.request("POST", "/v1/compliance/suppressions", body: body)
    }

    /// Bulk import. Never retried.
    public func `import`(_ items: [SuppressionInput]) async throws -> SuppressionImportResult {
        let list = JSONValue.array(items.map { .object(["e164": .string($0.e164), "reason": .string($0.reason)]) })
        return try await http.request("POST", "/v1/compliance/suppressions/import", body: .json([("items", list)]))
    }

    public func delete(_ id: Int) async throws {
        try await http.requestVoid("DELETE", "/v1/compliance/suppressions/\(id)")
    }
}
