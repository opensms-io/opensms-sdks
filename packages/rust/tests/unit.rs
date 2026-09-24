//! Offline unit tests through an injected mock transport (CONFORMANCE.md,
//! "Mock-transport unit tests"). No network; sleeping is replaced by a
//! recorder that returns immediately.

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use opensms::{
    BoxFuture, Client, CreateBatch, ErrorKind, HttpRequest, HttpResponse, ListMessages, Message,
    OpensmsError, QuoteSenderId, RequestOptions, SendMessage, Sleeper, Transport, VerifyOptions,
    VerifyOtp, USER_AGENT,
};
use serde_json::{json, Value};

const KEY: &str = "sk_test_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

type Canned = Result<HttpResponse, String>;

#[derive(Default)]
struct MockTransport {
    responses: Mutex<VecDeque<Canned>>,
    fallback: Mutex<Option<Canned>>,
    requests: Mutex<Vec<HttpRequest>>,
}

impl MockTransport {
    fn new(responses: Vec<Canned>) -> Arc<Self> {
        Arc::new(Self {
            responses: Mutex::new(responses.into()),
            ..Default::default()
        })
    }
    fn always(r: Canned) -> Arc<Self> {
        let m = Self::default();
        *m.fallback.lock().unwrap() = Some(r);
        Arc::new(m)
    }
    fn requests(&self) -> Vec<HttpRequest> {
        self.requests.lock().unwrap().clone()
    }
}

impl Transport for MockTransport {
    fn send(
        &self,
        request: HttpRequest,
        _timeout: Duration,
    ) -> BoxFuture<'_, Result<HttpResponse, String>> {
        self.requests.lock().unwrap().push(request);
        let next = self
            .responses
            .lock()
            .unwrap()
            .pop_front()
            .or_else(|| self.fallback.lock().unwrap().clone())
            .expect("no canned response left");
        Box::pin(async move { next })
    }
}

#[derive(Default)]
struct RecordingSleeper {
    delays: Mutex<Vec<Duration>>,
}

impl Sleeper for RecordingSleeper {
    fn sleep(&self, duration: Duration) -> BoxFuture<'static, ()> {
        self.delays.lock().unwrap().push(duration);
        Box::pin(async {})
    }
}

fn resp(status: u16, body: Value) -> Canned {
    let body = if body.is_null() {
        Vec::new()
    } else {
        serde_json::to_vec(&body).unwrap()
    };
    Ok(HttpResponse {
        status,
        headers: vec![("content-type".into(), "application/json".into())],
        body,
    })
}

fn resp_h(status: u16, headers: &[(&str, &str)], body: &str) -> Canned {
    Ok(HttpResponse {
        status,
        headers: headers
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect(),
        body: body.as_bytes().to_vec(),
    })
}

fn problem(status: u16, detail: &str) -> Canned {
    resp(
        status,
        json!({"type": "about:blank", "title": "Error", "status": status, "detail": detail}),
    )
}

fn message_json() -> Value {
    json!({"id": "00000000-0000-0000-0000-000000000002", "to": "+254700000012", "status": "queued", "price": "0.000000"})
}

fn setup(responses: Vec<Canned>) -> (Client, Arc<MockTransport>, Arc<RecordingSleeper>) {
    let t = MockTransport::new(responses);
    let s = Arc::new(RecordingSleeper::default());
    let c = Client::builder(KEY)
        .base_url("http://host/")
        .transport(t.clone())
        .sleeper(s.clone())
        .build()
        .unwrap();
    (c, t, s)
}

fn with(t: Arc<MockTransport>) -> (Client, Arc<RecordingSleeper>) {
    let s = Arc::new(RecordingSleeper::default());
    let c = Client::builder(KEY)
        .base_url("http://host")
        .transport(t)
        .sleeper(s.clone())
        .build()
        .unwrap();
    (c, s)
}

// 1. Header injection
#[tokio::test]
async fn header_injection() {
    let (c, t, _) = setup(vec![resp(201, message_json()), resp(200, message_json())]);
    c.messages()
        .send(&SendMessage::new("+254700000012", "hi"))
        .await
        .unwrap();
    c.messages().get("abc").await.unwrap();
    let reqs = t.requests();
    for r in &reqs {
        assert_eq!(
            r.header("authorization"),
            Some(format!("Bearer {KEY}").as_str())
        );
        assert_eq!(r.header("accept"), Some("application/json"));
        assert_eq!(r.header("user-agent"), Some(USER_AGENT));
        assert!(r.header("x-workspace-id").is_none());
        assert!(r.header("x-environment").is_none());
    }
    assert_eq!(USER_AGENT, "opensms-rust/0.1.0");
    assert_eq!(reqs[0].header("content-type"), Some("application/json"));
    assert!(reqs[1].header("content-type").is_none());
}

