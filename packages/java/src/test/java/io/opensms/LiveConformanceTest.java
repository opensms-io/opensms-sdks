package io.opensms;

import io.opensms.models.AnalyticsOverview;
import io.opensms.models.Batch;
import io.opensms.models.BatchStopResult;
import io.opensms.models.BatchValidationReport;
import io.opensms.models.Contact;
import io.opensms.models.ContactGroup;
import io.opensms.models.Country;
import io.opensms.models.CountryRules;
import io.opensms.models.LedgerEntry;
import io.opensms.models.Lookup;
import io.opensms.models.Message;
import io.opensms.models.MessageAttempt;
import io.opensms.models.OtpSendResult;
import io.opensms.models.OtpVerifyResult;
import io.opensms.models.Page;
import io.opensms.models.PriceList;
import io.opensms.models.SandboxMessage;
import io.opensms.models.SenderId;
import io.opensms.models.SenderIdDraft;
import io.opensms.models.StatusResult;
import io.opensms.models.Suppression;
import io.opensms.models.SuppressionImportResult;
import io.opensms.models.Template;
import io.opensms.models.WalletBalance;
import io.opensms.models.WebhookDelivery;
import io.opensms.models.WebhookEndpoint;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.api.TestMethodOrder;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.junit.jupiter.api.function.Executable;

import java.security.SecureRandom;
import java.time.Duration;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.function.Supplier;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.*;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

/**
 * The ordered live scenario from CONFORMANCE.md. Runs only when
 * {@code OPENSMS_BASE_URL} and {@code OPENSMS_API_KEY} are set; otherwise every
 * step is skipped (never failed).
 */
@EnabledIfEnvironmentVariable(named = "OPENSMS_BASE_URL", matches = ".+",
        disabledReason = "OPENSMS_BASE_URL not set: live conformance skipped")
