import Foundation

/// Parameters for ``Otp/send(_:idempotencyKey:)``.
public struct SendOtpParams {
    public var to: String
    public var senderId: String?
    /// Must contain `{{code}}`.
    public var template: String?
    /// 4 to 10, default 6.
    public var length: Int?
    /// 30 to 86400, default 600.
    public var ttlSeconds: Int?

    public init(to: String, senderId: String? = nil, template: String? = nil, length: Int? = nil, ttlSeconds: Int? = nil) {
        self.to = to
        self.senderId = senderId
        self.template = template
        self.length = length
        self.ttlSeconds = ttlSeconds
    }
}

/// The `otp` resource. Accessed as `opensms.otp`.
public final class Otp {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    /// Generate and send a one-time code.
    public func send(_ params: SendOtpParams, idempotencyKey: String? = nil) async throws -> OtpSendResult {
        let body = RequestBody.json([
            ("to", .string(params.to)),
            ("sender_id", params.senderId.json),
            ("template", params.template.json),
            ("length", params.length.json),
            ("ttl_seconds", params.ttlSeconds.json)
        ])
        return try await http.request("POST", "/v1/otp/send", body: body, idempotencyKey: idempotency(idempotencyKey))
    }

    /// Check a code. A wrong code returns `valid == false` and uses up an
    /// attempt, so this call is never retried.
    public func verify(otpId: String, code: String) async throws -> OtpVerification {
        _ = try idSeg(otpId, "otpId")
        let body = RequestBody.json([("otp_id", .string(otpId)), ("code", .string(code))])
        return try await http.request("POST", "/v1/otp/verify", body: body)
    }
}
