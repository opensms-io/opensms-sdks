//! Live conformance scenario (CONFORMANCE.md, "Live scenario"), run in order
//! against a real OpenSMS API. Skipped (passes with a notice) unless
//! `OPENSMS_BASE_URL` and `OPENSMS_API_KEY` are set. Never creates accounts
//! or keys.
//!
//! ```sh
//! source ../../spec/fixtures/credentials.sh
//! cargo test --test live -- --nocapture
//! ```

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime};

use opensms::{
    AnalyticsQuery, BatchItemInput, BoxFuture, CheckSenderId, Client, CreateBatch, CreateContact,
    CreateContactGroup, CreateLookup, CreateSenderIdDraft, CreateSuppression, CreateTemplate,
    CreateTopup, CreateWebhook, ErrorKind, HttpRequest, HttpResponse, LedgerParams, ListBatchItems,
    ListMessages, ListParams, NumberQuery, OpensmsError, PricingParams, QuoteSenderId,
    ReplayDelivery, RequestOptions, ReqwestTransport, SendMessage, SendOtp, SendToGroup, Transport,
    UpdateContact, UpdateContactGroup, UpdateSenderIdDraft, UpdateTemplate, UpdateWebhook,
    VerifyOtp,
};
use serde_json::json;

const ZERO: &str = "00000000-0000-0000-0000-000000000000";

/// Counts attempts while delegating to the real transport.
struct Counting {
    inner: ReqwestTransport,
    count: AtomicUsize,
}

impl Transport for Counting {
    fn send(&self, r: HttpRequest, t: Duration) -> BoxFuture<'_, Result<HttpResponse, String>> {
        self.count.fetch_add(1, Ordering::SeqCst);
        self.inner.send(r, t)
    }
}

fn env() -> Option<(String, String)> {
    let base = std::env::var("OPENSMS_BASE_URL")
        .ok()
        .filter(|s| !s.is_empty())?;
    let key = std::env::var("OPENSMS_API_KEY")
        .ok()
        .filter(|s| !s.is_empty())?;
    Some((base, key))
}

fn client(base: &str, key: &str) -> Client {
    Client::builder(key)
        .base_url(base)
        .timeout(Duration::from_secs(60))
        .build()
        .expect("client builds")
}

fn rand_hex(n: usize) -> String {
    let mut s = String::new();
    while s.len() < n {
        s.push_str(&opensms::uuid_v4().replace('-', ""));
    }
    s[..n].to_string()
}

fn rand_phone() -> String {
    let digits: String = rand_hex(8)
        .bytes()
        .map(|b| char::from(b'0' + (b % 10)))
        .collect();
    format!("+2547{digits}")
}

/// A random Safaricom-range KE number (`+25470` + 7 digits). The API limits
/// admissions per destination (5 per hour, 3 OTPs per 10 minutes), so the
/// shared `+254700000012` from CONFORMANCE.md is exhausted when several SDK
/// suites run in parallel; each send here gets a fresh destination instead.
fn rand_ke() -> String {
    let digits: String = rand_hex(7)
        .bytes()
        .map(|b| char::from(b'0' + (b % 10)))
        .collect();
    format!("+25470{digits}")
}

fn rand_upper(n: usize) -> String {
    rand_hex(n)
        .bytes()
        .map(|b| char::from(b'A' + (b % 26)))
        .collect()
}

#[track_caller]
fn expect_err<T: std::fmt::Debug>(
    r: Result<T, OpensmsError>,
    status: u16,
    detail: &str,
) -> OpensmsError {
    let e = r.expect_err(&format!("expected ERR({status}, {detail})"));
    assert_eq!(e.status, status, "status for {detail:?}: got {e:?}");
    assert_eq!(e.detail.as_deref(), Some(detail), "detail: got {e:?}");
    e
}

async fn pause() {
    tokio::time::sleep(Duration::from_millis(750)).await;
}

