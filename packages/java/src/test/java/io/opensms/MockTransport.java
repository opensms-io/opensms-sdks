package io.opensms;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;
import java.util.Map;

/** Records requests and replays scripted responses or network failures. No network. */
final class MockTransport implements HttpTransport {

    final List<Request> requests = new ArrayList<>();
    final List<Duration> sleeps = new ArrayList<>();
    private final Deque<Object> script = new ArrayDeque<>();

    MockTransport reply(int status, String body, String... headerPairs) {
        Map<String, List<String>> headers = new java.util.LinkedHashMap<>();
        headers.put("Content-Type", List.of(status >= 400 ? "application/problem+json" : "application/json"));
        for (int i = 0; i + 1 < headerPairs.length; i += 2) {
            headers.put(headerPairs[i], List.of(headerPairs[i + 1]));
        }
        script.add(new Response(status, headers, body == null ? null : body.getBytes(StandardCharsets.UTF_8)));
        return this;
    }

    /** Drop any remaining scripted responses. */
    MockTransport reset() {
        script.clear();
        return this;
    }

    MockTransport fail(IOException e) {
        script.add(e);
        return this;
    }

    @Override
    public Response send(Request request) throws IOException {
        requests.add(request);
        Object next = script.size() > 1 ? script.poll() : script.peek();
        if (next == null) {
            throw new IllegalStateException("no scripted response");
        }
        if (next instanceof IOException e) {
            throw e;
        }
        return (Response) next;
    }

    OpensmsClient client() {
        return client(OpensmsClientTest.KEY);
    }

    OpensmsClient client(String key) {
        return OpensmsClient.builder().apiKey(key).baseUrl("http://mock.test").transport(this)
                .sleeper(sleeps::add).build();
    }

    Request last() {
        return requests.get(requests.size() - 1);
    }

    static String body(Request r) {
        return r.body() == null ? null : new String(r.body(), StandardCharsets.UTF_8);
    }
}
