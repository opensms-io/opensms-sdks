# OpenSMS SDK - Conformance

Two suites every SDK ships: offline mock-transport unit tests and one ordered
live integration scenario. Expected values below were observed against the
isolated stack on 2026-09-24 with a sandbox (`sk_test_`) key whose workspace
has email verification approved.

## Environment

| Variable | Required | Meaning |
| --- | --- | --- |
| `OPENSMS_BASE_URL` | yes | e.g. `http://localhost:8080` for a local API |
| `OPENSMS_API_KEY` | yes | `sk_test_` key with every scope (see SURFACE.md "Scopes") |
| `OPENSMS_READONLY_API_KEY` | no | `sk_test_` key with only `messages:read`; enables step 29 |

Local runs: `source spec/fixtures/credentials.sh` (not committed) exports all
three. If `OPENSMS_BASE_URL` or `OPENSMS_API_KEY` is missing, the live suite
is **skipped**, never failed. The live suite must not create accounts or keys.

Sandbox facts the scenario relies on:

- The API admits at most 5 sends per destination per hour and 20 per day
  (`api/internal/messages` rate limits, answering `429 message rate limit
  exceeded` with a long Retry-After). So every live run picks its own
  destination: `DEST = "+25470" + 7 random digits` (and `DEST2` likewise for
  the second batch item). `+254700000012` below means DEST.
- Sends to a `+25470...` number resolve to KE / Safaricom, leave with sender
  `OPENSMS`, cost `"0.000000"` `KES`, and reach `delivered` through the mock
  provider in about a second.
- `sk_test_` keys cannot touch live-only operations (numbers writes, inbound
  reply, top-ups): those answer `422 This operation requires the live
  environment.` or `422 sandbox wallets cannot use payment providers`.
- The API host can be slow under load (Argon2 key verification on every
  request). Use a per-attempt timeout of at least 30 s in the live suite and
  poll with a deadline instead of fixed sleeps.

Use a per-run id `RUN` (8 random hex chars) in names and texts, and random
phone numbers of the form `+2547` + 8 random digits where uniqueness matters,
so parallel runs of different SDKs do not collide.

## Live scenario (run in this order)

Notation: `-> ERR(status, detail)` means the call raises OpensmsError with
that `status` and exactly that `detail`; `code` is null unless stated.

1. **Constructor** `new Client({apiKey: "not_a_key"})` fails locally with an
   argument error (no HTTP). `apiKey: "sk_test_short"` also fails.
2. **Auth error**: client with `apiKey = "sk_test_" + "A"*32`,
   `messages.list({limit: 1})` -> `ERR(401, "missing or invalid API key")`,
   `type == "about:blank"`, `title == "Unauthorized"`, `code == null`. Not
   retried (exactly one HTTP attempt if the SDK exposes a counter).
3. **Send**: `messages.send({to: "+254700000012", text: "conformance <lang> RUN", metadata: {sdk: "<lang>", run: RUN}})`
   returns a Message with: `id` a UUID, `to == "+254700000012"`,
   `sender_id == "OPENSMS"`, `traffic_type == "transactional"`,
   `status` in {`queued`, `sending`, `sent`, `delivered`}, `parts == 1`,
   `encoding == "gsm7"`, `country_iso2 == "KE"`, `currency == "KES"`,
   `price == "0.000000"`, `metadata.run == RUN`. Keep `id` as `M`.
4. **Idempotent replay**: `messages.send(P, {idempotencyKey: K})` twice with
   the same params `P` and a fresh key `K` returns the same `id` both times.
   Then `messages.send(P2, {idempotencyKey: K})` with a different `text` ->
   `ERR(409, "Idempotency-Key was already used with a different request")`.
5. **Get and wait**: poll `messages.get(M)` (deadline 20 s) until
   `status == "delivered"`; then `delivered_at` and `sent_at` are set and
   `text` equals what was sent.
