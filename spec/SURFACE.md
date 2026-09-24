# OpenSMS SDK - API-key Surface Contract

Single source of truth for what every OpenSMS SDK exposes. Extracted from the
API source (`api/cmd/opensms/main.go` route registration, each handler's
authentication function under `api/internal/**`, and the scope catalog served by
`GET /v1/keys/scopes`), then verified by calling every operation live with an
all-scope `sk_test_` key against the isolated stack on 2026-09-24. The
"Live" column is the status actually observed. `spec/openapi.json` is the
machine-readable contract (a JSON copy of `customer.openapi.yaml`); where the
two disagree this file wins and the difference is listed under **Drift**.

## Ground rules

- **Auth**: `Authorization: Bearer sk_test_...` or `sk_live_...`. A key is valid
  when it has one of those prefixes and more than 12 characters after it
  (`auth.ValidSecret`). The key alone selects the workspace and the
  environment (`sk_test_` = `sandbox`, `sk_live_` = `live`). SDKs never send
  `X-Workspace-ID` or `X-Environment`: batch and analytics reject them with
  `403` when they disagree with the key.
- **Base URL**: `https://api.opensms.io` (see DESIGN.md for the evidence).
- **Content**: JSON in, JSON out. Errors are `application/problem+json`
  (RFC 9457), see **Errors** below.
- **Unknown request fields are rejected** (`DisallowUnknownFields` in almost
  every handler, `400 invalid JSON`). SDKs must only send documented fields and
  must omit unset optionals rather than send `null`.
- **Idempotency-Key**: required on most POSTs (table column "Idem"). Two
  length limits exist: `<=255` (messages, batches, otp) and `<=200`
  (everything else). SDKs send a UUIDv4 (36 chars) unless the caller supplies
  one. Reusing a key with the same body replays the stored response with the
  original status; reusing it with a different body returns `409`.
- **Rate limit**: every API-key request passes a per-key RPS guard
  (`internal/ratelimit/http.go`, workspace `key_rps_limit`, 50 on this stack).
  Over the limit: `429` with `Retry-After: <seconds>`. Message admission and
  OTP verify have their own `429` + `Retry-After`. Not triggered live (80
  parallel requests all returned 200; Argon2 key verification throttles the
  client first), so the 429 behaviour is covered by mock-transport tests.
- **Pagination**: cursor based. Query `limit` and `cursor`; response
  `{ "items": [...], "next_cursor": string|null }`. Pass `next_cursor` back as
  `cursor` until it is `null`. Limits: messages `1..100` (default 20), all
  other cursor lists `1..200` (default 50). Exception: wallet ledger (see
  wallet). Several lists return a bare array with no paging (marked "array").
- **Money** is always a decimal string (`"0.000000"`), never a float. SDKs keep
  it a string.
- **Timestamps** are RFC 3339 strings with a numeric offset (the API mixes
  `+03:00` and `+00:00`); SDKs parse them as instants or keep them as strings.
- **IDs** are UUID strings except: webhook delivery `id` (int64), suppression
  `id` (int), content rule `id` (int), attempt `id` (int64), ledger entry `id`
  (int64).

## Errors

Every non-2xx body observed was problem+json with this shape
(`internal/httpx/problempb/problem.go`):

```json
{"type":"about:blank","title":"Bad Request","status":400,"detail":"to must be an E.164 phone number"}
{"type":"https://api.opensms.io/problems/invalid_message_id","title":"Bad Request","status":400,"detail":"Message ID must be a valid UUID.","code":"invalid_message_id"}
```

Fields: `type` (string), `title` (string), `status` (int), `detail` (string),
optional `code` (string), optional `trace_id` (string), optional `errors`
(`map<string, string[]>`, field validation). Most errors have **no `code`**
(`type` is `about:blank`); the only codes the key-callable handlers can emit are
`invalid_message_id`, `not_found`, `bad_request`, `temporarily_unavailable`
(messages get), `spend_cap_reached` and `fee_spend_fx_unavailable` (numbers).
Rate limiting (429), insufficient scope and admission rejections carry no
code. SDKs therefore branch on
`status` first and treat `code` as optional.

Headers worth surfacing on errors: `Retry-After` (429, some 503) and
`X-Request-ID` (set only on message and OTP admission rejections, for example
`422 destination is suppressed`; it is the rejection record id support can look
up).

Status meaning on the key surface:

