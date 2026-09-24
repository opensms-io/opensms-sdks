package io.opensms;

import java.util.List;
import java.util.Map;

/** Body of {@code senderIds.create}. {@code value}, {@code kind}, {@code countries} and {@code documents} are required. */
public final class SenderIdCreateParams {

    private final String value;
    private final String kind;
    private final List<String> countries;
    private final List<String> documents;
    private String useCase;
    private String sampleMessage;
    private String draftId;
    private Integer draftVersion;
    private String quoteId;

    /**
     * @param value     the sender ID text.
     * @param kind      {@code alphanumeric} or {@code numeric}.
     * @param countries ISO2 markets.
     * @param documents uploaded document ids (certificate, signatory-id, authorization).
     */
    public SenderIdCreateParams(String value, String kind, List<String> countries, List<String> documents) {
        this.value = value;
        this.kind = kind;
        this.countries = countries;
        this.documents = documents;
    }

    /** @param useCase {@code otp}, {@code transactional} or {@code marketing}. @return this. */
    public SenderIdCreateParams useCase(String useCase) { this.useCase = useCase; return this; }

    /** @param sampleMessage example message. @return this. */
    public SenderIdCreateParams sampleMessage(String sampleMessage) { this.sampleMessage = sampleMessage; return this; }

    /** @param draftId draft to mark submitted. @return this. */
    public SenderIdCreateParams draftId(String draftId) { this.draftId = draftId; return this; }

    /** @param draftVersion required with draftId. @return this. */
    public SenderIdCreateParams draftVersion(Integer draftVersion) { this.draftVersion = draftVersion; return this; }

    /** @param quoteId from {@code senderIds.quote}, required when a fee applies. @return this. */
    public SenderIdCreateParams quoteId(String quoteId) { this.quoteId = quoteId; return this; }

    Map<String, Object> toWire() {
        Map<String, Object> m = Wire.map();
        m.put("value", Wire.require(value, "value"));
        m.put("kind", Wire.require(kind, "kind"));
        m.put("countries", Wire.require(countries, "countries"));
        Wire.put(m, "use_case", useCase);
        Wire.put(m, "sample_message", sampleMessage);
        m.put("documents", Wire.require(documents, "documents"));
        Wire.put(m, "draft_id", draftId);
        Wire.put(m, "draft_version", draftVersion);
        Wire.put(m, "quote_id", quoteId);
        return m;
    }
}
