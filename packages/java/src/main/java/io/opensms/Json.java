package io.opensms;

import com.fasterxml.jackson.annotation.JsonAutoDetect;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.PropertyAccessor;
import com.fasterxml.jackson.core.JsonGenerator;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.fasterxml.jackson.databind.JsonSerializer;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.SerializerProvider;
import com.fasterxml.jackson.databind.module.SimpleModule;

import java.io.IOException;
import java.time.OffsetDateTime;
import java.time.format.DateTimeFormatter;

/**
 * The one place that maps wire names to Java names. Response models use
 * camelCase public fields; this mapper translates them from the API's
 * snake_case ({@code next_cursor} to {@code nextCursor}, {@code country_iso2} to
 * {@code countryIso2}), ignores unknown fields, and parses RFC 3339 timestamps
 * into {@link OffsetDateTime} without an extra dependency. Not part of the public API.
 */
final class Json {

    private Json() {
    }

    static final ObjectMapper MAPPER = create();

    private static ObjectMapper create() {
        SimpleModule time = new SimpleModule("opensms-time");
        time.addDeserializer(OffsetDateTime.class, new JsonDeserializer<>() {
            @Override
            public OffsetDateTime deserialize(JsonParser p, DeserializationContext ctx) throws IOException {
                String s = p.getValueAsString();
                if (s == null || s.isEmpty()) {
                    return null;
                }
                return OffsetDateTime.parse(s, DateTimeFormatter.ISO_OFFSET_DATE_TIME);
            }
        });
        time.addSerializer(OffsetDateTime.class, new JsonSerializer<>() {
            @Override
            public void serialize(OffsetDateTime v, JsonGenerator g, SerializerProvider sp) throws IOException {
                g.writeString(v.format(DateTimeFormatter.ISO_OFFSET_DATE_TIME));
            }
        });
        return new ObjectMapper()
                .registerModule(time)
                .setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
                .setSerializationInclusion(JsonInclude.Include.NON_NULL)
                .setVisibility(PropertyAccessor.ALL, JsonAutoDetect.Visibility.NONE)
                .setVisibility(PropertyAccessor.FIELD, JsonAutoDetect.Visibility.PUBLIC_ONLY)
                .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);
    }
}