| Status | When (observed detail strings) |
| --- | --- |
| 400 | validation (`invalid JSON`, `to must be an E.164 phone number`, `invalid cursor`, missing Idempotency-Key) |
| 401 | bad or missing key (`missing or invalid API key`); also **insufficient scope on messages and otp** (`insufficient scope`) |
| 402 | insufficient balance or spend cap (live) |
| 403 | insufficient scope everywhere else; sandbox send before email verification (`email verification is required for sandbox sending`); workspace not live |
| 404 | unknown id (`message not found`, `batch not found`, ...) |
| 409 | Idempotency-Key reused with a different body; illegal state change (`message cannot be cancelled in its current state`) |
| 410 | webhook or group-send snapshot expired |
| 413 | upload too large |
| 422 | business rule (`destination is suppressed`, `This operation requires the live environment.`, `sandbox wallets cannot use payment providers`) |
| 429 | rate limited, with `Retry-After` |
| 5xx | `database unavailable`, `rate limiter unavailable`, `503 temporarily_unavailable` |

## Scopes

All scopes from `GET /v1/keys/scopes` (owner role): `analytics:read`,
`compliance:manage`, `compliance:read`, `contacts:manage`, `keys:admin`,
`lookup:read`, `lookup:request`, `messages:read`, `messages:write`,
`numbers:manage`, `numbers:read`, `pricing:read`, `realtime:read`,
`sender-ids:read`, `sender-ids:write`, `senders:manage`, `templates:manage`,
`wallet:read`, `wallet:topup`, `wallet:write`, `webhooks:manage`,
`webhooks:read`, `webhooks:write`. `*` also satisfies any check. Implications
in code: `webhooks:manage` covers read and write, `webhooks:write` covers read;
`senders:manage` covers sender-ids read and write, `sender-ids:write` covers
read; `wallet:topup` satisfies `wallet:write`. `keys:admin` gates nothing a key
can call (key management is session only). A new key with no scopes gets
`messages:read` + `messages:write`.

## Legend

`Idem`: **req** = Idempotency-Key required (SDK always sends one), **opt** =
honoured when sent, **-** = ignored. `Retry`: whether the SDK may auto-retry
on 429/5xx/network error (see DESIGN.md). `Live`: statuses observed with a
sandbox key.

---

## messages (5)

Message object (`internal/messages/http.go` `Message`): `id` uuid, `created_at`,
`to` E.164, `sender_id` string, `text` string (omitted when empty), `parts` int,
`status` enum `queued|scheduled|held|sending|sent|delivered|failed|cancelled|expired`,
`status_reason?` string, `sent_at?`, `delivered_at?`, `failed_at?`,
`cancelled_at` datetime|null, `scheduled_at?`, `price?` decimal string,
`currency?` string, `traffic_type` `otp|transactional|marketing`,
`metadata` object|null, `encoding` `gsm7|ucs2`, `country_id|country_iso2|country_name`
string|null, `carrier_id|carrier_name` string|null, `destination_source`
`prefix|hlr|unknown`, `billing?` array (present on get/list, absent on create).

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `send(params)` | `POST /v1/messages` -> 201 Message | messages:write | req (<=255) | yes | 201, 400, 401, 403, 409, 422 |
| `list(params?)` | `GET /v1/messages` -> 200 Page<Message> | messages:read | - | yes | 200, 400 |
| `get(id)` | `GET /v1/messages/{id}` -> 200 Message | messages:read | - | yes | 200, 400 (`invalid_message_id`), 404 |
| `attempts(id)` | `GET /v1/messages/{id}/attempts` -> 200 Attempt[] (array) | messages:read | - | yes | 200, 404 |
| `cancel(id)` | `POST /v1/messages/{id}/cancel` -> 200 Message | messages:write | - | no | 200, 404, 409 |

`send` body: `to` string E.164 (req, `^\+[1-9][0-9]{7,14}$`), `text` string
(req, 1..1600 chars), `sender_id?` string (<=11 chars, or <=15 digits),
`traffic_type?` `otp|transactional|marketing` (default `transactional`),
`scheduled_at?` RFC 3339, `callback_url?` string, `metadata?` JSON object.
Sandbox sends always leave as `sender_id` `OPENSMS` and cost `0.000000`.

`list` query: `limit` 1..100 (default 20), `cursor`, `status` (enum above),
`to` (digits or `+digits` fragment), `country` (uppercase ISO2), `date_from`,
`date_to` (`YYYY-MM-DD` or RFC 3339; date-only `date_to` is inclusive). Each
key may appear once (duplicate -> 400).

