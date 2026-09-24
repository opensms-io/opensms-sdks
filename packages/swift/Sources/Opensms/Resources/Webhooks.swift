import Foundation

/// The `webhooks` resource. Accessed as `opensms.webhooks`.
public final class Webhooks {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<WebhookEndpoint> {
        try await http.request("GET", "/v1/webhooks", query: params.query)
    }

    /// Create an endpoint. The response carries the signing `secret` once.
    public func create(url: String, events: [String], enabled: Bool? = nil, idempotencyKey: String? = nil) async throws -> WebhookEndpoint {
        let body = RequestBody.json([("url", .string(url)), ("events", Optional(events).json), ("enabled", enabled.json)])
        return try await http.request("POST", "/v1/webhooks", body: body, idempotencyKey: idempotency(idempotencyKey))
    }

    public func get(_ id: String) async throws -> WebhookEndpoint {
        try await http.request("GET", "/v1/webhooks/\(try idSeg(id))")
    }

    /// Full replacement (`PUT`): `url`, `events` and `enabled` are all required.
    public func update(_ id: String, url: String, events: [String], enabled: Bool, idempotencyKey: String? = nil) async throws -> WebhookEndpoint {
        let body = RequestBody.json([("url", .string(url)), ("events", Optional(events).json), ("enabled", .bool(enabled))])
        return try await http.request("PUT", "/v1/webhooks/\(try idSeg(id))", body: body, idempotencyKey: idempotency(idempotencyKey))
    }

    public func delete(_ id: String, idempotencyKey: String? = nil) async throws {
        try await http.requestVoid("DELETE", "/v1/webhooks/\(try idSeg(id))", idempotencyKey: idempotency(idempotencyKey))
    }

    /// Queue a `webhook.test` delivery.
    public func test(_ id: String, idempotencyKey: String? = nil) async throws -> StatusAck {
        try await http.request("POST", "/v1/webhooks/\(try idSeg(id))/test", idempotencyKey: idempotency(idempotencyKey))
    }

    public func listDeliveries(_ id: String, _ params: ListParams = ListParams()) async throws -> Page<WebhookDelivery> {
        try await http.request("GET", "/v1/webhooks/\(try idSeg(id))/deliveries", query: params.query)
    }

    /// Replay a delivery. `generation` comes from the delivery; `reason` is 5 to 1000 characters.
    public func replayDelivery(_ id: String, deliveryId: Int, generation: Int, reason: String, idempotencyKey: String? = nil) async throws -> StatusAck {
        let body = RequestBody.json([("generation", .int(generation)), ("reason", .string(reason))])
        return try await http.request(
            "POST", "/v1/webhooks/\(try idSeg(id))/deliveries/\(deliveryId)/replay",
            body: body, idempotencyKey: idempotency(idempotencyKey)
        )
    }

    /// See ``OpensmsWebhooks/verifySignature(payload:header:secret:toleranceSeconds:now:)``.
    public func verifySignature(
        payload: Data, header: String, secret: String,
        toleranceSeconds: TimeInterval = OpensmsWebhooks.defaultTolerance, now: Date = Date()
    ) -> Bool {
        OpensmsWebhooks.verifySignature(payload: payload, header: header, secret: secret, toleranceSeconds: toleranceSeconds, now: now)
    }

    /// See ``OpensmsWebhooks/constructEvent(payload:header:secret:toleranceSeconds:now:)``.
    public func constructEvent(
        payload: Data, header: String, secret: String,
        toleranceSeconds: TimeInterval = OpensmsWebhooks.defaultTolerance, now: Date = Date()
    ) throws -> WebhookEvent {
        try OpensmsWebhooks.constructEvent(payload: payload, header: header, secret: secret, toleranceSeconds: toleranceSeconds, now: now)
    }
}
