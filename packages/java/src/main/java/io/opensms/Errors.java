package io.opensms;

import com.fasterxml.jackson.databind.JsonNode;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Maps a non-2xx response to {@link OpensmsException}. Not part of the public API. */
final class Errors {

    private Errors() {
    }

    static OpensmsException fromResponse(HttpTransport.Response res) {
        int status = res.status();
        String text = new String(res.body(), StandardCharsets.UTF_8);
        String type = null, title = null, detail = null, code = null, traceId = null;
        Map<String, List<String>> errors = null;
        Object body = text.isEmpty() ? null : text;

        JsonNode root = null;
        if (!text.isEmpty()) {
            try {
                root = Json.MAPPER.readTree(text);
            } catch (Exception ignored) {
                // not JSON (for example a proxy HTML page): keep the raw text in body
            }
        }
        if (root != null && root.isObject()) {
            body = root;
            type = str(root, "type");
            title = str(root, "title");
            detail = str(root, "detail");
            code = str(root, "code");
            traceId = str(root, "trace_id");
            JsonNode e = root.get("errors");
            if (e != null && e.isObject()) {
                errors = new LinkedHashMap<>();
                for (Iterator<Map.Entry<String, JsonNode>> it = e.fields(); it.hasNext(); ) {
                    Map.Entry<String, JsonNode> f = it.next();
                    List<String> msgs = new ArrayList<>();
                    if (f.getValue().isArray()) {
                        for (JsonNode m : f.getValue()) msgs.add(m.asText());
                    } else if (!f.getValue().isNull()) {
                        msgs.add(f.getValue().asText());
                    }
                    errors.put(f.getKey(), msgs);
                }
            }
        } else if (root != null) {
            body = root;
        }

        String message = detail != null ? detail
                : title != null ? title
                : "OpenSMS request failed with status " + status;
        return new OpensmsException(message, status, type, title, detail, code, traceId, errors,
                res.header("X-Request-ID"), parseRetryAfter(res.header("Retry-After")), body, null);
    }

    /** {@code Retry-After} as whole seconds: integer seconds or an HTTP date. {@code null} when absent or unparseable. */
    static Long parseRetryAfter(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String v = value.trim();
        try {
            double secs = Double.parseDouble(v);
            return secs < 0 ? 0L : (long) Math.ceil(secs);
        } catch (NumberFormatException ignored) {
            // fall through to HTTP date
        }
        try {
            Instant when = ZonedDateTime.parse(v, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant();
            long secs = (long) Math.ceil((when.toEpochMilli() - System.currentTimeMillis()) / 1000.0);
            return Math.max(0L, secs);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String str(JsonNode n, String field) {
        JsonNode v = n.get(field);
        return v == null || v.isNull() ? null : v.asText();
    }
}
