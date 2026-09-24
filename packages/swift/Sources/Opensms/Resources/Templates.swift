import Foundation

/// The `templates` resource. Accessed as `opensms.templates`.
public final class Templates {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<Template> {
        try await http.request("GET", "/v1/templates", query: params.query)
    }

    /// Create a template. `body` may use `{{name}}` placeholders.
    public func create(name: String, body: String, trafficType: String? = nil, idempotencyKey: String? = nil) async throws -> Template {
        let payload = RequestBody.json([("name", .string(name)), ("body", .string(body)), ("traffic_type", trafficType.json)])
        return try await http.request("POST", "/v1/templates", body: payload, idempotencyKey: idempotency(idempotencyKey))
    }

    public func get(_ id: String) async throws -> Template {
        try await http.request("GET", "/v1/templates/\(try idSeg(id))")
    }

    public func update(_ id: String, name: String? = nil, body: String? = nil, trafficType: String? = nil) async throws -> Template {
        let payload = RequestBody.json([("name", name.json), ("body", body.json), ("traffic_type", trafficType.json)])
        return try await http.request("PATCH", "/v1/templates/\(try idSeg(id))", body: payload)
    }

    public func delete(_ id: String) async throws {
        try await http.requestVoid("DELETE", "/v1/templates/\(try idSeg(id))")
    }
}
