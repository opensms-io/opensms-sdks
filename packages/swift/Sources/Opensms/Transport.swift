import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// SDK version, sent in the `User-Agent` header.
public let opensmsSDKVersion = "0.1.1"

/// An async sleeper, injectable so tests can observe retry delays without waiting.
public typealias OpensmsSleeper = (TimeInterval) async throws -> Void

/// Configuration for ``OpensmsClient``.
public struct OpensmsOptions {
    /// Secret API key, `sk_test_...` (sandbox) or `sk_live_...` (live).
    public var apiKey: String
    /// API base URL. Defaults to `https://opensms.io`. Trailing slashes are stripped.
    public var baseURL: String
    /// Per-attempt timeout in seconds. Defaults to `30`.
    public var timeout: TimeInterval
    /// Retries after the first attempt on `429`, `5xx` and network errors. Defaults to `2`. `0` disables retries.
    public var maxRetries: Int
    /// The `URLSession` used for every request. Inject one with a custom `URLProtocol` for tests.
    public var session: URLSession
    /// Replaces `Task.sleep` between retries. Tests inject a zero-delay recorder.
    public var sleeper: OpensmsSleeper?

    public init(
        apiKey: String,
        baseURL: String = "https://opensms.io",
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        session: URLSession = .shared,
        sleeper: OpensmsSleeper? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.timeout = timeout
        self.maxRetries = maxRetries
        self.session = session
        self.sleeper = sleeper
    }
}

/// A request body.
enum RequestBody {
    /// A JSON object; `nil` fields must already be dropped (see ``json(_:)``).
    case json(JSONValue)
    /// Raw bytes with an explicit content type (the CSV batch entry point).
    case raw(Data, contentType: String)

    /// Build a JSON object body from key/optional-value pairs. Swift `nil`
    /// values are dropped so unset optionals are absent from the wire, never `null`.
    static func json(_ pairs: [(String, JSONValue?)]) -> RequestBody {
        .json(.object(jsonObject(pairs)))
    }
}

/// Build a JSON object from key/optional-value pairs, dropping `nil` values.
func jsonObject(_ pairs: [(String, JSONValue?)]) -> [String: JSONValue] {
    var out: [String: JSONValue] = [:]
    for (key, value) in pairs {
        if let value { out[key] = value }
    }
    return out
}