6. **List + cursor**: `messages.list({limit: 1})` returns exactly 1 item and a
   non-null `nextCursor`; `messages.list({limit: 1, cursor: nextCursor})`
   returns 1 item with a different `id`. `messages.list({limit: 1, cursor: "garbage"})`
   -> `ERR(400, "invalid cursor")`. `messages.list({status: "bogus"})` ->
   `ERR(400, "invalid status")`. The pagination helper over
   `messages.list({limit: 2})` yields at least 3 items without error (stop
   after 3).
7. **Attempts**: `messages.attempts(M)` returns an array with at least one
   item; the first has `sequence == 1`, `route_name` starting with
   `"Mock provider (sandbox)"`, `status == "delivered"`, `price == "0.000000"`.
8. **Validation error**: `messages.send({to: "12345", text: "x"})` ->
   `ERR(400, "to must be an E.164 phone number")`, `title == "Bad Request"`,
   `type == "about:blank"`. Not retried.
9. **Coded error**: `messages.get("not-a-uuid")` -> `ERR(400, "Message ID must be a valid UUID.")`
   with `code == "invalid_message_id"` and
   `type == "https://api.opensms.io/problems/invalid_message_id"`.
10. **Not found**: `messages.get("00000000-0000-0000-0000-000000000000")` ->
    `ERR(404, "message not found")`.
11. **Schedule and cancel**: `messages.send({to: "+254700000012", text: "scheduled RUN", scheduledAt: now + 2h})`
    returns 201 with `status == "scheduled"`; `messages.cancel(id)` returns the Message with
    `status == "cancelled"` and non-null `cancelled_at`; a second
    `messages.cancel(id)` -> `ERR(409, "message cannot be cancelled in its current state")`.
    Cancelling the delivered `M` also returns that 409.
12. **Batch**: `batches.create({items: [{to: "+254700000012", text: "b1 RUN"}, {to: "+254700000013", text: "b2 RUN"}, {to: "bad", text: "x"}]})`
    -> Batch with `status == "ready"`, `total == 3`, `invalid == 1`,
    `sent == 0`. `batches.validation(id)` -> `rows` of length 3, `valid == 2`,
    `rows[2].valid == false`, `rows[2].error == "to must be an E.164 phone number"`.
    `batches.get(id)` echoes the same counts. `batches.start(id)` ->
    `status == "running"`. Poll `batches.listItems(id)` (deadline 20 s) until
    it returns 2 items; each has `to` and `status`.
13. **Batch stop**: create a second batch with one valid item, then
    `batches.stop(id)` before starting it -> `{id, status: "stopped", cancelled: 0}`;
    `batches.start(id)` afterwards -> `ERR(409, "batch is not ready to start")`. `batches.get("00000000-0000-0000-0000-000000000000")`
    -> `ERR(404, "batch not found")`.
14. **CSV batch**: `batches.createFromCsv("to,text\n+254700000014,csv RUN\n")`
    -> `status == "ready"`, `total == 1`, `invalid == 0`.
15. **OTP**: `otp.send({to: "+254700000012", length: 6, ttlSeconds: 300})` ->
    `{otpId}` (UUID). Poll `sandbox.listMessages({limit: 10})` (deadline 20 s)
    for an item with `traffic_type == "otp"` whose text matches
    `Your OpenSMS verification code is (\d{6})` and was created after the
    send; take the code `C`. `otp.verify({otpId, code: W})` with any 6-digit
    `W != C` -> `{valid: false, attemptsLeft: 4}`. `otp.verify({otpId, code: C})`
    -> `{valid: true, attemptsLeft: 3}`. `otp.send({to: "+254700000012", template: "no placeholder"})`
    -> `ERR(400, "template must contain {{code}}")`.
    `otp.verify({otpId: "00000000-0000-0000-0000-000000000000", code: "123456"})`
    -> `ERR(404, "OTP not found")`.
