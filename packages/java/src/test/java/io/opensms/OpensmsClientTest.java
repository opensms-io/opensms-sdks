package io.opensms;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.opensms.models.Batch;
import io.opensms.models.Message;
import io.opensms.models.OtpVerifyResult;
import io.opensms.models.Page;
import io.opensms.models.WebhookEvent;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

import static org.junit.jupiter.api.Assertions.*;

/** Offline mock-transport tests: CONFORMANCE.md "Mock-transport unit tests" 1 to 20. */
class OpensmsClientTest {

    static final String KEY = "sk_test_" + "A".repeat(32);
    static final String MSG = "{\"id\":\"11111111-1111-1111-1111-111111111111\",\"to\":\"+254700000012\","
            + "\"status\":\"queued\",\"price\":\"0.000000\",\"currency\":\"KES\",\"parts\":1,"
            + "\"created_at\":\"2026-09-24T07:42:35.56751+03:00\",\"brand_new_field\":{\"x\":1}}";
    static final String PROBLEM_503 = "{\"type\":\"about:blank\",\"title\":\"Service Unavailable\",\"status\":503,\"detail\":\"database unavailable\"}";
    private static final ObjectMapper M = new ObjectMapper();

    private static JsonNode json(String s) throws IOException {
        return M.readTree(s);
    }

    // 1
    @Test
    void headerInjection() {
        MockTransport mt = new MockTransport().reply(201, MSG);
        mt.client().messages().send(new SendMessageParams("+254700000012", "hi"));
        HttpTransport.Request r = mt.last();
        assertEquals("Bearer " + KEY, r.header("Authorization"));
        assertEquals("application/json", r.header("Accept"));
        assertEquals("opensms-java/0.1.1", r.header("User-Agent"));
        assertEquals("application/json", r.header("Content-Type"));
        assertNull(r.header("X-Workspace-ID"));
        assertNull(r.header("X-Environment"));

        mt.reply(200, MSG);
        mt.client().messages().get("abc");
        assertNull(mt.last().header("Content-Type"), "GET without a body sends no Content-Type");
        assertNull(mt.last().header("X-Workspace-ID"));
        assertNull(mt.last().header("X-Environment"));
    }

    // 2
    @Test
    void baseUrl() {
        assertEquals("https://opensms.io", new OpensmsClient(KEY).baseUrl());
        MockTransport mt = new MockTransport().reply(201, MSG);
        OpensmsClient c = OpensmsClient.builder().apiKey(KEY).baseUrl("http://host/").transport(mt).build();
        c.messages().send(new SendMessageParams("+254700000012", "hi"));
        assertEquals("http://host/v1/messages", mt.last().uri().toString());
    }

    // 3
    @Test
    void keyValidation() {
        assertThrows(IllegalArgumentException.class, () -> new OpensmsClient(null));
        assertThrows(IllegalArgumentException.class, () -> new OpensmsClient(""));
        assertThrows(IllegalArgumentException.class, () -> new OpensmsClient("pk_test_x"));
        assertThrows(IllegalArgumentException.class, () -> new OpensmsClient("sk_test_short"));
        assertThrows(IllegalArgumentException.class, () -> new OpensmsClient("not_a_key"));
        assertEquals("live", new OpensmsClient("sk_live_" + "b".repeat(32)).environment());
        assertEquals("sandbox", new OpensmsClient("sk_test_" + "b".repeat(32)).environment());
    }

    // 4
    @Test
    void bodyMapping() throws IOException {
        MockTransport mt = new MockTransport().reply(201, MSG);
        mt.client().messages().send(new SendMessageParams("+254700000012", "hello")
                .senderId("ACME").trafficType("otp").scheduledAt(Instant.parse("2026-10-01T10:00:00Z"))
                .callbackUrl("https://cb.test/x").metadata(Map.of("order", "42")));
        JsonNode b = json(MockTransport.body(mt.last()));
        Set<String> keys = new TreeSet<>();
        b.fieldNames().forEachRemaining(keys::add);
        assertEquals(new TreeSet<>(List.of("to", "text", "sender_id", "traffic_type", "scheduled_at",
                "callback_url", "metadata")), keys);
        assertEquals("2026-10-01T10:00:00Z", b.get("scheduled_at").asText());
        assertEquals("42", b.get("metadata").get("order").asText());

        mt.reply(201, MSG);
        mt.client().messages().send(new SendMessageParams("+254700000012", "hello"));
        String raw = MockTransport.body(mt.last());
        assertFalse(raw.contains("null"), "unset optionals are omitted, not null: " + raw);
        JsonNode b2 = json(raw);
        assertEquals(2, b2.size());
    }