/// The HTTP transport: the only code that touches the network. Owns
/// authentication headers, JSON encoding and decoding, Idempotency-Key
/// headers, retries with backoff (honouring `Retry-After`), and error mapping
/// to ``OpensmsError``. Resources are thin and call this.
final class Transport {
    let apiKey: String
    let baseURL: String
    let timeout: TimeInterval
    let maxRetries: Int
    let session: URLSession
    private let sleeper: OpensmsSleeper
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(_ options: OpensmsOptions) {
        self.apiKey = options.apiKey
        var base = options.baseURL
        while base.hasSuffix("/") { base.removeLast() }
        self.baseURL = base
        self.timeout = options.timeout
        self.maxRetries = max(0, options.maxRetries)
        self.session = options.session
        self.sleeper = options.sleeper ?? { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
        self.decoder = makeDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = encoder
    }

    // MARK: Public entry points for resources

    /// Perform a request and decode the JSON response as `T`.
    func request<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [(String, String?)] = [],
        body: RequestBody? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let data = try await send(method, path, query: query, body: body, idempotencyKey: idempotencyKey)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OpensmsError(status: 0, message: "OpenSMS: failed to decode response: \(error)")
        }
    }

    /// Perform a request whose response has no body worth decoding (`204`).
    func requestVoid(
        _ method: String,
        _ path: String,
        query: [(String, String?)] = [],
        body: RequestBody? = nil,
        idempotencyKey: String? = nil
    ) async throws {
        _ = try await send(method, path, query: query, body: body, idempotencyKey: idempotencyKey)
    }

    // MARK: Core loop

    private func send(
        _ method: String,
        _ path: String,
        query: [(String, String?)],
        body: RequestBody?,
        idempotencyKey: String?
    ) async throws -> Data {
        let url = try buildURL(path, query: query)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("opensms-swift/\(opensmsSDKVersion)", forHTTPHeaderField: "User-Agent")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        switch body {
        case .json(let value)?:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(value)
        case .raw(let data, let contentType)?:
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        case nil:
            break
        }

        // POSTs are only safe to repeat when they carry an Idempotency-Key.
        let retryable = method != "POST" || idempotencyKey != nil
        var attempt = 0
        while true {
            attempt += 1
            let canRetry = retryable && attempt <= maxRetries
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if canRetry {
                    try await sleeper(backoff(attempt))
                    continue
                }
                throw OpensmsError(status: 0, message: "OpenSMS request failed: \(error.localizedDescription)")
            }
            guard let http = response as? HTTPURLResponse else {
                throw OpensmsError(status: 0, message: "OpenSMS: non-HTTP response")
            }
            if (200...299).contains(http.statusCode) {
                return data
            }
            let retryAfter = parseRetryAfter(http.value(forHTTPHeaderField: "Retry-After"))
            let error = OpensmsError.from(status: http.statusCode, headers: http, data: data, retryAfter: retryAfter)
            guard canRetry, Self.isRetryableStatus(http.statusCode) else { throw error }
            if let retryAfter {
                if retryAfter > 60 { throw error }
                try await sleeper(TimeInterval(retryAfter))
            } else {
                try await sleeper(backoff(attempt))
            }
        }
    }

    static func isRetryableStatus(_ status: Int) -> Bool {
        [429, 500, 502, 503, 504].contains(status)
    }

    /// Full-jitter exponential backoff before retry `n` (1-based):
    /// `random(0, min(8, 0.5 * 2^(n-1)))` seconds.
    private func backoff(_ n: Int) -> TimeInterval {
        let cap = min(8.0, 0.5 * pow(2.0, Double(n - 1)))
        return Double.random(in: 0...cap)
    }

    /// Parse `Retry-After` as integer seconds or an HTTP date. Returns whole seconds.
    private func parseRetryAfter(_ header: String?) -> Int? {
        guard let raw = header?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = Int(raw) { return max(0, seconds) }
        if let seconds = Double(raw) { return max(0, Int(seconds.rounded(.up))) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return max(0, Int(date.timeIntervalSinceNow.rounded(.up)))
            }
        }
        return nil
    }

    // MARK: URL building

    private func buildURL(_ path: String, query: [(String, String?)]) throws -> URL {
        var text = baseURL + path
        let items = query.compactMap { key, value -> String? in
            guard let value else { return nil }
            return "\(encodeQuery(key))=\(encodeQuery(value))"
        }
        if !items.isEmpty { text += "?" + items.joined(separator: "&") }
        guard let url = URL(string: text) else {
            throw OpensmsArgumentError("OpenSMS: invalid URL \(text)")
        }
        return url
    }
}

private let unreserved = CharacterSet(charactersIn:
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
private let queryAllowed = unreserved.union(CharacterSet(charactersIn: ","))

/// Percent-encode one path segment (`/` becomes `%2F`).
func seg(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
}

/// Percent-encode a query key or value (`+` becomes `%2B`; commas stay literal
/// so list parameters read `countries=KE,NG`).
func encodeQuery(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? value
}

/// Validate that an id argument is non-empty and return its escaped segment.
func idSeg(_ value: String, _ name: String = "id") throws -> String {
    if value.trimmingCharacters(in: .whitespaces).isEmpty {
        throw OpensmsArgumentError("OpenSMS: `\(name)` must be a non-empty string.")
    }
    return seg(value)
}

/// Generate a fresh Idempotency-Key (UUIDv4, 36 characters) unless one was given.
func idempotency(_ key: String?) -> String {
    key ?? UUID().uuidString.lowercased()
}

extension Optional where Wrapped == Int {
    /// Query string form of an optional integer.
    var q: String? { map(String.init) }
}

extension Optional where Wrapped == Bool {
    var q: String? { map { $0 ? "true" : "false" } }
}
