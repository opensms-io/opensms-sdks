package io.opensms;

import java.util.Map;

/**
 * One suppression to create or import.
 *
 * @param e164   phone number in E.164.
 * @param reason {@code stop_keyword}, {@code manual}, {@code complaint} or {@code invalid_number}.
 */
public record SuppressionInput(String e164, String reason) {

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("e164", Wire.require(e164, "e164"));
        m.put("reason", Wire.require(reason, "reason"));
        return m;
    }
}
