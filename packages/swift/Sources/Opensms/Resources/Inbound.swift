import Foundation

/// The `inbound` resource. Accessed as `opensms.inbound`.
public final class Inbound {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<InboundMessage> {
        try await http.request("GET", "/v1/inbound", query: params.query)
    }

    /// Reply to an inbound message (live keys only). Returns the sent ``Message``.
    public func reply(_ id: String, text: String, idempotencyKey: String? = nil) async throws -> Message {
        try await http.request("POST", "/v1/inbound/\(try idSeg(id))/reply", body: .json([("text", .string(text))]), idempotencyKey: idempotency(idempotencyKey))
    }
}
