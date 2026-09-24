package io.opensms;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * Thrown for every non-2xx response and for transport failures that survive all
 * retries. Mapped from the RFC 9457 {@code application/problem+json} body.
 *
 * <p>Branch on {@link #getStatus()}: most OpenSMS errors carry no {@code code}.
 * Note that insufficient scope is {@code 401} on messages and OTP but {@code 403}
 * everywhere else.
 */
public class OpensmsException extends RuntimeException {

    private final int status;
    private final String type;
    private final String title;
    private final String detail;
    private final String code;
    private final String traceId;
    private final Map<String, List<String>> errors;
    private final String requestId;
    private final Long retryAfter;
    private final Object body;

    /**
     * @param message    exception message.
     * @param status     HTTP status, {@code 0} when no response was received.
     * @param type       problem {@code type}, or {@code null}.
     * @param title      problem {@code title}, or {@code null}.
     * @param detail     problem {@code detail}, or {@code null}.
     * @param code       problem {@code code}, or {@code null}.
     * @param traceId    problem {@code trace_id}, or {@code null}.
     * @param errors     problem {@code errors} field map, or {@code null}.
     * @param requestId  {@code X-Request-ID} response header, or {@code null}.
     * @param retryAfter {@code Retry-After} in seconds, or {@code null}.
     * @param body       decoded body ({@link JsonNode}) or raw text, or {@code null}.
     * @param cause      underlying cause, or {@code null}.
     */
    public OpensmsException(String message, int status, String type, String title, String detail,
                            String code, String traceId, Map<String, List<String>> errors,
                            String requestId, Long retryAfter, Object body, Throwable cause) {
        super(message, cause);
        this.status = status;
        this.type = type;
        this.title = title;
        this.detail = detail;
        this.code = code;
        this.traceId = traceId;
        this.errors = errors == null ? null : Collections.unmodifiableMap(errors);
        this.requestId = requestId;
        this.retryAfter = retryAfter;
        this.body = body;
    }

    /** A client-side error with no HTTP response (network failure, bad signature). */
    static OpensmsException local(String message, String code, Throwable cause) {
        return new OpensmsException(message, 0, null, null, null, code, null, null, null, null, null, cause);
    }

    /** @return HTTP status, {@code 0} when no response was received. */
    public int getStatus() { return status; }

    /** @return problem {@code type} ({@code about:blank} or {@code https://api.opensms.io/problems/<code>}). */
    public String getType() { return type; }

    /** @return problem {@code title}, for example {@code Bad Request}. */
    public String getTitle() { return title; }

    /** @return problem {@code detail}, the human-readable explanation. */
    public String getDetail() { return detail; }

    /** @return machine code, absent on most errors. */
    public String getCode() { return code; }

    /** @return problem {@code trace_id}, if any. */
    public String getTraceId() { return traceId; }

    /** @return field validation errors, if any. */
    public Map<String, List<String>> getErrors() { return errors; }

    /** @return {@code X-Request-ID}, set on message and OTP admission rejections. */
    public String getRequestId() { return requestId; }

    /** @return {@code Retry-After} in seconds, if the server sent one. */
    public Long getRetryAfter() { return retryAfter; }

    /** @return the decoded JSON body ({@link JsonNode}) or the raw text when it was not JSON. */
    public Object getBody() { return body; }
}
