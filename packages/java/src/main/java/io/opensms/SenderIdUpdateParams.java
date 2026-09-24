package io.opensms;

import java.util.List;
import java.util.Map;

/** Body of {@code senderIds.update} (amend a registration). */
public final class SenderIdUpdateParams {

    private final String useCase;
    private final List<String> countries;
    private final List<String> documents;
    private String sampleMessage;

    /**
     * @param useCase   use case.
     * @param countries ISO2 markets.
     * @param documents document ids.
     */
    public SenderIdUpdateParams(String useCase, List<String> countries, List<String> documents) {
        this.useCase = useCase;
        this.countries = countries;
        this.documents = documents;
    }

    /** @param sampleMessage example message. @return this. */
    public SenderIdUpdateParams sampleMessage(String sampleMessage) { this.sampleMessage = sampleMessage; return this; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("use_case", Wire.require(useCase, "useCase"));
        m.put("countries", Wire.require(countries, "countries"));
        m.put("documents", Wire.require(documents, "documents"));
        Wire.put(m, "sample_message", sampleMessage);
        return m;
    }
}