    // 5
    @Test
    void idempotencyKeyAuto() {
        MockTransport mt = new MockTransport().reply(201, MSG);
        OpensmsClient c = mt.client();
        c.messages().send(new SendMessageParams("+254700000012", "hi"));
        String k = mt.last().header("Idempotency-Key");
        assertNotNull(k);
        assertEquals(36, k.length());
        assertTrue(k.matches("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"));

        c.messages().send(new SendMessageParams("+254700000012", "hi"), RequestOptions.idempotencyKey("my-key-1"));
        assertEquals("my-key-1", mt.last().header("Idempotency-Key"));

        mt.reply(200, MSG);
        c.messages().get("11111111-1111-1111-1111-111111111111");
        assertNull(mt.last().header("Idempotency-Key"));
    }

    // 6
    @Test
    void retryOn429WithRetryAfter() {
        MockTransport mt = new MockTransport()
                .reply(429, "{\"type\":\"about:blank\",\"title\":\"Too Many Requests\",\"status\":429,\"detail\":\"rate limited\"}",
                        "Retry-After", "2")
                .reply(201, MSG);
        Message m = mt.client().messages().send(new SendMessageParams("+254700000012", "hi"));
        assertEquals("11111111-1111-1111-1111-111111111111", m.id);
        assertEquals(2, mt.requests.size());
        assertEquals(List.of(Duration.ofSeconds(2)), mt.sleeps);
        String k1 = mt.requests.get(0).header("Idempotency-Key");
        assertNotNull(k1);
        assertEquals(k1, mt.requests.get(1).header("Idempotency-Key"));
    }

    // 7
    @Test
    void retryOn503WithoutRetryAfter() {
        MockTransport mt = new MockTransport().reply(503, PROBLEM_503).reply(200, MSG);
        Message m = mt.client().messages().get("x");
        assertNotNull(m);
        assertEquals(2, mt.requests.size());
        assertEquals(1, mt.sleeps.size());
        Duration d = mt.sleeps.get(0);
        assertFalse(d.isNegative());
        assertTrue(d.compareTo(Duration.ofMillis(500)) <= 0, "backoff within [0, 0.5 s]: " + d);
    }

    // 8
    @Test
    void retriesExhausted() {
        MockTransport mt = new MockTransport().reply(500, "{\"title\":\"Internal Server Error\",\"status\":500}");
        OpensmsClient c = OpensmsClient.builder().apiKey(KEY).baseUrl("http://mock.test").transport(mt)
                .maxRetries(2).sleeper(mt.sleeps::add).build();
        OpensmsException e = assertThrows(OpensmsException.class, () -> c.messages().list());
        assertEquals(500, e.getStatus());
        assertEquals(3, mt.requests.size());
        assertEquals(2, mt.sleeps.size());
        assertEquals("Internal Server Error", e.getMessage());
    }

    // 9
    @Test
    void retryAfterTooLarge() {
        MockTransport mt = new MockTransport().reply(429,
                "{\"type\":\"about:blank\",\"title\":\"Too Many Requests\",\"status\":429}", "Retry-After", "120");
        OpensmsException e = assertThrows(OpensmsException.class, () -> mt.client().messages().list());
        assertEquals(429, e.getStatus());
        assertEquals(120L, e.getRetryAfter());
        assertEquals(1, mt.requests.size());
        assertTrue(mt.sleeps.isEmpty());
    }