Attempt: `id` int64, `sequence` int, `route_id` uuid, `route_name` string,
`price` string|null, `currency` string|null, `provider?`, `provider_message_id?`,
`status` `submitting|submission_unknown|submitted|not_accepted|delivered|failed|expired`,
`error_code?`, `submitted_at`, `dlr_at?`, `submit_latency_ms?` int,
`dlr_latency_ms?` int.

`cancel` only succeeds for `queued` or `scheduled` messages
(`TransitionService.Cancel`); anything else, for example `delivered`, returns
`409`. Sandbox messages usually reach `delivered` within a second, so only a
scheduled message is reliably cancellable.

## batches (6)

Batch: `id`, `status` (`ready|running|stopped|completed|failed`), `total`, `sent`,
`delivered`, `failed`, `invalid`, `duplicates`, `suppressed` (ints),
`estimated_cost` number|null, `created_at`, `completed_at?`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `create(params)` | `POST /v1/messages/batch` -> 202 Batch | messages:write | req (<=255) | yes | 202, 403 |
| `createFromCsv(csv, {dedupe?})` | `POST /v1/messages/batch` `text/csv` body -> 202 Batch | messages:write | req | yes | 202 |
| `get(id)` | `GET /v1/batches/{id}` -> 200 Batch | messages:read | - | yes | 200, 404 |
| `validation(id)` | `GET /v1/batches/{id}/validation` -> 200 Report | messages:read | - | yes | 200, 404 |
| `start(id)` | `POST /v1/batches/{id}/start` -> 200 Batch | messages:write | req (<=255) | yes | 200, 400, 409 (not ready) |
| `stop(id)` | `POST /v1/batches/{id}/stop` -> 200 `{id, status:"stopped", cancelled:int}` | messages:write | req (<=255) | yes | 200, 400 |
| `listItems(id, {status?, limit?, cursor?})` | `GET /v1/batches/{id}/items` -> 200 Page<BatchItem> | messages:read | - | yes | 200 |

(`createFromCsv` is a second entry point to the same operation and is not
counted separately.)

`create` JSON body: `{ items: BatchItemInput[] (req, 1..MaxItems), dedupe?: bool (default true) }`.
BatchItemInput: `to` (req), `text` (req), `sender_id?`, `traffic_type?`,
`callback_url?`, `metadata?` object. Invalid rows do not fail the request; they
are counted in `invalid` and listed by `validation`. CSV: header row
`to,text[,sender_id,...]`, `Content-Type: text/csv`. The batch is created in
`ready` and sends nothing until `start`.

Report: `{ rows: [{row:int, item:BatchItemInput, valid:bool, duplicate?:bool, suppressed?:bool, error?:string}], total, valid, invalid, duplicates, suppressed }`.

BatchItem (live, slimmer than Message): `id`, `created_at`, `to`, `text`,
`sender_id`, `parts`, `status`, `traffic_type`, `metadata`. SDKs model it as
Message with all fields optional.

## otp (2)

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `send(params)` | `POST /v1/otp/send` -> 201 `{otp_id}` | messages:write | req (<=255) | yes | 201, 400, 401 |
| `verify({otpId, code})` | `POST /v1/otp/verify` -> 200 `{valid:bool, attempts_left:int}` | messages:write | - | **no** | 200, 404 |

`send` body: `to` E.164 (req), `sender_id?`, `template?` string that must
contain `{{code}}` (default `Your OpenSMS verification code is {{code}}`),
`length?` 4..10 (default 6), `ttl_seconds?` 30..86400 (default 600).
`verify` body: `otp_id` uuid, `code` string 4..10. A wrong code returns
`200 {"valid":false}` and burns an attempt (max 5), so verify is never retried.
In sandbox the code can be read back from `sandbox.listMessages()` text.

## lookups (2)

Lookup: `id`, `state` `queued|submitting|unknown|completed|failed`, `country`,
`carrier` string|null, `ported` bool|null, `valid` bool|null, `source`
string|null (`prefix|hlr|mock`), `price` decimal string, `currency`,
`checked_at` datetime|null.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `create({to})` | `POST /v1/lookup` -> 200 (completed) or 202 (pending) Lookup | lookup:request | req (<=200) | yes | 200, 400, 403 |
| `get(id)` | `GET /v1/lookup/{id}` -> 200 Lookup | lookup:read | - | yes | 200, 404 (`not_found`) |

