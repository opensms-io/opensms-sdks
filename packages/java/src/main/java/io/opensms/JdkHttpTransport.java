package io.opensms;

import java.io.IOException;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Map;
import java.util.Set;

/**
 * Default {@link HttpTransport} backed by {@link HttpClient}. The per-attempt
 * timeout is applied to every request; the client's connect timeout is set to
 * the same value when this transport creates the client itself.
 */
public final class JdkHttpTransport implements HttpTransport {

    /** Headers the JDK client manages itself and refuses to accept. */
    private static final Set<String> RESTRICTED = Set.of("content-length", "host", "connection");

    private final HttpClient http;
    private final Duration timeout;

    /**
     * @param http    the client to use, or {@code null} to create one.
     * @param timeout per-attempt timeout (connect plus response).
     */
    public JdkHttpTransport(HttpClient http, Duration timeout) {
        this.timeout = timeout;
        this.http = http != null ? http : HttpClient.newBuilder().connectTimeout(timeout).build();
    }

    @Override
    public Response send(Request request) throws IOException, InterruptedException {
        HttpRequest.Builder rb = HttpRequest.newBuilder(request.uri()).timeout(timeout);
        for (Map.Entry<String, String> h : request.headers().entrySet()) {
            if (!RESTRICTED.contains(h.getKey().toLowerCase())) {
                rb.header(h.getKey(), h.getValue());
            }
        }
        HttpRequest.BodyPublisher publisher = request.body() == null
                ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofByteArray(request.body());
        rb.method(request.method(), publisher);
        HttpResponse<byte[]> res = http.send(rb.build(), HttpResponse.BodyHandlers.ofByteArray());
        return new Response(res.statusCode(), res.headers().map(), res.body());
    }
}
