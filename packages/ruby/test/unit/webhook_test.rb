# frozen_string_literal: true

require "test_helper"

# CONFORMANCE.md "Mock-transport unit tests" 18: the DESIGN.md test vector.
class WebhookTest < Minitest::Test
  SECRET = "whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE"
  T = 1_790_208_000
  BODY = '{"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001",' \
         '"environment":"sandbox","created_at":"2026-09-24T00:00:00Z","data":{"id":"00000000-0000-0000-0000-000000000002",' \
         '"status":"delivered"}}'
  SIG = "eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23"
  HEADER = "t=#{T},v1=#{SIG}".freeze

  def verify(body: BODY, header: HEADER, secret: SECRET, now: T)
    Opensms::Webhook.verify_signature(body, header, secret, now: now)
  end

  def test_vector_body_is_230_bytes
    assert_equal 230, BODY.bytesize
  end

  def test_valid
    assert verify
  end

  def test_tolerance_boundary_inclusive
    assert verify(now: T + 300)
  end

  def test_expired_future_and_past
    refute verify(now: T + 301)
    refute verify(now: T - 301)
  end

  def test_tampered_body
    refute verify(body: BODY.sub('"status":"delivered"', '"status":"failed"'))
  end

  def test_secret_without_prefix
    refute verify(secret: SECRET.delete_prefix("whsec_"))
  end

  def test_swapped_order
    assert verify(header: "v1=#{SIG},t=#{T}")
  end

  def test_extra_component
    refute verify(header: "#{HEADER},v0=abc")
  end

  def test_timestamp_only
    refute verify(header: "t=#{T}")
  end

  def test_uppercase_hex
    assert verify(header: "t=#{T},v1=#{SIG.upcase}")
  end

  def test_other_malformed_headers
    refute verify(header: nil)
    refute verify(header: "")
    refute verify(header: "#{HEADER},")
    refute verify(header: "t=#{T},v1=#{SIG},t=#{T}")
    refute verify(header: "t=abc,v1=#{SIG}")
    refute verify(header: "t=#{T},v1=#{SIG[0, 62]}")
    refute verify(header: " t = #{T},v1=#{SIG}")
    refute verify(secret: "")
    refute verify(secret: "   ")
  end

  def test_whitespace_around_parts_is_trimmed
    assert verify(header: " t=#{T} , v1=#{SIG} ")
  end

  def test_construct_event_valid
    event = Opensms::Webhook.construct_event(BODY, HEADER, SECRET, now: T)
    assert_equal "message.delivered", event.type
    assert_equal "delivered", event.data[:status]
    assert_equal "evt_01", event.id
    assert_equal "sandbox", event.environment
  end

  def test_construct_event_tampered
    err = assert_raises(Opensms::Error) do
      Opensms::Webhook.construct_event(BODY.sub("delivered\"}", "failed\"}"), HEADER, SECRET, now: T)
    end
    assert_equal "invalid_signature", err.code
    assert_equal 0, err.status
  end

  def test_construct_event_expired
    err = assert_raises(Opensms::Error) { Opensms::Webhook.construct_event(BODY, HEADER, SECRET, now: T + 301) }
    assert_equal "expired_signature", err.code
    assert_equal 0, err.status
  end

  def test_client_delegates
    client = Opensms::Client.new(api_key: "sk_test_#{'A' * 32}")
    assert client.webhooks.verify_signature(BODY, HEADER, SECRET, now: T)
    assert_equal "message.delivered", client.webhooks.construct_event(BODY, HEADER, SECRET, now: Time.at(T)).type
    refute client.webhooks.verify_signature(BODY, HEADER, SECRET, tolerance_seconds: 10, now: T + 11)
  end

  def test_default_now_is_current_time
    refute Opensms::Webhook.verify_signature(BODY, HEADER, SECRET)
  end
end
