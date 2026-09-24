package io.opensms;

/**
 * Per-call options. Currently carries an explicit {@code Idempotency-Key}; when
 * none is given, methods that support idempotency generate a UUIDv4 once per call
 * and reuse it on every retry.
 *
 * <pre>{@code
 * client.messages().send(params, RequestOptions.idempotencyKey("order-123-sms"));
 * }</pre>
 */
public final class RequestOptions {

    private final String idempotencyKey;

    private RequestOptions(String idempotencyKey) {
        this.idempotencyKey = idempotencyKey;
    }

    /** No options. */
    public static RequestOptions none() {
        return new RequestOptions(null);
    }

    /**
     * Use {@code key} as the {@code Idempotency-Key} for this call.
     *
     * @param key at most 200 characters (255 for messages, batches and OTP).
     * @return the options.
     */
    public static RequestOptions idempotencyKey(String key) {
        if (key == null || key.isEmpty()) {
            throw new IllegalArgumentException("idempotencyKey must be non-empty");
        }
        return new RequestOptions(key);
    }

    /** @return the explicit key, or {@code null} to let the SDK generate one. */
    public String getIdempotencyKey() {
        return idempotencyKey;
    }
}
