package io.opensms;

import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.JsonNode;
import io.opensms.models.LedgerEntry;
import io.opensms.models.Topup;
import io.opensms.models.WalletBalance;

import java.util.Collections;
import java.util.List;

/** Wallet balances, ledger and top-ups. Accessed as {@code client.wallet()}. */
public final class Wallet {

    private final ApiTransport t;

    Wallet(ApiTransport t) {
        this.t = t;
    }

    /** @return balances for the key's environment. */
    public List<WalletBalance> balances() {
        return data(t.get("/v1/wallet", null, ApiTransport.type(JsonNode.class)),
                ApiTransport.listOf(WalletBalance.class));
    }

    /** @return the newest ledger entries (server default page size). */
    public List<LedgerEntry> ledger() {
        return ledger(null, null);
    }

    /**
     * The ledger pages by id, not by cursor: pass the smallest {@code id} you have
     * seen as {@code before}; stop when fewer than {@code limit} entries come back.
     *
     * @param limit  1..200, or {@code null}.
     * @param before return entries with a smaller id, or {@code null}.
     * @return ledger entries, newest first.
     */
    public List<LedgerEntry> ledger(Integer limit, Long before) {
        return data(t.get("/v1/wallet/ledger", Query.of().add("limit", limit).add("before", before),
                ApiTransport.type(JsonNode.class)), ApiTransport.listOf(LedgerEntry.class));
    }

    /**
     * Start a payment to top up the wallet (live keys only).
     *
     * @param params amount, currency, channel and payer email.
     * @return the payment initialisation, including {@code authorizationUrl}.
     */
    public Topup createTopup(TopupParams params) {
        return createTopup(params, null);
    }

    /**
     * @param params  amount, currency, channel and payer email.
     * @param options per-call options.
     * @return the payment initialisation.
     */
    public Topup createTopup(TopupParams params, RequestOptions options) {
        return t.json("POST", "/v1/wallet/topups", params.toWire(), ApiTransport.idempotencyKey(options),
                ApiTransport.type(Topup.class));
    }

    private static <T> List<T> data(JsonNode root, JavaType listType) {
        if (root == null || root.get("data") == null || root.get("data").isNull()) {
            return Collections.emptyList();
        }
        return Json.MAPPER.convertValue(root.get("data"), listType);
    }
}
