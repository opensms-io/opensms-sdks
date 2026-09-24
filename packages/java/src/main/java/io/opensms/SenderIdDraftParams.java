package io.opensms;

import java.util.List;
import java.util.Map;

/**
 * Body of {@code senderIds.createDraft} (all optional) and
 * {@code senderIds.updateDraft} ({@code version} required, the optimistic lock).
 */
public final class SenderIdDraftParams {

    private Integer version;
    private String source;
    private String value;
    private String kind;
    private List<String> countries;
    private String useCase;
    private String sampleMessage;
    private List<String> documents;

    /** Empty parameters. */
    public SenderIdDraftParams() {
    }

    /** @param version current draft version (updates only). @return this. */
    public SenderIdDraftParams version(Integer version) { this.version = version; return this; }

    /** @param source {@code onboarding} or {@code application} (create only). @return this. */
    public SenderIdDraftParams source(String source) { this.source = source; return this; }

    /** @param value sender ID text. @return this. */
    public SenderIdDraftParams value(String value) { this.value = value; return this; }

    /** @param kind {@code alphanumeric} or {@code numeric}. @return this. */
    public SenderIdDraftParams kind(String kind) { this.kind = kind; return this; }

    /** @param countries ISO2 markets. @return this. */
    public SenderIdDraftParams countries(List<String> countries) { this.countries = countries; return this; }

    /** @param useCase use case. @return this. */
    public SenderIdDraftParams useCase(String useCase) { this.useCase = useCase; return this; }

    /** @param sampleMessage example message. @return this. */
    public SenderIdDraftParams sampleMessage(String sampleMessage) { this.sampleMessage = sampleMessage; return this; }

    /** @param documents document ids. @return this. */
    public SenderIdDraftParams documents(List<String> documents) { this.documents = documents; return this; }

    Integer version() { return version; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        Wire.put(m, "version", version);
        Wire.put(m, "source", source);
        Wire.put(m, "value", value);
        Wire.put(m, "kind", kind);
        Wire.put(m, "countries", countries);
        Wire.put(m, "use_case", useCase);
        Wire.put(m, "sample_message", sampleMessage);
        Wire.put(m, "documents", documents);
        return m;
    }
}
