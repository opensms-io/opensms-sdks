package io.opensms;

import java.util.Map;

/**
 * Body of {@code wallet.createTopup} (live keys only).
 *
 * @param amount   decimal string, for example {@code "100.00"}.
 * @param currency ISO 4217 currency.
 * @param channel  {@code card}, {@code mobile_money} or {@code bank_transfer}.
 * @param email    payer email, a verified member of the workspace.
 */
public record TopupParams(String amount, String currency, String channel, String email) {

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("amount", Wire.require(amount, "amount"));
        m.put("currency", Wire.require(currency, "currency"));
        m.put("channel", Wire.require(channel, "channel"));
        m.put("email", Wire.require(email, "email"));
        return m;
    }
}
