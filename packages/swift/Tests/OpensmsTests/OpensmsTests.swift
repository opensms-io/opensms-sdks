import XCTest
@testable import Opensms

/// Offline mock-transport tests: CONFORMANCE.md "Mock-transport unit tests" 1 to 20.
final class OpensmsTests: XCTestCase {
    static let testKey = "sk_test_" + String(repeating: "a", count: 32)
    static let liveKey = "sk_live_" + String(repeating: "b", count: 32)
    static let messageJSON = #"{"id":"11111111-1111-1111-1111-111111111111","to":"+254700000012","sender_id":"OPENSMS","status":"queued","parts":1,"price":"0.000000","currency":"KES","created_at":"2026-09-24T08:25:59.396241+03:00","brand_new_field":{"x":1}}"#

    private var recorder = SleepRecorder()

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        recorder = SleepRecorder()
    }

    private func client(baseURL: String = "https://api.opensms.io", maxRetries: Int = 2) throws -> OpensmsClient {
        try OpensmsClient(
            apiKey: Self.testKey,
            baseURL: baseURL,
            maxRetries: maxRetries,
            session: MockURLProtocol.makeSession(),
            sleeper: recorder.sleeper
        )
    }

    private func jsonBody(_ req: CapturedRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(req.body)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func expectError(_ block: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async -> OpensmsError? {
        do {
            try await block()
            XCTFail("expected OpensmsError", file: file, line: line)
            return nil
        } catch let error as OpensmsError {
            return error
        } catch {
            XCTFail("expected OpensmsError, got \(error)", file: file, line: line)
            return nil
        }
    }

    // 1. Header injection
    func testHeaderInjection() async throws {
        MockURLProtocol.enqueue(StubResponse(status: 201, json: Self.messageJSON), StubResponse(json: #"{"items":[],"next_cursor":null}"#))
        let c = try client()
        _ = try await c.messages.send(.init(to: "+254700000012", text: "hi"))
        _ = try await c.messages.list()
        let reqs = MockURLProtocol.capturedRequests()
        XCTAssertEqual(reqs.count, 2)
        for req in reqs {
            XCTAssertEqual(req.header("Authorization"), "Bearer \(Self.testKey)")
            XCTAssertEqual(req.header("Accept"), "application/json")
            XCTAssertEqual(req.header("User-Agent"), "opensms-swift/0.1.0")
            XCTAssertNil(req.header("X-Workspace-ID"))
            XCTAssertNil(req.header("X-Environment"))
        }
        XCTAssertEqual(reqs[0].header("Content-Type"), "application/json")
        XCTAssertNil(reqs[1].header("Content-Type"))
    }

    // 2. Base URL
    func testBaseURL() async throws {
        XCTAssertEqual(try OpensmsClient(apiKey: Self.testKey).baseURL, "https://api.opensms.io")
        MockURLProtocol.enqueue(StubResponse(status: 201, json: Self.messageJSON))
        _ = try await client(baseURL: "http://host/").messages.send(.init(to: "+254700000012", text: "hi"))
        XCTAssertEqual(MockURLProtocol.capturedRequests().first?.url.absoluteString, "http://host/v1/messages")
    }

    // 3. Key validation
    func testKeyValidation() throws {
        for bad in ["", "pk_test_x", "sk_test_short", "sk_test_123456789012", "not_a_key"] {
            XCTAssertThrowsError(try OpensmsClient(apiKey: bad), bad) { XCTAssertTrue($0 is OpensmsArgumentError) }
        }
        XCTAssertEqual(try OpensmsClient(apiKey: Self.liveKey).environment, "live")
        XCTAssertEqual(try OpensmsClient(apiKey: Self.testKey).environment, "sandbox")
        XCTAssertEqual(try OpensmsClient(apiKey: "sk_test_1234567890123").environment, "sandbox")
    }

    // 4. Body mapping
    func testSendBodyMapping() async throws {
        MockURLProtocol.enqueue(StubResponse(status: 201, json: Self.messageJSON), StubResponse(status: 201, json: Self.messageJSON))
        let c = try client()
        _ = try await c.messages.send(.init(
            to: "+254700000012", text: "hi", senderId: "ACME", trafficType: "marketing",
            scheduledAt: .date(Date(timeIntervalSince1970: 1_790_208_000)),
            callbackUrl: "https://example.com/cb", metadata: ["sdk": "swift", "n": 1]
        ))
        _ = try await c.messages.send(.init(to: "+254700000012", text: "hi"))
        let reqs = MockURLProtocol.capturedRequests()
        let full = try jsonBody(reqs[0])
        XCTAssertEqual(Set(full.keys), ["to", "text", "sender_id", "traffic_type", "scheduled_at", "callback_url", "metadata"])
        XCTAssertEqual(full["scheduled_at"] as? String, "2026-09-24T00:00:00Z")
        XCTAssertEqual(full["sender_id"] as? String, "ACME")
        XCTAssertEqual((full["metadata"] as? [String: Any])?["sdk"] as? String, "swift")
        XCTAssertEqual((full["metadata"] as? [String: Any])?["n"] as? Int, 1)
        let minimal = try jsonBody(reqs[1])
        XCTAssertEqual(Set(minimal.keys), ["to", "text"])
        XCTAssertFalse(String(decoding: reqs[1].body!, as: UTF8.self).contains("null"))
    }

    // 5. Idempotency-Key auto
    func testIdempotencyKey() async throws {
        MockURLProtocol.enqueue(StubResponse(status: 201, json: Self.messageJSON), StubResponse(status: 201, json: Self.messageJSON), StubResponse(json: Self.messageJSON))
        let c = try client()
        _ = try await c.messages.send(.init(to: "+254700000012", text: "a"))
        _ = try await c.messages.send(.init(to: "+254700000012", text: "a"), idempotencyKey: "my-key-1")
        _ = try await c.messages.get("11111111-1111-1111-1111-111111111111")
        let reqs = MockURLProtocol.capturedRequests()
        let auto = try XCTUnwrap(reqs[0].header("Idempotency-Key"))
        XCTAssertEqual(auto.count, 36)
        XCTAssertNotNil(UUID(uuidString: auto))
        XCTAssertEqual(reqs[1].header("Idempotency-Key"), "my-key-1")
        XCTAssertNil(reqs[2].header("Idempotency-Key"))
    }

    // 6. Retry on 429 with Retry-After
    func testRetryOn429WithRetryAfter() async throws {
        MockURLProtocol.enqueue(
            .problem(429, #"{"type":"about:blank","title":"Too Many Requests","status":429,"detail":"rate limited"}"#, headers: ["Retry-After": "2"]),
            StubResponse(status: 201, json: Self.messageJSON)
        )
        let m = try await client().messages.send(.init(to: "+254700000012", text: "a"))
        XCTAssertEqual(m.id, "11111111-1111-1111-1111-111111111111")
        let reqs = MockURLProtocol.capturedRequests()
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(recorder.delays, [2])
        XCTAssertNotNil(reqs[0].header("Idempotency-Key"))
        XCTAssertEqual(reqs[0].header("Idempotency-Key"), reqs[1].header("Idempotency-Key"))
    }

    // 6b. Retry-After as an HTTP date
    func testRetryAfterHTTPDate() async throws {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let when = f.string(from: Date().addingTimeInterval(5))
        MockURLProtocol.enqueue(.problem(503, "{}", headers: ["Retry-After": when]), StubResponse(json: Self.messageJSON))
        _ = try await client().messages.get("x")
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 2)
        let delay = try XCTUnwrap(recorder.delays.first)
        XCTAssertTrue((3...6).contains(delay), "delay \(delay)")
    }

    // 7. Retry on 503 without Retry-After
    func testRetryOn503Backoff() async throws {
        MockURLProtocol.enqueue(.problem(503, #"{"title":"Service Unavailable","status":503}"#), StubResponse(json: Self.messageJSON))
        _ = try await client().messages.get("11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 2)
        XCTAssertEqual(recorder.delays.count, 1)
        XCTAssertTrue((0...0.5).contains(recorder.delays[0]))
    }

    // 8. Retries exhausted
    func testRetriesExhausted() async throws {
        MockURLProtocol.enqueue(.problem(500, "{}"), .problem(500, "{}"), .problem(500, "{}"))
        let c = try client(maxRetries: 2)
        let err = await expectError { _ = try await c.messages.get("x") }
        XCTAssertEqual(err?.status, 500)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 3)
        XCTAssertEqual(recorder.delays.count, 2)
        XCTAssertTrue((0...1.0).contains(recorder.delays[1]))
    }

    // 9. Retry-After too large
    func testRetryAfterTooLarge() async throws {
        MockURLProtocol.enqueue(.problem(429, #"{"title":"Too Many Requests","status":429}"#, headers: ["Retry-After": "120"]))
        let c = try client()
        let err = await expectError { _ = try await c.messages.list() }
        XCTAssertEqual(err?.status, 429)
        XCTAssertEqual(err?.retryAfter, 120)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1)
        XCTAssertTrue(recorder.delays.isEmpty)
    }

    // 10. No retry on 400/401/404/409/422
    func testNoRetryOnClientErrors() async throws {
        let c = try client()
        for status in [400, 401, 404, 409, 422] {
            MockURLProtocol.reset()
            MockURLProtocol.enqueue(.problem(status, #"{"type":"about:blank","status":\#(status),"detail":"nope"}"#))
            let err = await expectError { _ = try await c.messages.send(.init(to: "+254700000012", text: "a")) }
            XCTAssertEqual(err?.status, status)
            XCTAssertEqual(err?.detail, "nope")
            XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1, "status \(status)")
        }
    }

    // 11. No retry for non-idempotent POST
    func testNoRetryForNonIdempotentPost() async throws {
        let c = try client()
        MockURLProtocol.enqueue(.problem(503, "{}"), StubResponse(json: #"{"valid":true,"attempts_left":4}"#))
        var err = await expectError { _ = try await c.otp.verify(otpId: "00000000-0000-0000-0000-000000000000", code: "123456") }
        XCTAssertEqual(err?.status, 503)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1)
        XCTAssertNil(MockURLProtocol.capturedRequests()[0].header("Idempotency-Key"))

        MockURLProtocol.reset()
        MockURLProtocol.enqueue(.problem(503, "{}"), StubResponse(json: Self.messageJSON))
        err = await expectError { _ = try await c.messages.cancel("11111111-1111-1111-1111-111111111111") }
        XCTAssertEqual(err?.status, 503)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1)

        MockURLProtocol.reset()
        MockURLProtocol.enqueue(.networkError(), StubResponse(json: "{}"))
        err = await expectError { _ = try await c.suppressions.create(e164: "+254700000001", reason: "manual") }
        XCTAssertEqual(err?.status, 0)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1)
    }

    // 12. Network error
    func testNetworkErrorRetriesThenSucceeds() async throws {
        MockURLProtocol.enqueue(.networkError(), .networkError(.timedOut), StubResponse(json: Self.messageJSON))
        let m = try await client().messages.get("11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(m.status, "queued")
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 3)

        MockURLProtocol.reset()
        MockURLProtocol.enqueue(.networkError(), .networkError(), .networkError())
        let c = try client()
        let err = await expectError { _ = try await c.messages.get("x") }
        XCTAssertEqual(err?.status, 0)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 3)
    }

    // 13. Error mapping
    func testErrorMapping() async throws {
        let c = try client()
        MockURLProtocol.enqueue(.problem(400, #"{"type":"https://api.opensms.io/problems/invalid_message_id","title":"Bad Request","status":400,"detail":"Message ID must be a valid UUID.","code":"invalid_message_id","trace_id":"t1","errors":{"to":["bad"]}}"#))
        var err = await expectError { _ = try await c.messages.get("not-a-uuid") }
        XCTAssertEqual(err?.status, 400)
        XCTAssertEqual(err?.type, "https://api.opensms.io/problems/invalid_message_id")
        XCTAssertEqual(err?.title, "Bad Request")
        XCTAssertEqual(err?.detail, "Message ID must be a valid UUID.")
        XCTAssertEqual(err?.code, "invalid_message_id")
        XCTAssertEqual(err?.traceId, "t1")
        XCTAssertEqual(err?.errors?["to"], ["bad"])
        XCTAssertEqual(err?.message, "Message ID must be a valid UUID.")
        XCTAssertEqual(err?.localizedDescription, "Message ID must be a valid UUID.")

        MockURLProtocol.enqueue(.problem(401, #"{"type":"about:blank","title":"Unauthorized","status":401,"detail":"missing or invalid API key"}"#))
        err = await expectError { _ = try await c.messages.list() }
        XCTAssertNil(err?.code)
        XCTAssertEqual(err?.type, "about:blank")

        MockURLProtocol.enqueue(.problem(422, #"{"type":"about:blank","title":"Unprocessable Entity","status":422,"detail":"destination is suppressed"}"#, headers: ["X-Request-ID": "r1"]))
        err = await expectError { _ = try await c.messages.send(.init(to: "+254700000012", text: "a")) }
        XCTAssertEqual(err?.requestId, "r1")

        MockURLProtocol.enqueue(StubResponse(status: 502, headers: ["Content-Type": "text/html"], text: "<html>Bad Gateway</html>"),
                                StubResponse(status: 502, headers: ["Content-Type": "text/html"], text: "<html>Bad Gateway</html>"),
                                StubResponse(status: 502, headers: ["Content-Type": "text/html"], text: "<html>Bad Gateway</html>"))
        err = await expectError { _ = try await c.messages.list() }
        XCTAssertEqual(err?.status, 502)
        XCTAssertNil(err?.detail)
        XCTAssertNil(err?.title)
        XCTAssertEqual(err?.body, .string("<html>Bad Gateway</html>"))
        XCTAssertEqual(err?.message, "OpenSMS request failed with status 502")

        MockURLProtocol.enqueue(.problem(400, #"{"title":"Bad Request","status":400}"#))
        err = await expectError { _ = try await c.messages.list() }
        XCTAssertEqual(err?.message, "Bad Request")
    }

    // 14. 204 handling
    func testDeleteNoContent() async throws {
        MockURLProtocol.enqueue(StubResponse(status: 204, headers: [:], json: ""))
        try await client().contacts.delete("c1")
        let req = try XCTUnwrap(MockURLProtocol.capturedRequests().first)
        XCTAssertEqual(req.method, "DELETE")
        XCTAssertEqual(req.url.absoluteString, "https://api.opensms.io/v1/contacts/c1")
    }

    // 15. Pagination
    func testPaginationHelper() async throws {
        let m = { (id: String) in #"{"id":"\#(id)","status":"delivered"}"# }
        MockURLProtocol.enqueue(
            StubResponse(json: #"{"items":[\#(m("a")),\#(m("b"))],"next_cursor":"c1"}"#),
            StubResponse(json: #"{"items":[\#(m("c"))],"next_cursor":null}"#)
        )
        let c = try client()
        var ids: [String] = []
        for try await message in c.paginate(c.messages.list, ListMessagesParams(limit: 2)) {
            ids.append(message.id)
        }
        XCTAssertEqual(ids, ["a", "b", "c"])
        let reqs = MockURLProtocol.capturedRequests()
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(reqs[0].url.query, "limit=2")
        let second = URLComponents(url: reqs[1].url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        XCTAssertTrue(second.contains(URLQueryItem(name: "cursor", value: "c1")))
        XCTAssertTrue(second.contains(URLQueryItem(name: "limit", value: "2")))
    }

    // 15b. Pagination over a method with a path parameter, stopped early
    func testPaginationClosureAndEarlyStop() async throws {
        MockURLProtocol.enqueue(StubResponse(json: #"{"items":[{"id":"x"},{"id":"y"}],"next_cursor":"n"}"#))
        let c = try client()
        var seen = 0
        for try await _ in c.paginate({ try await c.batches.listItems("b1", $0) }, ListBatchItemsParams(limit: 2)) {
            seen += 1
            if seen == 1 { break }
        }
        XCTAssertEqual(seen, 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1, "breaking out must not fetch the next page")
        XCTAssertTrue(MockURLProtocol.capturedRequests()[0].url.absoluteString.hasPrefix("https://api.opensms.io/v1/batches/b1/items?"))
    }

    // 16. Query encoding
    func testQueryEncoding() async throws {
        MockURLProtocol.enqueue(StubResponse(json: #"{"quote_id":"sq_1","entries":[],"totals":[]}"#), StubResponse(json: #"{"items":[],"next_cursor":null}"#))
        let c = try client()
        _ = try await c.senderIds.quote(countries: ["KE", "NG"])
        _ = try await c.messages.list(ListMessagesParams(status: "delivered", to: "+2547"))
        let reqs = MockURLProtocol.capturedRequests()
        XCTAssertEqual(reqs[0].url.absoluteString, "https://api.opensms.io/v1/sender-ids/quote?countries=KE,NG")
        XCTAssertEqual(reqs[1].url.absoluteString, "https://api.opensms.io/v1/messages?status=delivered&to=%2B2547")
    }

    // 17. Path escaping and id validation
    func testPathEscaping() async throws {
        MockURLProtocol.enqueue(StubResponse(json: Self.messageJSON))
        let c = try client()
        _ = try await c.messages.get("a/b")
        XCTAssertEqual(MockURLProtocol.capturedRequests()[0].url.absoluteString, "https://api.opensms.io/v1/messages/a%2Fb")
        do {
            _ = try await c.messages.get("")
            XCTFail("empty id must throw")
        } catch {
            XCTAssertTrue(error is OpensmsArgumentError)
        }
        XCTAssertEqual(MockURLProtocol.capturedRequests().count, 1)
    }

    // 18. Webhook signature vector (DESIGN.md)
    static let secret = "whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE"
    static let ts: TimeInterval = 1_790_208_000
    static let body = #"{"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001","environment":"sandbox","created_at":"2026-09-24T00:00:00Z","data":{"id":"00000000-0000-0000-0000-000000000002","status":"delivered"}}"#
    static let digest = "eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23"
    static let header = "t=1790208000,v1=\(digest)"

    func testWebhookSignatureVector() throws {
        XCTAssertEqual(Data(Self.body.utf8).count, 230)
        func verify(_ body: String = OpensmsTests.body, _ header: String = OpensmsTests.header, secret: String = OpensmsTests.secret, now: Date = Date(timeIntervalSince1970: OpensmsTests.ts)) -> Bool {
            OpensmsWebhooks.verifySignature(payload: body, header: header, secret: secret, now: now)
        }
        XCTAssertTrue(verify())
        XCTAssertTrue(verify(now: Date(timeIntervalSince1970: Self.ts + 300)))
        XCTAssertFalse(verify(now: Date(timeIntervalSince1970: Self.ts + 301)))
        XCTAssertFalse(verify(now: Date(timeIntervalSince1970: Self.ts - 301)))
        XCTAssertFalse(verify(Self.body.replacingOccurrences(of: #""status":"delivered""#, with: #""status":"failed""#)))
        XCTAssertFalse(verify(secret: String(Self.secret.dropFirst("whsec_".count))))
        XCTAssertTrue(verify(Self.body, "v1=\(Self.digest),t=1790208000"))
        XCTAssertFalse(verify(Self.body, Self.header + ",v0=abc"))
        XCTAssertFalse(verify(Self.body, "t=1790208000"))
        XCTAssertTrue(verify(Self.body, "t=1790208000,v1=\(Self.digest.uppercased())"))
        XCTAssertFalse(verify(secret: ""))
        XCTAssertFalse(verify(Self.body, "t=1790208000,t=1790208000,v1=\(Self.digest)"))
        XCTAssertFalse(verify(Self.body, "t=abc,v1=\(Self.digest)"))

        // The portable HMAC fallback agrees with the vector.
        let mac = PortableHMAC.sha256(key: Array(Self.secret.utf8), message: Array("1790208000.\(Self.body)".utf8))
        XCTAssertEqual(mac.map { String(format: "%02x", $0) }.joined(), Self.digest)
    }

    func testConstructEvent() throws {
        let now = Date(timeIntervalSince1970: Self.ts)
        let c = try client()
        let event = try c.webhooks.constructEvent(payload: Data(Self.body.utf8), header: Self.header, secret: Self.secret, now: now)
        XCTAssertEqual(event.id, "evt_01")
        XCTAssertEqual(event.type, "message.delivered")
        XCTAssertEqual(event.workspaceId, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(event.data?["status"]?.stringValue, "delivered")

        let tampered = Self.body.replacingOccurrences(of: #""status":"delivered""#, with: #""status":"failed""#)
        XCTAssertThrowsError(try OpensmsWebhooks.constructEvent(payload: tampered, header: Self.header, secret: Self.secret, now: now)) {
            XCTAssertEqual(($0 as? OpensmsError)?.code, "invalid_signature")
            XCTAssertEqual(($0 as? OpensmsError)?.status, 0)
        }
        XCTAssertThrowsError(try OpensmsWebhooks.constructEvent(payload: Self.body, header: Self.header, secret: Self.secret,
                                                                now: Date(timeIntervalSince1970: Self.ts + 301))) {
            XCTAssertEqual(($0 as? OpensmsError)?.code, "expired_signature")
        }
    }

    // 19. Batch CSV
    func testBatchCsv() async throws {
        MockURLProtocol.enqueue(StubResponse(status: 202, json: #"{"id":"b1","status":"ready","total":1,"invalid":0}"#))
        let csv = "to,text\n+254700000014,csv run\n"
        let batch = try await client().batches.createFromCsv(csv)
        XCTAssertEqual(batch.status, "ready")
        let req = try XCTUnwrap(MockURLProtocol.capturedRequests().first)
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.url.absoluteString, "https://api.opensms.io/v1/messages/batch")
        XCTAssertEqual(req.header("Content-Type"), "text/csv")
        XCTAssertEqual(req.body.map { String(decoding: $0, as: UTF8.self) }, csv)
        XCTAssertEqual(req.header("Idempotency-Key")?.count, 36)
    }

    // 20. Decimal strings and unknown fields
    func testDecimalStringsAndUnknownFields() async throws {
        MockURLProtocol.enqueue(StubResponse(json: Self.messageJSON))
        let m = try await client().messages.get("11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(m.price, "0.000000")
        XCTAssertEqual(m.currency, "KES")
        XCTAssertNil(m.deliveredAt)
        let created = try XCTUnwrap(m.createdAt)
        XCTAssertEqual(created.timeIntervalSince1970, 1_790_227_559.396241, accuracy: 0.001)
    }

    // Extra: request shapes for the other resources
    func testResourceRequestShapes() async throws {
        let c = try client()
        MockURLProtocol.enqueue(
            StubResponse(status: 202, json: #"{"id":"b1","status":"ready"}"#),
            StubResponse(json: #"{"id":"w1","url":"https://x","events":["a"],"enabled":true}"#),
            StubResponse(json: #"{"data":[{"id":7,"amount":"1.000000"}]}"#),
            StubResponse(status: 201, json: #"{"created":1,"received":1}"#),
            StubResponse(json: #"{"id":"d1","version":2,"status":"active"}"#),
            StubResponse(json: #"[{"key":"k","name":"Kenya","sent":1,"delivery_rate":100,"spend":"0.000000"}]"#)
        )
        _ = try await c.batches.create(.init(items: [.init(to: "+254700000012", text: "b1")], dedupe: false))
        _ = try await c.webhooks.update("w1", url: "https://x", events: ["a"], enabled: false)
        let ledger = try await c.wallet.ledger(limit: 1, before: 10)
        let imported = try await c.suppressions.import([.init(e164: "+254700000001", reason: "complaint")])
        _ = try await c.senderIds.updateDraft("d1", .init(version: 1, sampleMessage: "Your order has shipped"))
        let rows = try await c.analytics.byCountry(.init(range: "7d"))

        let reqs = MockURLProtocol.capturedRequests()
        let batchBody = try jsonBody(reqs[0])
        XCTAssertEqual(batchBody["dedupe"] as? Bool, false)
        XCTAssertEqual((batchBody["items"] as? [[String: Any]])?.first?.keys.sorted(), ["text", "to"])
        XCTAssertEqual(reqs[1].method, "PUT")
        XCTAssertEqual(try jsonBody(reqs[1])["enabled"] as? Bool, false)
        XCTAssertNotNil(reqs[1].header("Idempotency-Key"))
        XCTAssertEqual(reqs[2].url.absoluteString, "https://api.opensms.io/v1/wallet/ledger?limit=1&before=10")
        XCTAssertEqual(ledger.first?.id, 7)
        XCTAssertEqual(imported.created, 1)
        XCTAssertNil(reqs[3].header("Idempotency-Key"))
        XCTAssertEqual(reqs[4].method, "PATCH")
        XCTAssertEqual(Set(try jsonBody(reqs[4]).keys), ["version", "sample_message"])
        XCTAssertEqual(reqs[5].url.absoluteString, "https://api.opensms.io/v1/analytics/by-country?range=7d")
        XCTAssertEqual(rows.first?.deliveryRate, 100)
    }
}