// 2. Base URL
#[tokio::test]
async fn base_url_default_and_trailing_slash() {
    let d = Client::new(KEY).unwrap();
    assert_eq!(d.base_url(), "https://api.opensms.io");
    let (c, t, _) = setup(vec![resp(201, message_json())]);
    c.messages()
        .send(&SendMessage::new("+254700000012", "hi"))
        .await
        .unwrap();
    assert_eq!(t.requests()[0].url, "http://host/v1/messages");
}

// 3. Key validation
#[test]
fn key_validation() {
    for bad in [
        "",
        "pk_test_x",
        "sk_test_short",
        "not_a_key",
        "sk_test_123456789012",
    ] {
        let e = Client::new(bad).unwrap_err();
        assert_eq!(e.kind, ErrorKind::InvalidArgument, "{bad}");
        assert_eq!(e.status, 0);
    }
    let live = Client::new(format!("sk_live_{}", "B".repeat(32))).unwrap();
    assert_eq!(live.environment(), "live");
    let test = Client::new(format!("sk_test_{}", "B".repeat(32))).unwrap();
    assert_eq!(test.environment(), "sandbox");
}

// 4. Body mapping
#[tokio::test]
async fn body_mapping_snake_case_and_omits_unset() {
    let (c, t, _) = setup(vec![resp(201, message_json()), resp(201, message_json())]);
    let p = SendMessage {
        sender_id: Some("ACME".into()),
        traffic_type: Some("marketing".into()),
        scheduled_at: Some("2026-09-24T12:00:00Z".into()),
        callback_url: Some("https://example.com/cb".into()),
        metadata: Some(json!({"k": "v"})),
        ..SendMessage::new("+254700000012", "hi")
    };
    c.messages().send(&p).await.unwrap();
    let body: Value = serde_json::from_slice(t.requests()[0].body.as_ref().unwrap()).unwrap();
    let mut keys: Vec<&String> = body.as_object().unwrap().keys().collect();
    keys.sort();
    assert_eq!(
        keys,
        vec![
            "callback_url",
            "metadata",
            "scheduled_at",
            "sender_id",
            "text",
            "to",
            "traffic_type"
        ]
    );
    c.messages()
        .send(&SendMessage::new("+254700000012", "hi"))
        .await
        .unwrap();
    let body: Value = serde_json::from_slice(t.requests()[1].body.as_ref().unwrap()).unwrap();
    assert_eq!(body, json!({"to": "+254700000012", "text": "hi"}));
}

// 5. Idempotency-Key auto
#[tokio::test]
async fn idempotency_key_auto_explicit_and_absent() {
    let (c, t, _) = setup(vec![
        resp(201, message_json()),
        resp(201, message_json()),
        resp(200, message_json()),
    ]);
    c.messages()
        .send(&SendMessage::new("+254700000012", "hi"))
        .await
        .unwrap();
    c.messages()
        .send_with(
            &SendMessage::new("+254700000012", "hi"),
            &RequestOptions::idempotency_key("my-key"),
        )
        .await
        .unwrap();
    c.messages().get("x").await.unwrap();
    let reqs = t.requests();
    let auto = reqs[0].header("idempotency-key").unwrap();
    assert_eq!(auto.len(), 36);
    assert_eq!(auto.matches('-').count(), 4);
    assert_eq!(reqs[1].header("idempotency-key"), Some("my-key"));
    assert!(reqs[2].header("idempotency-key").is_none());
}

// 6. Retry on 429 with Retry-After
#[tokio::test]
async fn retry_429_honours_retry_after_and_reuses_key() {
    let (c, t, s) = setup(vec![
        resp_h(
            429,
            &[
                ("Retry-After", "2"),
                ("Content-Type", "application/problem+json"),
            ],
            r#"{"type":"about:blank","title":"Too Many Requests","status":429,"detail":"rate limited"}"#,
        ),
        resp(201, message_json()),
    ]);
    c.messages()
        .send(&SendMessage::new("+254700000012", "hi"))
        .await
        .unwrap();
    let reqs = t.requests();
    assert_eq!(reqs.len(), 2);
    assert_eq!(*s.delays.lock().unwrap(), vec![Duration::from_secs(2)]);
    assert_eq!(
        reqs[0].header("idempotency-key"),
        reqs[1].header("idempotency-key")
    );
    assert!(reqs[0].header("idempotency-key").is_some());
}