    // 10
    @Test
    void noRetryOnClientErrors() {
        for (int status : new int[] {400, 401, 404, 409, 422}) {
            MockTransport mt = new MockTransport().reply(status,
                    "{\"type\":\"about:blank\",\"title\":\"x\",\"status\":" + status + ",\"detail\":\"d" + status + "\"}");
            OpensmsException e = assertThrows(OpensmsException.class,
                    () -> mt.client().messages().send(new SendMessageParams("+254700000012", "hi")));
            assertEquals(status, e.getStatus());
            assertEquals("d" + status, e.getDetail());
            assertEquals(1, mt.requests.size(), "status " + status + " must not be retried");
        }
    }

    // 11
    @Test
    void noRetryForNonIdempotentPost() {
        MockTransport mt = new MockTransport().reply(503, PROBLEM_503);
        OpensmsException e = assertThrows(OpensmsException.class,
                () -> mt.client().otp().verify("22222222-2222-2222-2222-222222222222", "123456"));
        assertEquals(503, e.getStatus());
        assertEquals(1, mt.requests.size());
        assertNull(mt.last().header("Idempotency-Key"));

        MockTransport mt2 = new MockTransport().reply(503, PROBLEM_503);
        assertThrows(OpensmsException.class, () -> mt2.client().messages().cancel("m1"));
        assertEquals(1, mt2.requests.size());

        MockTransport mt3 = new MockTransport().reply(503, PROBLEM_503);
        assertThrows(OpensmsException.class, () -> mt3.client().suppressions().create("+254700000099", "manual"));
        assertEquals(1, mt3.requests.size());
    }

    // 12
    @Test
    void networkErrors() {
        MockTransport mt = new MockTransport()
                .fail(new IOException("connection reset"))
                .fail(new HttpTimeoutException("timed out"))
                .reply(200, MSG);
        assertNotNull(mt.client().messages().get("x"));
        assertEquals(3, mt.requests.size());

        MockTransport down = new MockTransport().fail(new IOException("connection refused"));
        OpensmsException e = assertThrows(OpensmsException.class, () -> down.client().messages().get("x"));
        assertEquals(0, e.getStatus());
        assertEquals(3, down.requests.size());
        assertNotNull(e.getCause());
    }

    // 13
    @Test
    void errorMapping() {
        MockTransport mt = new MockTransport().reply(400,
                "{\"type\":\"https://api.opensms.io/problems/invalid_message_id\",\"title\":\"Bad Request\",\"status\":400,"
                        + "\"detail\":\"Message ID must be a valid UUID.\",\"code\":\"invalid_message_id\",\"trace_id\":\"t1\","
                        + "\"errors\":{\"to\":[\"bad\"]}}");
        OpensmsException e = assertThrows(OpensmsException.class, () -> mt.client().messages().get("nope"));
        assertEquals(400, e.getStatus());
        assertEquals("https://api.opensms.io/problems/invalid_message_id", e.getType());
        assertEquals("Bad Request", e.getTitle());
        assertEquals("Message ID must be a valid UUID.", e.getDetail());
        assertEquals("invalid_message_id", e.getCode());
        assertEquals("t1", e.getTraceId());
        assertEquals(List.of("bad"), e.getErrors().get("to"));
        assertEquals("Message ID must be a valid UUID.", e.getMessage());
        assertInstanceOf(JsonNode.class, e.getBody());

        MockTransport blank = new MockTransport().reply(401,
                "{\"type\":\"about:blank\",\"title\":\"Unauthorized\",\"status\":401,\"detail\":\"missing or invalid API key\"}");
        OpensmsException e2 = assertThrows(OpensmsException.class, () -> blank.client().messages().list());
        assertNull(e2.getCode());
        assertEquals("about:blank", e2.getType());

        MockTransport rid = new MockTransport().reply(422,
                "{\"type\":\"about:blank\",\"title\":\"Unprocessable Entity\",\"status\":422,\"detail\":\"destination is suppressed\"}",
                "X-Request-ID", "r1");
        OpensmsException e3 = assertThrows(OpensmsException.class,
                () -> rid.client().messages().send(new SendMessageParams("+254700000012", "x")));
        assertEquals("r1", e3.getRequestId());

        MockTransport html = new MockTransport().reply(502, "<html><body>Bad Gateway</body></html>");
        OpensmsClient noRetry = OpensmsClient.builder().apiKey(KEY).baseUrl("http://mock.test").transport(html)
                .maxRetries(0).build();
        OpensmsException e4 = assertThrows(OpensmsException.class, () -> noRetry.messages().list());
        assertEquals(502, e4.getStatus());
        assertNull(e4.getDetail());
        assertEquals("<html><body>Bad Gateway</body></html>", e4.getBody());
        assertEquals("OpenSMS request failed with status 502", e4.getMessage());
    }