#[tokio::test]
async fn live_conformance() {
    let Some((base, key)) = env() else {
        eprintln!("SKIPPED: set OPENSMS_BASE_URL and OPENSMS_API_KEY to run the live conformance scenario");
        return;
    };
    let run = rand_hex(8);
    let c = client(&base, &key);
    let started = Instant::now();
    let step = |n: u32, name: &str| {
        eprintln!(
            "[{:>6.1}s] step {n}: {name}",
            started.elapsed().as_secs_f64()
        )
    };

    // 1. Constructor
    step(1, "constructor");
    assert_eq!(
        Client::new("not_a_key").unwrap_err().kind,
        ErrorKind::InvalidArgument
    );
    assert_eq!(
        Client::new("sk_test_short").unwrap_err().kind,
        ErrorKind::InvalidArgument
    );

    // 2. Auth error, exactly one attempt
    step(2, "auth error");
    let counting = Arc::new(Counting {
        inner: ReqwestTransport::new().unwrap(),
        count: AtomicUsize::new(0),
    });
    let bad = Client::builder(format!("sk_test_{}", "A".repeat(32)))
        .base_url(&base)
        .timeout(Duration::from_secs(60))
        .transport(counting.clone())
        .build()
        .unwrap();
    let e = expect_err(
        bad.messages()
            .list(ListMessages {
                limit: Some(1),
                ..Default::default()
            })
            .await,
        401,
        "missing or invalid API key",
    );
    assert_eq!(e.r#type.as_deref(), Some("about:blank"));
    assert_eq!(e.title.as_deref(), Some("Unauthorized"));
    assert_eq!(e.code, None);
    assert_eq!(counting.count.load(Ordering::SeqCst), 1);

    // 3. Send
    step(3, "send");
    let to3 = rand_ke();
    let m = c
        .messages()
        .send(&SendMessage {
            metadata: Some(json!({"sdk": "rust", "run": run})),
            ..SendMessage::new(&to3, format!("conformance rust {run}"))
        })
        .await
        .expect("send");
    assert_eq!(m.id.len(), 36);
    assert_eq!(m.to.as_deref(), Some(to3.as_str()));
    assert_eq!(m.sender_id.as_deref(), Some("OPENSMS"));
    assert_eq!(m.traffic_type.as_deref(), Some("transactional"));
    assert!(
        ["queued", "sending", "sent", "delivered"].contains(&m.status.as_deref().unwrap()),
        "{:?}",
        m.status
    );
    assert_eq!(m.parts, Some(1));
    assert_eq!(m.encoding.as_deref(), Some("gsm7"));
    assert_eq!(m.country_iso2.as_deref(), Some("KE"));
    assert_eq!(m.currency.as_deref(), Some("KES"));
    assert_eq!(m.price.as_deref(), Some("0.000000"));
    assert_eq!(m.metadata.as_ref().unwrap()["run"], run.as_str());
    let mid = m.id.clone();

    // 4. Idempotent replay
    step(4, "idempotent replay");
    let k = RequestOptions::idempotency_key(format!("rust-{run}-{}", rand_hex(8)));
    let to4 = rand_ke();
    let p = SendMessage::new(&to4, format!("idem rust {run}"));
    let a = c.messages().send_with(&p, &k).await.expect("idem 1");
    let b = c.messages().send_with(&p, &k).await.expect("idem 2");
    assert_eq!(a.id, b.id);
    let p2 = SendMessage::new(&to4, format!("idem rust {run} changed"));
    expect_err(
        c.messages().send_with(&p2, &k).await,
        409,
        "Idempotency-Key was already used with a different request",
    );

    // 5. Get and wait for delivery
    step(5, "get and wait");
    let deadline = Instant::now() + Duration::from_secs(20);
    let delivered = loop {
        let g = c.messages().get(&mid).await.expect("get");
        if g.status.as_deref() == Some("delivered") {
            break g;
        }
        assert!(
            Instant::now() < deadline,
            "message not delivered in 20 s: {:?}",
            g.status
        );
        pause().await;
    };
    assert!(delivered.delivered_at.is_some());
    assert!(delivered.sent_at.is_some());
    assert_eq!(
        delivered.text.as_deref(),
        Some(format!("conformance rust {run}").as_str())
    );

    // 6. List + cursor
    step(6, "list and cursor");
    let p1 = c
        .messages()
        .list(ListMessages {
            limit: Some(1),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(p1.items.len(), 1);
    let cur = p1.next_cursor.clone().expect("next_cursor");
    let p2 = c
        .messages()
        .list(ListMessages {
            limit: Some(1),
            cursor: Some(cur),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(p2.items.len(), 1);
    assert_ne!(p1.items[0].id, p2.items[0].id);
    expect_err(
        c.messages()
            .list(ListMessages {
                limit: Some(1),
                cursor: Some("garbage".into()),
                ..Default::default()
            })
            .await,
        400,
        "invalid cursor",
    );
    expect_err(
        c.messages()
            .list(ListMessages {
                status: Some("bogus".into()),
                ..Default::default()
            })
            .await,
        400,
        "invalid status",
    );
    let mut it = c.paginate(|cursor| {
        c.messages().list(ListMessages {
            limit: Some(2),
            cursor,
            ..Default::default()
        })
    });
    let mut seen = 0;
    while let Some(item) = it.next().await {
        item.expect("paginate");
        seen += 1;
        if seen == 3 {
            break;
        }
    }
    assert_eq!(seen, 3);

    // 7. Attempts
    step(7, "attempts");
    let atts = c.messages().attempts(&mid).await.unwrap();
    assert!(!atts.is_empty());
    assert_eq!(atts[0].sequence, Some(1));
    assert!(atts[0]
        .route_name
        .as_deref()
        .unwrap()
        .starts_with("Mock provider (sandbox)"));
    assert_eq!(atts[0].status.as_deref(), Some("delivered"));
    assert_eq!(atts[0].price.as_deref(), Some("0.000000"));

    // 8. Validation error
    step(8, "validation error");
    let e = expect_err(
        c.messages().send(&SendMessage::new("12345", "x")).await,
        400,
        "to must be an E.164 phone number",
    );
    assert_eq!(e.title.as_deref(), Some("Bad Request"));
    assert_eq!(e.r#type.as_deref(), Some("about:blank"));

    // 9. Coded error
    step(9, "coded error");
    let e = expect_err(
        c.messages().get("not-a-uuid").await,
        400,
        "Message ID must be a valid UUID.",
    );
    assert_eq!(e.code.as_deref(), Some("invalid_message_id"));
    assert_eq!(
        e.r#type.as_deref(),
        Some("https://api.opensms.io/problems/invalid_message_id")
    );

    // 10. Not found
    step(10, "not found");
    expect_err(c.messages().get(ZERO).await, 404, "message not found");

    // 11. Schedule and cancel
    step(11, "schedule and cancel");
    let at = opensms::rfc3339(SystemTime::now() + Duration::from_secs(7200));
    let s = c
        .messages()
        .send(&SendMessage {
            scheduled_at: Some(at),
            ..SendMessage::new(rand_ke(), format!("scheduled {run}"))
        })
        .await
        .unwrap();
    assert_eq!(s.status.as_deref(), Some("scheduled"));
    let cancelled = c.messages().cancel(&s.id).await.unwrap();
    assert_eq!(cancelled.status.as_deref(), Some("cancelled"));
    assert!(cancelled.cancelled_at.is_some());
    expect_err(
        c.messages().cancel(&s.id).await,
        409,
        "message cannot be cancelled in its current state",
    );
    expect_err(
        c.messages().cancel(&mid).await,
        409,
        "message cannot be cancelled in its current state",
    );

    // 12. Batch
    step(12, "batch");
    let batch = c
        .batches()
        .create(&CreateBatch {
            items: vec![
                BatchItemInput::new(rand_ke(), format!("b1 {run}")),
                BatchItemInput::new(rand_ke(), format!("b2 {run}")),
                BatchItemInput::new("bad", "x"),
            ],
            dedupe: None,
        })
        .await
        .unwrap();
    assert_eq!(batch.status.as_deref(), Some("ready"));
    assert_eq!(
        (batch.total, batch.invalid, batch.sent),
        (Some(3), Some(1), Some(0))
    );
    let rep = c.batches().validation(&batch.id).await.unwrap();
    assert_eq!(rep.rows.len(), 3);
    assert_eq!(rep.valid, Some(2));
    assert_eq!(rep.rows[2].valid, Some(false));
    assert_eq!(
        rep.rows[2].error.as_deref(),
        Some("to must be an E.164 phone number")
    );
    let g = c.batches().get(&batch.id).await.unwrap();
    assert_eq!((g.total, g.invalid, g.sent), (Some(3), Some(1), Some(0)));
    let started_b = c.batches().start(&batch.id).await.unwrap();
    assert_eq!(started_b.status.as_deref(), Some("running"));
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let items = c
            .batches()
            .list_items(&batch.id, ListBatchItems::default())
            .await
            .unwrap();
        if items.items.len() == 2 {
            for i in &items.items {
                assert!(i.to.is_some() && i.status.is_some());
            }
            break;
        }
        assert!(
            Instant::now() < deadline,
            "batch items: {}",
            items.items.len()
        );
        pause().await;
    }

    // 13. Batch stop
    step(13, "batch stop");
    let b2 = c
        .batches()
        .create(&CreateBatch {
            items: vec![BatchItemInput::new(rand_ke(), format!("stop {run}"))],
            dedupe: None,
        })
        .await
        .unwrap();
    let stopped = c.batches().stop(&b2.id).await.unwrap();
    assert_eq!(stopped.id, b2.id);
    assert_eq!(stopped.status.as_deref(), Some("stopped"));
    assert_eq!(stopped.cancelled, Some(0));
    expect_err(
        c.batches().start(&b2.id).await,
        409,
        "batch is not ready to start",
    );
    expect_err(c.batches().get(ZERO).await, 404, "batch not found");

    // 14. CSV batch
    step(14, "csv batch");
    let csvb = c
        .batches()
        .create_from_csv(format!("to,text\n{},csv {run}\n", rand_ke()), None)
        .await
        .unwrap();
    assert_eq!(csvb.status.as_deref(), Some("ready"));
    assert_eq!((csvb.total, csvb.invalid), (Some(1), Some(0)));

    // 15. OTP
    step(15, "otp");
    let otp_to = rand_ke();
    let otp_sent_at = SystemTime::now() - Duration::from_secs(5);
    let otp = c
        .otp()
        .send(&SendOtp {
            length: Some(6),
            ttl_seconds: Some(300),
            ..SendOtp::new(&otp_to)
        })
        .await
        .unwrap();
    assert_eq!(otp.otp_id.len(), 36);
    let since = opensms::rfc3339(otp_sent_at);
    let deadline = Instant::now() + Duration::from_secs(20);
    let code = 'outer: loop {
        let page = c
            .sandbox()
            .list_messages(ListParams::limit(10))
            .await
            .unwrap();
        for sm in &page.items {
            let text = sm.text.as_deref().unwrap_or("");
            let created = sm.created_at.as_deref().unwrap_or("");
            // Compare instants: normalise the created_at offset to UTC seconds.
            if sm.traffic_type.as_deref() == Some("otp")
                && sm.to.as_deref() == Some(otp_to.as_str())
                && utc_key(created) >= since
            {
                if let Some(rest) = text.strip_prefix("Your OpenSMS verification code is ") {
                    let digits: String = rest.chars().take(6).collect();
                    if digits.len() == 6 && digits.chars().all(|ch| ch.is_ascii_digit()) {
                        break 'outer digits;
                    }
                }
            }
        }
        assert!(
            Instant::now() < deadline,
            "OTP not visible in sandbox messages"
        );
        pause().await;
    };
    let wrong = if code == "000000" { "111111" } else { "000000" };
    let v = c
        .otp()
        .verify(&VerifyOtp::new(&otp.otp_id, wrong))
        .await
        .unwrap();
    assert_eq!((v.valid, v.attempts_left), (Some(false), Some(4)));
    let v = c
        .otp()
        .verify(&VerifyOtp::new(&otp.otp_id, &code))
        .await
        .unwrap();
    assert_eq!((v.valid, v.attempts_left), (Some(true), Some(3)));
    expect_err(
        c.otp()
            .send(&SendOtp {
                template: Some("no placeholder".into()),
                ..SendOtp::new(rand_ke())
            })
            .await,
        400,
        "template must contain {{code}}",
    );
    expect_err(
        c.otp().verify(&VerifyOtp::new(ZERO, "123456")).await,
        404,
        "OTP not found",
    );

    // 16. Lookup
    step(16, "lookup");
    let l = c
        .lookups()
        .create(&CreateLookup {
            to: "+254700000012".into(),
        })
        .await
        .unwrap();
    assert_eq!(l.state.as_deref(), Some("completed"));
    assert_eq!(l.country.as_deref(), Some("KE"));
    assert_eq!(l.source.as_deref(), Some("mock"));
    assert_eq!(l.price.as_deref(), Some("0.000000"));
    let lg = c.lookups().get(&l.id).await.unwrap();
    assert_eq!(
        (lg.id.as_str(), lg.state.as_deref()),
        (l.id.as_str(), l.state.as_deref())
    );
    let e = expect_err(c.lookups().get(ZERO).await, 404, "Lookup not found.");
    assert_eq!(e.code.as_deref(), Some("not_found"));

    // 17. Contacts
    step(17, "contacts");
    let r1 = rand_phone();
    let contact = c
        .contacts()
        .create(&CreateContact {
            e164: r1.clone(),
            name: Some(format!("Ada {run}")),
            attributes: Some(json!({"tier": "gold"})),
        })
        .await
        .unwrap();
    assert_eq!(contact.e164.as_deref(), Some(r1.as_str()));
    let cg = c.contacts().get(&contact.id).await.unwrap();
    assert_eq!(cg.id, contact.id);
    assert_eq!(cg.e164, contact.e164);
    let cu = c
        .contacts()
        .update(
            &contact.id,
            &UpdateContact {
                name: Some(format!("Ada L {run}")),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert_eq!(cu.name.as_deref(), Some(format!("Ada L {run}").as_str()));
    assert_eq!(cu.attributes.as_ref().unwrap()["tier"], "gold");
    let all = c
        .paginate(|cursor| {
            c.contacts().list(ListParams {
                limit: Some(200),
                cursor,
            })
        })
        .collect_all()
        .await
        .unwrap();
    assert!(all.iter().any(|x| x.id == contact.id));
    expect_err(
        c.contacts()
            .create(&CreateContact {
                e164: r1.clone(),
                ..Default::default()
            })
            .await,
        409,
        "A record with this phone number or name already exists.",
    );

    // 18. Contact groups
    step(18, "contact groups");
    let grp = c
        .contact_groups()
        .create(&CreateContactGroup {
            name: format!("grp {run}"),
            contact_ids: Some(vec![contact.id.clone()]),
        })
        .await
        .unwrap();
    assert_eq!(grp.contact_ids.as_deref(), Some(&[contact.id.clone()][..]));
    c.contact_groups()
        .update(
            &grp.id,
            &UpdateContactGroup {
                name: Some(format!("grp2 {run}")),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    let gb = c
        .contact_groups()
        .send(
            &grp.id,
            &SendToGroup {
                text: Some(format!("Hi {run}")),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert_eq!(gb.status.as_deref(), Some("running"));
    assert_eq!(gb.total, Some(1));
    let empty = c
        .contact_groups()
        .create(&CreateContactGroup {
            name: format!("empty {run}"),
            contact_ids: None,
        })
        .await
        .unwrap();
    expect_err(
        c.contact_groups()
            .send(
                &empty.id,
                &SendToGroup {
                    text: Some("x".into()),
                    ..Default::default()
                },
            )
            .await,
        422,
        "Group must contain between 1 and 1000 contacts.",
    );
    c.contact_groups().delete(&empty.id).await.unwrap();

    // 19. Templates
    step(19, "templates");
    let tpl = c
        .templates()
        .create(&CreateTemplate {
            name: format!("tpl-{run}"),
            body: "Hi {{name}}".into(),
            traffic_type: Some("transactional".into()),
        })
        .await
        .unwrap();
    assert_eq!(tpl.variables.as_deref(), Some(&["name".to_string()][..]));
    let tu = c
        .templates()
        .update(
            &tpl.id,
            &UpdateTemplate {
                body: Some("Hello {{name}}".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert_eq!(tu.body.as_deref(), Some("Hello {{name}}"));
    assert_eq!(tu.variables.as_deref(), Some(&["name".to_string()][..]));
    let tb = c
        .contact_groups()
        .send(
            &grp.id,
            &SendToGroup {
                template_id: Some(tpl.id.clone()),
                variables: Some(HashMap::from([("name".to_string(), "Ada".to_string())])),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert_eq!(tb.status.as_deref(), Some("running"));
    c.templates().delete(&tpl.id).await.unwrap();
    c.contact_groups().delete(&grp.id).await.unwrap();
    c.contacts().delete(&contact.id).await.unwrap();
    expect_err(
        c.contacts().get(&contact.id).await,
        404,
        "Record not found.",
    );

    // 20. Webhooks
    step(20, "webhooks");
    let wh = c
        .webhooks()
        .create(&CreateWebhook {
            url: format!("https://example.com/opensms/{run}"),
            events: vec!["message.delivered".into(), "message.failed".into()],
            enabled: None,
        })
        .await
        .unwrap();
    assert!(wh.secret.as_deref().unwrap().starts_with("whsec_"));
    assert_eq!(wh.enabled, Some(true));
    let whg = c.webhooks().get(&wh.id).await.unwrap();
    assert!(whg.secret.is_none());
    expect_err(
        c.webhooks()
            .create(&CreateWebhook {
                url: "http://example.com/x".into(),
                events: vec!["message.delivered".into()],
                enabled: None,
            })
            .await,
        400,
        "url must be an HTTPS URL without credentials or fragment",
    );
    let v2 = format!("https://example.com/opensms/{run}/v2");
    let whu = c
        .webhooks()
        .update(
            &wh.id,
            &UpdateWebhook {
                url: v2.clone(),
                events: vec!["message.delivered".into()],
                enabled: true,
            },
        )
        .await
        .unwrap();
    assert_eq!(whu.url.as_deref(), Some(v2.as_str()));
    assert_eq!(
        whu.events.as_deref(),
        Some(&["message.delivered".to_string()][..])
    );
    let tr = c.webhooks().test(&wh.id).await.unwrap();
    assert_eq!(tr.status.as_deref(), Some("pending"));
    let dels = c
        .webhooks()
        .list_deliveries(&wh.id, ListParams::default())
        .await
        .unwrap();
    let d = dels
        .items
        .iter()
        .find(|d| d.event.as_deref() == Some("webhook.test"))
        .expect("webhook.test delivery");
    let generation = d.generation.expect("generation");
    match c
        .webhooks()
        .replay_delivery(
            &wh.id,
            d.id,
            &ReplayDelivery {
                generation,
                reason: "sdk conformance replay".into(),
            },
        )
        .await
    {
        Ok(r) => assert!(r.status.is_some()),
        Err(e) => {
            assert_eq!(e.status, 409, "{e:?}");
            assert_eq!(
                e.detail.as_deref(),
                Some("Delivery state, lease or generation does not permit replay.")
            );
        }
    }
    c.webhooks().delete(&wh.id).await.unwrap();
    expect_err(c.webhooks().get(&wh.id).await, 404, "webhook not found");

    // 21. Suppressions
    step(21, "suppressions");
    let r2 = rand_phone();
    let sup = c
        .suppressions()
        .create(&CreateSuppression {
            e164: r2.clone(),
            reason: "manual".into(),
        })
        .await
        .unwrap();
    assert_eq!(sup.reason.as_deref(), Some("manual"));
    let e = expect_err(
        c.messages().send(&SendMessage::new(&r2, "x")).await,
        422,
        "destination is suppressed",
    );
    assert!(!e.request_id.as_deref().unwrap_or("").is_empty());
    let sups = c
        .paginate(|cursor| {
            c.suppressions().list(ListParams {
                limit: Some(200),
                cursor,
            })
        })
        .collect_all()
        .await
        .unwrap();
    assert!(sups.iter().any(|s| s.e164.as_deref() == Some(r2.as_str())));
    let r3 = rand_phone();
    let imp = c
        .suppressions()
        .import(&[CreateSuppression {
            e164: r3,
            reason: "complaint".into(),
        }])
        .await
        .unwrap();
    assert_eq!((imp.created, imp.received), (Some(1), Some(1)));
    c.suppressions().delete(sup.id).await.unwrap();
    expect_err(
        c.suppressions().delete(sup.id).await,
        404,
        "suppression not found",
    );

    // 22. Compliance
    step(22, "compliance");
    let ke = c.compliance().get_country("KE").await.unwrap();
    assert_eq!(ke.iso2.as_deref(), Some("KE"));
    assert_eq!(ke.dial_code.as_deref(), Some("+254"));
    assert!(ke
        .stop_keywords
        .as_ref()
        .unwrap()
        .iter()
        .any(|k| k == "STOP"));
    expect_err(
        c.compliance().get_country("ZZ").await,
        404,
        "country not found",
    );
    assert!(c
        .compliance()
        .list_countries()
        .await
        .unwrap()
        .iter()
        .any(|x| x.iso2.as_deref() == Some("KE")));
    let _rules = c.compliance().list_content_rules().await.unwrap();

    // 23. Wallet
    step(23, "wallet");
    let bal = c.wallet().balances().await.unwrap();
    assert!(!bal.is_empty());
    assert_eq!(bal[0].environment.as_deref(), Some("sandbox"));
    assert_eq!(bal[0].currency.as_deref(), Some("KES"));
    assert!(bal[0].balance.as_deref().unwrap().parse::<f64>().is_ok());
    let led = c
        .wallet()
        .ledger(LedgerParams {
            limit: Some(1),
            before: None,
        })
        .await
        .unwrap();
    assert_eq!(led.len(), 1);
    expect_err(
        c.wallet()
            .ledger(LedgerParams {
                limit: Some(0),
                before: None,
            })
            .await,
        400,
        "limit must be between 1 and 200",
    );
    expect_err(
        c.wallet()
            .create_topup(&CreateTopup {
                amount: "100".into(),
                currency: "KES".into(),
                channel: "card".into(),
                email: "dev@opensms.test".into(),
            })
            .await,
        422,
        "sandbox wallets cannot use payment providers",
    );

    // 24. Pricing
    step(24, "pricing");
    let pl = c
        .pricing()
        .get(PricingParams {
            product: Some("sms".into()),
            country: Some("KE".into()),
        })
        .await
        .unwrap();
    assert_eq!(pl.currency.as_deref(), Some("KES"));
    assert_eq!(pl.product.as_deref(), Some("sms"));
    assert!(pl
        .entries
        .as_ref()
        .unwrap()
        .iter()
        .all(|e| e.country_iso2.as_deref() == Some("KE")));
    expect_err(
        c.pricing()
            .get(PricingParams {
                product: Some("bogus".into()),
                country: None,
            })
            .await,
        400,
        "product must be sms, lookup, or number_monthly",
    );

    // 25. Analytics
    step(25, "analytics");
    let ov = c
        .analytics()
        .overview(AnalyticsQuery::default())
        .await
        .unwrap();
    assert_eq!(ov.environment.as_deref(), Some("sandbox"));
    assert_eq!(ov.currency.as_deref(), Some("KES"));
    assert!(ov.sent.is_some());
    c.analytics()
        .overview(AnalyticsQuery {
            range: Some("7d".into()),
            ..Default::default()
        })
        .await
        .unwrap();
    c.analytics()
        .by_country(AnalyticsQuery::default())
        .await
        .unwrap();
    c.analytics()
        .by_carrier(AnalyticsQuery::default())
        .await
        .unwrap();
    c.analytics()
        .by_sender_id(AnalyticsQuery::default())
        .await
        .unwrap();
    c.analytics()
        .timeseries(AnalyticsQuery::default())
        .await
        .unwrap();

    // 26. Numbers and inbound
    step(26, "numbers and inbound");
    c.numbers().list(ListParams::default()).await.unwrap();
    let q = NumberQuery {
        country: "KE".into(),
        kind: "long_code".into(),
    };
    c.numbers().available(&q).await.unwrap();
    expect_err(
        c.numbers().assign(&q).await,
        422,
        "This operation requires the live environment.",
    );
    let inb = c.inbound().list(ListParams::default()).await.unwrap();
    assert!(inb.items.is_empty());

    // Extra coverage beyond CONFORMANCE.md: the remaining list/get methods
    // and the live-only writes, which a sandbox key sees as 4xx.
    step(26, "extra coverage");
    c.webhooks().list(ListParams::limit(5)).await.unwrap();
    c.templates().list(ListParams::limit(5)).await.unwrap();
    let groups = c.contact_groups().list(ListParams::limit(5)).await.unwrap();
    if let Some(g0) = groups.items.first() {
        c.contact_groups().get(&g0.id).await.unwrap();
    }
    let rule = opensms::NumberRuleInput {
        r#match: "any".into(),
        pattern: None,
        action: "auto_reply".into(),
        target: "Thanks".into(),
        position: None,
    };
    let live_only = "This operation requires the live environment.";
    for (name, r) in [
        ("release", c.numbers().release(ZERO).await.map(|_| ())),
        (
            "list_rules",
            c.numbers()
                .list_rules(ZERO, ListParams::default())
                .await
                .map(|_| ()),
        ),
        (
            "create_rule",
            c.numbers().create_rule(ZERO, &rule).await.map(|_| ()),
        ),
        (
            "update_rule",
            c.numbers().update_rule(ZERO, ZERO, &rule).await.map(|_| ()),
        ),
        (
            "delete_rule",
            c.numbers().delete_rule(ZERO, ZERO).await.map(|_| ()),
        ),
    ] {
        let e = r.expect_err(name);
        assert_eq!(
            (e.status, e.detail.as_deref()),
            (422, Some(live_only)),
            "numbers.{name}"
        );
    }
    let e = c
        .inbound()
        .reply(ZERO, &opensms::ReplyInbound { text: "hi".into() })
        .await
        .expect_err("inbound.reply");
    assert!(matches!(e.status, 404 | 422), "inbound.reply: {e:?}");
    let e = c
        .sender_ids()
        .create(&opensms::CreateSenderId {
            value: format!("SDK{}", rand_upper(4)),
            kind: "alphanumeric".into(),
            countries: vec!["KE".into()],
            documents: vec![],
            ..Default::default()
        })
        .await
        .expect_err("sender_ids.create");
    assert!((400..500).contains(&e.status), "sender_ids.create: {e:?}");
    let e = c
        .sender_ids()
        .update(
            ZERO,
            &opensms::UpdateSenderId {
                use_case: "transactional".into(),
                countries: vec!["KE".into()],
                documents: vec![],
                sample_message: None,
            },
        )
        .await
        .expect_err("sender_ids.update");
    assert!((400..500).contains(&e.status), "sender_ids.update: {e:?}");
    let e = c
        .sender_ids()
        .delete(ZERO)
        .await
        .expect_err("sender_ids.delete");
    assert_eq!(e.status, 404, "sender_ids.delete: {e:?}");

    // 27. Sender IDs
    step(27, "sender ids");
    let sids = c.sender_ids().list(ListParams::default()).await.unwrap();
    assert!(sids
        .items
        .iter()
        .any(|s| s.value.as_deref() == Some("OPENSMS") && s.status.as_deref() == Some("approved")));
    let chk = c
        .sender_ids()
        .check(&CheckSenderId {
            value: "ACME".into(),
            country: Some("KE".into()),
        })
        .await
        .unwrap();
    assert_eq!(chk.valid, Some(true));
    let quote = c
        .sender_ids()
        .quote(&QuoteSenderId {
            countries: vec!["KE".into()],
        })
        .await
        .unwrap();
    assert!(quote.quote_id.as_deref().unwrap().starts_with("sq_"));
    c.sender_ids().list_documents().await.unwrap();
    let draft = c
        .sender_ids()
        .create_draft(&CreateSenderIdDraft {
            source: Some("application".into()),
            value: Some(format!("SDK{}", rand_upper(4))),
            kind: Some("alphanumeric".into()),
            countries: Some(vec!["KE".into()]),
            use_case: Some("transactional".into()),
            sample_message: Some("Your order shipped".into()),
            documents: None,
        })
        .await
        .unwrap();
    assert_eq!(draft.version, Some(1));
    assert_eq!(draft.status.as_deref(), Some("active"));
    let du = c
        .sender_ids()
        .update_draft(
            &draft.id,
            &UpdateSenderIdDraft {
                version: 1,
                sample_message: Some("Your order has shipped".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert_eq!(du.version, Some(2));
    c.sender_ids()
        .list_drafts(ListParams::default())
        .await
        .unwrap();
    c.sender_ids().get_draft(&draft.id).await.unwrap();
    c.sender_ids().delete_draft(&draft.id).await.unwrap();
    expect_err(c.sender_ids().get(ZERO).await, 404, "sender ID not found");

    // 28. Countries
    step(28, "countries");
    let countries = c.countries().list().await.unwrap();
    assert!(countries
        .iter()
        .any(|x| x.iso2.as_deref() == Some("KE") && x.dial_code.as_deref() == Some("+254")));
    assert!(!c.countries().carriers("KE").await.unwrap().is_empty());
    c.countries().routes("KE").await.unwrap();
    assert_eq!(
        c.countries()
            .compliance("KE")
            .await
            .unwrap()
            .iso2
            .as_deref(),
        Some("KE")
    );

    // 29. Scope errors
    match std::env::var("OPENSMS_READONLY_API_KEY")
        .ok()
        .filter(|s| !s.is_empty())
    {
        Some(ro) => {
            step(29, "scope errors");
            let r = client(&base, &ro);
            expect_err(
                r.messages().send(&SendMessage::new(rand_ke(), "x")).await,
                401,
                "insufficient scope",
            );
            expect_err(
                r.contacts().list(ListParams::default()).await,
                403,
                "Insufficient API key scope.",
            );
            r.messages()
                .list(ListMessages {
                    limit: Some(1),
                    ..Default::default()
                })
                .await
                .unwrap();
        }
        None => eprintln!("step 29 skipped: OPENSMS_READONLY_API_KEY not set"),
    }
    eprintln!(
        "live conformance passed in {:.1}s",
        started.elapsed().as_secs_f64()
    );
}

/// Convert an RFC 3339 timestamp with any offset into a UTC
/// `YYYY-MM-DDTHH:MM:SSZ` string so it compares lexically with
/// [`opensms::rfc3339`] output.
fn utc_key(ts: &str) -> String {
    let parse = || -> Option<String> {
        let (date, rest) = ts.split_once('T')?;
        let secs_end = rest.find(['Z', '+', '-'])?;
        let time = &rest[..secs_end];
        let hms: String = time.chars().take(8).collect();
        let off = &rest[secs_end..];
        let offset_secs: i64 = if off.starts_with('Z') {
            0
        } else {
            let sign = if off.starts_with('-') { -1 } else { 1 };
            let h: i64 = off.get(1..3)?.parse().ok()?;
            let m: i64 = off.get(4..6)?.parse().ok()?;
            sign * (h * 3600 + m * 60)
        };
        let mut d = date.split('-').map(|p| p.parse::<i64>());
        let (y, mo, da) = (d.next()?.ok()?, d.next()?.ok()?, d.next()?.ok()?);
        let mut t = hms.split(':').map(|p| p.parse::<i64>());
        let (h, mi, s) = (t.next()?.ok()?, t.next()?.ok()?, t.next()?.ok()?);
        // days from civil
        let yy = if mo <= 2 { y - 1 } else { y };
        let era = yy.div_euclid(400);
        let yoe = yy - era * 400;
        let doy = (153 * (if mo > 2 { mo - 3 } else { mo + 9 }) + 2) / 5 + da - 1;
        let days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;
        let unix = days * 86400 + h * 3600 + mi * 60 + s - offset_secs;
        Some(opensms::rfc3339(
            SystemTime::UNIX_EPOCH + Duration::from_secs(unix as u64),
        ))
    };
    parse().unwrap_or_default()
}
