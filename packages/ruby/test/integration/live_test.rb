# frozen_string_literal: true

require "test_helper"
require "securerandom"
require "time"

# Live conformance scenario from spec/CONFORMANCE.md, steps 1-29, run in
# order. Skips unless OPENSMS_BASE_URL and OPENSMS_API_KEY are set.
#
#   source ../../spec/fixtures/credentials.sh && rake integration
class LiveTest < Minitest::Test
  i_suck_and_my_tests_are_order_dependent!

  BASE_URL = ENV.fetch("OPENSMS_BASE_URL", nil)
  API_KEY = ENV.fetch("OPENSMS_API_KEY", nil)
  READONLY_KEY = ENV.fetch("OPENSMS_READONLY_API_KEY", nil)
  RUN = SecureRandom.hex(4)
  # CONFORMANCE.md names +254700000012 for sends. The API limits sends per
  # destination (5 per hour, 20 per day per workspace) and every SDK shares the
  # test workspace, so sends go to a random +2547 number per run instead. Any
  # +2547 number resolves to KE in the sandbox.
  PHONE = "+2547#{format('%08d', SecureRandom.random_number(100_000_000))}"
  PHONE2 = "+2547#{format('%08d', SecureRandom.random_number(100_000_000))}"
  OTP_PHONE = "+2547#{format('%08d', SecureRandom.random_number(100_000_000))}"
  LOOKUP_PHONE = "+254700000012"
  ZERO_ID = "00000000-0000-0000-0000-000000000000"
  UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/.freeze

  # Shared state between ordered steps.
  STATE = {}

  # Counts HTTP attempts so step 2 can assert "not retried".
  class CountingHttp < Opensms::NetHttpClient
    attr_reader :count

    def initialize
      super
      @count = 0
    end

    def call(*args)
      @count += 1
      super
    end
  end

  def setup
    skip "OPENSMS_BASE_URL and OPENSMS_API_KEY are not set" if BASE_URL.to_s.empty? || API_KEY.to_s.empty?
    @client = Opensms::Client.new(api_key: API_KEY, base_url: BASE_URL, timeout: 60)
  end

  def rphone
    "+2547#{format('%08d', SecureRandom.random_number(100_000_000))}"
  end

  def assert_err(status, detail)
    err = assert_raises(Opensms::Error) { yield }
    assert_equal status, err.status, "status for #{err.message}"
    assert_equal detail, err.detail
    err
  end

  def poll(deadline: 20, interval: 0.5)
    stop = Time.now + deadline
    loop do
      result = yield
      return result if result
      flunk "deadline of #{deadline}s passed while polling" if Time.now > stop

      sleep interval
    end
  end

  def test_01_constructor
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: "not_a_key", base_url: BASE_URL) }
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: "sk_test_short", base_url: BASE_URL) }
  end

  def test_02_auth_error
    http = CountingHttp.new
    client = Opensms::Client.new(api_key: "sk_test_#{'A' * 32}", base_url: BASE_URL, timeout: 60, http_client: http)
    err = assert_err(401, "missing or invalid API key") { client.messages.list(limit: 1) }
    assert_equal "about:blank", err.type
    assert_equal "Unauthorized", err.title
    assert_nil err.code
    assert_equal 1, http.count
  end

  def test_03_send
    msg = @client.messages.send(to: PHONE, text: "conformance ruby #{RUN}", metadata: { sdk: "ruby", run: RUN })
    assert_match UUID, msg[:id]
    assert_equal PHONE, msg[:to]
    assert_equal "OPENSMS", msg[:sender_id]
    assert_equal "transactional", msg[:traffic_type]
    assert_includes %w[queued sending sent delivered], msg[:status]
    assert_equal 1, msg[:parts]
    assert_equal "gsm7", msg[:encoding]
    assert_equal "KE", msg[:country_iso2]
    assert_equal "KES", msg[:currency]
    assert_equal "0.000000", msg[:price]
    assert_equal RUN, msg[:metadata][:run]
    STATE[:m] = msg[:id]
    STATE[:m_text] = "conformance ruby #{RUN}"
  end

  def test_04_idempotent_replay
    key = SecureRandom.uuid
    params = { to: PHONE, text: "idem ruby #{RUN}" }
    a = @client.messages.send(params, idempotency_key: key)
    b = @client.messages.send(params, idempotency_key: key)
    assert_equal a[:id], b[:id]
    assert_err(409, "Idempotency-Key was already used with a different request") do
      @client.messages.send({ to: PHONE, text: "idem ruby #{RUN} changed" }, idempotency_key: key)
    end
  end

  def test_05_get_and_wait
    m = STATE.fetch(:m)
    msg = poll { (r = @client.messages.get(m))[:status] == "delivered" && r }
    refute_nil msg[:delivered_at]
    refute_nil msg[:sent_at]
    assert_equal STATE[:m_text], msg[:text]
  end

  def test_06_list_and_cursor
    p1 = @client.messages.list(limit: 1)
    assert_equal 1, p1.items.size
    refute_nil p1.next_cursor
    p2 = @client.messages.list(limit: 1, cursor: p1.next_cursor)
    assert_equal 1, p2.items.size
    refute_equal p1.items[0][:id], p2.items[0][:id]
    assert_err(400, "invalid cursor") { @client.messages.list(limit: 1, cursor: "garbage") }
    assert_err(400, "invalid status") { @client.messages.list(status: "bogus") }
    items = @client.paginate(:messages, :list, limit: 2).first(3)
    assert_equal 3, items.size
  end

  def test_07_attempts
    attempts = @client.messages.attempts(STATE.fetch(:m))
    assert_kind_of Array, attempts
    refute_empty attempts
    first = attempts.first
    assert_equal 1, first[:sequence]
    assert first[:route_name].start_with?("Mock provider (sandbox)"), first[:route_name]
    assert_equal "delivered", first[:status]
    assert_equal "0.000000", first[:price]
  end

  def test_08_validation_error
    err = assert_err(400, "to must be an E.164 phone number") { @client.messages.send(to: "12345", text: "x") }
    assert_equal "Bad Request", err.title
    assert_equal "about:blank", err.type
  end

  def test_09_coded_error
    err = assert_err(400, "Message ID must be a valid UUID.") { @client.messages.get("not-a-uuid") }
    assert_equal "invalid_message_id", err.code
    assert_equal "https://api.opensms.io/problems/invalid_message_id", err.type
  end

  def test_10_not_found
    assert_err(404, "message not found") { @client.messages.get(ZERO_ID) }
  end

  def test_11_schedule_and_cancel
    msg = @client.messages.send(to: PHONE, text: "scheduled #{RUN}", scheduled_at: Time.now + 7200)
    assert_equal "scheduled", msg[:status]
    cancelled = @client.messages.cancel(msg[:id])
    assert_equal "cancelled", cancelled[:status]
    refute_nil cancelled[:cancelled_at]
    assert_err(409, "message cannot be cancelled in its current state") { @client.messages.cancel(msg[:id]) }
    assert_err(409, "message cannot be cancelled in its current state") { @client.messages.cancel(STATE.fetch(:m)) }
  end

  def test_12_batch
    batch = @client.batches.create(items: [
                                     { to: PHONE, text: "b1 #{RUN}" },
                                     { to: PHONE2, text: "b2 #{RUN}" },
                                     { to: "bad", text: "x" }
                                   ])
    assert_equal "ready", batch[:status]
    assert_equal 3, batch[:total]
    assert_equal 1, batch[:invalid]
    assert_equal 0, batch[:sent]
    report = @client.batches.validation(batch[:id])
    assert_equal 3, report[:rows].size
    assert_equal 2, report[:valid]
    assert_equal false, report[:rows][2][:valid]
    assert_equal "to must be an E.164 phone number", report[:rows][2][:error]
    got = @client.batches.get(batch[:id])
    assert_equal [3, 1, 0], got.values_at(:total, :invalid, :sent)
    assert_equal "running", @client.batches.start(batch[:id])[:status]
    items = poll { (p = @client.batches.list_items(batch[:id])).items.size == 2 && p.items }
    items.each do |i|
      refute_nil i[:to]
      refute_nil i[:status]
    end
  end

  def test_13_batch_stop
    batch = @client.batches.create(items: [{ to: PHONE, text: "stop #{RUN}" }])
    stopped = @client.batches.stop(batch[:id])
    assert_equal({ id: batch[:id], status: "stopped", cancelled: 0 }, stopped.slice(:id, :status, :cancelled))
    assert_err(409, "batch is not ready to start") { @client.batches.start(batch[:id]) }
    assert_err(404, "batch not found") { @client.batches.get(ZERO_ID) }
  end

  def test_14_csv_batch
    batch = @client.batches.create_from_csv("to,text\n#{PHONE2},csv #{RUN}\n")
    assert_equal "ready", batch[:status]
    assert_equal 1, batch[:total]
    assert_equal 0, batch[:invalid]
  end

  def test_15_otp
    sent_at = Time.now - 5
    otp = @client.otp.send(to: OTP_PHONE, length: 6, ttl_seconds: 300)
    otp_id = otp[:otp_id]
    assert_match UUID, otp_id
    code = poll do
      found = @client.sandbox.list_messages(limit: 10).items.find do |m|
        m[:traffic_type] == "otp" && m[:text].to_s.match?(/Your OpenSMS verification code is (\d{6})/) &&
          Time.parse(m[:created_at]) >= sent_at
      end
      found && found[:text][/Your OpenSMS verification code is (\d{6})/, 1]
    end
    wrong = code == "000000" ? "111111" : "000000"
    res = @client.otp.verify(otp_id: otp_id, code: wrong)
    assert_equal false, res[:valid]
    assert_equal 4, res[:attempts_left]
    res = @client.otp.verify(otp_id: otp_id, code: code)
    assert_equal true, res[:valid]
    assert_equal 3, res[:attempts_left]
    assert_err(400, "template must contain {{code}}") { @client.otp.send(to: OTP_PHONE, template: "no placeholder") }
    assert_err(404, "OTP not found") { @client.otp.verify(otp_id: ZERO_ID, code: "123456") }
  end

  def test_16_lookup
    lookup = @client.lookups.create(to: LOOKUP_PHONE)
    assert_equal "completed", lookup[:state]
    assert_equal "KE", lookup[:country]
    assert_equal "mock", lookup[:source]
    assert_equal "0.000000", lookup[:price]
    got = @client.lookups.get(lookup[:id])
    assert_equal lookup[:id], got[:id]
    assert_equal lookup[:state], got[:state]
    err = assert_err(404, "Lookup not found.") { @client.lookups.get(ZERO_ID) }
    assert_equal "not_found", err.code
  end

  def test_17_to_19_contacts_groups_templates
    r1 = rphone
    contact = @client.contacts.create(e164: r1, name: "Ada #{RUN}", attributes: { tier: "gold" })
    assert_equal r1, contact[:e164]
    cid = contact[:id]
    assert_equal contact[:e164], @client.contacts.get(cid)[:e164]
    upd = @client.contacts.update(cid, name: "Ada L #{RUN}")
    assert_equal "Ada L #{RUN}", upd[:name]
    assert_equal "gold", upd[:attributes][:tier]
    assert(@client.paginate(:contacts, :list, limit: 200).any? { |c| c[:id] == cid })
    assert_err(409, "A record with this phone number or name already exists.") { @client.contacts.create(e164: r1) }

    # 18
    group = @client.contact_groups.create(name: "grp #{RUN}", contact_ids: [cid])
    assert_equal [cid], group[:contact_ids]
    gid = group[:id]
    assert_equal "grp2 #{RUN}", @client.contact_groups.update(gid, name: "grp2 #{RUN}")[:name]
    batch = @client.contact_groups.send(gid, text: "Hi #{RUN}")
    assert_equal "running", batch[:status]
    assert_equal 1, batch[:total]
    empty = @client.contact_groups.create(name: "empty #{RUN}")
    assert_err(422, "Group must contain between 1 and 1000 contacts.") do
      @client.contact_groups.send(empty[:id], text: "x")
    end
    @client.contact_groups.delete(empty[:id])

    # 19
    tpl = @client.templates.create(name: "tpl-#{RUN}", body: "Hi {{name}}", traffic_type: "transactional")
    assert_equal ["name"], tpl[:variables]
    upd = @client.templates.update(tpl[:id], body: "Hello {{name}}")
    assert_equal "Hello {{name}}", upd[:body]
    assert_equal ["name"], upd[:variables]
    assert_equal "running", @client.contact_groups.send(gid, template_id: tpl[:id], variables: { name: "Ada" })[:status]
    assert_nil @client.templates.delete(tpl[:id])
    assert_nil @client.contact_groups.delete(gid)
    assert_nil @client.contacts.delete(cid)
    assert_err(404, "Record not found.") { @client.contacts.get(cid) }
  end

  def test_20_webhooks
    hook = @client.webhooks.create(url: "https://example.com/opensms/#{RUN}",
                                   events: ["message.delivered", "message.failed"])
    assert hook[:secret].start_with?("whsec_")
    assert_equal true, hook[:enabled]
    id = hook[:id]
    assert_nil @client.webhooks.get(id)[:secret]
    assert_err(400, "url must be an HTTPS URL without credentials or fragment") do
      @client.webhooks.create(url: "http://example.com/x", events: ["message.delivered"])
    end
    upd = @client.webhooks.update(id, url: "https://example.com/opensms/#{RUN}/v2", events: ["message.delivered"],
                                      enabled: true)
    assert_equal "https://example.com/opensms/#{RUN}/v2", upd[:url]
    assert_equal ["message.delivered"], upd[:events]
    assert_equal({ status: "pending" }, @client.webhooks.test(id))
    delivery = poll { @client.webhooks.list_deliveries(id).items.find { |d| d[:event] == "webhook.test" } }
    assert_kind_of Integer, delivery[:id]
    assert_kind_of Integer, delivery[:generation]
    begin
      res = @client.webhooks.replay_delivery(id, delivery[:id], generation: delivery[:generation],
                                                                reason: "sdk conformance replay")
      refute_nil res[:status]
    rescue Opensms::Error => e
      assert_equal 409, e.status
      assert_equal "Delivery state, lease or generation does not permit replay.", e.detail
    end
    assert_nil @client.webhooks.delete(id)
    assert_err(404, "webhook not found") { @client.webhooks.get(id) }
  end

  def test_21_suppressions
    r2 = rphone
    sup = @client.suppressions.create(e164: r2, reason: "manual")
    assert_kind_of Integer, sup[:id]
    assert_equal "manual", sup[:reason]
    err = assert_err(422, "destination is suppressed") { @client.messages.send(to: r2, text: "x") }
    assert_kind_of String, err.request_id
    refute_empty err.request_id
    assert(@client.paginate(:suppressions, :list, limit: 200).any? { |s| s[:e164] == r2 })
    assert_equal({ created: 1, received: 1 }, @client.suppressions.import([{ e164: rphone, reason: "complaint" }]))
    assert_nil @client.suppressions.delete(sup[:id])
    assert_err(404, "suppression not found") { @client.suppressions.delete(sup[:id]) }
  end

  def test_22_compliance
    ke = @client.compliance.get_country("KE")
    assert_equal "KE", ke[:iso2]
    assert_equal "+254", ke[:dial_code]
    assert_includes ke[:stop_keywords], "STOP"
    assert_err(404, "country not found") { @client.compliance.get_country("ZZ") }
    assert(@client.compliance.list_countries.any? { |c| c[:iso2] == "KE" })
    rules = @client.compliance.list_content_rules
    assert_kind_of Array, rules
    rules.each { |r| assert_kind_of Integer, r[:id] }
  end

  def test_23_wallet
    balances = @client.wallet.balances
    refute_empty balances
    assert_equal "sandbox", balances.first[:environment]
    assert_equal "KES", balances.first[:currency]
    assert_match(/\A-?\d+\.\d+\z/, balances.first[:balance])
    ledger = @client.wallet.ledger(limit: 1)
    assert_equal 1, ledger.size
    assert_kind_of Integer, ledger.first[:id]
    assert_err(400, "limit must be between 1 and 200") { @client.wallet.ledger(limit: 0) }
    assert_err(422, "sandbox wallets cannot use payment providers") do
      @client.wallet.create_topup(amount: "100", currency: "KES", channel: "card", email: "dev@opensms.test")
    end
  end

  def test_24_pricing
    prices = @client.pricing.get(product: "sms", country: "KE")
    assert_equal "KES", prices[:currency]
    assert_equal "sms", prices[:product]
    prices[:entries].each { |e| assert_equal "KE", e[:country_iso2] }
    assert_err(400, "product must be sms, lookup, or number_monthly") { @client.pricing.get(product: "bogus") }
  end

  def test_25_analytics
    ov = @client.analytics.overview
    assert_equal "sandbox", ov[:environment]
    assert_equal "KES", ov[:currency]
    assert_kind_of Integer, ov[:sent]
    refute_nil @client.analytics.overview(range: "7d")
    %i[by_country by_carrier by_sender_id timeseries].each do |m|
      assert_kind_of Array, @client.analytics.public_send(m), m
    end
  end

  def test_26_numbers_and_inbound
    assert_kind_of Opensms::Page, @client.numbers.list
    assert_kind_of Array, @client.numbers.available(country: "KE", kind: "long_code")
    assert_err(422, "This operation requires the live environment.") do
      @client.numbers.assign(country: "KE", kind: "long_code")
    end
    inbound = @client.inbound.list
    assert_kind_of Opensms::Page, inbound
    assert_equal [], inbound.items
  end

  def test_27_sender_ids
    assert(@client.paginate(:sender_ids, :list, limit: 200).any? { |s| s[:value] == "OPENSMS" && s[:status] == "approved" })
    assert_equal true, @client.sender_ids.check(value: "ACME", country: "KE")[:valid]
    assert @client.sender_ids.quote(countries: ["KE"])[:quote_id].start_with?("sq_")
    assert_kind_of Array, @client.sender_ids.list_documents
    value = "SDK#{Array.new(4) { ('A'..'Z').to_a.sample }.join}"
    draft = @client.sender_ids.create_draft(source: "application", value: value, kind: "alphanumeric",
                                            countries: ["KE"], use_case: "transactional",
                                            sample_message: "Your order shipped")
    assert_equal 1, draft[:version]
    assert_equal "active", draft[:status]
    upd = @client.sender_ids.update_draft(draft[:id], version: 1, sample_message: "Your order has shipped")
    assert_equal 2, upd[:version]
    assert_equal draft[:id], @client.sender_ids.get_draft(draft[:id])[:id]
    assert_nil @client.sender_ids.delete_draft(draft[:id])
    assert_err(404, "sender ID not found") { @client.sender_ids.get(ZERO_ID) }
  end

  def test_28_countries
    ke = @client.countries.list.find { |c| c[:iso2] == "KE" }
    refute_nil ke
    assert_equal "+254", ke[:dial_code]
    refute_empty @client.countries.carriers("KE")
    assert_kind_of Array, @client.countries.routes("KE")
    assert_equal "KE", @client.countries.compliance("KE")[:iso2]
  end

  def test_29_scope_errors
    skip "OPENSMS_READONLY_API_KEY is not set" if READONLY_KEY.to_s.empty?

    ro = Opensms::Client.new(api_key: READONLY_KEY, base_url: BASE_URL, timeout: 60)
    assert_err(401, "insufficient scope") { ro.messages.send(to: PHONE, text: "x") }
    assert_err(403, "Insufficient API key scope.") { ro.contacts.list }
    assert_kind_of Opensms::Page, ro.messages.list(limit: 1)
  end
end
