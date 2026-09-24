import Foundation

/// Parameters for ``Messages/send(_:idempotencyKey:)``.
public struct SendMessageParams {
    /// Destination in E.164, for example `+254700000012`.
    public var to: String
    /// Message text, 1 to 1600 characters.
    public var text: String
    /// Sender ID (up to 11 characters, or up to 15 digits).
    public var senderId: String?
    /// `otp`, `transactional` (default) or `marketing`.
    public var trafficType: String?
    /// Send later. A `Date` or an RFC 3339 string.
    public var scheduledAt: DateTimeInput?
    /// Per-message delivery callback URL.
    public var callbackUrl: String?
    /// Free-form metadata echoed back on the message.
    public var metadata: JSONObject?

    public init(
        to: String,
        text: String,
        senderId: String? = nil,
        trafficType: String? = nil,
        scheduledAt: DateTimeInput? = nil,
        callbackUrl: String? = nil,
        metadata: JSONObject? = nil
    ) {
        self.to = to
        self.text = text
        self.senderId = senderId
        self.trafficType = trafficType
        self.scheduledAt = scheduledAt
        self.callbackUrl = callbackUrl
        self.metadata = metadata
    }

    var body: RequestBody {
        .json([
            ("to", .string(to)),
            ("text", .string(text)),
            ("sender_id", senderId.json),
            ("traffic_type", trafficType.json),
            ("scheduled_at", scheduledAt.json),
            ("callback_url", callbackUrl.json),
            ("metadata", metadata.json)
        ])
    }
}

/// Parameters for ``Messages/list(_:)``.
public struct ListMessagesParams: CursorParams {
    /// 1 to 100, default 20.
    public var limit: Int?
    public var cursor: String?
    public var status: String?
    /// Digits or `+digits` fragment of the destination.
    public var to: String?
    /// Uppercase ISO2 country.
    public var country: String?
    /// `YYYY-MM-DD` or RFC 3339.
    public var dateFrom: DateTimeInput?
    /// `YYYY-MM-DD` (inclusive) or RFC 3339.
    public var dateTo: DateTimeInput?

    public init(
        limit: Int? = nil,
        cursor: String? = nil,
        status: String? = nil,
        to: String? = nil,
        country: String? = nil,
        dateFrom: DateTimeInput? = nil,
        dateTo: DateTimeInput? = nil
    ) {
        self.limit = limit
        self.cursor = cursor
        self.status = status
        self.to = to
        self.country = country
        self.dateFrom = dateFrom
        self.dateTo = dateTo
    }
}

/// The `messages` resource. Accessed as `opensms.messages`.
public final class Messages {
    private let http: Transport
    init(_ http: Transport) { self.http = http }

    /// Send one SMS. An Idempotency-Key is generated when not given and reused on retries.
    public func send(_ params: SendMessageParams, idempotencyKey: String? = nil) async throws -> Message {
        try await http.request("POST", "/v1/messages", body: params.body, idempotencyKey: idempotency(idempotencyKey))
    }

    /// List messages, newest first.
    public func list(_ params: ListMessagesParams = ListMessagesParams()) async throws -> Page<Message> {
        try await http.request("GET", "/v1/messages", query: [
            ("limit", params.limit.q),
            ("cursor", params.cursor),
            ("status", params.status),
            ("to", params.to),
            ("country", params.country),
            ("date_from", params.dateFrom?.wireValue),
            ("date_to", params.dateTo?.wireValue)
        ])
    }

    /// Fetch one message.
    public func get(_ id: String) async throws -> Message {
        try await http.request("GET", "/v1/messages/\(try idSeg(id))")
    }

    /// Provider submission attempts for a message.
    public func attempts(_ id: String) async throws -> [MessageAttempt] {
        try await http.request("GET", "/v1/messages/\(try idSeg(id))/attempts")
    }

    /// Cancel a `queued` or `scheduled` message. Never retried.
    public func cancel(_ id: String) async throws -> Message {
        try await http.request("POST", "/v1/messages/\(try idSeg(id))/cancel")
    }
}
