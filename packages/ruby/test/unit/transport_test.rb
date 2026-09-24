# frozen_string_literal: true

require "test_helper"

# CONFORMANCE.md "Mock-transport unit tests" 1-3, 5-14, 17, 20.
class TransportTest < Minitest::Test
  include ClientHelpers

  # 1. Header injection
  def test_headers_are_injected_and_workspace_headers_never_sent
    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send(to: "+254700000012", text: "hi")
    h = @http.last.headers
    assert_equal "Bearer #{KEY}", h["Authorization"]
    assert_equal "application/json", h["Accept"]
    assert_equal "opensms-ruby/#{Opensms::VERSION}", h["User-Agent"]
    assert_equal "opensms-ruby/0.1.0", h["User-Agent"]
    assert_equal "application/json", h["Content-Type"]
    refute h.keys.any? { |k| k.casecmp?("X-Workspace-ID") || k.casecmp?("X-Environment") }
  end

  def test_get_has_no_content_type
    @http.enqueue(status: 200, body: sample_msg)
    @client.messages.get("abc")
    refute @http.last.headers.key?("Content-Type")
    assert_nil @http.last.body
  end

  def test_timeout_is_passed_to_http_client
    client = build_client(timeout: 45)
    @http.enqueue(status: 200, body: sample_msg)
    client.messages.get("abc")
    assert_equal 45, @http.last.timeout
  end

  # 2. Base URL
  def test_default_base_url
    client = Opensms::Client.new(api_key: KEY, http_client: @http)
    assert_equal "https://api.opensms.io", client.base_url
    @http.enqueue(status: 200, body: { items: [], next_cursor: nil })
    client.messages.list
    assert_equal "https://api.opensms.io/v1/messages", @http.last.url
  end

  def test_trailing_slash_is_stripped
    client = Opensms::Client.new(api_key: KEY, base_url: "http://host/", http_client: @http)
    @http.enqueue(status: 201, body: sample_msg)
    client.messages.send(to: "+254700000012", text: "x")
    assert_equal "http://host/v1/messages", @http.last.url
  end

  # 3. Key validation
  def test_key_validation
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: nil) }
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: "") }
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: "pk_test_x") }
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: "sk_test_short") }
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: "not_a_key") }
    assert_raises(ArgumentError) { Opensms::Client.new(api_key: "sk_test_#{'a' * 12}") }
    assert_equal "sandbox", Opensms::Client.new(api_key: "sk_test_#{'a' * 13}").environment
    assert_equal "live", Opensms::Client.new(api_key: "sk_live_#{'A' * 32}").environment
    assert_equal "sandbox", Opensms::Client.new(api_key: "sk_test_#{'A' * 32}").environment
    assert_empty @http.requests
  end

  # 5. Idempotency-Key
  def test_idempotency_key_generated_explicit_and_absent_on_get
    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send(to: "+254700000012", text: "hi")
    key = @http.last.headers["Idempotency-Key"]
    assert_equal 36, key.length
    assert_match(/\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, key)

    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send({ to: "+254700000012", text: "hi" }, idempotency_key: "my-key-1")
    assert_equal "my-key-1", @http.last.headers["Idempotency-Key"]

    @http.enqueue(status: 201, body: sample_msg)
    @client.messages.send(to: "+254700000012", text: "hi")
    refute_equal key, @http.last.headers["Idempotency-Key"]

    @http.enqueue(status: 200, body: sample_msg)
    @client.messages.get("x")
    refute @http.last.headers.key?("Idempotency-Key")
  end

  # 6. Retry on 429 with Retry-After
  def test_retry_on_429_honours_retry_after_and_reuses_idempotency_key
    @http.enqueue_problem(429, "too many requests", headers: { "Retry-After" => "2" })
    @http.enqueue(status: 201, body: sample_msg)
    msg = @client.messages.send(to: "+254700000012", text: "hi")
    assert_equal sample_msg[:id], msg[:id]
    assert_equal 2, @http.requests.size
    assert_equal [2], @sleeps
    keys = @http.requests.map { |r| r.headers["Idempotency-Key"] }
    refute_nil keys[0]
    assert_equal keys[0], keys[1]
  end

  def test_retry_after_http_date
    date = (Time.now + 3).httpdate
    @http.enqueue_problem(503, "busy", headers: { "Retry-After" => date })
    @http.enqueue(status: 200, body: sample_msg)
    @client.messages.get("x")
    assert_equal 2, @http.requests.size
    assert_operator @sleeps.first, :<=, 4
    assert_operator @sleeps.first, :>=, 0
  end

  # 7. Retry on 503 without Retry-After
  def test_retry_on_503_with_backoff
    client = Opensms::Client.new(api_key: KEY, http_client: @http, sleeper: ->(s) { @sleeps << s })
    @http.enqueue_problem(503, "unavailable")
    @http.enqueue(status: 200, body: sample_msg)
    client.messages.get("x")
    assert_equal 2, @http.requests.size
    assert_equal 1, @sleeps.size
    assert_operator @sleeps.first, :>=, 0
    assert_operator @sleeps.first, :<=, 0.5
  end

  def test_backoff_grows_and_is_capped
    client = build_client(max_retries: 6, random: -> { 0.999999 })
    6.times { @http.enqueue_problem(500, "boom") }
    @http.enqueue(status: 200, body: sample_msg)
    client.messages.get("x")
    caps = [0.5, 1, 2, 4, 8, 8]
    @sleeps.zip(caps).each { |s, cap| assert_in_delta cap, s, 0.001 }
  end

  # 8. Retries exhausted
  def test_retries_exhausted
    3.times { @http.enqueue_problem(500, "boom") }
    err = assert_raises(Opensms::Error) { @client.messages.get("x") }
    assert_equal 500, err.status
    assert_equal 3, @http.requests.size
  end

  def test_max_retries_zero_disables_retries
    client = build_client(max_retries: 0)
    @http.enqueue_problem(503, "busy")
    assert_raises(Opensms::Error) { client.messages.get("x") }
    assert_equal 1, @http.requests.size
  end

  # 9. Retry-After too large
  def test_retry_after_over_60_is_not_retried
    @http.enqueue_problem(429, "slow down", headers: { "Retry-After" => "120" })
    err = assert_raises(Opensms::Error) { @client.messages.get("x") }
    assert_equal 429, err.status
    assert_equal 120, err.retry_after
    assert_equal 1, @http.requests.size
    assert_empty @sleeps
  end

  # 10. No retry on 4xx
  def test_no_retry_on_client_errors
    [400, 401, 402, 403, 404, 409, 410, 413, 422].each do |status|
      http = MockHttp.new
      client = Opensms::Client.new(api_key: KEY, http_client: http, sleeper: ->(_) {})
      http.enqueue_problem(status, "nope")
      err = assert_raises(Opensms::Error) { client.messages.send(to: "+254700000012", text: "x") }
      assert_equal status, err.status
      assert_equal 1, http.requests.size, "status #{status} was retried"
    end
  end

  # 11. No retry for non-idempotent POSTs
  def test_no_retry_for_non_idempotent_posts
    calls = {
      "otp.verify" => -> { @client.otp.verify(otp_id: "o", code: "123456") },
      "messages.cancel" => -> { @client.messages.cancel("m") },
      "sender_ids.create" => lambda {
        @client.sender_ids.create(value: "ACME", kind: "alphanumeric", countries: ["KE"], documents: [])
      },
      "sender_ids.create_draft" => -> { @client.sender_ids.create_draft(value: "ACME") },
      "suppressions.create" => -> { @client.suppressions.create(e164: "+254700000001", reason: "manual") },
      "suppressions.import" => -> { @client.suppressions.import([{ e164: "+254700000001", reason: "manual" }]) }
    }
    calls.each do |name, call|
      before = @http.requests.size
      @http.enqueue_problem(503, "busy")
      @http.enqueue(status: 200, body: {})
      err = assert_raises(Opensms::Error, name) { call.call }
      assert_equal 503, err.status
      assert_equal 1, @http.requests.size - before, "#{name} was retried"
      refute @http.last.headers.key?("Idempotency-Key"), "#{name} sent an Idempotency-Key"
      @http.requests.clear
      @http.instance_variable_get(:@queue).clear
    end
  end

  # 12. Network errors
  def test_network_error_is_retried_on_get
    @http.enqueue_error.enqueue_error(Net::ReadTimeout.new)
    @http.enqueue(status: 200, body: sample_msg)
    assert_equal sample_msg[:id], @client.messages.get("x")[:id]
    assert_equal 3, @http.requests.size
  end

  def test_network_error_exhausted_gives_status_zero
    3.times { @http.enqueue_error }
    err = assert_raises(Opensms::Error) { @client.messages.get("x") }
    assert_equal 0, err.status
    assert_equal 3, @http.requests.size
  end

  def test_network_error_on_non_idempotent_post_is_not_retried
    @http.enqueue_error
    err = assert_raises(Opensms::Error) { @client.otp.verify(otp_id: "o", code: "123456") }
    assert_equal 0, err.status
    assert_equal 1, @http.requests.size
  end

  # 13. Error mapping
  def test_problem_mapping
    body = '{"type":"https://api.opensms.io/problems/invalid_message_id","title":"Bad Request","status":400,' \
           '"detail":"Message ID must be a valid UUID.","code":"invalid_message_id","trace_id":"t1",' \
           '"errors":{"to":["bad"]}}'
    @http.enqueue(status: 400, body: body, headers: { "Content-Type" => "application/problem+json" })
    err = assert_raises(Opensms::Error) { @client.messages.get("x") }
    assert_equal 400, err.status
    assert_equal "https://api.opensms.io/problems/invalid_message_id", err.type
    assert_equal "Bad Request", err.title
    assert_equal "Message ID must be a valid UUID.", err.detail
    assert_equal "invalid_message_id", err.code
    assert_equal "t1", err.trace_id
    assert_equal ["bad"], err.errors[:to]
    assert_equal "Message ID must be a valid UUID.", err.message
    assert_kind_of StandardError, err
  end

  def test_about_blank_has_nil_code
    @http.enqueue_problem(401, "missing or invalid API key", title: "Unauthorized")
    err = assert_raises(Opensms::Error) { @client.messages.get("x") }
    assert_nil err.code
    assert_equal "about:blank", err.type
    assert_nil err.request_id
  end

  def test_request_id_header
    @http.enqueue_problem(422, "destination is suppressed", headers: { "X-Request-ID" => "r1" })
    err = assert_raises(Opensms::Error) { @client.messages.send(to: "+254700000012", text: "x") }
    assert_equal "r1", err.request_id
  end

  def test_html_error_body
    html = "<html><body>Bad gateway</body></html>"
    client = build_client(max_retries: 0)
    @http.enqueue(status: 502, body: html, headers: { "Content-Type" => "text/html" })
    err = assert_raises(Opensms::Error) { client.messages.get("x") }
    assert_equal 502, err.status
    assert_nil err.detail
    assert_nil err.title
    assert_equal html, err.body
    assert_equal "OpenSMS request failed with status 502", err.message
  end

  def test_message_falls_back_to_title
    client = build_client(max_retries: 0)
    @http.enqueue(status: 500, body: { title: "Internal Server Error", status: 500 })
    err = assert_raises(Opensms::Error) { client.messages.get("x") }
    assert_equal "Internal Server Error", err.message
  end

  def test_unknown_problem_fields_preserved_in_body
    @http.enqueue_problem(400, "bad", extra_field: "kept")
    err = assert_raises(Opensms::Error) { @client.messages.get("x") }
    assert_equal "kept", err.body[:extra_field]
  end

  # 14. 204 handling
  def test_204_returns_nil
    @http.enqueue(status: 204, body: nil)
    assert_nil @client.contacts.delete("c1")
    assert_equal :delete, @http.last.method
  end

  # 17. Path escaping
  def test_path_escaping
    @http.enqueue(status: 200, body: sample_msg)
    @client.messages.get("a/b")
    assert_equal "http://mock.local/v1/messages/a%2Fb", @http.last.url
    @http.enqueue(status: 200, body: sample_msg)
    @client.messages.get("a b?c")
    assert_equal "http://mock.local/v1/messages/a%20b%3Fc", @http.last.url
  end

  def test_empty_id_fails_without_request
    assert_raises(ArgumentError) { @client.messages.get("") }
    assert_raises(ArgumentError) { @client.messages.get(nil) }
    assert_raises(ArgumentError) { @client.webhooks.replay_delivery("w", nil, generation: 1, reason: "again") }
    assert_empty @http.requests
  end

  # 20. Decimal strings and unknown fields
  def test_decimal_strings_and_unknown_fields
    @http.enqueue(status: 200, body: '{"id":"m1","price":"0.000000","brand_new_field":{"x":1}}',
                  headers: { "Content-Type" => "application/json" })
    msg = @client.messages.get("m1")
    assert_equal "0.000000", msg[:price]
    assert_kind_of String, msg[:price]
    assert_equal "m1", msg[:id]
  end
end
