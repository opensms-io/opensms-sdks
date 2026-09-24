package io.opensms;

import java.io.IOException;
import java.net.URI;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/**
 * The pluggable network layer. The default implementation, {@link JdkHttpTransport},
 * wraps {@link java.net.http.HttpClient}. Tests (or callers with special needs)
 * can supply their own implementation through
 * {@link OpensmsClient.Builder#transport(HttpTransport)}.
 *
 * <p>An implementation performs exactly one HTTP exchange per call. Retries,
 * headers and error mapping are handled above it.
 */
@FunctionalInterface
public interface HttpTransport {

    /**
     * Perform one HTTP exchange.
     *
     * @param request the fully built request.
     * @return the raw response.
     * @throws IOException          on a network failure or timeout (retried when safe).
     * @throws InterruptedException when the calling thread is interrupted.
     */
    Response send(Request request) throws IOException, InterruptedException;

    /**
     * One outgoing request.
     *
     * @param method  HTTP method.
     * @param uri     absolute URI including the query string.
     * @param headers request headers (single value per name).
     * @param body    request body bytes, or {@code null} for none.
     */
    record Request(String method, URI uri, Map<String, String> headers, byte[] body) {
        /**
         * Case-insensitive header lookup.
         *
         * @param name header name.
         * @return the value, or {@code null} when absent.
         */
        public String header(String name) {
            for (Map.Entry<String, String> e : headers.entrySet()) {
                if (e.getKey().equalsIgnoreCase(name)) {
                    return e.getValue();
                }
            }
            return null;
        }
    }

    /**
     * One raw response.
     *
     * @param status  HTTP status code.
     * @param headers response headers.
     * @param body    response body bytes (never {@code null}; may be empty).
     */
    record Response(int status, Map<String, List<String>> headers, byte[] body) {
        /** Normalises a {@code null} body or header map to empty. */
        public Response {
            headers = headers == null ? Collections.emptyMap() : headers;
            body = body == null ? new byte[0] : body;
        }

        /**
         * Case-insensitive lookup of the first value of a header.
         *
         * @param name header name.
         * @return the first value, or {@code null} when absent.
         */
        public String header(String name) {
            for (Map.Entry<String, List<String>> e : headers.entrySet()) {
                if (e.getKey() != null && e.getKey().equalsIgnoreCase(name) && !e.getValue().isEmpty()) {
                    return e.getValue().get(0);
                }
            }
            return null;
        }
    }
}
