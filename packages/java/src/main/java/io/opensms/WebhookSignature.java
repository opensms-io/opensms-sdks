package io.opensms;

import io.opensms.models.WebhookEvent;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HashMap;
import java.util.Map;

/**
 * Verifies {@code X-OpenSMS-Signature: t=<unix>,v1=<hex>} headers. {@code v1} is
 * {@code hex(HMAC-SHA256(secret, "<t>." + rawBody))}, keyed with the full
 * {@code whsec_...} secret as UTF-8 bytes. Mirrors the server's parser exactly.
 * Needs no API key, so a webhook receiver can use it on its own.
 *
 * <pre>{@code
 * WebhookEvent event = WebhookSignature.constructEvent(rawBody, request.getHeader("X-OpenSMS-Signature"), secret);
 * }</pre>
 */
public final class WebhookSignature {

    /** The header carrying the signature. */
    public static final String HEADER = "X-OpenSMS-Signature";
    /** Default clock tolerance in seconds. */
    public static final long DEFAULT_TOLERANCE_SECONDS = 300;

    private WebhookSignature() {
    }

    /** Outcome of a verification. */
    enum Result { VALID, INVALID, EXPIRED }

    /**
     * @param payload raw body.
     * @param header  header value.
     * @param secret  endpoint secret.
     * @return whether valid, with the default tolerance and the current time.
     */
    public static boolean verify(byte[] payload, String header, String secret) {
        return check(payload, header, secret, DEFAULT_TOLERANCE_SECONDS, now()) == Result.VALID;
    }

    /**
     * @param payload raw body (UTF-8).
     * @param header  header value.
     * @param secret  endpoint secret.
     * @return whether valid, with the default tolerance and the current time.
     */
    public static boolean verify(String payload, String header, String secret) {
        return verify(bytes(payload), header, secret);
    }

    /**
     * @param payload          raw body.
     * @param header           header value.
     * @param secret           endpoint secret.
     * @param toleranceSeconds allowed clock difference.
     * @param nowEpochSeconds  the current time in Unix seconds (injectable for tests).
     * @return whether valid.
     */
    public static boolean verify(byte[] payload, String header, String secret, long toleranceSeconds,
                                 long nowEpochSeconds) {
        return check(payload, header, secret, toleranceSeconds, nowEpochSeconds) == Result.VALID;
    }

    /**
     * @param payload          raw body (UTF-8).
     * @param header           header value.
     * @param secret           endpoint secret.
     * @param toleranceSeconds allowed clock difference.
     * @param nowEpochSeconds  the current time in Unix seconds.
     * @return whether valid.
     */
    public static boolean verify(String payload, String header, String secret, long toleranceSeconds,
                                 long nowEpochSeconds) {
        return verify(bytes(payload), header, secret, toleranceSeconds, nowEpochSeconds);
    }

    /**
     * Verify, then parse the event envelope.
     *
     * @param payload raw body.
     * @param header  header value.
     * @param secret  endpoint secret.
     * @return the event.
     * @throws OpensmsException status 0, code {@code invalid_signature} or {@code expired_signature}.
     */
    public static WebhookEvent constructEvent(byte[] payload, String header, String secret) {
        return constructEvent(payload, header, secret, DEFAULT_TOLERANCE_SECONDS, now());
    }

    /**
     * @param payload raw body (UTF-8).
     * @param header  header value.
     * @param secret  endpoint secret.
     * @return the event.
     */
    public static WebhookEvent constructEvent(String payload, String header, String secret) {
        return constructEvent(bytes(payload), header, secret);
    }