## contacts (5)

Contact: `id`, `workspace_id`, `e164`, `name` string|null, `attributes` object,
`created_at`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/contacts` -> 200 Page<Contact> | contacts:manage | - | yes | 200, 403 |
| `create({e164, name?, attributes?})` | `POST /v1/contacts` -> 201 Contact | contacts:manage | req (<=200) | yes | 201, 400, 409 (duplicate e164) |
| `get(id)` | `GET /v1/contacts/{id}` -> 200 Contact | contacts:manage | - | yes | 200, 404 |
| `update(id, {e164?, name?, attributes?})` | `PATCH /v1/contacts/{id}` -> 200 Contact | contacts:manage | - | yes | 200 |
| `delete(id)` | `DELETE /v1/contacts/{id}` -> 204 | contacts:manage | - | yes | 204 |

## contactGroups (6)

Group: `id`, `workspace_id`, `name`, `contact_ids` uuid[], `created_at`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/contact-groups` -> 200 Page<Group> | contacts:manage | - | yes | 200 |
| `create({name, contactIds?})` | `POST /v1/contact-groups` -> 201 Group | contacts:manage | req (<=200) | yes | 201 |
| `get(id)` | `GET /v1/contact-groups/{id}` -> 200 Group | contacts:manage | - | yes | 200 |
| `update(id, {name?, contactIds?})` | `PATCH /v1/contact-groups/{id}` -> 200 Group | contacts:manage | - | yes | 200 |
| `delete(id)` | `DELETE /v1/contact-groups/{id}` -> 204 | contacts:manage | - | yes | 204 |
| `send(id, params)` | `POST /v1/contact-groups/{id}/send` -> 200 Batch | contacts:manage + messages:write (+ templates:manage with template_id) | req (<=200) | yes | 200, 400, 422 (empty group) |

`send` body: `text?` or `template_id?` (one of them), `variables?`
map<string,string>, `sender_id?`, `traffic_type?`, `callback_url?`. The result
is a Batch already `running`.

## templates (5)

Template: `id`, `workspace_id`, `name`, `body`, `traffic_type`, `created_at`,
`updated_at`, `variables` string[] (parsed `{{name}}` placeholders).

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/templates` -> 200 Page<Template> | templates:manage | - | yes | 200, 403 |
| `create({name, body, trafficType?})` | `POST /v1/templates` -> 201 Template | templates:manage | req (<=200) | yes | 201, 400, 409 (duplicate name) |
| `get(id)` | `GET /v1/templates/{id}` -> 200 Template | templates:manage | - | yes | 200, 404 |
| `update(id, {name?, body?, trafficType?})` | `PATCH /v1/templates/{id}` -> 200 Template | templates:manage | - | yes | 200 |
| `delete(id)` | `DELETE /v1/templates/{id}` -> 204 | templates:manage | - | yes | 204 |

## webhooks (8)

Endpoint: `id`, `url`, `events` string[], `enabled` bool,
`consecutive_failures` int, `disabled_at?`, `created_at`, `secret?` (only in the
create response, format `whsec_<base64url>`; shown once).
Delivery: `id` int64, `generation` int, `event`, `payload` any, `attempts` int,
`next_retry_at?`, `status` (`pending|delivered|failed|...`), `last_response_code?`,
`last_error?`, `created_at`, `delivered_at?`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/webhooks` -> 200 Page<Endpoint> | webhooks:read | - | yes | 200, 403 |
| `create({url, events, enabled?})` | `POST /v1/webhooks` -> 201 Endpoint (+secret) | webhooks:write | req (<=200) | yes | 201, 400 |
| `get(id)` | `GET /v1/webhooks/{id}` -> 200 Endpoint | webhooks:read | - | yes | 200, 404 |
| `update(id, {url, events, enabled})` | `PUT /v1/webhooks/{id}` -> 200 Endpoint | webhooks:write | opt | yes | 200 |
| `delete(id)` | `DELETE /v1/webhooks/{id}` -> 204 | webhooks:write | opt | yes | 204 |
| `test(id)` | `POST /v1/webhooks/{id}/test` -> 202 `{status}` | webhooks:write | req (<=200) | yes | 202, 404 |
| `listDeliveries(id, {limit?, cursor?})` | `GET /v1/webhooks/{id}/deliveries` -> 200 Page<Delivery> | webhooks:read | - | yes | 200 |
| `replayDelivery(id, deliveryId, {generation, reason})` | `POST /v1/webhooks/{id}/deliveries/{delivery_id}/replay` -> 202 `{status}` | webhooks:write | req (<=200) | yes | 404, 409 |

