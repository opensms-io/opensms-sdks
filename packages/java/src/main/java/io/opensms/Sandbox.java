package io.opensms;

import io.opensms.models.Page;
import io.opensms.models.SandboxMessage;

/** Sandbox inspection. Accessed as {@code client.sandbox()}. */
public final class Sandbox {

    private final ApiTransport t;

    Sandbox(ApiTransport t) {
        this.t = t;
    }

    /** @return the first page of sandbox messages. */
    public Page<SandboxMessage> listMessages() {
        return listMessages(new ListParams());
    }

    /**
     * Messages sent with a test key, with their rendered text (including OTP codes).
     *
     * @param params paging.
     * @return one page.
     */
    public Page<SandboxMessage> listMessages(ListParams params) {
        return t.get("/v1/sandbox/messages", params.toQuery(), ApiTransport.pageOf(SandboxMessage.class));
    }
}