16. **Lookup**: `lookups.create({to: "+254700000012"})` -> `state == "completed"`,
    `country == "KE"`, `source == "mock"`, `price == "0.000000"`;
    `lookups.get(id)` returns the same `id` and `state`.
    `lookups.get("00000000-0000-0000-0000-000000000000")` ->
    `ERR(404, "Lookup not found.")` with `code == "not_found"`.
17. **Contacts**: `contacts.create({e164: R1, name: "Ada RUN", attributes: {tier: "gold"}})`
    (R1 random) -> 201 Contact with `e164 == R1`; `contacts.get(id)` equal;
    `contacts.update(id, {name: "Ada L RUN"})` -> `name == "Ada L RUN"`,
    `attributes.tier == "gold"` (PATCH keeps other fields);
    `contacts.list({limit: 200})` contains `id` (use the pagination helper).
    Creating R1 again (new Idempotency-Key) ->
    `ERR(409, "A record with this phone number or name already exists.")`.
18. **Contact groups**: `contactGroups.create({name: "grp RUN", contactIds: [contactId]})`
    -> `contact_ids == [contactId]`; `contactGroups.update(id, {name: "grp2 RUN"})`;
    `contactGroups.send(id, {text: "Hi RUN"})` -> Batch with
    `status == "running"` and `total == 1`. Sending to an empty group ->
    `ERR(422, "Group must contain between 1 and 1000 contacts.")`.
19. **Templates**: `templates.create({name: "tpl-RUN", body: "Hi {{name}}", trafficType: "transactional"})`
    -> `variables == ["name"]`; `templates.update(id, {body: "Hello {{name}}"})`
    -> `body == "Hello {{name}}"`, `variables == ["name"]`;
    `contactGroups.send(groupId, {templateId: id, variables: {name: "Ada"}})`
    -> Batch `status == "running"`. Then delete in order: template (204),
    group (204), contact (204). `contacts.get(contactId)` afterwards ->
    `ERR(404, "Record not found.")`.
20. **Webhooks**: `webhooks.create({url: "https://example.com/opensms/RUN", events: ["message.delivered", "message.failed"]})`
    -> `secret` starts with `whsec_`, `enabled == true`. `webhooks.get(id)` has
    no `secret`. `webhooks.create({url: "http://example.com/x", events: ["message.delivered"]})`
    -> `ERR(400, "url must be an HTTPS URL without credentials or fragment")`.
    `webhooks.update(id, {url: "https://example.com/opensms/RUN/v2", events: ["message.delivered"], enabled: true})`
    -> updated `url` and `events`. `webhooks.test(id)` -> `{status: "pending"}`.
    `webhooks.listDeliveries(id)` -> at least one item with
    `event == "webhook.test"`, integer `id` and `generation`.
    `webhooks.replayDelivery(id, deliveryId, {generation, reason: "sdk conformance replay"})`
    -> either `{status}` or `ERR(409, "Delivery state, lease or generation does not permit replay.")`
    (outbound delivery is disabled on this stack, so the delivery stays
    pending and 409 is what was observed). `webhooks.delete(id)` -> void;
    `webhooks.get(id)` -> `ERR(404, "webhook not found")`.
21. **Suppressions**: `suppressions.create({e164: R2, reason: "manual"})` ->
    integer `id`, `reason == "manual"`. `messages.send({to: R2, text: "x"})` ->
    `ERR(422, "destination is suppressed")` and `requestId` is a non-empty
    string (from `X-Request-ID`). `suppressions.list()` contains R2.
    `suppressions.import([{e164: R3, reason: "complaint"}])` ->
    `{created: 1, received: 1}`. `suppressions.delete(id)` -> void; deleting
    it again -> `ERR(404, "suppression not found")`.
22. **Compliance**: `compliance.getCountry("KE")` -> `iso2 == "KE"`,
    `dial_code == "+254"`, `stop_keywords` contains `"STOP"`;
    `compliance.getCountry("ZZ")` -> `ERR(404, "country not found")`;
    `compliance.listCountries()` contains KE; `compliance.listContentRules()`
    is an array whose items have integer `id`.
