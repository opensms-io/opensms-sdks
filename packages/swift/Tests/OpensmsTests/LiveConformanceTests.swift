import XCTest
@testable import Opensms

/// The ordered live scenario from CONFORMANCE.md. Runs only when
/// `OPENSMS_BASE_URL` and `OPENSMS_API_KEY` are set; skipped otherwise.
///
///     source spec/fixtures/credentials.sh && swift test --filter LiveConformanceTests
final class LiveConformanceTests: XCTestCase {
    private var baseURL = ""
    private var apiKey = ""
    private var c: OpensmsClient!
    private let run = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
    /// CONFORMANCE.md uses +254700000012, but the server caps each destination
    /// at 5 messages per hour and 20 per day (`internal/messages/rate_limits.go`)
    /// and every SDK suite shares one workspace, so each run sends to its own
    /// random Safaricom (+25470...) numbers instead.
    private let sandboxTo = "+25470" + (0..<7).map { _ in String(Int.random(in: 0...9)) }.joined()
    private let sandboxTo2 = "+25470" + (0..<7).map { _ in String(Int.random(in: 0...9)) }.joined()
    private let sandboxTo3 = "+25470" + (0..<7).map { _ in String(Int.random(in: 0...9)) }.joined()

    // State shared between steps.
    private var messageId = ""
    private var contactId = ""
    private var groupId = ""
    private var emptyGroupId = ""

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["OPENSMS_BASE_URL"], !base.isEmpty,
              let key = env["OPENSMS_API_KEY"], !key.isEmpty else {
            throw XCTSkip("OPENSMS_BASE_URL and OPENSMS_API_KEY are not set; live conformance skipped.")
        }
        baseURL = base
        apiKey = key
        c = try OpensmsClient(apiKey: key, baseURL: base, timeout: 60)
    }

    // MARK: Helpers

    private func randomPhone() -> String {
        "+25470" + (0..<7).map { _ in String(Int.random(in: 0...9)) }.joined()
    }

    /// Run one step; a thrown error fails the step but the scenario continues.
    private func step(_ name: String, _ body: () async throws -> Void) async {
        do {
            try await body()
        } catch {
            XCTFail("step \(name) threw: \(error)")
        }
    }

    /// Assert that `block` throws an OpensmsError with `status` and exactly `detail`.
    @discardableResult
    private func expectErr(
        _ status: Int, _ detail: String?, file: StaticString = #filePath, line: UInt = #line,
        _ block: () async throws -> Void
    ) async -> OpensmsError? {
        do {
            try await block()
            XCTFail("expected ERR(\(status), \(detail ?? "-")) but the call succeeded", file: file, line: line)
            return nil
        } catch let error as OpensmsError {
            XCTAssertEqual(error.status, status, "status for \(detail ?? "-"): \(error)", file: file, line: line)
            if let detail { XCTAssertEqual(error.detail, detail, file: file, line: line) }
            return error
        } catch {
            XCTFail("expected OpensmsError, got \(error)", file: file, line: line)
            return nil
        }
    }

    /// Poll `probe` until it returns a value or the deadline passes.
    private func poll<T>(_ seconds: TimeInterval, _ probe: () async throws -> T?) async throws -> T? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let value = try await probe() { return value }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        return nil
    }

    private func isUUID(_ s: String?) -> Bool { s.flatMap(UUID.init(uuidString:)) != nil }

    // MARK: Scenario

    func testLiveScenario() async throws {
        await step("1 constructor") {
            XCTAssertThrowsError(try OpensmsClient(apiKey: "not_a_key", baseURL: baseURL)) { XCTAssertTrue($0 is OpensmsArgumentError) }
            XCTAssertThrowsError(try OpensmsClient(apiKey: "sk_test_short", baseURL: baseURL)) { XCTAssertTrue($0 is OpensmsArgumentError) }
        }

        await step("2 auth error") {
            let recorder = LiveSleepRecorder()
            let bad = try OpensmsClient(apiKey: "sk_test_" + String(repeating: "A", count: 32), baseURL: baseURL, timeout: 60, sleeper: recorder.sleeper)
            let err = await expectErr(401, "missing or invalid API key") { _ = try await bad.messages.list(.init(limit: 1)) }
            XCTAssertEqual(err?.type, "about:blank")
            XCTAssertEqual(err?.title, "Unauthorized")
            XCTAssertNil(err?.code)
            XCTAssertEqual(recorder.count, 0, "a 401 must not be retried")
        }

        await step("3 send") {
            let m = try await c.messages.send(.init(to: sandboxTo, text: "conformance swift \(run)", metadata: ["sdk": "swift", "run": .string(run)]))
            XCTAssertTrue(isUUID(m.id))
            XCTAssertEqual(m.to, sandboxTo)
            XCTAssertEqual(m.senderId, "OPENSMS")
            XCTAssertEqual(m.trafficType, "transactional")
            XCTAssertTrue(["queued", "sending", "sent", "delivered"].contains(m.status ?? ""), "status \(m.status ?? "nil")")
            XCTAssertEqual(m.parts, 1)
            XCTAssertEqual(m.encoding, "gsm7")
            XCTAssertEqual(m.countryIso2, "KE")
            XCTAssertEqual(m.currency, "KES")
            XCTAssertEqual(m.price, "0.000000")
            XCTAssertEqual(m.metadata?["run"]?.stringValue, run)
            messageId = m.id
        }

        await step("4 idempotent replay") {
            let key = UUID().uuidString.lowercased()
            let p = SendMessageParams(to: sandboxTo, text: "idem swift \(run)")
            let a = try await c.messages.send(p, idempotencyKey: key)
            let b = try await c.messages.send(p, idempotencyKey: key)
            XCTAssertEqual(a.id, b.id)
            await expectErr(409, "Idempotency-Key was already used with a different request") {
                _ = try await c.messages.send(SendMessageParams(to: sandboxTo, text: "idem swift \(run) changed"), idempotencyKey: key)
            }
        }

        await step("5 get and wait") {
            let delivered = try await poll(30) { () -> Message? in
                let m = try await c.messages.get(messageId)
                return m.status == "delivered" ? m : nil
            }
            let m = try XCTUnwrap(delivered, "message never reached delivered")
            XCTAssertNotNil(m.deliveredAt)
            XCTAssertNotNil(m.sentAt)
            XCTAssertEqual(m.text, "conformance swift \(run)")
        }

        await step("6 list and cursor") {
            let first = try await c.messages.list(.init(limit: 1))
            XCTAssertEqual(first.items.count, 1)
            let cursor = try XCTUnwrap(first.nextCursor)
            let second = try await c.messages.list(.init(limit: 1, cursor: cursor))
            XCTAssertEqual(second.items.count, 1)
            XCTAssertNotEqual(second.items.first?.id, first.items.first?.id)
            await expectErr(400, "invalid cursor") { _ = try await c.messages.list(.init(limit: 1, cursor: "garbage")) }
            await expectErr(400, "invalid status") { _ = try await c.messages.list(.init(status: "bogus")) }
            var seen = 0
            for try await _ in c.paginate(c.messages.list, ListMessagesParams(limit: 2)) {
                seen += 1
                if seen == 3 { break }
            }
            XCTAssertEqual(seen, 3)
        }

        await step("7 attempts") {
            let attempts = try await c.messages.attempts(messageId)
            let first = try XCTUnwrap(attempts.first)
            XCTAssertEqual(first.sequence, 1)
            XCTAssertTrue(first.routeName?.hasPrefix("Mock provider (sandbox)") ?? false, "route \(first.routeName ?? "nil")")
            XCTAssertEqual(first.status, "delivered")
            XCTAssertEqual(first.price, "0.000000")
        }

        await step("8 validation error") {
            let recorder = LiveSleepRecorder()
            let client = try OpensmsClient(apiKey: apiKey, baseURL: baseURL, timeout: 60, sleeper: recorder.sleeper)
            let err = await expectErr(400, "to must be an E.164 phone number") { _ = try await client.messages.send(.init(to: "12345", text: "x")) }
            XCTAssertEqual(err?.title, "Bad Request")
            XCTAssertEqual(err?.type, "about:blank")
            XCTAssertEqual(recorder.count, 0)
        }

        await step("9 coded error") {
            let err = await expectErr(400, "Message ID must be a valid UUID.") { _ = try await c.messages.get("not-a-uuid") }
            XCTAssertEqual(err?.code, "invalid_message_id")
            XCTAssertEqual(err?.type, "https://api.opensms.io/problems/invalid_message_id")
        }

        await step("10 not found") {
            await expectErr(404, "message not found") { _ = try await c.messages.get("00000000-0000-0000-0000-000000000000") }
        }

        await step("11 schedule and cancel") {
            let m = try await c.messages.send(.init(to: sandboxTo, text: "scheduled \(run)", scheduledAt: .date(Date().addingTimeInterval(7200))))
            XCTAssertEqual(m.status, "scheduled")
            let cancelled = try await c.messages.cancel(m.id)
            XCTAssertEqual(cancelled.status, "cancelled")
            XCTAssertNotNil(cancelled.cancelledAt)
            await expectErr(409, "message cannot be cancelled in its current state") { _ = try await c.messages.cancel(m.id) }
            await expectErr(409, "message cannot be cancelled in its current state") { _ = try await c.messages.cancel(messageId) }
        }

        await step("12 batch") {
            let batch = try await c.batches.create(.init(items: [
                .init(to: sandboxTo, text: "b1 \(run)"),
                .init(to: sandboxTo2, text: "b2 \(run)"),
                .init(to: "bad", text: "x")
            ]))
            XCTAssertEqual(batch.status, "ready")
            XCTAssertEqual(batch.total, 3)
            XCTAssertEqual(batch.invalid, 1)
            XCTAssertEqual(batch.sent, 0)
            let report = try await c.batches.validation(batch.id)
            XCTAssertEqual(report.rows?.count, 3)
            XCTAssertEqual(report.valid, 2)
            XCTAssertEqual(report.rows?[2].valid, false)
            XCTAssertEqual(report.rows?[2].error, "to must be an E.164 phone number")
            let again = try await c.batches.get(batch.id)
            XCTAssertEqual(again.total, 3)
            XCTAssertEqual(again.invalid, 1)
            let started = try await c.batches.start(batch.id)
            XCTAssertEqual(started.status, "running")
            let items = try await poll(30) { () -> [Message]? in
                let page = try await c.batches.listItems(batch.id)
                return page.items.count >= 2 ? page.items : nil
            }
            let list = try XCTUnwrap(items, "batch items never appeared")
            XCTAssertEqual(list.count, 2)
            for item in list {
                XCTAssertNotNil(item.to)
                XCTAssertNotNil(item.status)
            }
        }

        await step("13 batch stop") {
            let batch = try await c.batches.create(.init(items: [.init(to: sandboxTo, text: "stop \(run)")]))
            let stopped = try await c.batches.stop(batch.id)
            XCTAssertEqual(stopped.id, batch.id)
            XCTAssertEqual(stopped.status, "stopped")
            XCTAssertEqual(stopped.cancelled, 0)
            await expectErr(409, "batch is not ready to start") { _ = try await c.batches.start(batch.id) }
            await expectErr(404, "batch not found") { _ = try await c.batches.get("00000000-0000-0000-0000-000000000000") }
        }

        await step("14 csv batch") {
            let batch = try await c.batches.createFromCsv("to,text\n\(sandboxTo3),csv \(run)\n")
            XCTAssertEqual(batch.status, "ready")
            XCTAssertEqual(batch.total, 1)
            XCTAssertEqual(batch.invalid, 0)
        }

        await step("15 otp") {
            // A per-run destination keeps parallel SDK runs from reading each other's codes.
            let to = randomPhone()
            let sentAfter = Date().addingTimeInterval(-5)
            let sent = try await c.otp.send(.init(to: to, length: 6, ttlSeconds: 300))
            XCTAssertTrue(isUUID(sent.otpId))
            let regex = try NSRegularExpression(pattern: "Your OpenSMS verification code is (\\d{6})")
            let code = try await poll(30) { () -> String? in
                let page = try await c.sandbox.listMessages(.init(limit: 10))
                for m in page.items where m.trafficType == "otp" && m.to == to && (m.createdAt ?? .distantPast) >= sentAfter {
                    let text = m.text ?? ""
                    if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                       let r = Range(match.range(at: 1), in: text) {
                        return String(text[r])
                    }
                }
                return nil
            }
            let c6 = try XCTUnwrap(code, "OTP code never appeared in the sandbox")
            let wrong = String((Int(c6)! + 1) % 1_000_000).leftPad(6)
            let bad = try await c.otp.verify(otpId: sent.otpId, code: wrong)
            XCTAssertEqual(bad.valid, false)
            XCTAssertEqual(bad.attemptsLeft, 4)
            let good = try await c.otp.verify(otpId: sent.otpId, code: c6)
            XCTAssertEqual(good.valid, true)
            XCTAssertEqual(good.attemptsLeft, 3)
            await expectErr(400, "template must contain {{code}}") { _ = try await c.otp.send(.init(to: sandboxTo, template: "no placeholder")) }
            await expectErr(404, "OTP not found") { _ = try await c.otp.verify(otpId: "00000000-0000-0000-0000-000000000000", code: "123456") }
        }

        await step("16 lookup") {
            let l = try await c.lookups.create(to: sandboxTo)
            XCTAssertEqual(l.state, "completed")
            XCTAssertEqual(l.country, "KE")
            XCTAssertEqual(l.source, "mock")
            XCTAssertEqual(l.price, "0.000000")
            let again = try await c.lookups.get(l.id)
            XCTAssertEqual(again.id, l.id)
            XCTAssertEqual(again.state, l.state)
            let err = await expectErr(404, "Lookup not found.") { _ = try await c.lookups.get("00000000-0000-0000-0000-000000000000") }
            XCTAssertEqual(err?.code, "not_found")
        }

        await step("17 contacts") {
            let r1 = randomPhone()
            let contact = try await c.contacts.create(e164: r1, name: "Ada \(run)", attributes: ["tier": "gold"])
            XCTAssertEqual(contact.e164, r1)
            contactId = contact.id
            let fetched = try await c.contacts.get(contact.id)
            XCTAssertEqual(fetched.id, contact.id)
            XCTAssertEqual(fetched.e164, r1)
            XCTAssertEqual(fetched.name, "Ada \(run)")
            let updated = try await c.contacts.update(contact.id, name: "Ada L \(run)")
            XCTAssertEqual(updated.name, "Ada L \(run)")
            XCTAssertEqual(updated.attributes?["tier"]?.stringValue, "gold")
            var found = false
            for try await item in c.paginate(c.contacts.list, ListParams(limit: 200)) where item.id == contact.id {
                found = true
                break
            }
            XCTAssertTrue(found, "contact not in list")
            await expectErr(409, "A record with this phone number or name already exists.") { _ = try await c.contacts.create(e164: r1) }
        }

        await step("18 contact groups") {
            let group = try await c.contactGroups.create(name: "grp \(run)", contactIds: [contactId])
            XCTAssertEqual(group.contactIds, [contactId])
            groupId = group.id
            let renamed = try await c.contactGroups.update(group.id, name: "grp2 \(run)")
            XCTAssertEqual(renamed.name, "grp2 \(run)")
            let fetched = try await c.contactGroups.get(group.id)
            XCTAssertEqual(fetched.name, "grp2 \(run)")
            let batch = try await c.contactGroups.send(group.id, .init(text: "Hi \(run)"))
            XCTAssertEqual(batch.status, "running")
            XCTAssertEqual(batch.total, 1)
            let empty = try await c.contactGroups.create(name: "empty \(run)")
            emptyGroupId = empty.id
            await expectErr(422, "Group must contain between 1 and 1000 contacts.") { _ = try await c.contactGroups.send(empty.id, .init(text: "Hi \(run)")) }
            _ = try await c.contactGroups.list(.init(limit: 5))
        }

        await step("19 templates") {
            let tpl = try await c.templates.create(name: "tpl-\(run)", body: "Hi {{name}}", trafficType: "transactional")
            XCTAssertEqual(tpl.variables, ["name"])
            let updated = try await c.templates.update(tpl.id, body: "Hello {{name}}")
            XCTAssertEqual(updated.body, "Hello {{name}}")
            XCTAssertEqual(updated.variables, ["name"])
            let v1 = try await c.templates.get(tpl.id)
            XCTAssertEqual(v1.name, "tpl-\(run)")
            _ = try await c.templates.list(.init(limit: 5))
            let batch = try await c.contactGroups.send(groupId, .init(templateId: tpl.id, variables: ["name": "Ada"]))
            XCTAssertEqual(batch.status, "running")
            try await c.templates.delete(tpl.id)
            try await c.contactGroups.delete(groupId)
            try await c.contactGroups.delete(emptyGroupId)
            try await c.contacts.delete(contactId)
            await expectErr(404, "Record not found.") { _ = try await c.contacts.get(contactId) }
        }

        await step("20 webhooks") {
            let hook = try await c.webhooks.create(url: "https://example.com/opensms/\(run)", events: ["message.delivered", "message.failed"])
            XCTAssertTrue(hook.secret?.hasPrefix("whsec_") ?? false)
            XCTAssertEqual(hook.enabled, true)
            let fetched = try await c.webhooks.get(hook.id)
            XCTAssertNil(fetched.secret)
            await expectErr(400, "url must be an HTTPS URL without credentials or fragment") {
                _ = try await c.webhooks.create(url: "http://example.com/x", events: ["message.delivered"])
            }
            let updated = try await c.webhooks.update(hook.id, url: "https://example.com/opensms/\(run)/v2", events: ["message.delivered"], enabled: true)
            XCTAssertEqual(updated.url, "https://example.com/opensms/\(run)/v2")
            XCTAssertEqual(updated.events, ["message.delivered"])
            _ = try await c.webhooks.list(.init(limit: 5))
            let ack = try await c.webhooks.test(hook.id)
            XCTAssertEqual(ack.status, "pending")
            let delivery = try await poll(30) { () -> WebhookDelivery? in
                try await c.webhooks.listDeliveries(hook.id).items.first { $0.event == "webhook.test" }
            }
            let d = try XCTUnwrap(delivery, "no webhook.test delivery")
            XCTAssertNotNil(d.generation)
            do {
                let replay = try await c.webhooks.replayDelivery(hook.id, deliveryId: d.id, generation: d.generation ?? 0, reason: "sdk conformance replay")
                XCTAssertNotNil(replay.status)
            } catch let error as OpensmsError {
                XCTAssertEqual(error.status, 409)
                XCTAssertEqual(error.detail, "Delivery state, lease or generation does not permit replay.")
            }
            try await c.webhooks.delete(hook.id)
            await expectErr(404, "webhook not found") { _ = try await c.webhooks.get(hook.id) }
        }

        await step("21 suppressions") {
            let r2 = randomPhone()
            let s = try await c.suppressions.create(e164: r2, reason: "manual")
            XCTAssertEqual(s.reason, "manual")
            let err = await expectErr(422, "destination is suppressed") { _ = try await c.messages.send(.init(to: r2, text: "x")) }
            XCTAssertFalse(err?.requestId?.isEmpty ?? true, "requestId missing")
            var found = false
            for try await item in c.paginate(c.suppressions.list, ListParams(limit: 200)) where item.e164 == r2 {
                found = true
                break
            }
            XCTAssertTrue(found, "suppression not listed")
            let imported = try await c.suppressions.import([.init(e164: randomPhone(), reason: "complaint")])
            XCTAssertEqual(imported.created, 1)
            XCTAssertEqual(imported.received, 1)
            try await c.suppressions.delete(s.id)
            await expectErr(404, "suppression not found") { try await c.suppressions.delete(s.id) }
        }

        await step("22 compliance") {
            let ke = try await c.compliance.getCountry("KE")
            XCTAssertEqual(ke.iso2, "KE")
            XCTAssertEqual(ke.dialCode, "+254")
            XCTAssertTrue(ke.stopKeywords?.contains("STOP") ?? false)
            await expectErr(404, "country not found") { _ = try await c.compliance.getCountry("ZZ") }
            let v2 = try await c.compliance.listCountries()
            XCTAssertTrue(v2.contains { $0.iso2 == "KE" })
            _ = try await c.compliance.listContentRules() // decoding enforces integer ids
        }

        await step("23 wallet") {
            let balances = try await c.wallet.balances()
            let first = try XCTUnwrap(balances.first)
            XCTAssertEqual(first.environment, "sandbox")
            XCTAssertEqual(first.currency, "KES")
            XCTAssertNotNil(first.balance.flatMap { Decimal(string: $0) })
            let v3 = try await c.wallet.ledger(limit: 1)
            XCTAssertEqual(v3.count, 1)
            await expectErr(400, "limit must be between 1 and 200") { _ = try await c.wallet.ledger(limit: 0) }
            await expectErr(422, "sandbox wallets cannot use payment providers") {
                _ = try await c.wallet.createTopup(.init(amount: "100", currency: "KES", channel: "card", email: "dev@opensms.test"))
            }
        }

        await step("24 pricing") {
            let prices = try await c.pricing.get(product: "sms", country: "KE")
            XCTAssertEqual(prices.currency, "KES")
            XCTAssertEqual(prices.product, "sms")
            XCTAssertTrue(prices.entries?.allSatisfy { $0.countryIso2 == "KE" } ?? false)
            await expectErr(400, "product must be sms, lookup, or number_monthly") { _ = try await c.pricing.get(product: "bogus") }
        }

        await step("25 analytics") {
            let overview = try await c.analytics.overview()
            XCTAssertEqual(overview.environment, "sandbox")
            XCTAssertEqual(overview.currency, "KES")
            XCTAssertNotNil(overview.sent)
            _ = try await c.analytics.overview(.init(range: "7d"))
            _ = try await c.analytics.byCountry()
            _ = try await c.analytics.byCarrier()
            _ = try await c.analytics.bySenderId()
            _ = try await c.analytics.timeseries()
        }

        await step("26 numbers and inbound") {
            _ = try await c.numbers.list()
            _ = try await c.numbers.available(country: "KE", kind: "long_code")
            await expectErr(422, "This operation requires the live environment.") { _ = try await c.numbers.assign(country: "KE", kind: "long_code") }
            let v4 = try await c.inbound.list()
            XCTAssertEqual(v4.items.count, 0)
        }

        await step("27 sender ids") {
            let list = try await c.senderIds.list()
            XCTAssertTrue(list.items.contains { $0.value == "OPENSMS" && $0.status == "approved" })
            let v5 = try await c.senderIds.check(value: "ACME", country: "KE")
            XCTAssertEqual(v5.valid, true)
            let v6 = try await c.senderIds.quote(countries: ["KE"])
            XCTAssertTrue(v6.quoteId?.hasPrefix("sq_") ?? false)
            _ = try await c.senderIds.listDocuments()
            let letters = (0..<4).map { _ in String("ABCDEFGHIJKLMNOPQRSTUVWXYZ".randomElement()!) }.joined()
            let draft = try await c.senderIds.createDraft(.init(
                source: "application", value: "SDK" + letters, kind: "alphanumeric", countries: ["KE"],
                useCase: "transactional", sampleMessage: "Your order shipped"
            ))
            XCTAssertEqual(draft.version, 1)
            XCTAssertEqual(draft.status, "active")
            let updated = try await c.senderIds.updateDraft(draft.id, .init(version: 1, sampleMessage: "Your order has shipped"))
            XCTAssertEqual(updated.version, 2)
            let v7 = try await c.senderIds.getDraft(draft.id)
            XCTAssertEqual(v7.sampleMessage, "Your order has shipped")
            _ = try await c.senderIds.listDrafts(.init(limit: 5))
            try await c.senderIds.deleteDraft(draft.id)
            await expectErr(404, "sender ID not found") { _ = try await c.senderIds.get("00000000-0000-0000-0000-000000000000") }
        }

        await step("28 countries") {
            let countries = try await c.countries.list()
            XCTAssertTrue(countries.contains { $0.iso2 == "KE" && $0.dialCode == "+254" })
            let v8 = try await c.countries.carriers("KE")
            XCTAssertFalse(v8.isEmpty)
            _ = try await c.countries.routes("KE")
            let v9 = try await c.countries.compliance("KE")
            XCTAssertEqual(v9.iso2, "KE")
        }

        await step("29 scope errors") {
            guard let readonly = ProcessInfo.processInfo.environment["OPENSMS_READONLY_API_KEY"], !readonly.isEmpty else { return }
            let ro = try OpensmsClient(apiKey: readonly, baseURL: baseURL, timeout: 60)
            await expectErr(401, "insufficient scope") { _ = try await ro.messages.send(.init(to: sandboxTo, text: "scope \(run)")) }
            await expectErr(403, "Insufficient API key scope.") { _ = try await ro.contacts.list() }
            let v10 = try await ro.messages.list(.init(limit: 1))
            XCTAssertLessThanOrEqual(v10.items.count, 1)
        }
    }
}

private final class LiveSleepRecorder {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    var sleeper: (TimeInterval) async throws -> Void { { [self] _ in bump() } }
    private func bump() { lock.lock(); defer { lock.unlock() }; n += 1 }
}

private extension String {
    func leftPad(_ width: Int) -> String {
        count >= width ? self : String(repeating: "0", count: width - count) + self
    }
}
