package io.opensms;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Internal helper for URL query strings and path segments. Unset (null) values
 * are omitted; list values are joined with commas. Not part of the public API.
 */
final class Query {

    private final Map<String, String> params = new LinkedHashMap<>();

    private Query() {
    }

    static Query of() {
        return new Query();
    }

    /** Add a parameter when {@code value} is non-null. Lists are joined with commas. */
    Query add(String key, Object value) {
        if (value == null) {
            return this;
        }
        if (value instanceof List<?> list) {
            if (list.isEmpty()) {
                return this;
            }
            StringBuilder sb = new StringBuilder();
            for (Object o : list) {
                if (sb.length() > 0) sb.append(',');
                sb.append(o);
            }
            params.put(key, sb.toString());
        } else {
            params.put(key, String.valueOf(value));
        }
        return this;
    }

    /** Render with a leading {@code ?}, or the empty string when nothing is set. */
    String build() {
        if (params.isEmpty()) {
            return "";
        }
        StringBuilder sb = new StringBuilder("?");
        boolean first = true;
        for (Map.Entry<String, String> e : params.entrySet()) {
            if (!first) sb.append('&');
            first = false;
            sb.append(encQuery(e.getKey())).append('=').append(encQuery(e.getValue()));
        }
        return sb.toString();
    }

    /** Encode a query component; commas stay literal (they are list separators). */
    static String encQuery(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8).replace("+", "%20").replace("%2C", ",");
    }

    /** Encode one path segment: {@code a/b} becomes {@code a%2Fb}, spaces become {@code %20}. */
    static String seg(String s) {
        return URLEncoder.encode(s, StandardCharsets.UTF_8).replace("+", "%20");
    }
}
