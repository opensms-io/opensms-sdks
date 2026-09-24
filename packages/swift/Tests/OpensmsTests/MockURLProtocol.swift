import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A captured request (URL, method, headers, body) for assertions.
struct CapturedRequest {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data?

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A queued canned response, or a network failure.
struct StubResponse {
    let status: Int
    let headers: [String: String]
    let body: Data
    let error: URLError?

    init(status: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], json: String = "{}") {
        self.status = status
        self.headers = headers
        self.body = Data(json.utf8)
        self.error = nil
    }

    init(status: Int, headers: [String: String], text: String) {
        self.status = status
        self.headers = headers
        self.body = Data(text.utf8)
        self.error = nil
    }

    /// A problem+json error response.
    static func problem(_ status: Int, _ json: String, headers: [String: String] = [:]) -> StubResponse {
        StubResponse(status: status, headers: headers.merging(["Content-Type": "application/problem+json"]) { a, _ in a }, json: json)
    }

    /// A transport failure (no HTTP response).
    static func networkError(_ code: URLError.Code = .networkConnectionLost) -> StubResponse {
        StubResponse(error: URLError(code))
    }

    private init(error: URLError) {
        self.status = 0
        self.headers = [:]
        self.body = Data()
        self.error = error
    }
}

/// A `URLProtocol` that intercepts every request, records it, and replies with
/// a queued ``StubResponse``. Register it on a `URLSession` so SDK tests run
/// fully offline.
final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responses: [StubResponse] = []
    private static var captured: [CapturedRequest] = []

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responses = []
        captured = []
    }

    static func enqueue(_ items: StubResponse...) {
        lock.lock(); defer { lock.unlock() }
        responses.append(contentsOf: items)
    }

    static func capturedRequests() -> [CapturedRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var bodyData = request.httpBody
        if bodyData == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
            bodyData = data
        }

        MockURLProtocol.lock.lock()
        MockURLProtocol.captured.append(CapturedRequest(
            url: request.url!,
            method: request.httpMethod ?? "GET",
            headers: request.allHTTPHeaderFields ?? [:],
            body: bodyData
        ))
        let stub = MockURLProtocol.responses.isEmpty ? StubResponse() : MockURLProtocol.responses.removeFirst()
        MockURLProtocol.lock.unlock()

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Zero-delay sleeper that records every requested delay.
final class SleepRecorder {
    private let lock = NSLock()
    private var _delays: [TimeInterval] = []

    var delays: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return _delays
    }

    var sleeper: (TimeInterval) async throws -> Void {
        { [self] seconds in record(seconds) }
    }

    private func record(_ seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _delays.append(seconds)
    }
}
