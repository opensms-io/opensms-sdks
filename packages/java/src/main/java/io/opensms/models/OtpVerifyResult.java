package io.opensms.models;

/** Result of verifying an OTP code. Fields the API omits decode as null. */
public final class OtpVerifyResult {
    public Boolean valid;
    public Integer attemptsLeft;
}