    // 14
    @Test
    void noContent() {
        MockTransport mt = new MockTransport().reply(204, "");
        mt.client().contacts().delete("c1");
        assertEquals("DELETE", mt.last().method());
        assertEquals("/v1/contacts/c1", mt.last().uri().getPath());
        assertNull(mt.last().body());
    }

    // 15
    @Test
    void pagination() {
        MockTransport mt = new MockTransport()
                .reply(200, "{\"items\":[{\"id\":\"a\"},{\"id\":\"b\"}],\"next_cursor\":\"c1\"}")
                .reply(200, "{\"items\":[{\"id\":\"c\"}],\"next_cursor\":null}");
        OpensmsClient c = mt.client();
        MessageListParams params = new MessageListParams().limit(2);
        List<String> ids = new ArrayList<>();
        for (Message m : c.paginate(c.messages()::list, params)) {
            ids.add(m.id);
        }
        assertEquals(List.of("a", "b", "c"), ids);
        assertEquals(2, mt.requests.size());
        assertEquals("limit=2", mt.requests.get(0).uri().getRawQuery());
        assertEquals("limit=2&cursor=c1", mt.requests.get(1).uri().getRawQuery());
        assertNull(params.getCursor(), "caller's params are not modified");
    }

    @Test
    void paginationIsLazy() {
        MockTransport mt = new MockTransport()
                .reply(200, "{\"items\":[{\"id\":\"a\"}],\"next_cursor\":\"c1\"}")
                .reply(200, "{\"items\":[{\"id\":\"b\"}],\"next_cursor\":null}");
        OpensmsClient c = mt.client();
        Iterator<Message> it = c.paginate(p -> c.batches().listItems("b1", p), new BatchItemListParams()).iterator();
        assertEquals(0, mt.requests.size());
        assertEquals("a", it.next().id);
        assertEquals(1, mt.requests.size());
        assertEquals("/v1/batches/b1/items", mt.last().uri().getPath());
    }

    // 16
    @Test
    void queryEncoding() {
        MockTransport mt = new MockTransport().reply(200, "{\"quote_id\":\"sq_1\",\"entries\":[],\"totals\":[]}");
        mt.client().senderIds().quote(List.of("KE", "NG"));
        assertEquals("countries=KE,NG", mt.last().uri().getRawQuery());

        mt.reply(200, "{\"items\":[],\"next_cursor\":null}");
        mt.client().messages().list(new MessageListParams().status("delivered").to("+2547"));
        String q = mt.last().uri().getRawQuery();
        assertEquals("status=delivered&to=%2B2547", q);
        assertFalse(q.contains("limit"));
        assertFalse(q.contains("cursor"));

        mt.client().messages().list();
        assertNull(mt.last().uri().getRawQuery());
    }

    // 17
    @Test
    void pathEscaping() {
        MockTransport mt = new MockTransport().reply(200, MSG);
        mt.client().messages().get("a/b");
        assertEquals("/v1/messages/a%2Fb", mt.last().uri().getRawPath());
        assertThrows(IllegalArgumentException.class, () -> mt.client().messages().get(""));
        assertThrows(IllegalArgumentException.class, () -> mt.client().contacts().delete(null));
        assertEquals(1, mt.requests.size(), "empty ids fail before any request");
    }

    // 18
    static final String SECRET = "whsec_c2RrLWNvbmZvcm1hbmNlLXRlc3QtdmVjdG9yLTAwMDE";
    static final long TS = 1790208000L;
    static final String BODY = "{\"id\":\"evt_01\",\"type\":\"message.delivered\",\"workspace_id\":\"00000000-0000-0000-0000-000000000001\","
            + "\"environment\":\"sandbox\",\"created_at\":\"2026-09-24T00:00:00Z\",\"data\":{\"id\":\"00000000-0000-0000-0000-000000000002\","
            + "\"status\":\"delivered\"}}";
    static final String SIG = "eeb2ec420dd348b253dae35c1f3bce03d261109eb8788e3ad836072e894fac23";
    static final String HEADER = "t=1790208000,v1=" + SIG;

