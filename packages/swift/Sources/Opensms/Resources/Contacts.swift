import Foundation

/// The `contacts` resource. Accessed as `opensms.contacts`.
public final class Contacts {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<Contact> {
        try await http.request("GET", "/v1/contacts", query: params.query)
    }

    public func create(e164: String, name: String? = nil, attributes: JSONObject? = nil, idempotencyKey: String? = nil) async throws -> Contact {
        let body = RequestBody.json([("e164", .string(e164)), ("name", name.json), ("attributes", attributes.json)])
        return try await http.request("POST", "/v1/contacts", body: body, idempotencyKey: idempotency(idempotencyKey))
    }

    public func get(_ id: String) async throws -> Contact {
        try await http.request("GET", "/v1/contacts/\(try idSeg(id))")
    }

    /// Partial update: only the fields you pass change.
    public func update(_ id: String, e164: String? = nil, name: String? = nil, attributes: JSONObject? = nil) async throws -> Contact {
        let body = RequestBody.json([("e164", e164.json), ("name", name.json), ("attributes", attributes.json)])
        return try await http.request("PATCH", "/v1/contacts/\(try idSeg(id))", body: body)
    }

    public func delete(_ id: String) async throws {
        try await http.requestVoid("DELETE", "/v1/contacts/\(try idSeg(id))")
    }
}