@EnabledIfEnvironmentVariable(named = "OPENSMS_API_KEY", matches = ".+",
        disabledReason = "OPENSMS_API_KEY not set: live conformance skipped")
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class LiveConformanceTest {

    private static final SecureRandom RND = new SecureRandom();
    private static final Duration TIMEOUT = Duration.ofSeconds(60);
    private static final Duration POLL_DEADLINE = Duration.ofSeconds(60);
    private static final String ZERO = "00000000-0000-0000-0000-000000000000";
    private static final String KE = "+254700000012";
    private static final Pattern UUID_RE = Pattern.compile("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");

    private String baseUrl;
    private String apiKey;
    private OpensmsClient c;
    private final String run = hex(4);

    // state carried between steps
    private String messageId;
    private String contactId;
    private String groupId;
    private String templateId;

    @BeforeAll
    void setUp() {
        baseUrl = System.getenv("OPENSMS_BASE_URL");
        apiKey = System.getenv("OPENSMS_API_KEY");
        assumeTrue(baseUrl != null && !baseUrl.isBlank() && apiKey != null && !apiKey.isBlank(),
                "OPENSMS_BASE_URL and OPENSMS_API_KEY not set: live conformance skipped");
        c = client(apiKey, null);
    }

    private OpensmsClient client(String key, AtomicInteger counter) {
        HttpTransport jdk = new JdkHttpTransport(null, TIMEOUT);
        HttpTransport t = counter == null ? jdk : req -> {
            counter.incrementAndGet();
            return jdk.send(req);
        };
        return OpensmsClient.builder().apiKey(key).baseUrl(baseUrl).timeout(TIMEOUT).transport(t).build();
    }

    // -- helpers -------------------------------------------------------------

    private static String hex(int bytes) {
        byte[] b = new byte[bytes];
        RND.nextBytes(b);
        StringBuilder sb = new StringBuilder();
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }

    /**
     * A fresh Safaricom-prefix number. The fixture number +254700000012 is shared by
     * every SDK's live run in the same workspace and quickly hits the server's
     * per-destination admission limit (5 per number per hour), so sends use a
     * random number with the same country and carrier instead.
     */
    private static String randomSafaricom() {
        return "+25470" + String.format("%07d", RND.nextInt(10_000_000));
    }

    private static String randomKe() {
        return randomSafaricom();
    }

    private static OpensmsException err(int status, String detail, Executable call) {
        OpensmsException e = assertThrows(OpensmsException.class, call);
        assertEquals(status, e.getStatus(), "status for: " + e.getMessage());
        if (detail != null) {
            assertEquals(detail, e.getDetail());
        }
        return e;
    }

    private static <T> T poll(Supplier<T> fetch, java.util.function.Predicate<T> done, String what) {
        long deadline = System.nanoTime() + POLL_DEADLINE.toNanos();
        T last = null;
        while (System.nanoTime() < deadline) {
            last = fetch.get();
            if (done.test(last)) {
                return last;
            }
            try {
                Thread.sleep(750);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        fail("timed out waiting for " + what);
        return last;
    }

    private static <T> T first(Iterable<T> items, java.util.function.Predicate<T> p) {
        for (T t : items) {
            if (p.test(t)) return t;
        }
        return null;
    }

    // -- scenario --------------------------------------------------------------

    @Test @Order(1)
    void s01_constructor() {
        assertThrows(IllegalArgumentException.class, () -> OpensmsClient.builder().apiKey("not_a_key").baseUrl(baseUrl).build());
        assertThrows(IllegalArgumentException.class, () -> OpensmsClient.builder().apiKey("sk_test_short").baseUrl(baseUrl).build());
    }

    @Test @Order(2)
    void s02_authError() {
        AtomicInteger calls = new AtomicInteger();
        OpensmsClient bad = client("sk_test_" + "A".repeat(32), calls);
        OpensmsException e = err(401, "missing or invalid API key", () -> bad.messages().list(new MessageListParams().limit(1)));
        assertEquals("about:blank", e.getType());
        assertEquals("Unauthorized", e.getTitle());
        assertNull(e.getCode());
        assertEquals(1, calls.get());
    }

    @Test @Order(3)
    void s03_send() {
        String to = randomSafaricom();
        Message m = c.messages().send(new SendMessageParams(to, "conformance java " + run)
                .metadata(Map.of("sdk", "java", "run", run)));
        assertTrue(UUID_RE.matcher(m.id).matches(), m.id);
        assertEquals(to, m.to);
        assertEquals("OPENSMS", m.senderId);
        assertEquals("transactional", m.trafficType);
        assertTrue(Set.of("queued", "sending", "sent", "delivered").contains(m.status), m.status);
        assertEquals(1, m.parts);
        assertEquals("gsm7", m.encoding);
        assertEquals("KE", m.countryIso2);
        assertEquals("KES", m.currency);
        assertEquals("0.000000", m.price);
        assertEquals(run, m.metadata.get("run"));
        messageId = m.id;
    }

    @Test @Order(4)
    void s04_idempotentReplay() {
        String key = "java-" + run + "-" + hex(8);
        String to = randomSafaricom();
        SendMessageParams p = new SendMessageParams(to, "idem java " + run);
        Message a = c.messages().send(p, RequestOptions.idempotencyKey(key));
        Message b = c.messages().send(p, RequestOptions.idempotencyKey(key));
        assertEquals(a.id, b.id);
        err(409, "Idempotency-Key was already used with a different request",
                () -> c.messages().send(new SendMessageParams(to, "idem java changed " + run), RequestOptions.idempotencyKey(key)));
    }

    @Test @Order(5)
    void s05_getAndWait() {
        assumeTrue(messageId != null, "step 3 did not run");
        Message m = poll(() -> c.messages().get(messageId), x -> "delivered".equals(x.status), "message delivered");
        assertNotNull(m.deliveredAt);
        assertNotNull(m.sentAt);
        assertEquals("conformance java " + run, m.text);
    }

    @Test @Order(6)
    void s06_listAndCursor() {
        Page<Message> p1 = c.messages().list(new MessageListParams().limit(1));
        assertEquals(1, p1.items.size());
        assertNotNull(p1.nextCursor);
        Page<Message> p2 = c.messages().list(new MessageListParams().limit(1).cursor(p1.nextCursor));
        assertEquals(1, p2.items.size());
        assertNotEquals(p1.items.get(0).id, p2.items.get(0).id);
        err(400, "invalid cursor", () -> c.messages().list(new MessageListParams().limit(1).cursor("garbage")));
        err(400, "invalid status", () -> c.messages().list(new MessageListParams().status("bogus")));
        int n = 0;
        for (Message ignored : c.paginate(c.messages()::list, new MessageListParams().limit(2))) {
            if (++n == 3) break;
        }
        assertEquals(3, n);
    }

    @Test @Order(7)
    void s07_attempts() {
        assumeTrue(messageId != null, "step 3 did not run");
        List<MessageAttempt> attempts = c.messages().attempts(messageId);
        assertFalse(attempts.isEmpty());
        MessageAttempt a = attempts.get(0);
        assertEquals(1, a.sequence);
        assertTrue(a.routeName.startsWith("Mock provider (sandbox)"), a.routeName);
        assertEquals("delivered", a.status);
        assertEquals("0.000000", a.price);
    }

    @Test @Order(8)
    void s08_validationError() {
        AtomicInteger calls = new AtomicInteger();
        OpensmsClient counted = client(apiKey, calls);
        OpensmsException e = err(400, "to must be an E.164 phone number",
                () -> counted.messages().send(new SendMessageParams("12345", "x")));
        assertEquals("Bad Request", e.getTitle());
        assertEquals("about:blank", e.getType());
        assertEquals(1, calls.get());
    }

    @Test @Order(9)
    void s09_codedError() {
        OpensmsException e = err(400, "Message ID must be a valid UUID.", () -> c.messages().get("not-a-uuid"));
        assertEquals("invalid_message_id", e.getCode());
        assertEquals("https://api.opensms.io/problems/invalid_message_id", e.getType());
    }

    @Test @Order(10)
    void s10_notFound() {
        err(404, "message not found", () -> c.messages().get(ZERO));
    }

    @Test @Order(11)
    void s11_scheduleAndCancel() {
        Message s = c.messages().send(new SendMessageParams(randomSafaricom(), "scheduled " + run)
                .scheduledAt(Instant.now().plus(Duration.ofHours(2))));
        assertEquals("scheduled", s.status);
        Message x = c.messages().cancel(s.id);
        assertEquals("cancelled", x.status);
        assertNotNull(x.cancelledAt);
        err(409, "message cannot be cancelled in its current state", () -> c.messages().cancel(s.id));
        if (messageId != null) {
            err(409, "message cannot be cancelled in its current state", () -> c.messages().cancel(messageId));
        }
    }

    @Test @Order(12)
    void s12_batch() {
        Batch b = c.batches().create(List.of(
                new BatchItemInput(randomSafaricom(), "b1 " + run),
                new BatchItemInput(randomSafaricom(), "b2 " + run),
                new BatchItemInput("bad", "x")));
        assertEquals("ready", b.status);
        assertEquals(3, b.total);
        assertEquals(1, b.invalid);
        assertEquals(0, b.sent);
        BatchValidationReport r = c.batches().validation(b.id);
        assertEquals(3, r.rows.size());
        assertEquals(2, r.valid);
        assertFalse(r.rows.get(2).valid);
        assertEquals("to must be an E.164 phone number", r.rows.get(2).error);
        Batch g = c.batches().get(b.id);
        assertEquals(3, g.total);
        assertEquals(1, g.invalid);
        Batch started = c.batches().start(b.id);
        assertEquals("running", started.status);
        Page<Message> items = poll(() -> c.batches().listItems(b.id), p -> p.items != null && p.items.size() == 2, "batch items");
        for (Message m : items.items) {
            assertNotNull(m.to);
            assertNotNull(m.status);
        }
    }

    @Test @Order(13)
    void s13_batchStop() {
        Batch b = c.batches().create(List.of(new BatchItemInput(randomSafaricom(), "stop " + run)));
        BatchStopResult s = c.batches().stop(b.id);
        assertEquals(b.id, s.id);
        assertEquals("stopped", s.status);
        assertEquals(0, s.cancelled);
        err(409, "batch is not ready to start", () -> c.batches().start(b.id));
        err(404, "batch not found", () -> c.batches().get(ZERO));
    }

    @Test @Order(14)
    void s14_csvBatch() {
        Batch b = c.batches().createFromCsv("to,text\n" + randomSafaricom() + ",csv " + run + "\n");
        assertEquals("ready", b.status);
        assertEquals(1, b.total);
        assertEquals(0, b.invalid);
    }

    @Test @Order(15)
    void s15_otp() {
        String to = randomSafaricom();
        OffsetDateTime before = OffsetDateTime.now().minusSeconds(5);
        OtpSendResult sent = c.otp().send(new OtpSendParams(to).length(6).ttlSeconds(300));
        assertTrue(UUID_RE.matcher(sent.otpId).matches(), sent.otpId);
        Pattern codeRe = Pattern.compile("Your OpenSMS verification code is (\\d{6})");
        SandboxMessage sm = poll(() -> first(c.sandbox().listMessages(ListParams.ofLimit(10)).items,
                        x -> "otp".equals(x.trafficType) && to.equals(x.to) && x.text != null
                                && codeRe.matcher(x.text).find() && x.createdAt != null && x.createdAt.isAfter(before)),
                x -> x != null, "OTP in sandbox messages");
        Matcher m = codeRe.matcher(sm.text);
        assertTrue(m.find());
        String code = m.group(1);
        String wrong = code.equals("000000") ? "111111" : "000000";
        OtpVerifyResult w = c.otp().verify(sent.otpId, wrong);
        assertFalse(w.valid);
        assertEquals(4, w.attemptsLeft);
        OtpVerifyResult ok = c.otp().verify(sent.otpId, code);
        assertTrue(ok.valid);
        assertEquals(3, ok.attemptsLeft);
        err(400, "template must contain {{code}}", () -> c.otp().send(new OtpSendParams(randomSafaricom()).template("no placeholder")));
        err(404, "OTP not found", () -> c.otp().verify(ZERO, "123456"));
    }

    @Test @Order(16)
    void s16_lookup() {
        Lookup l = c.lookups().create(KE);
        assertEquals("completed", l.state);
        assertEquals("KE", l.country);
        assertEquals("mock", l.source);
        assertEquals("0.000000", l.price);
        Lookup g = c.lookups().get(l.id);
        assertEquals(l.id, g.id);
        assertEquals(l.state, g.state);
        OpensmsException e = err(404, "Lookup not found.", () -> c.lookups().get(ZERO));
        assertEquals("not_found", e.getCode());
    }

    @Test @Order(17)
    void s17_contacts() {
        String r1 = randomKe();
        Contact ct = c.contacts().create(new ContactParams().e164(r1).name("Ada " + run).attributes(Map.of("tier", "gold")));
        assertEquals(r1, ct.e164);
        contactId = ct.id;
        Contact g = c.contacts().get(ct.id);
        assertEquals(ct.id, g.id);
        assertEquals(r1, g.e164);
        Contact u = c.contacts().update(ct.id, new ContactParams().name("Ada L " + run));
        assertEquals("Ada L " + run, u.name);
        assertEquals("gold", u.attributes.get("tier"));
        assertNotNull(first(c.paginate(c.contacts()::list, ListParams.ofLimit(200)), x -> ct.id.equals(x.id)));
        err(409, "A record with this phone number or name already exists.",
                () -> c.contacts().create(new ContactParams().e164(r1)));
    }

    @Test @Order(18)
    void s18_contactGroups() {
        assumeTrue(contactId != null, "step 17 did not run");
        ContactGroup grp = c.contactGroups().create(new ContactGroupParams().name("grp " + run).contactIds(List.of(contactId)));
        assertEquals(List.of(contactId), grp.contactIds);
        groupId = grp.id;
        ContactGroup up = c.contactGroups().update(grp.id, new ContactGroupParams().name("grp2 " + run));
        assertEquals("grp2 " + run, up.name);
        assertEquals(grp.id, c.contactGroups().get(grp.id).id);
        Batch b = c.contactGroups().send(grp.id, new GroupSendParams().text("Hi " + run));
        assertEquals("running", b.status);
        assertEquals(1, b.total);

        ContactGroup empty = c.contactGroups().create(new ContactGroupParams().name("empty " + run));
        try {
            err(422, "Group must contain between 1 and 1000 contacts.",
                    () -> c.contactGroups().send(empty.id, new GroupSendParams().text("x")));
        } finally {
            c.contactGroups().delete(empty.id);
        }
    }

    @Test @Order(19)
    void s19_templates() {
        assumeTrue(groupId != null && contactId != null, "steps 17-18 did not run");
        Template t = c.templates().create(new TemplateParams().name("tpl-" + run).body("Hi {{name}}").trafficType("transactional"));
        templateId = t.id;
        assertEquals(List.of("name"), t.variables);
        Template u = c.templates().update(t.id, new TemplateParams().body("Hello {{name}}"));
        assertEquals("Hello {{name}}", u.body);
        assertEquals(List.of("name"), u.variables);
        assertEquals(t.id, c.templates().get(t.id).id);
        assertNotNull(first(c.paginate(c.templates()::list, ListParams.ofLimit(200)), x -> t.id.equals(x.id)));
        Batch b = c.contactGroups().send(groupId, new GroupSendParams().templateId(t.id).variables(Map.of("name", "Ada")));
        assertEquals("running", b.status);
        c.templates().delete(t.id);
        c.contactGroups().delete(groupId);
        c.contacts().delete(contactId);
        err(404, "Record not found.", () -> c.contacts().get(contactId));
    }

    @Test @Order(20)
    void s20_webhooks() {
        WebhookEndpoint w = c.webhooks().create(new WebhookParams("https://example.com/opensms/" + run,
                List.of("message.delivered", "message.failed")));
        assertTrue(w.secret != null && w.secret.startsWith("whsec_"), w.secret);
        assertEquals(Boolean.TRUE, w.enabled);
        try {
            assertNull(c.webhooks().get(w.id).secret);
            assertNotNull(first(c.paginate(c.webhooks()::list, ListParams.ofLimit(200)), x -> w.id.equals(x.id)));
            err(400, "url must be an HTTPS URL without credentials or fragment",
                    () -> c.webhooks().create(new WebhookParams("http://example.com/x", List.of("message.delivered"))));
            WebhookEndpoint u = c.webhooks().update(w.id, new WebhookParams("https://example.com/opensms/" + run + "/v2",
                    List.of("message.delivered")).enabled(true));
            assertEquals("https://example.com/opensms/" + run + "/v2", u.url);
            assertEquals(List.of("message.delivered"), u.events);
            StatusResult tr = c.webhooks().test(w.id);
            assertEquals("pending", tr.status);
            WebhookDelivery d = poll(() -> first(c.webhooks().listDeliveries(w.id).items, x -> "webhook.test".equals(x.event)),
                    x -> x != null, "webhook.test delivery");
            assertNotNull(d.id);
            assertNotNull(d.generation);
            try {
                StatusResult rr = c.webhooks().replayDelivery(w.id, d.id, d.generation, "sdk conformance replay");
                assertNotNull(rr.status);
            } catch (OpensmsException e) {
                assertEquals(409, e.getStatus());
                assertEquals("Delivery state, lease or generation does not permit replay.", e.getDetail());
            }
        } finally {
            c.webhooks().delete(w.id);
        }
        err(404, "webhook not found", () -> c.webhooks().get(w.id));
    }

    @Test @Order(21)
    void s21_suppressions() {
        String r2 = randomKe();
        String r3 = randomKe();
        Suppression s = c.suppressions().create(r2, "manual");
        assertNotNull(s.id);
        assertEquals("manual", s.reason);
        OpensmsException e = err(422, "destination is suppressed", () -> c.messages().send(new SendMessageParams(r2, "x")));
        assertNotNull(e.getRequestId());
        assertFalse(e.getRequestId().isEmpty());
        assertNotNull(first(c.paginate(c.suppressions()::list, ListParams.ofLimit(200)), x -> r2.equals(x.e164)));
        SuppressionImportResult imp = c.suppressions().importItems(List.of(new SuppressionInput(r3, "complaint")));
        assertEquals(1, imp.created);
        assertEquals(1, imp.received);
        c.suppressions().delete(s.id);
        err(404, "suppression not found", () -> c.suppressions().delete(s.id));
    }

    @Test @Order(22)
    void s22_compliance() {
        CountryRules ke = c.compliance().getCountry("KE");
        assertEquals("KE", ke.iso2);
        assertEquals("+254", ke.dialCode);
        assertTrue(ke.stopKeywords.contains("STOP"));
        err(404, "country not found", () -> c.compliance().getCountry("ZZ"));
        assertNotNull(first(c.compliance().listCountries(), x -> "KE".equals(x.iso2)));
        c.compliance().listContentRules().forEach(r -> assertNotNull(r.id));
    }

    @Test @Order(23)
    void s23_wallet() {
        List<WalletBalance> bal = c.wallet().balances();
        assertFalse(bal.isEmpty());
        assertEquals("sandbox", bal.get(0).environment);
        assertEquals("KES", bal.get(0).currency);
        assertTrue(bal.get(0).balance.matches("-?\\d+\\.\\d+"), bal.get(0).balance);
        List<LedgerEntry> l = c.wallet().ledger(1, null);
        assertEquals(1, l.size());
        assertNotNull(l.get(0).id);
        err(400, "limit must be between 1 and 200", () -> c.wallet().ledger(0, null));
        err(422, "sandbox wallets cannot use payment providers",
                () -> c.wallet().createTopup(new TopupParams("100", "KES", "card", "dev@opensms.test")));
    }

    @Test @Order(24)
    void s24_pricing() {
        PriceList p = c.pricing().get("sms", "KE");
        assertEquals("KES", p.currency);
        assertEquals("sms", p.product);
        p.entries.forEach(e -> assertEquals("KE", e.countryIso2));
        err(400, "product must be sms, lookup, or number_monthly", () -> c.pricing().get("bogus", null));
    }

    @Test @Order(25)
    void s25_analytics() {
        AnalyticsOverview o = c.analytics().overview();
        assertEquals("sandbox", o.environment);
        assertEquals("KES", o.currency);
        assertNotNull(o.sent);
        assertNotNull(c.analytics().overview(new AnalyticsParams().range("7d")));
        assertNotNull(c.analytics().byCountry());
        assertNotNull(c.analytics().byCarrier());
        assertNotNull(c.analytics().bySenderId());
        assertNotNull(c.analytics().timeseries());
    }

    @Test @Order(26)
    void s26_numbersAndInbound() {
        assertNotNull(c.numbers().list().items);
        assertNotNull(c.numbers().available("KE", "long_code"));
        err(422, "This operation requires the live environment.", () -> c.numbers().assign("KE", "long_code"));
        assertEquals(List.of(), c.inbound().list().items);
    }

    @Test @Order(27)
    void s27_senderIds() {
        assertNotNull(first(c.paginate(c.senderIds()::list, ListParams.ofLimit(200)),
                (SenderId x) -> "OPENSMS".equals(x.value) && "approved".equals(x.status)));
        assertEquals(Boolean.TRUE, c.senderIds().check("ACME", "KE").valid);
        assertTrue(c.senderIds().quote(List.of("KE")).quoteId.startsWith("sq_"));
        assertNotNull(c.senderIds().listDocuments());
        StringBuilder letters = new StringBuilder();
        for (int i = 0; i < 4; i++) letters.append((char) ('A' + RND.nextInt(26)));
        SenderIdDraft d = c.senderIds().createDraft(new SenderIdDraftParams().source("application").value("SDK" + letters)
                .kind("alphanumeric").countries(List.of("KE")).useCase("transactional").sampleMessage("Your order shipped"));
        assertEquals(1, d.version);
        assertEquals("active", d.status);
        try {
            SenderIdDraft u = c.senderIds().updateDraft(d.id, new SenderIdDraftParams().version(1).sampleMessage("Your order has shipped"));
            assertEquals(2, u.version);
            assertEquals(d.id, c.senderIds().getDraft(d.id).id);
            assertNotNull(c.senderIds().listDrafts().items);
        } finally {
            c.senderIds().deleteDraft(d.id);
        }
        err(404, "sender ID not found", () -> c.senderIds().get(ZERO));
    }

    @Test @Order(28)
    void s28_countries() {
        Country ke = first(c.countries().list(), x -> "KE".equals(x.iso2));
        assertNotNull(ke);
        assertEquals("+254", ke.dialCode);
        assertFalse(c.countries().carriers("KE").isEmpty());
        assertNotNull(c.countries().routes("KE"));
        assertEquals("KE", c.countries().compliance("KE").iso2);
    }

    @Test @Order(29)
    void s29_scopeErrors() {
        String ro = System.getenv("OPENSMS_READONLY_API_KEY");
        assumeTrue(ro != null && !ro.isBlank(), "OPENSMS_READONLY_API_KEY not set");
        OpensmsClient r = client(ro, null);
        err(401, "insufficient scope", () -> r.messages().send(new SendMessageParams(randomSafaricom(), "ro " + run)));
        err(403, "Insufficient API key scope.", () -> r.contacts().list());
        List<Message> items = new ArrayList<>(r.messages().list(new MessageListParams().limit(1)).items);
        assertTrue(items.size() <= 1);
    }
}