    private static boolean v(String body, String header, String secret, long now) {
        return WebhookSignature.verify(body, header, secret, 300, now);
    }

    @Test
    void webhookSignatureVector() {
        assertEquals(230, BODY.getBytes(StandardCharsets.UTF_8).length);
        assertEquals(HEADER, WebhookSignature.sign(BODY.getBytes(StandardCharsets.UTF_8), SECRET, TS));
        assertTrue(v(BODY, HEADER, SECRET, TS), "valid");
        assertTrue(v(BODY, HEADER, SECRET, TS + 300), "boundary inclusive");
        assertFalse(v(BODY, HEADER, SECRET, TS + 301), "expired +301");
        assertFalse(v(BODY, HEADER, SECRET, TS - 301), "expired -301");
        assertFalse(v(BODY.replace("\"status\":\"delivered\"", "\"status\":\"failed\""), HEADER, SECRET, TS), "tampered");
        assertFalse(v(BODY, HEADER, SECRET.substring("whsec_".length()), TS), "no whsec_ prefix");
        assertTrue(v(BODY, "v1=" + SIG + ",t=1790208000", SECRET, TS), "order swapped");
        assertFalse(v(BODY, HEADER + ",v0=abc", SECRET, TS), "extra v0");
        assertFalse(v(BODY, "t=1790208000", SECRET, TS), "t only");
        assertTrue(v(BODY, "t=1790208000,v1=" + SIG.toUpperCase(), SECRET, TS), "uppercase hex");
        assertFalse(v(BODY, HEADER, "", TS), "empty secret");
        assertFalse(v(BODY, "t=1790208000,t=1790208000,v1=" + SIG, SECRET, TS), "duplicate key");
        assertFalse(v(BODY, "t=abc,v1=" + SIG, SECRET, TS), "non-integer t");

        WebhookEvent ev = WebhookSignature.constructEvent(BODY, HEADER, SECRET, 300, TS);
        assertEquals("message.delivered", ev.type);
        assertEquals("delivered", ev.data.get("status").asText());
        assertEquals("evt_01", ev.id);

        OpensmsException bad = assertThrows(OpensmsException.class, () -> WebhookSignature.constructEvent(
                BODY.replace("\"status\":\"delivered\"", "\"status\":\"failed\""), HEADER, SECRET, 300, TS));
        assertEquals("invalid_signature", bad.getCode());
        assertEquals(0, bad.getStatus());

        OpensmsException old = assertThrows(OpensmsException.class,
                () -> WebhookSignature.constructEvent(BODY, HEADER, SECRET, 300, TS + 301));
        assertEquals("expired_signature", old.getCode());

        // also reachable from the client
        assertFalse(new OpensmsClient(KEY).webhooks().verifySignature(BODY, HEADER, SECRET), "expired against the real clock");
    }

    // 19
    @Test
    void batchCsv() {
        MockTransport mt = new MockTransport().reply(202, "{\"id\":\"b1\",\"status\":\"ready\",\"total\":1,\"invalid\":0}");
        String csv = "to,text\n+254700000014,csv run\n";
        Batch b = mt.client().batches().createFromCsv(csv);
        assertEquals("ready", b.status);
        assertEquals("text/csv", mt.last().header("Content-Type"));
        assertEquals(csv, MockTransport.body(mt.last()));
        assertEquals("/v1/messages/batch", mt.last().uri().getPath());
        assertNotNull(mt.last().header("Idempotency-Key"));
    }

    // 20
    @Test
    void decimalStringsAndUnknownFields() {
        MockTransport mt = new MockTransport().reply(200, MSG);
        Message m = mt.client().messages().get("11111111-1111-1111-1111-111111111111");
        assertEquals("0.000000", m.price);
        assertEquals(1, m.parts);
        assertEquals(Instant.parse("2026-09-24T04:42:35.567510Z"), m.createdAt.toInstant());
    }

