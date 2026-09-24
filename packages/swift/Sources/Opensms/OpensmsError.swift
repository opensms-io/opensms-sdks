import Foundation

/// Thrown for every non-2xx API response and for transport failures that
/// survive all retries.
///
/// Mapped from the RFC 9457 `application/problem+json` body. Most API errors
/// carry no ``code``, so branch on ``status`` first and use ``detail`` for
/// display. A ``status`` of `0` means no HTTP response was received (network
/// failure, timeout) or a local failure such as a bad webhook signature.
public struct OpensmsError: Error, LocalizedError, CustomStringConvertible {
    /// HTTP status code, or `0` when there was no response.
    public let status: Int
    /// Problem `type`, usually `about:blank` or `https://api.opensms.io/problems/<code>`.
    public let type: String?
    /// Problem `title`, for example `Bad Request`.
    public let title: String?
    /// Problem `detail`, the human-readable explanation.
    public let detail: String?
    /// Problem `code`, present only on a few errors (`invalid_message_id`, `not_found`, ...).
    public let code: String?
    /// Problem `trace_id`, when present.
    public let traceId: String?
    /// Field validation errors (`errors`), when present.
    public let errors: [String: [String]]?
    /// The `X-Request-ID` response header (message and OTP admission rejections).
    public let requestId: String?
    /// The `Retry-After` response header in seconds (429 and some 503).
    public let retryAfter: Int?
    /// The raw decoded body: the JSON value, or `.string(text)` when the body is not JSON.
    public let body: JSONValue?
    /// Human-readable message: `detail`, else `title`, else a generic fallback.
    public let message: String

    public init(
        status: Int,
        type: String? = nil,
        title: String? = nil,
        detail: String? = nil,
        code: String? = nil,
        traceId: String? = nil,
        errors: [String: [String]]? = nil,
        requestId: String? = nil,
        retryAfter: Int? = nil,
        body: JSONValue? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.type = type
        self.title = title
        self.detail = detail
        self.code = code
        self.traceId = traceId
        self.errors = errors
        self.requestId = requestId
        self.retryAfter = retryAfter
        self.body = body
        self.message = message ?? detail ?? title ?? "OpenSMS request failed with status \(status)"
    }

    public var errorDescription: String? { message }

    public var description: String {
        var parts = ["status: \(status)"]
        if let code { parts.append("code: \(code)") }
        parts.append("message: \(message)")
        return "OpensmsError(\(parts.joined(separator: ", ")))"
    }

    /// Build an error from a response status, headers and body.
    static func from(status: Int, headers: HTTPURLResponse?, data: Data, retryAfter: Int?) -> OpensmsError {
        let requestId = headers?.value(forHTTPHeaderField: "X-Request-ID").flatMap { $0.isEmpty ? nil : $0 }
        var raw: JSONValue?
        if !data.isEmpty {
            if let json = try? JSONDecoder().decode(JSONValue.self, from: data) {
                raw = json
            } else {
                raw = .string(String(decoding: data, as: UTF8.self))
            }
        }
        guard case .object(let obj)? = raw else {
            return OpensmsError(status: status, requestId: requestId, retryAfter: retryAfter, body: raw)
        }
        var fieldErrors: [String: [String]]?
        if case .object(let map)? = obj["errors"] {
            var out: [String: [String]] = [:]
            for (key, value) in map {
                switch value {
                case .array(let list): out[key] = list.compactMap { $0.stringValue }
                case .string(let s): out[key] = [s]
                default: continue
                }
            }
            fieldErrors = out
        }
        return OpensmsError(
            status: status,
            type: obj["type"]?.stringValue,
            title: obj["title"]?.stringValue,
            detail: obj["detail"]?.stringValue,
            code: obj["code"]?.stringValue,
            traceId: obj["trace_id"]?.stringValue,
            errors: fieldErrors,
            requestId: requestId,
            retryAfter: retryAfter,
            body: raw
        )
    }
}

/// Thrown locally, before any HTTP request, when an argument is invalid: a
/// malformed API key at construction, or an empty id passed to a method.
public struct OpensmsArgumentError: Error, LocalizedError, CustomStringConvertible {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
    public var description: String { "OpensmsArgumentError(\(message))" }
}