`url` must be `https://`, no credentials or fragment. `events` is a non-empty
list of unique strings; the server does not validate names. Event names the
platform emits include `message.created`, `message.sent`, `message.delivered`,
`message.failed`, `message.cancelled`, `message.received`, `batch.started`,
`batch.completed`, `wallet.low_balance`, `sender_id.approved`,
`sender_id.rejected`, `number.renewed`, `webhook.test`. `update` is a full
replacement: `url`, `events` and `enabled` are all required (PATCH has the
same semantics and is not exposed separately). Replay `reason` is 5..1000
characters; `generation` comes from the delivery. The legacy alias
`POST /v1/webhooks/{id}/deliveries/{delivery_id}` behaves the same and is not
used. Payload signing is covered in DESIGN.md.

## inbound (2)

InboundMessage: `id`, `from` E.164, `to`, `text?`, `received_at`,
`virtual_number_id?`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/inbound` -> 200 Page<InboundMessage> | messages:read | - | yes | 200 (always empty in sandbox) |
| `reply(id, {text})` | `POST /v1/inbound/{id}/reply` -> 201 Message | messages:write | req (<=255, forwarded to messages) | yes | 422 (sandbox: live only) |

## numbers (8)

Number: `id`, `country`, `number`, `kind` `long_code|short_code|toll_free`,
`monthly_fee` decimal string, `fee_currency`, `status`
`available|assigned|releasing`, `inbound` bool, `outbound` bool,
`assigned_at?`, `renews_at?`. Rule: `id`, `match` `keyword|prefix|regex|any`,
`pattern?` (required unless match is `any`), `action`
`webhook|auto_reply|forward_email`, `target` (1..2048), `position` 0..10000.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/numbers` -> 200 Page<Number> | numbers:read | - | yes | 200, 403 |
| `available({country, kind})` | `GET /v1/numbers/available` -> 200 Number[] (array) | numbers:read | - | yes | 200 |
| `assign({country, kind})` | `POST /v1/numbers` -> 201 Number | numbers:manage | req (<=200) | yes | 422 (sandbox) |
| `release(id)` | `DELETE /v1/numbers/{id}` -> 204 | numbers:manage | - | yes | 422 (sandbox) |
| `listRules(id, {limit?, cursor?})` | `GET /v1/numbers/{id}/rules` -> 200 Page<Rule> | numbers:read | - | yes | 422 (sandbox) |
| `createRule(id, rule)` | `POST /v1/numbers/{id}/rules` -> 201 Rule | numbers:manage | req (<=200) | yes | 422 (sandbox) |
| `updateRule(id, ruleId, rule)` | `PUT /v1/numbers/{id}/rules/{rule_id}` -> 200 Rule | numbers:manage | - | yes | 422 (sandbox) |
| `deleteRule(id, ruleId)` | `DELETE /v1/numbers/{id}/rules/{rule_id}` -> 204 | numbers:manage | - | yes | 422 (sandbox) |

Everything except `list` and `available` requires a live key
(`422 This operation requires the live environment.`). Assignment charges the
wallet.

## senderIds (13)