    // extra coverage of the resource wiring
    @Test
    void resourceRoutes() throws IOException {
        MockTransport mt = new MockTransport().reply(200, "{}");
        OpensmsClient c = mt.client();

        c.webhooks().update("w1", new WebhookParams("https://x.test/h", List.of("message.delivered")).enabled(true));
        assertEquals("PUT", mt.last().method());
        assertEquals("{\"url\":\"https://x.test/h\",\"events\":[\"message.delivered\"],\"enabled\":true}", MockTransport.body(mt.last()));
        assertNotNull(mt.last().header("Idempotency-Key"));
        assertThrows(IllegalArgumentException.class,
                () -> c.webhooks().update("w1", new WebhookParams("https://x.test/h", List.of("message.delivered"))));

        c.webhooks().replayDelivery("w1", 42, 3, "sdk replay reason");
        assertEquals("/v1/webhooks/w1/deliveries/42/replay", mt.last().uri().getPath());
        assertEquals("{\"generation\":3,\"reason\":\"sdk replay reason\"}", MockTransport.body(mt.last()));

        c.otp().verify("o1", "123456");
        assertEquals("{\"otp_id\":\"o1\",\"code\":\"123456\"}", MockTransport.body(mt.last()));

        c.contactGroups().create(new ContactGroupParams().name("g").contactIds(List.of("c1")));
        assertEquals("{\"name\":\"g\",\"contact_ids\":[\"c1\"]}", MockTransport.body(mt.last()));

        c.contactGroups().send("g1", new GroupSendParams().templateId("t1").variables(Map.of("name", "Ada")));
        assertEquals("{\"template_id\":\"t1\",\"variables\":{\"name\":\"Ada\"}}", MockTransport.body(mt.last()));

        c.batches().create(List.of(new BatchItemInput("+254700000012", "b1")), false);
        assertEquals("{\"items\":[{\"to\":\"+254700000012\",\"text\":\"b1\"}],\"dedupe\":false}", MockTransport.body(mt.last()));

        c.senderIds().updateDraft("d1", new SenderIdDraftParams().version(1).sampleMessage("s"));
        assertEquals("{\"version\":1,\"sample_message\":\"s\"}", MockTransport.body(mt.last()));
        assertEquals("PATCH", mt.last().method());
        assertThrows(IllegalArgumentException.class, () -> c.senderIds().updateDraft("d1", new SenderIdDraftParams()));

        c.senderIds().createDraft(new SenderIdDraftParams().value("X"));
        assertNull(mt.last().header("Idempotency-Key"));

        c.suppressions().importItems(List.of(new SuppressionInput("+254700000001", "complaint")));
        assertEquals("{\"items\":[{\"e164\":\"+254700000001\",\"reason\":\"complaint\"}]}", MockTransport.body(mt.last()));

        c.analytics().overview(new AnalyticsParams().range("7d").currency("KES"));
        assertEquals("/v1/analytics/overview", mt.last().uri().getPath());
        assertEquals("currency=KES&range=7d", mt.last().uri().getRawQuery());

        mt.reset().reply(200, "[]");
        c.numbers().available("KE", "long_code");
        assertEquals("country=KE&kind=long_code", mt.last().uri().getRawQuery());

        mt.reset().reply(200, "{\"data\":[{\"id\":7,\"amount\":\"1.000000\"}]}");
        assertEquals(7L, c.wallet().ledger(1, 100L).get(0).id);
        assertEquals("limit=1&before=100", mt.last().uri().getRawQuery());

        mt.reset().reply(200, "{\"items\":[{\"id\":\"d1\",\"is_current\":true}]}");
        assertTrue(c.senderIds().listDocuments().get(0).isCurrent);

        mt.reset().reply(200, "{\"valid\":false,\"attempts_left\":4}");
        OtpVerifyResult r = c.otp().verify("o1", "000000");
        assertEquals(4, r.attemptsLeft);
        assertFalse(r.valid);

        mt.reset().reply(200, "{\"items\":[],\"next_cursor\":null}");
        Page<io.opensms.models.Suppression> page = c.suppressions().list(ListParams.ofLimit(5));
        assertNull(page.nextCursor);
        assertEquals("limit=5", mt.last().uri().getRawQuery());
    }
}
