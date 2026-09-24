# frozen_string_literal: true

require "test_helper"
require "time"

# CONFORMANCE.md "Mock-transport unit tests" 4, 15, 16, 19, plus a routing
# check for every SURFACE.md method.
class ResourcesTest < Minitest::Test
  include ClientHelpers

  # 4. Body mapping
  def test_send_body_mapping
    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send(
      to: "+254700000012", text: "hi", sender_id: "ACME", traffic_type: "marketing",
      scheduled_at: Time.utc(2026, 9, 24, 12, 0, 0), callback_url: "https://x.test/cb", metadata: { a: 1 }
    )
    body = @http.last.json
    assert_equal %i[to text sender_id traffic_type scheduled_at callback_url metadata].sort, body.keys.sort
    assert_equal "2026-09-24T12:00:00Z", body[:scheduled_at]
    assert_equal({ a: 1 }, body[:metadata])
  end

  def test_scheduled_at_non_utc_time_is_serialized_as_utc
    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send(to: "+254700000012", text: "hi",
                          scheduled_at: Time.new(2026, 9, 24, 15, 0, 0, "+03:00"))
    assert_equal "2026-09-24T12:00:00Z", @http.last.json[:scheduled_at]
  end

  def test_unset_optionals_are_absent
    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send(to: "+254700000012", text: "hi", sender_id: nil)
    assert_equal({ to: "+254700000012", text: "hi" }, @http.last.json)
    refute_includes @http.last.body, "null"
  end

  def test_positional_hash_with_string_keys
    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send({ "to" => "+254700000012", "text" => "hi" })
    assert_equal({ to: "+254700000012", text: "hi" }, @http.last.json)
  end

  def test_unknown_and_missing_fields_raise_locally
    assert_raises(ArgumentError) { @client.messages.send(to: "+254700000012", text: "x", bogus: 1) }
    assert_raises(ArgumentError) { @client.messages.send(to: "+254700000012") }
    assert_raises(ArgumentError) { @client.webhooks.update("w", url: "https://x", events: ["a"]) }
    assert_empty @http.requests
  end

  def test_webhook_update_sends_enabled_false
    @http.enqueue(status: 200, body: { id: "w" })
    @client.webhooks.update("w", url: "https://x.test", events: ["message.delivered"], enabled: false)
    assert_equal false, @http.last.json[:enabled]
    assert_equal :put, @http.last.method
  end

  def test_otp_and_group_mapping
    @http.enqueue(status: 201, body: { otp_id: "o1" })
    assert_equal "o1", @client.otp.send(to: "+254700000012", length: 6, ttl_seconds: 300)[:otp_id]
    assert_equal({ to: "+254700000012", length: 6, ttl_seconds: 300 }, @http.last.json)

    @http.enqueue(status: 200, body: { valid: true, attempts_left: 3 })
    res = @client.otp.verify(otp_id: "o1", code: "123456")
    assert_equal 3, res[:attempts_left]
    assert_equal({ otp_id: "o1", code: "123456" }, @http.last.json)

    @http.enqueue(status: 201, body: { id: "g" })
    @client.contact_groups.create(name: "g", contact_ids: ["c1"])
    assert_equal({ name: "g", contact_ids: ["c1"] }, @http.last.json)

    @http.enqueue(status: 200, body: { id: "b" })
    @client.contact_groups.send("g", template_id: "t", variables: { name: "Ada" })
    assert_equal({ template_id: "t", variables: { name: "Ada" } }, @http.last.json)
  end

  def test_batch_items_are_filtered
    @http.enqueue(status: 202, body: { id: "b", status: "ready" })
    @client.batches.create(items: [{ to: "+254700000012", text: "a" }, { "to" => "bad", "text" => "x" }], dedupe: false)
    assert_equal({ items: [{ to: "+254700000012", text: "a" }, { to: "bad", text: "x" }], dedupe: false },
                 @http.last.json)
    assert_equal 36, @http.last.headers["Idempotency-Key"].length
  end

  # 15. Pagination
  def test_pagination_helper
    @http.enqueue(status: 200, body: { items: [{ id: "a" }, { id: "b" }], next_cursor: "c1" })
    @http.enqueue(status: 200, body: { items: [{ id: "c" }], next_cursor: nil })
    ids = @client.paginate(:messages, :list, limit: 2).map { |m| m[:id] }.to_a
    assert_equal %w[a b c], ids
    assert_equal 2, @http.requests.size
    assert_equal "limit=2", @http.requests[0].query
    assert_equal "limit=2&cursor=c1", @http.requests[1].query
  end

  def test_pagination_is_lazy
    @http.enqueue(status: 200, body: { items: [{ id: "a" }, { id: "b" }], next_cursor: "c1" })
    @http.enqueue(status: 200, body: { items: [{ id: "c" }], next_cursor: nil })
    assert_equal %w[a], @client.paginate(:messages, :list, limit: 2).first(1).map { |m| m[:id] }
    assert_equal 1, @http.requests.size
  end

  def test_pagination_with_method_object_and_positional_args
    @http.enqueue(status: 200, body: { items: [{ id: "i1" }], next_cursor: "n" })
    @http.enqueue(status: 200, body: { items: [{ id: "i2" }], next_cursor: nil })
    ids = @client.paginate(@client.batches.method(:list_items), "b1", status: "sent").map { |i| i[:id] }.to_a
    assert_equal %w[i1 i2], ids
    assert_equal "/v1/batches/b1/items", @http.last.path
    assert_equal "status=sent&cursor=n", @http.last.query
  end

  def test_page_object
    @http.enqueue(status: 200, body: { items: [{ id: "a" }], next_cursor: "c" })
    page = @client.messages.list(limit: 1)
    assert_kind_of Opensms::Page, page
    assert_equal "c", page.next_cursor
    assert_equal ["a"], page.map { |m| m[:id] }
  end

  # 16. Query encoding
  def test_query_encoding
    @http.enqueue(status: 200, body: {})
    @client.sender_ids.quote(countries: %w[KE NG])
    assert_equal "countries=KE,NG", @http.last.query
    assert_equal "KE,NG", URI.decode_www_form(@http.last.query).to_h["countries"]

    @http.enqueue(status: 200, body: { items: [], next_cursor: nil })
    @client.messages.list(status: "delivered", to: "+2547", cursor: nil)
    assert_equal "status=delivered&to=%2B2547", @http.last.query

    @http.enqueue(status: 200, body: { items: [], next_cursor: nil })
    @client.messages.list
    assert_nil @http.last.query
  end

  def test_date_query_serialization
    @http.enqueue(status: 200, body: { items: [], next_cursor: nil })
    @client.messages.list(date_from: Date.new(2026, 9, 1), date_to: Time.utc(2026, 9, 2, 3, 4, 5))
    q = URI.decode_www_form(@http.last.query).to_h
    assert_equal "2026-09-01", q["date_from"]
    assert_equal "2026-09-02T03:04:05Z", q["date_to"]
  end

  # 19. Batch CSV
  def test_batch_csv
    csv = "to,text\n+254700000014,csv run\n"
    @http.enqueue(status: 202, body: { id: "b", status: "ready" })
    @client.batches.create_from_csv(csv)
    req = @http.last
    assert_equal "/v1/messages/batch", req.path
    assert_equal "text/csv", req.headers["Content-Type"]
    assert_equal csv, req.body
    assert_equal 36, req.headers["Idempotency-Key"].length
  end

  def test_batch_csv_without_dedupe_uses_multipart
    @http.enqueue(status: 202, body: { id: "b" })
    @client.batches.create_from_csv("to,text\n+254700000014,x\n", dedupe: false, idempotency_key: "k")
    req = @http.last
    assert_match(%r{\Amultipart/form-data; boundary=}, req.headers["Content-Type"])
    assert_includes req.body, %(name="dedupe"\r\n\r\nfalse)
    assert_includes req.body, "+254700000014,x"
    assert_equal "k", req.headers["Idempotency-Key"]
  end

  def test_wallet_envelopes_and_documents
    @http.enqueue(status: 200, body: { data: [{ id: "w", balance: "10.000000" }] })
    assert_equal "10.000000", @client.wallet.balances.first[:balance]
    @http.enqueue(status: 200, body: { data: [{ id: 5 }] })
    assert_equal [{ id: 5 }], @client.wallet.ledger(limit: 1, before: 9)
    assert_equal "limit=1&before=9", @http.last.query
    @http.enqueue(status: 200, body: { items: [{ id: "d" }] })
    assert_equal [{ id: "d" }], @client.sender_ids.list_documents
  end

  # Every SURFACE.md method: [call, http method, path, idempotency key expected].
  ROUTES = [
    [->(c) { c.messages.send(to: "+254700000012", text: "x") }, :post, "/v1/messages", true],
    [->(c) { c.messages.list }, :get, "/v1/messages", false],
    [->(c) { c.messages.get("m") }, :get, "/v1/messages/m", false],
    [->(c) { c.messages.attempts("m") }, :get, "/v1/messages/m/attempts", false],
    [->(c) { c.messages.cancel("m") }, :post, "/v1/messages/m/cancel", false],
    [->(c) { c.batches.create(items: [{ to: "+1", text: "x" }]) }, :post, "/v1/messages/batch", true],
    [->(c) { c.batches.create_from_csv("to,text\n") }, :post, "/v1/messages/batch", true],
    [->(c) { c.batches.get("b") }, :get, "/v1/batches/b", false],
    [->(c) { c.batches.validation("b") }, :get, "/v1/batches/b/validation", false],
    [->(c) { c.batches.start("b") }, :post, "/v1/batches/b/start", true],
    [->(c) { c.batches.stop("b") }, :post, "/v1/batches/b/stop", true],
    [->(c) { c.batches.list_items("b") }, :get, "/v1/batches/b/items", false],
    [->(c) { c.otp.send(to: "+254700000012") }, :post, "/v1/otp/send", true],
    [->(c) { c.otp.verify(otp_id: "o", code: "1234") }, :post, "/v1/otp/verify", false],
    [->(c) { c.lookups.create(to: "+254700000012") }, :post, "/v1/lookup", true],
    [->(c) { c.lookups.get("l") }, :get, "/v1/lookup/l", false],
    [->(c) { c.contacts.list }, :get, "/v1/contacts", false],
    [->(c) { c.contacts.create(e164: "+254700000012") }, :post, "/v1/contacts", true],
    [->(c) { c.contacts.get("c") }, :get, "/v1/contacts/c", false],
    [->(c) { c.contacts.update("c", name: "n") }, :patch, "/v1/contacts/c", false],
    [->(c) { c.contacts.delete("c") }, :delete, "/v1/contacts/c", false],
    [->(c) { c.contact_groups.list }, :get, "/v1/contact-groups", false],
    [->(c) { c.contact_groups.create(name: "g") }, :post, "/v1/contact-groups", true],
    [->(c) { c.contact_groups.get("g") }, :get, "/v1/contact-groups/g", false],
    [->(c) { c.contact_groups.update("g", name: "n") }, :patch, "/v1/contact-groups/g", false],
    [->(c) { c.contact_groups.delete("g") }, :delete, "/v1/contact-groups/g", false],
    [->(c) { c.contact_groups.send("g", text: "hi") }, :post, "/v1/contact-groups/g/send", true],
    [->(c) { c.templates.list }, :get, "/v1/templates", false],
    [->(c) { c.templates.create(name: "t", body: "b") }, :post, "/v1/templates", true],
    [->(c) { c.templates.get("t") }, :get, "/v1/templates/t", false],
    [->(c) { c.templates.update("t", body: "b") }, :patch, "/v1/templates/t", false],
    [->(c) { c.templates.delete("t") }, :delete, "/v1/templates/t", false],
    [->(c) { c.webhooks.list }, :get, "/v1/webhooks", false],
    [->(c) { c.webhooks.create(url: "https://x", events: ["e"]) }, :post, "/v1/webhooks", true],
    [->(c) { c.webhooks.get("w") }, :get, "/v1/webhooks/w", false],
    [->(c) { c.webhooks.update("w", url: "https://x", events: ["e"], enabled: true) }, :put, "/v1/webhooks/w", true],
    [->(c) { c.webhooks.delete("w") }, :delete, "/v1/webhooks/w", true],
    [->(c) { c.webhooks.test("w") }, :post, "/v1/webhooks/w/test", true],
    [->(c) { c.webhooks.list_deliveries("w") }, :get, "/v1/webhooks/w/deliveries", false],
    [->(c) { c.webhooks.replay_delivery("w", 7, generation: 1, reason: "again") }, :post,
     "/v1/webhooks/w/deliveries/7/replay", true],
    [->(c) { c.inbound.list }, :get, "/v1/inbound", false],
    [->(c) { c.inbound.reply("i", text: "hi") }, :post, "/v1/inbound/i/reply", true],
    [->(c) { c.numbers.list }, :get, "/v1/numbers", false],
    [->(c) { c.numbers.available(country: "KE", kind: "long_code") }, :get, "/v1/numbers/available", false],
    [->(c) { c.numbers.assign(country: "KE", kind: "long_code") }, :post, "/v1/numbers", true],
    [->(c) { c.numbers.release("n") }, :delete, "/v1/numbers/n", false],
    [->(c) { c.numbers.list_rules("n") }, :get, "/v1/numbers/n/rules", false],
    [->(c) { c.numbers.create_rule("n", match: "any", action: "webhook", target: "https://x") }, :post,
     "/v1/numbers/n/rules", true],
    [->(c) { c.numbers.update_rule("n", "r", match: "any", action: "webhook", target: "https://x") }, :put,
     "/v1/numbers/n/rules/r", false],
    [->(c) { c.numbers.delete_rule("n", "r") }, :delete, "/v1/numbers/n/rules/r", false],
    [->(c) { c.sender_ids.list }, :get, "/v1/sender-ids", false],
    [->(c) { c.sender_ids.get("s") }, :get, "/v1/sender-ids/s", false],
    [->(c) { c.sender_ids.create(value: "A", kind: "alphanumeric", countries: ["KE"], documents: []) }, :post,
     "/v1/sender-ids", false],
    [->(c) { c.sender_ids.update("s", use_case: "u", countries: ["KE"], documents: []) }, :patch,
     "/v1/sender-ids/s", false],
    [->(c) { c.sender_ids.delete("s") }, :delete, "/v1/sender-ids/s", false],
    [->(c) { c.sender_ids.check(value: "ACME") }, :get, "/v1/sender-ids/check", false],
    [->(c) { c.sender_ids.quote(countries: ["KE"]) }, :get, "/v1/sender-ids/quote", false],
    [->(c) { c.sender_ids.list_documents }, :get, "/v1/sender-documents", false],
    [->(c) { c.sender_ids.list_drafts }, :get, "/v1/sender-id-drafts", false],
    [->(c) { c.sender_ids.create_draft(value: "A") }, :post, "/v1/sender-id-drafts", false],
    [->(c) { c.sender_ids.get_draft("d") }, :get, "/v1/sender-id-drafts/d", false],
    [->(c) { c.sender_ids.update_draft("d", version: 1) }, :patch, "/v1/sender-id-drafts/d", false],
    [->(c) { c.sender_ids.delete_draft("d") }, :delete, "/v1/sender-id-drafts/d", false],
    [->(c) { c.suppressions.list }, :get, "/v1/compliance/suppressions", false],
    [->(c) { c.suppressions.create(e164: "+1", reason: "manual") }, :post, "/v1/compliance/suppressions", false],
    [->(c) { c.suppressions.import([{ e164: "+1", reason: "manual" }]) }, :post,
     "/v1/compliance/suppressions/import", false],
    [->(c) { c.suppressions.delete(5) }, :delete, "/v1/compliance/suppressions/5", false],
    [->(c) { c.compliance.list_countries }, :get, "/v1/compliance/countries", false],
    [->(c) { c.compliance.get_country("KE") }, :get, "/v1/compliance/countries/KE", false],
    [->(c) { c.compliance.list_content_rules }, :get, "/v1/content-rules", false],
    [->(c) { c.wallet.balances }, :get, "/v1/wallet", false],
    [->(c) { c.wallet.ledger }, :get, "/v1/wallet/ledger", false],
    [->(c) { c.wallet.create_topup(amount: "1", currency: "KES", channel: "card", email: "a@b.c") }, :post,
     "/v1/wallet/topups", true],
    [->(c) { c.pricing.get }, :get, "/v1/pricing", false],
    [->(c) { c.analytics.overview }, :get, "/v1/analytics/overview", false],
    [->(c) { c.analytics.by_country }, :get, "/v1/analytics/by-country", false],
    [->(c) { c.analytics.by_carrier }, :get, "/v1/analytics/by-carrier", false],
    [->(c) { c.analytics.by_sender_id }, :get, "/v1/analytics/by-sender-id", false],
    [->(c) { c.analytics.timeseries }, :get, "/v1/analytics/timeseries", false],
    [->(c) { c.sandbox.list_messages }, :get, "/v1/sandbox/messages", false],
    [->(c) { c.countries.list }, :get, "/v1/countries", false],
    [->(c) { c.countries.carriers("KE") }, :get, "/v1/countries/KE/carriers", false],
    [->(c) { c.countries.routes("KE") }, :get, "/v1/countries/KE/routes", false],
    [->(c) { c.countries.compliance("KE") }, :get, "/v1/countries/KE/compliance", false]
  ].freeze

  def test_every_surface_method_routes_correctly
    ROUTES.each do |call, method, path, idem|
      call.call(@client)
      req = @http.last
      label = "#{method.upcase} #{path}"
      assert_equal method, req.method, label
      assert_equal path, req.path, label
      assert_equal idem, req.headers.key?("Idempotency-Key"), "#{label} idempotency"
    end
    # 83 SURFACE methods plus the create_from_csv entry point.
    assert_equal 84, ROUTES.size
  end

  def test_client_exposes_all_resources
    %i[messages batches otp lookups contacts contact_groups templates webhooks inbound numbers sender_ids
       suppressions compliance wallet pricing analytics sandbox countries].each do |name|
      refute_nil @client.public_send(name), name
    end
  end
end
