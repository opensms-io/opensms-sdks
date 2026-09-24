package io.opensms;

import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.type.TypeFactory;
import io.opensms.models.Page;

import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ThreadLocalRandom;

/**
 * The single place that talks to the network. Owns authentication and standard
 * headers, JSON encoding and decoding, the {@code Idempotency-Key} header, retries
 * with backoff (honouring {@code Retry-After}), and mapping non-2xx responses to
 * {@link OpensmsException}. Resources are thin and delegate here. Not part of the
 * public API.
 */
final class ApiTransport {

    static final String USER_AGENT = "opensms-java/" + OpensmsClient.VERSION;

    private static final Set<Integer> RETRY_STATUSES = Set.of(429, 500, 502, 503, 504);
    private static final long MAX_RETRY_AFTER_SECONDS = 60;
    private static final long BACKOFF_BASE_MS = 500;
    private static final long BACKOFF_CAP_MS = 8000;

    private final String apiKey;
    private final String baseUrl;
    private final int maxRetries;
    private final HttpTransport http;
    private final Sleeper sleeper;

    ApiTransport(String apiKey, String baseUrl, int maxRetries, HttpTransport http, Sleeper sleeper) {
        this.apiKey = apiKey;
        this.baseUrl = baseUrl;
        this.maxRetries = maxRetries;
        this.http = http;
        this.sleeper = sleeper;
    }

    // -- type helpers -------------------------------------------------------

    static JavaType type(Class<?> c) {
        return TypeFactory.defaultInstance().constructType(c);
    }

    static JavaType listOf(Class<?> element) {
        return Json.MAPPER.getTypeFactory().constructCollectionType(List.class, element);
    }

    static JavaType pageOf(Class<?> element) {
        return Json.MAPPER.getTypeFactory().constructParametricType(Page.class, element);
    }

    static final JavaType VOID = type(Void.class);

    /** The explicit key from {@code opts}, else a fresh UUIDv4 (generated once per call). */
    static String idempotencyKey(RequestOptions opts) {
        if (opts != null && opts.getIdempotencyKey() != null) {
            return opts.getIdempotencyKey();
        }
        return UUID.randomUUID().toString();
    }

    // -- entry points used by resources ---------------------------------------

    <T> T get(String path, Query query, JavaType type) {
        return execute("GET", path + (query == null ? "" : query.build()), null, null, null, type);
    }

    /**
     * JSON request. A POST without {@code idempotencyKey} is never retried.
     *
     * @param idempotencyKey header value, or {@code null} to send none.
     */
    <T> T json(String method, String path, Object body, String idempotencyKey, JavaType type) {
        byte[] bytes = null;
        if (body != null) {
            try {
                bytes = Json.MAPPER.writeValueAsBytes(body);
            } catch (IOException e) {
                throw new IllegalArgumentException("request body could not be encoded as JSON", e);
            }
        }
        return execute(method, path, bytes, bytes == null ? null : "application/json", idempotencyKey, type);
    }

    <T> T raw(String method, String path, byte[] body, String contentType, String idempotencyKey, JavaType type) {
        return execute(method, path, body, contentType, idempotencyKey, type);
    }

    // -- core -------------------------------------------------------------------

    private <T> T execute(String method, String pathAndQuery, byte[] body, String contentType,
                          String idempotencyKey, JavaType type) {
        Map<String, String> headers = new LinkedHashMap<>();
        headers.put("Authorization", "Bearer " + apiKey);
        headers.put("Accept", "application/json");
        headers.put("User-Agent", USER_AGENT);
        if (contentType != null) {
            headers.put("Content-Type", contentType);
        }
        if (idempotencyKey != null) {
            headers.put("Idempotency-Key", idempotencyKey);
        }
        HttpTransport.Request request = new HttpTransport.Request(
                method, URI.create(baseUrl + pathAndQuery), headers, body);
        boolean safeToRepeat = !"POST".equals(method) || idempotencyKey != null;

        for (int attempt = 1; ; attempt++) {
            boolean mayRetry = safeToRepeat && attempt <= maxRetries;
            HttpTransport.Response res;
            try {
                res = http.send(request);
            } catch (IOException e) {
                if (mayRetry) {
                    pause(backoff(attempt));
                    continue;
                }
                throw OpensmsException.local("OpenSMS request failed: " + e, null, e);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw OpensmsException.local("OpenSMS request interrupted", null, e);
            }

            int status = res.status();
            if (status >= 200 && status < 300) {
                return decode(res, type);
            }
            OpensmsException err = Errors.fromResponse(res);
            if (mayRetry && RETRY_STATUSES.contains(status)) {
                Long retryAfter = err.getRetryAfter();
                if (retryAfter != null) {
                    if (retryAfter > MAX_RETRY_AFTER_SECONDS) {
                        throw err;
                    }
                    pause(Duration.ofSeconds(retryAfter));
                } else {
                    pause(backoff(attempt));
                }
                continue;
            }
            throw err;
        }
    }

    /** Full-jitter exponential backoff: {@code random(0, min(8 s, 0.5 s * 2^(n-1)))}. */
    static Duration backoff(int retryNumber) {
        long ceiling = Math.min(BACKOFF_CAP_MS, BACKOFF_BASE_MS << Math.min(retryNumber - 1, 20));
        return Duration.ofMillis(ThreadLocalRandom.current().nextLong(ceiling + 1));
    }

    private void pause(Duration d) {
        try {
            sleeper.sleep(d);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw OpensmsException.local("OpenSMS request interrupted", null, e);
        }
    }

    @SuppressWarnings("unchecked")
    private static <T> T decode(HttpTransport.Response res, JavaType type) {
        if (type.getRawClass() == Void.class || res.status() == 204 || res.body().length == 0) {
            return null;
        }
        try {
            return (T) Json.MAPPER.readValue(res.body(), type);
        } catch (IOException e) {
            String text = new String(res.body(), StandardCharsets.UTF_8);
            throw new OpensmsException("OpenSMS response could not be decoded: " + e.getMessage(),
                    res.status(), null, null, null, null, null, null, null, null, text, e);
        }
    }
}
