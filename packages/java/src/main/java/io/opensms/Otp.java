package io.opensms;

import io.opensms.models.OtpSendResult;
import io.opensms.models.OtpVerifyResult;

import java.util.Map;

/** Send and verify one-time passcodes. Accessed as {@code client.otp()}. */
public final class Otp {

    private final ApiTransport t;

    Otp(ApiTransport t) {
        this.t = t;
    }

    /**
     * @param params destination and options.
     * @return {@code {otpId}}.
     */
    public OtpSendResult send(OtpSendParams params) {
        return send(params, null);
    }

    /**
     * @param params  destination and options.
     * @param options per-call options.
     * @return {@code {otpId}}.
     */
    public OtpSendResult send(OtpSendParams params, RequestOptions options) {
        return t.json("POST", "/v1/otp/send", params.toWire(), ApiTransport.idempotencyKey(options),
                ApiTransport.type(OtpSendResult.class));
    }

    /**
     * Verify a code. A wrong code returns {@code valid=false} and uses up an
     * attempt, so this call is never retried automatically.
     *
     * @param otpId from {@link #send}.
     * @param code  the code the user entered.
     * @return {@code {valid, attemptsLeft}}.
     */
    public OtpVerifyResult verify(String otpId, String code) {
        Map<String, Object> body = Wire.map();
        body.put("otp_id", Wire.require(otpId, "otpId"));
        body.put("code", Wire.require(code, "code"));
        return t.json("POST", "/v1/otp/verify", body, null, ApiTransport.type(OtpVerifyResult.class));
    }
}
