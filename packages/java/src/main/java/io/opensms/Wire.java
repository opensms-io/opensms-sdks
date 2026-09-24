package io.opensms;

import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

/** Internal helpers for building JSON request bodies. Not part of the public API. */
final class Wire {

    private Wire() {
    }

    /** A new ordered map for accumulating wire fields. */
    static Map<String, Object> map() {
        return new LinkedHashMap<>();
    }

    /** Put {@code value} under {@code key} only when non-null, so unset optionals are omitted. */
    static void put(Map<String, Object> m, String key, Object value) {
        if (value != null) {
            m.put(key, value);
        }
    }

    /** Fail fast with an argument error when a required value is missing. */
    static <T> T require(T value, String name) {
        if (value == null || (value instanceof String s && s.isEmpty())) {
            throw new IllegalArgumentException(name + " is required");
        }
        return value;
    }

    /** Validate a path id (non-empty, else an argument error before any request) and URL-escape it. */
    static String id(String value, String name) {
        if (value == null || value.isEmpty()) {
            throw new IllegalArgumentException(name + " is required");
        }
        return Query.seg(value);
    }

    /** RFC 3339 in UTC, for example {@code 2026-09-24T10:00:00Z}. */
    static String rfc3339(Instant t) {
        return t == null ? null : DateTimeFormatter.ISO_INSTANT.format(t);
    }

    /** RFC 3339 in UTC. */
    static String rfc3339(OffsetDateTime t) {
        return t == null ? null : rfc3339(t.withOffsetSameInstant(ZoneOffset.UTC).toInstant());
    }
}