// 7. Retry on 503 without Retry-After
#[tokio::test]
async fn retry_503_backoff_within_first_window() {
    let (c, t, s) = setup(vec![
        problem(503, "database unavailable"),
        resp(200, message_json()),
    ]);
    c.messages().get("x").await.unwrap();
    assert_eq!(t.requests().len(), 2);
    let d = s.delays.lock().unwrap().clone();
    assert_eq!(d.len(), 1);
    assert!(d[0] <= Duration::from_millis(500));
}

// 8. Retries exhausted
#[tokio::test]
async fn retries_exhausted_after_three_attempts() {
    let t = MockTransport::always(problem(500, "boom"));
    let (c, _) = with(t.clone());
    let e = c.messages().get("x").await.unwrap_err();
    assert_eq!(e.status, 500);
    assert_eq!(t.requests().len(), 3);
}

// 9. Retry-After too large
#[tokio::test]
async fn retry_after_over_60_is_not_retried() {
    let (c, t, s) = setup(vec![resp_h(
        429,
        &[("Retry-After", "120")],
        r#"{"title":"Too Many Requests","status":429}"#,
    )]);
    let e = c.messages().get("x").await.unwrap_err();
    assert_eq!(e.status, 429);
    assert_eq!(e.retry_after, Some(120));
    assert_eq!(t.requests().len(), 1);
    assert!(s.delays.lock().unwrap().is_empty());
}

// 10. No retry on 400/401/404/409/422
#[tokio::test]
async fn no_retry_on_client_errors() {
    for status in [400u16, 401, 404, 409, 422] {
        let t = MockTransport::always(problem(status, "nope"));
        let (c, _) = with(t.clone());
        let e = c
            .messages()
            .send(&SendMessage::new("+254700000012", "hi"))
            .await
            .unwrap_err();
        assert_eq!(e.status, status);
        assert_eq!(e.kind, ErrorKind::Api);
        assert_eq!(t.requests().len(), 1, "status {status}");
    }
}

// 11. No retry for non-idempotent POST
#[tokio::test]
async fn no_retry_for_non_idempotent_posts() {
    let t = MockTransport::always(problem(503, "unavailable"));
    let (c, _) = with(t.clone());
    let e = c
        .otp()
        .verify(&VerifyOtp::new("id", "123456"))
        .await
        .unwrap_err();
    assert_eq!(e.status, 503);
    assert_eq!(t.requests().len(), 1);
    assert!(t.requests()[0].header("idempotency-key").is_none());

    let t = MockTransport::always(problem(503, "unavailable"));
    let (c, _) = with(t.clone());
    let e = c.messages().cancel("id").await.unwrap_err();
    assert_eq!(e.status, 503);
    assert_eq!(t.requests().len(), 1);
}

// 12. Network error
#[tokio::test]
async fn network_errors_retry_then_succeed_or_status_zero() {
    let (c, t, _) = setup(vec![
        Err("reset".into()),
        Err("reset".into()),
        resp(200, message_json()),
    ]);
    c.messages().get("x").await.unwrap();
    assert_eq!(t.requests().len(), 3);

    let t = MockTransport::always(Err("connection refused".into()));
    let (c, _) = with(t.clone());
    let e = c.messages().get("x").await.unwrap_err();
    assert_eq!(e.status, 0);
    assert_eq!(e.kind, ErrorKind::Transport);
    assert_eq!(t.requests().len(), 3);
}