SenderId: `id`, `value`, `kind` `alphanumeric|numeric`, `countries` string[],
`use_case`, `sample_message?`, `status` (`pending|approved|rejected|...`),
`rejection_reason?`, `restricted` bool, `restriction_reason?`, `created_at`,
`registrations?` array (on get/create). Draft: `id`, `source`
`onboarding|application`, `value`, `kind`, `countries`, `use_case`,
`sample_message`, `documents` uuid[], `version` int, `status`
`active|submitted`, `submitted_sender_id` uuid|null, `created_at`, `updated_at`.
Document: `id`, `kind` `certificate|signatory-id|authorization`, `filename`,
`content_type`, `size`, `scan_status`, `review_status`, `review_reason?`,
`reviewed_at?`, `version`, `supersedes_id?`, `is_current`, `created_at`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/sender-ids` -> 200 Page<SenderId> | sender-ids:read | - | yes | 200, 403 |
| `get(id)` | `GET /v1/sender-ids/{id}` -> 200 SenderId | sender-ids:read | - | yes | 404 |
| `create(params)` | `POST /v1/sender-ids` -> 201 SenderId | sender-ids:write | - | **no** | 422 |
| `update(id, {useCase, countries, documents, sampleMessage?})` | `PATCH /v1/sender-ids/{id}` -> 200 SenderId | sender-ids:write | - | yes | 422 |
| `delete(id)` | `DELETE /v1/sender-ids/{id}` -> 204 | sender-ids:write | - | yes | 404 |
| `check({value, country?})` | `GET /v1/sender-ids/check` -> 200 `{valid, available, reserved, reason}` | sender-ids:read | - | yes | 200 |
| `quote({countries})` | `GET /v1/sender-ids/quote?countries=KE,NG` -> 200 `{quote_id, entries[{country,provider,fee_amount,fee_currency}], totals[{currency,amount}]}` | sender-ids:read | - | yes | 200 |
| `listDocuments()` | `GET /v1/sender-documents` -> 200 `{items: Document[]}` (no cursor) | sender-ids:read | - | yes | 200 |
| `listDrafts({limit?, cursor?})` | `GET /v1/sender-id-drafts` -> 200 Page<Draft> | sender-ids:read | - | yes | 200 |
| `createDraft(params)` | `POST /v1/sender-id-drafts` -> 201 Draft | sender-ids:write | - | no | 201 |
| `getDraft(id)` | `GET /v1/sender-id-drafts/{id}` -> 200 Draft | sender-ids:read | - | yes | 200 |
| `updateDraft(id, {version, ...})` | `PATCH /v1/sender-id-drafts/{id}` -> 200 Draft | sender-ids:write | - | yes | 200 |
| `deleteDraft(id)` | `DELETE /v1/sender-id-drafts/{id}` -> 204 | sender-ids:write | - | yes | 204 |

`create` body: `value` (req), `kind` (req), `countries` string[] (req),
`use_case?`, `sample_message?`, `documents` uuid[] (req; certificate,
signatory-id and authorization documents are required for a custom sender),
`draft_id?`, `draft_version?`, `quote_id?`. Registration may charge fees
(see `quote`), which is why create is not auto-retried. `createDraft` body:
`source?`, `value?`, `kind?`, `countries?`, `use_case?`, `sample_message?`,
`documents?`. `updateDraft` requires the current `version` (optimistic lock,
409 on mismatch). Document **upload** and **download** are session only.

## suppressions (4)

Suppression: `id` int, `e164`, `reason` `stop_keyword|manual|complaint|invalid_number`, `created_at`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list({limit?, cursor?})` | `GET /v1/compliance/suppressions` -> 200 Page<Suppression> | compliance:read | - | yes | 200, 403 |
| `create({e164, reason})` | `POST /v1/compliance/suppressions` -> 201 Suppression | compliance:manage | - | no | 201 |
| `import(items[])` | `POST /v1/compliance/suppressions/import` body `{items:[{e164, reason}]}` -> 201 `{created, received}` | compliance:manage | - | no | 201 |
| `delete(id)` | `DELETE /v1/compliance/suppressions/{id}` -> 204 | compliance:manage | - | yes | 204, 404 |

Sending to a suppressed number is rejected with `422 destination is suppressed`.

## compliance (3)

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `listCountries()` | `GET /v1/compliance/countries` -> 200 CountryRules[] (array) | compliance:read | - | yes | 200 |
| `getCountry(iso2)` | `GET /v1/compliance/countries/{iso2}` -> 200 CountryRules | compliance:read | - | yes | 200, 404 |
| `listContentRules()` | `GET /v1/content-rules` -> 200 ContentRule[] (array) | compliance:read | - | yes | 200 |

CountryRules: `iso2`, `name`, `status`, `dial_code`, `stop_keywords` string[],
`quiet_hours` `[{traffic_type, start_local, end_local, enforce}]`,
`content_rules` `[{kind, pattern, action, traffic_types, enabled}]`.
ContentRule: `id` int, `country_iso2` string|null, `kind`
`blocked_keyword|regex`, `pattern`, `action` `reject|hold_for_review`,
`traffic_types` string[], `enabled` bool.

## wallet (3)

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `balances()` | `GET /v1/wallet` -> 200 `{data: [{id, currency, balance, reserved, environment}]}` | wallet:read | - | yes | 200, 403 |
| `ledger({limit?, before?})` | `GET /v1/wallet/ledger` -> 200 `{data: LedgerEntry[]}` | wallet:read | - | yes | 200, 400 |
| `createTopup({amount, currency, channel, email})` | `POST /v1/wallet/topups` -> 201 `{id, reference, authorization_url, access_code, amount, currency, status}` | wallet:write (or wallet:topup) | req (<=200) | yes | 422 (sandbox) |