23. **Wallet**: `wallet.balances()` -> non-empty list, first has
    `environment == "sandbox"`, `currency == "KES"`, decimal-string `balance`.
    `wallet.ledger({limit: 1})` -> exactly 1 entry with integer `id`.
    `wallet.ledger({limit: 0})` -> `ERR(400, "limit must be between 1 and 200")`.
    `wallet.createTopup({amount: "100", currency: "KES", channel: "card", email: "dev@opensms.test"})`
    -> `ERR(422, "sandbox wallets cannot use payment providers")`.
24. **Pricing**: `pricing.get({product: "sms", country: "KE"})` ->
    `currency == "KES"`, `product == "sms"`, every entry has
    `country_iso2 == "KE"`. `pricing.get({product: "bogus"})` ->
    `ERR(400, "product must be sms, lookup, or number_monthly")`.
25. **Analytics**: `analytics.overview()` -> `environment == "sandbox"`,
    `currency == "KES"`, integer `sent`; `analytics.overview({range: "7d"})`
    ok; `byCountry`, `byCarrier`, `bySenderId`, `timeseries` return arrays.
    Do not assert counts (sandbox rollups are inconsistent, see SURFACE.md
    drift 12).
26. **Numbers and inbound**: `numbers.list()` -> Page (items may be empty);
    `numbers.available({country: "KE", kind: "long_code"})` -> array;
    `numbers.assign({country: "KE", kind: "long_code"})` ->
    `ERR(422, "This operation requires the live environment.")`;
    `inbound.list()` -> Page with `items == []`.
27. **Sender IDs**: `senderIds.list()` contains an item with
    `value == "OPENSMS"` and `status == "approved"`;
    `senderIds.check({value: "ACME", country: "KE"})` -> `valid == true`;
    `senderIds.quote({countries: ["KE"]})` -> `quote_id` starting with `sq_`;
    `senderIds.listDocuments()` -> list (may be empty);
    `senderIds.createDraft({source: "application", value: "SDK" + 4 random uppercase letters, kind: "alphanumeric", countries: ["KE"], useCase: "transactional", sampleMessage: "Your order shipped"})`
    -> `version == 1`, `status == "active"`;
    `senderIds.updateDraft(id, {version: 1, sampleMessage: "Your order has shipped"})`
    -> `version == 2`; `senderIds.getDraft(id)`; `senderIds.deleteDraft(id)` ->
    void. `senderIds.get("00000000-0000-0000-0000-000000000000")` ->
    `ERR(404, "sender ID not found")`.
28. **Countries**: `countries.list()` contains `iso2 == "KE"` with
    `dial_code == "+254"`; `countries.carriers("KE")` is non-empty;
    `countries.routes("KE")` is an array; `countries.compliance("KE")` has
    `iso2 == "KE"`.
29. **Scope errors** (only if `OPENSMS_READONLY_API_KEY` is set):
    `messages.send(...)` -> `ERR(401, "insufficient scope")`;
    `contacts.list()` -> `ERR(403, "Insufficient API key scope.")`;
    `messages.list({limit: 1})` succeeds.

The scenario leaves behind only sandbox messages, batches, one lookup, one
imported suppression (R3) and whatever a failed run did not clean up; all are
scoped to the sandbox environment of the test workspace.

## Mock-transport unit tests (offline, every SDK)

Each test drives the client through an injected transport that records
requests and returns canned responses; sleeping is replaced by an injected
zero-delay sleeper that records requested delays.

1. **Header injection**: any call sends `Authorization: Bearer <key>`,
   `Accept: application/json`, `User-Agent: opensms-<lang>/<version>`; JSON
   calls send `Content-Type: application/json`; no call sends
   `X-Workspace-ID` or `X-Environment`.
2. **Base URL**: default is `https://api.opensms.io`; a custom
   `baseUrl` with a trailing slash produces `http://host/v1/messages`
   (no double slash).
