import Foundation

/// The `lookups` resource. Accessed as `opensms.lookups`.
public final class Lookups {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    /// Look up a number's country, carrier and portability.
    public func create(to: String, idempotencyKey: String? = nil) async throws -> Lookup {
        try await http.request("POST", "/v1/lookup", body: .json([("to", .string(to))]), idempotencyKey: idempotency(idempotencyKey))
    }

    public func get(_ id: String) async throws -> Lookup {
        try await http.request("GET", "/v1/lookup/\(try idSeg(id))")
    }
}
