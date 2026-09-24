package io.opensms.models;

import java.time.OffsetDateTime;

/** A wallet ledger entry. Fields the API omits decode as null. */
public final class LedgerEntry {
    /** Pass the smallest id seen as {@code before} to page. */
    public Long id;
    public String walletId;
    public String type;
    public String amount;
    public String balanceAfter;
    public String reservedDelta;
    public String reservedAfter;
    public String reference;
    public String paymentId;
    public String messageId;
    public OffsetDateTime createdAt;
}