3. **Key validation**: missing key, `pk_test_x`, `sk_test_short` fail at
   construction; `sk_live_` + 32 chars and `sk_test_` + 32 chars succeed;
   `environment` is `live` and `sandbox` respectively.
4. **Body mapping**: `messages.send({to, text, senderId, trafficType, scheduledAt, callbackUrl, metadata})`
   produces exactly the snake_case keys `to, text, sender_id, traffic_type,
   scheduled_at, callback_url, metadata`; unset optionals are absent (not
   `null`).
5. **Idempotency-Key auto**: `messages.send` without an explicit key sends a
   36-character UUID `Idempotency-Key`; an explicit `idempotencyKey` is sent
   verbatim; `messages.get` sends none.
6. **Retry on 429 with Retry-After**: responses `429` (`Retry-After: 2`,
   problem body) then `201` -> call succeeds, 2 requests, the sleeper was
   asked for 2 s, and **both requests carry the same Idempotency-Key**.
7. **Retry on 503 without Retry-After**: `503` then `200` on a GET ->
   succeeds after 2 requests with a backoff delay in `[0, 0.5 s]`.
8. **Retries exhausted**: `maxRetries: 2` and three `500` responses ->
   OpensmsError `status == 500` after exactly 3 requests.
9. **Retry-After too large**: `429` with `Retry-After: 120` -> OpensmsError
   `status == 429`, `retryAfter == 120`, only 1 request.
10. **No retry on 400/401/404/409/422**: each returns an OpensmsError after 1
    request.
11. **No retry for non-idempotent POST**: `otp.verify` and `messages.cancel`
    receiving `503` fail after 1 request.
12. **Network error**: transport throws twice then succeeds on a GET ->
    success after 3 attempts; if it always throws -> OpensmsError
    `status == 0`.
13. **Error mapping**: body
    `{"type":"https://api.opensms.io/problems/invalid_message_id","title":"Bad Request","status":400,"detail":"Message ID must be a valid UUID.","code":"invalid_message_id","trace_id":"t1","errors":{"to":["bad"]}}`
    with `Content-Type: application/problem+json` -> `status 400`,
    `type`, `title`, `detail`, `code == "invalid_message_id"`,
    `traceId == "t1"`, `errors.to == ["bad"]`, message equals `detail`.
    An `about:blank` body without `code` -> `code` null. A `422` with header
    `X-Request-ID: r1` -> `requestId == "r1"`. A `502` with an HTML body ->
    `status 502`, null `detail`, raw text in `body`.
14. **204 handling**: `contacts.delete(id)` on `204` with an empty body
    returns void and does not try to parse JSON.
15. **Pagination**: pages `{items:[a,b], next_cursor:"c1"}`, then
    `{items:[c], next_cursor:null}` -> helper yields `a, b, c`; the second
    request carries `cursor=c1` and the same `limit`.
16. **Query encoding**: `senderIds.quote({countries: ["KE","NG"]})` sends
    `countries=KE,NG`; `messages.list({status: "delivered", to: "+2547"})`
    URL-encodes `+` as `%2B`; unset params are absent.
17. **Path escaping**: `messages.get("a/b")` requests `/v1/messages/a%2Fb`
    (never a different path).
18. **Webhook signature vector**: every row of the table in DESIGN.md
    "Webhook signature verification", with the injected `now`.
    `constructEvent` on the valid row returns an event with
    `type == "message.delivered"` and `data.status == "delivered"`; on the
    tampered row it raises OpensmsError with `code == "invalid_signature"`;
    on the `+301` row with `code == "expired_signature"`.
19. **Batch CSV**: `batches.createFromCsv(text)` sends `Content-Type: text/csv`
    and the raw text as the body, with an Idempotency-Key.
20. **Decimal strings**: a Message with `"price":"0.000000"` decodes with
    `price` still the string `"0.000000"`; unknown response fields are
    ignored.
