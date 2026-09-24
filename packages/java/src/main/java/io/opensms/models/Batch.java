package io.opensms.models;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

/** A batch of messages. Fields the API omits decode as null. */
public final class Batch {
    public String id;
    /** ready, running, stopped, completed or failed. */
    public String status;
    public Integer total;
    public Integer sent;
    public Integer delivered;
    public Integer failed;
    public Integer invalid;
    public Integer duplicates;
    public Integer suppressed;
    /** Estimated cost, or null. */
    public BigDecimal estimatedCost;
    public OffsetDateTime createdAt;
    public OffsetDateTime completedAt;
}