LedgerEntry: `id` int64, `wallet_id`, `type`, `amount`, `balance_after`,
`reserved_delta`, `reserved_after`, `reference?`, `payment_id?`,
`message_id?`, `created_at`. The ledger is the one list that does **not** use
cursors: `limit` 1..200, `before` = the smallest `id` already seen; stop when
fewer than `limit` rows come back. `channel` is
`card|mobile_money|bank_transfer`; top-ups only work with a live key
(`422 sandbox wallets cannot use payment providers`).

## pricing (1)

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `get({product?, country?})` | `GET /v1/pricing` -> 200 PriceList | pricing:read | - | yes | 200, 400, 403 |

`product` `sms|lookup|number_monthly` (default `sms`), `country` ISO2.
PriceList: `workspace_id`, `currency`, `product`, `entries[]` with
`country_iso2`, `country_name`, `carrier_id`, `carrier_name`, `product`,
`min_monthly_volume`, `markup_type`, `markup_value`, `sell_currency`,
`sell_amount` string|null, `converted_amount` string|null,
`converted_currency`, `workspace_override`, `effective_from`, `fx_rate`.

## analytics (5)

Common query: `currency?` 3 letters (defaults to the workspace currency),
`range?` `Nd` with N 1..366 (default `30d`) **or** `from?`/`to?`
(RFC 3339 or `YYYY-MM-DD`, not combined with `range`), `bucket?` `day|hour`.
Metrics: `sent`, `delivered`, `failed`, `parts` (int64), `delivery_rate`
number, `spend` decimal string, `p50_ms?`, `p95_ms?`.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `overview(q?)` | `GET /v1/analytics/overview` -> 200 Metrics + `{from, to, currency, environment}` | analytics:read | - | yes | 200, 403 |
| `byCountry(q?)` | `GET /v1/analytics/by-country` -> 200 `[Metrics + {key, name}]` | analytics:read | - | yes | 200 |
| `byCarrier(q?)` | `GET /v1/analytics/by-carrier` -> 200 `[Metrics + {key, name}]` | analytics:read | - | yes | 200 |
| `bySenderId(q?)` | `GET /v1/analytics/by-sender-id` -> 200 `[Metrics + {key, name}]` | analytics:read | - | yes | 200 |
| `timeseries(q?)` | `GET /v1/analytics/timeseries` -> 200 `[Metrics + {bucket}]` | analytics:read | - | yes | 200 |

## sandbox (1)

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `listMessages({limit?, cursor?})` | `GET /v1/sandbox/messages` -> 200 Page<SandboxMessage> | messages:read | - | yes | 200 |

SandboxMessage: `id`, `to`, `sender_id`, `text`, `parts`, `status`,
`traffic_type`, `created_at`, `sent_at?`. Shows the rendered text of sandbox
sends, including OTP codes.

## countries (4)

Public catalog. Works without a key; with a key the handler resolves the
workspace (pricing context). SDKs always send the key.

| Method | HTTP | Scope | Idem | Retry | Live |
| --- | --- | --- | --- | --- | --- |
| `list()` | `GET /v1/countries` -> 200 Country[] (array) | none | - | yes | 200 |
| `carriers(iso2)` | `GET /v1/countries/{iso2}/carriers` -> 200 `[{id, name, mcc_mnc[], prefixes[]}]` | none | - | yes | 200 |
| `routes(iso2)` | `GET /v1/countries/{iso2}/routes` -> 200 Route[] (array) | none | - | yes | 200 |
| `compliance(iso2)` | `GET /v1/countries/{iso2}/compliance` -> 200 CountryRules | none | - | yes | 200 |

Country: `iso2`, `name`, `dial_code`, `currency`, `status`,
`price_per_message` `{amount, currency}`|null, `sender_kinds` string[],
`providers_available` int.

---

## Totals

18 resources, 83 methods: messages 5, batches 6, otp 2, lookups 2, contacts 5,
contactGroups 6, templates 5, webhooks 8, inbound 2, numbers 8, senderIds 13,
suppressions 4, compliance 3, wallet 3, pricing 1, analytics 5, sandbox 1,
countries 4. Every one was called live; methods whose only observed status is
4xx are live-only (numbers writes, inbound reply, top-ups) or need uploaded
documents (sender ID create and amend).