// 13. Error mapping
#[tokio::test]
async fn error_mapping() {
    let body = r#"{"type":"https://api.opensms.io/problems/invalid_message_id","title":"Bad Request","status":400,"detail":"Message ID must be a valid UUID.","code":"invalid_message_id","trace_id":"t1","errors":{"to":["bad"]}}"#;
    let (c, _, _) = setup(vec![
        resp_h(400, &[("Content-Type", "application/problem+json")], body),
        problem(404, "message not found"),
        resp_h(
            422,
            &[("X-Request-ID", "r1")],
            r#"{"type":"about:blank","title":"Unprocessable Entity","status":422,"detail":"destination is suppressed"}"#,
        ),
        resp_h(
            502,
            &[("Content-Type", "text/html")],
            "<html>bad gateway</html>",
        ),
    ]);
    let e = c.messages().get("x").await.unwrap_err();
    assert_eq!(e.status, 400);
    assert_eq!(
        e.r#type.as_deref(),
        Some("https://api.opensms.io/problems/invalid_message_id")
    );
    assert_eq!(e.title.as_deref(), Some("Bad Request"));
    assert_eq!(
        e.detail.as_deref(),
        Some("Message ID must be a valid UUID.")
    );
    assert_eq!(e.code.as_deref(), Some("invalid_message_id"));
    assert_eq!(e.trace_id.as_deref(), Some("t1"));
    assert_eq!(e.errors.as_ref().unwrap()["to"], vec!["bad".to_string()]);
    assert_eq!(e.message, "Message ID must be a valid UUID.");

    let e = c.messages().get("x").await.unwrap_err();
    assert_eq!(e.code, None);

    let e = c
        .messages()
        .send(&SendMessage::new("+254700000012", "x"))
        .await
        .unwrap_err();
    assert_eq!(e.request_id.as_deref(), Some("r1"));

    let c2 = Client::builder(KEY)
        .base_url("http://host")
        .max_retries(0)
        .transport(MockTransport::new(vec![resp_h(
            502,
            &[("Content-Type", "text/html")],
            "<html>bad gateway</html>",
        )]))
        .build()
        .unwrap();
    let e = c2.messages().get("x").await.unwrap_err();
    assert_eq!(e.status, 502);
    assert_eq!(e.detail, None);
    assert_eq!(
        e.body,
        Some(Value::String("<html>bad gateway</html>".into()))
    );
    assert_eq!(e.message, "OpenSMS request failed with status 502");
}

// 14. 204 handling
#[tokio::test]
async fn delete_204_returns_unit() {
    let (c, t, _) = setup(vec![resp(204, Value::Null)]);
    c.contacts().delete("c1").await.unwrap();
    let r = &t.requests()[0];
    assert_eq!(r.method, "DELETE");
    assert_eq!(r.url, "http://host/v1/contacts/c1");
}

// 15. Pagination
#[tokio::test]
async fn pagination_follows_cursor() {
    let (c, t, _) = setup(vec![
        resp(
            200,
            json!({"items": [{"id": "a"}, {"id": "b"}], "next_cursor": "c1"}),
        ),
        resp(200, json!({"items": [{"id": "c"}], "next_cursor": null})),
    ]);
    let mut it = c.paginate(|cursor| {
        c.messages().list(ListMessages {
            limit: Some(2),
            cursor,
            ..Default::default()
        })
    });
    let mut ids = Vec::new();
    while let Some(m) = it.next().await {
        let m: Message = m.unwrap();
        ids.push(m.id);
    }
    assert_eq!(ids, vec!["a", "b", "c"]);
    let reqs = t.requests();
    assert_eq!(reqs.len(), 2);
    assert_eq!(reqs[0].url, "http://host/v1/messages?limit=2");
    assert_eq!(reqs[1].url, "http://host/v1/messages?limit=2&cursor=c1");
}

// 16. Query encoding
#[tokio::test]
async fn query_encoding() {
    let (c, t, _) = setup(vec![
        resp(
            200,
            json!({"quote_id": "sq_1", "entries": [], "totals": []}),
        ),
        resp(200, json!({"items": [], "next_cursor": null})),
    ]);
    c.sender_ids()
        .quote(&QuoteSenderId {
            countries: vec!["KE".into(), "NG".into()],
        })
        .await
        .unwrap();
    c.messages()
        .list(ListMessages {
            status: Some("delivered".into()),
            to: Some("+2547".into()),
            ..Default::default()
        })
        .await
        .unwrap();
    let reqs = t.requests();
    assert_eq!(
        reqs[0].url,
        "http://host/v1/sender-ids/quote?countries=KE,NG"
    );
    assert_eq!(
        reqs[1].url,
        "http://host/v1/messages?status=delivered&to=%2B2547"
    );
}

// 17. Path escaping
#[tokio::test]
async fn path_escaping_and_empty_id() {
    let (c, t, _) = setup(vec![resp(200, message_json())]);
    c.messages().get("a/b").await.unwrap();
    assert_eq!(t.requests()[0].url, "http://host/v1/messages/a%2Fb");
    let e = c.messages().get("").await.unwrap_err();
    assert_eq!(e.kind, ErrorKind::InvalidArgument);
    assert_eq!(t.requests().len(), 1);
}

