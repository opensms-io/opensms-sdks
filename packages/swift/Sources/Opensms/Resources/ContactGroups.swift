import Foundation

/// Parameters for ``ContactGroups/send(_:_:idempotencyKey:)``. Pass `text` or `templateId`, not both.
public struct GroupSendParams {
    public var text: String?
    public var templateId: String?
    public var variables: [String: String]?
    public var senderId: String?
    public var trafficType: String?
    public var callbackUrl: String?

    public init(
        text: String? = nil,
        templateId: String? = nil,
        variables: [String: String]? = nil,
        senderId: String? = nil,
        trafficType: String? = nil,
        callbackUrl: String? = nil
    ) {
        self.text = text
        self.templateId = templateId
        self.variables = variables
        self.senderId = senderId
        self.trafficType = trafficType
        self.callbackUrl = callbackUrl
    }
}

/// The `contactGroups` resource. Accessed as `opensms.contactGroups`.
public final class ContactGroups {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<ContactGroup> {
        try await http.request("GET", "/v1/contact-groups", query: params.query)
    }

    public func create(name: String, contactIds: [String]? = nil, idempotencyKey: String? = nil) async throws -> ContactGroup {
        let body = RequestBody.json([("name", .string(name)), ("contact_ids", contactIds.json)])
        return try await http.request("POST", "/v1/contact-groups", body: body, idempotencyKey: idempotency(idempotencyKey))
    }

    public func get(_ id: String) async throws -> ContactGroup {
        try await http.request("GET", "/v1/contact-groups/\(try idSeg(id))")
    }

    public func update(_ id: String, name: String? = nil, contactIds: [String]? = nil) async throws -> ContactGroup {
        let body = RequestBody.json([("name", name.json), ("contact_ids", contactIds.json)])
        return try await http.request("PATCH", "/v1/contact-groups/\(try idSeg(id))", body: body)
    }

    public func delete(_ id: String) async throws {
        try await http.requestVoid("DELETE", "/v1/contact-groups/\(try idSeg(id))")
    }

    /// Send to every contact in the group. Returns a ``Batch`` already `running`.
    public func send(_ id: String, _ params: GroupSendParams, idempotencyKey: String? = nil) async throws -> Batch {
        let body = RequestBody.json([
            ("text", params.text.json),
            ("template_id", params.templateId.json),
            ("variables", params.variables.json),
            ("sender_id", params.senderId.json),
            ("traffic_type", params.trafficType.json),
            ("callback_url", params.callbackUrl.json)
        ])
        return try await http.request("POST", "/v1/contact-groups/\(try idSeg(id))/send", body: body, idempotencyKey: idempotency(idempotencyKey))
    }
}