    /**
     * @param payload          raw body.
     * @param header           header value.
     * @param secret           endpoint secret.
     * @param toleranceSeconds allowed clock difference.
     * @param nowEpochSeconds  the current time in Unix seconds.
     * @return the event.
     */
    public static WebhookEvent constructEvent(byte[] payload, String header, String secret,
                                              long toleranceSeconds, long nowEpochSeconds) {
        Result r = check(payload, header, secret, toleranceSeconds, nowEpochSeconds);
        if (r == Result.EXPIRED) {
            throw OpensmsException.local("Webhook signature timestamp is outside the tolerance", "expired_signature", null);
        }
        if (r != Result.VALID) {
            throw OpensmsException.local("Webhook signature is invalid", "invalid_signature", null);
        }
        try {
            return Json.MAPPER.readValue(payload, WebhookEvent.class);
        } catch (Exception e) {
            throw OpensmsException.local("Webhook payload is not valid JSON: " + e.getMessage(), "invalid_payload", e);
        }
    }

    /**
     * @param payload          raw body (UTF-8).
     * @param header           header value.
     * @param secret           endpoint secret.
     * @param toleranceSeconds allowed clock difference.
     * @param nowEpochSeconds  the current time in Unix seconds.
     * @return the event.
     */
    public static WebhookEvent constructEvent(String payload, String header, String secret,
                                              long toleranceSeconds, long nowEpochSeconds) {
        return constructEvent(bytes(payload), header, secret, toleranceSeconds, nowEpochSeconds);
    }

    /**
     * Compute a header value, for tests of your own receiver.
     *
     * @param payload          raw body.
     * @param secret           endpoint secret.
     * @param timestampSeconds Unix seconds.
     * @return {@code t=<ts>,v1=<hex>}.
     */
    public static String sign(byte[] payload, String secret, long timestampSeconds) {
        String ts = Long.toString(timestampSeconds);
        return "t=" + ts + ",v1=" + hex(mac(secret, ts, payload));
    }

    static Result check(byte[] payload, String header, String secret, long tolerance, long now) {
        if (secret == null || secret.trim().isEmpty() || tolerance < 0 || header == null || payload == null) {
            return Result.INVALID;
        }
        Map<String, String> values = new HashMap<>();
        for (String part : header.split(",", -1)) {
            String p = part.trim();
            int eq = p.indexOf('=');
            if (eq <= 0 || eq == p.length() - 1) {
                return Result.INVALID;
            }
            String k = p.substring(0, eq);
            if (values.containsKey(k)) {
                return Result.INVALID;
            }
            values.put(k, p.substring(eq + 1));
        }
        if (values.size() != 2 || !values.containsKey("t") || !values.containsKey("v1")) {
            return Result.INVALID;
        }
        long ts;
        try {
            ts = Long.parseLong(values.get("t"));
        } catch (NumberFormatException e) {
            return Result.INVALID;
        }
        if (now - ts > tolerance || ts - now > tolerance) {
            return Result.EXPIRED;
        }
        byte[] want = unhex(values.get("v1"));
        if (want == null || want.length != 32) {
            return Result.INVALID;
        }
        byte[] got = mac(secret, values.get("t"), payload);
        return MessageDigest.isEqual(got, want) ? Result.VALID : Result.INVALID;
    }

    private static byte[] mac(String secret, String ts, byte[] body) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            mac.update(ts.getBytes(StandardCharsets.UTF_8));
            mac.update((byte) '.');
            mac.update(body);
            return mac.doFinal();
        } catch (Exception e) {
            throw new IllegalStateException("HmacSHA256 unavailable", e);
        }
    }

    private static String hex(byte[] b) {
        StringBuilder sb = new StringBuilder(b.length * 2);
        for (byte x : b) sb.append(String.format("%02x", x));
        return sb.toString();
    }

    private static byte[] unhex(String s) {
        if (s.length() % 2 != 0) return null;
        byte[] out = new byte[s.length() / 2];
        for (int i = 0; i < out.length; i++) {
            int hi = Character.digit(s.charAt(2 * i), 16);
            int lo = Character.digit(s.charAt(2 * i + 1), 16);
            if (hi < 0 || lo < 0) return null;
            out[i] = (byte) ((hi << 4) | lo);
        }
        return out;
    }

    private static byte[] bytes(String s) {
        return s == null ? null : s.getBytes(StandardCharsets.UTF_8);
    }

    private static long now() {
        return System.currentTimeMillis() / 1000L;
    }
}
