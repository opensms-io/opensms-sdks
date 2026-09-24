package io.opensms.models;

/** Result of sending an OTP. Fields the API omits decode as null. */
public final class OtpSendResult {
    /** Pass this to verify. */
    public String otpId;
}