## Not in the SDK (session only or not an API operation)

All of these returned `401` when called with a valid all-scope `sk_test_` key
(or were confirmed session-only in code).

| Operation | Reason |
| --- | --- |
| `/v1/auth/*` (signup, login, 2FA, sessions, logout, password reset, email verification, cookie exchange, invitations accept) | account authentication, session tokens only |
| `/v1/me`, `/v1/me/notifications` | the signed-in user, not the workspace |
| `/v1/keys`, `/v1/keys/scopes`, `/v1/keys/{id}/rotate`, `DELETE /v1/keys/{id}` | key management requires a console session (owner, admin, developer); `keys:admin` scope does not unlock it |
| `/v1/workspace`, `/v1/workspaces` | workspace profile and creation |
| `/v1/members`, `/v1/invitations` | team management |
| `/v1/settings/*`, `/v1/workspace/retention`, `/v1/workspace/spend-cap` | workspace policy (routing, notifications, retention, spend cap) |
| `/v1/wallet/auto-topup` (GET, PUT), `/v1/wallet/topups/manual`, `/v1/wallet/sandbox-credits` | "Session authentication required." / "Browser session required." |
| `/v1/payment-methods` | stored cards, console only |
| `/v1/invoices` | billing documents, console only |
| `/v1/onboarding/*` | KYC flow (company, documents, phone) |
| `/v1/legal/*` | terms acceptance |
| `/v1/notifications` | in-app notifications |
| `/v1/account/*` | export and deletion |
| `POST /v1/sender-documents`, `GET /v1/sender-documents/{id}/download` | upload and download are owner/admin session only (list is key-callable) |
| `/v1/realtime`, `/v1/realtime/tickets` | WebSocket stream; ticket needs HTTPS and an allowed browser Origin (`403` live). Key auth with `realtime:read` exists on the socket but a WebSocket client is out of scope for v1 |
| `/v1/payments/paystack/webhook`, `/callbacks/providers/{id}/dlr` | inbound callbacks from payment and SMS providers |
| `/status`, `/status/subscribe*`, `/healthz`, `/readyz`, `/metrics`, `/legal/*` | public or operational, not workspace API |
| `/admin/v1/*` | operator console |

## Drift (spec vs live code)

1. `servers` in the OpenAPI file lists only `http://localhost:8080`; no
   production URL. Production is `https://api.opensms.io` (problem `type` base
   in `problempb`, landing page examples).
2. Insufficient scope on `/v1/messages*` and `/v1/otp/*` returns **401**
   `insufficient scope`; every other handler returns 403. Spec does not
   document 403 for messages.
3. `POST /v1/messages` documents only 201/400/401/409; live also returns 403
   (sandbox before email verification, workspace not live), 422 (admission:
   `destination is suppressed`), and by code 402, 429, 503.
4. `POST /v1/messages/batch` does not document 403 (scope); `POST
   /v1/batches/{id}/start` and `/stop` do not document the 400 for a missing
   Idempotency-Key.
5. `PUT` and `PATCH /v1/webhooks/{id}` document `enabled` as optional; live
   returns `400 enabled is required`. Both verbs are full replacements.
6. `POST /v1/inbound/{id}/reply` is documented as `202` with no body; the
   handler forwards to `POST /v1/messages` and returns `201` with a Message.
7. `GET /v1/sender-documents` (key-callable, `sender-ids:read`) is missing from
   the spec. `GET /v1/wallet/auto-topup` and `PUT` have no `security` block in
   the spec but are session only.
8. `GET /v1/batches/{id}/items` reuses the full Message schema; live items
   carry only `id, created_at, to, text, sender_id, parts, status,
   traffic_type, metadata`.
9. Unknown ids: `GET /v1/webhooks/{id}/deliveries` and `GET
   /v1/batches/{id}/items` return `200` with an empty page instead of 404.
10. Idempotency-Key limit differs by handler (255 vs 200 bytes); the spec
    marks it required without the bound.
11. Most problem bodies carry no `code`; the spec's `code` is optional, so
    this is consistent, but SDK users cannot branch on codes for common
    validation errors.
12. Analytics in sandbox reported `delivered: 3` and `failed: 3` for the same 3
    sent messages (overview and every breakdown). Looks like a rollup bug, not
    an SDK concern; conformance does not assert analytics numbers.
13. Timestamps come back with mixed offsets (`+03:00` from messages and
    batches, `+00:00` from contacts), both valid RFC 3339.
