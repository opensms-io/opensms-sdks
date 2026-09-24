import Foundation

/// Parameters for ``Numbers/createRule(_:_:idempotencyKey:)`` and ``Numbers/updateRule(_:ruleId:_:)``.
public struct InboundRuleParams {
    /// `keyword|prefix|regex|any`
    public var match: String
    /// Required unless `match` is `any`.
    public var pattern: String?
    /// `webhook|auto_reply|forward_email`
    public var action: String
    /// 1 to 2048 characters.
    public var target: String
    /// 0 to 10000.
    public var position: Int?

    public init(match: String, pattern: String? = nil, action: String, target: String, position: Int? = nil) {
        self.match = match
        self.pattern = pattern
        self.action = action
        self.target = target
        self.position = position
    }

    var body: RequestBody {
        .json([
            ("match", .string(match)),
            ("pattern", pattern.json),
            ("action", .string(action)),
            ("target", .string(target)),
            ("position", position.json)
        ])
    }
}

/// The `numbers` resource. Accessed as `opensms.numbers`. Everything except
/// ``list(_:)`` and ``available(country:kind:)`` needs a live key.
public final class Numbers {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    public func list(_ params: ListParams = ListParams()) async throws -> Page<VirtualNumber> {
        try await http.request("GET", "/v1/numbers", query: params.query)
    }

    /// Numbers available to assign. `kind` is `long_code|short_code|toll_free`.
    public func available(country: String, kind: String) async throws -> [VirtualNumber] {
        try await http.request("GET", "/v1/numbers/available", query: [("country", country), ("kind", kind)])
    }

    /// Assign a number to the workspace (charges the wallet).
    public func assign(country: String, kind: String, idempotencyKey: String? = nil) async throws -> VirtualNumber {
        let body = RequestBody.json([("country", .string(country)), ("kind", .string(kind))])
        return try await http.request("POST", "/v1/numbers", body: body, idempotencyKey: idempotency(idempotencyKey))
    }

    public func release(_ id: String) async throws {
        try await http.requestVoid("DELETE", "/v1/numbers/\(try idSeg(id))")
    }

    public func listRules(_ id: String, _ params: ListParams = ListParams()) async throws -> Page<InboundRule> {
        try await http.request("GET", "/v1/numbers/\(try idSeg(id))/rules", query: params.query)
    }

    public func createRule(_ id: String, _ rule: InboundRuleParams, idempotencyKey: String? = nil) async throws -> InboundRule {
        try await http.request("POST", "/v1/numbers/\(try idSeg(id))/rules", body: rule.body, idempotencyKey: idempotency(idempotencyKey))
    }

    public func updateRule(_ id: String, ruleId: String, _ rule: InboundRuleParams) async throws -> InboundRule {
        try await http.request("PUT", "/v1/numbers/\(try idSeg(id))/rules/\(try idSeg(ruleId, "ruleId"))", body: rule.body)
    }

    public func deleteRule(_ id: String, ruleId: String) async throws {
        try await http.requestVoid("DELETE", "/v1/numbers/\(try idSeg(id))/rules/\(try idSeg(ruleId, "ruleId"))")
    }
}