// 18. Webhook signature vector
const SECRET: &str = "whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE";
const TS: i64 = 1790208000;
const BODY: &str = r#"{"id":"evt_01","type":"message.delivered","workspace_id":"00000000-0000-0000-0000-000000000001","environment":"sandbox","created_at":"2026-09-24T00:00:00Z","data":{"id":"00000000-0000-0000-0000-000000000002","status":"delivered"}}"#;
const SIG: &str = "eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23";

fn at(now: i64) -> VerifyOptions {
    VerifyOptions {
        now: Some(now),
        ..Default::default()
    }
}

#[test]
fn webhook_signature_vector() {
    use opensms::webhook::{construct_event, verify_signature};
    assert_eq!(BODY.len(), 230);
    let header = format!("t={TS},v1={SIG}");
    let b = BODY.as_bytes();
    assert!(verify_signature(b, &header, SECRET, at(TS)));
    assert!(verify_signature(b, &header, SECRET, at(TS + 300)));
    assert!(!verify_signature(b, &header, SECRET, at(TS + 301)));
    assert!(!verify_signature(b, &header, SECRET, at(TS - 301)));
    let tampered = BODY.replace(r#""status":"delivered""#, r#""status":"failed""#);
    assert!(!verify_signature(
        tampered.as_bytes(),
        &header,
        SECRET,
        at(TS)
    ));
    assert!(!verify_signature(
        b,
        &header,
        SECRET.trim_start_matches("whsec_"),
        at(TS)
    ));
    assert!(verify_signature(
        b,
        &format!("v1={SIG},t={TS}"),
        SECRET,
        at(TS)
    ));
    assert!(!verify_signature(
        b,
        &format!("{header},v0=abc"),
        SECRET,
        at(TS)
    ));
    assert!(!verify_signature(b, &format!("t={TS}"), SECRET, at(TS)));
    assert!(verify_signature(
        b,
        &format!("t={TS},v1={}", SIG.to_uppercase()),
        SECRET,
        at(TS)
    ));
    assert!(!verify_signature(b, &header, "", at(TS)));

    let ev = construct_event(b, &header, SECRET, at(TS)).unwrap();
    assert_eq!(ev.r#type.as_deref(), Some("message.delivered"));
    assert_eq!(ev.data.as_ref().unwrap()["status"], "delivered");

    let e: OpensmsError =
        construct_event(tampered.as_bytes(), &header, SECRET, at(TS)).unwrap_err();
    assert_eq!(e.code.as_deref(), Some("invalid_signature"));
    assert_eq!(e.status, 0);
    let e = construct_event(b, &header, SECRET, at(TS + 301)).unwrap_err();
    assert_eq!(e.code.as_deref(), Some("expired_signature"));

    // Also reachable from the client.
    let c = Client::new(KEY).unwrap();
    assert!(c.webhooks().verify_signature(b, &header, SECRET, at(TS)));
}

// 19. Batch CSV
#[tokio::test]
async fn batch_csv_sends_text_csv_with_key() {
    let (c, t, _) = setup(vec![resp(
        202,
        json!({"id": "b1", "status": "ready", "total": 1}),
    )]);
    let csv = "to,text\n+254700000014,hello\n";
    let b = c.batches().create_from_csv(csv, None).await.unwrap();
    assert_eq!(b.total, Some(1));
    let r = &t.requests()[0];
    assert_eq!(r.url, "http://host/v1/messages/batch");
    assert_eq!(r.header("content-type"), Some("text/csv"));
    assert_eq!(r.body.as_deref(), Some(csv.as_bytes()));
    assert_eq!(r.header("idempotency-key").map(str::len), Some(36));
}

#[tokio::test]
async fn batch_json_body() {
    let (c, t, _) = setup(vec![resp(202, json!({"id": "b1", "status": "ready"}))]);
    c.batches()
        .create(&CreateBatch {
            items: vec![opensms::BatchItemInput::new("+254700000012", "x")],
            dedupe: None,
        })
        .await
        .unwrap();
    let body: Value = serde_json::from_slice(t.requests()[0].body.as_ref().unwrap()).unwrap();
    assert_eq!(
        body,
        json!({"items": [{"to": "+254700000012", "text": "x"}]})
    );
}

// 20. Decimal strings and unknown fields
#[tokio::test]
async fn decimal_strings_and_unknown_fields() {
    let (c, _, _) = setup(vec![resp(
        200,
        json!({
            "id": "m1", "price": "0.000000", "currency": "KES", "brand_new_field": {"x": 1}
        }),
    )]);
    let m = c.messages().get("m1").await.unwrap();
    assert_eq!(m.price.as_deref(), Some("0.000000"));
    assert_eq!(m.status, None);
}
