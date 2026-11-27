package com.incidentplatform.ingestion.normalizer;

import com.fasterxml.jackson.databind.JsonNode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.Locale;

public abstract class BaseNormalizer implements AlertNormalizer {

    protected final Logger log = LoggerFactory.getLogger(getClass());

    protected String getTextOrThrow(JsonNode node, String field) {
        final JsonNode value = node == null ? null : node.get(field);
        if (value == null || value.isNull() || value.asText().isBlank()) {
            throw new NormalizationException(getSourceName(),
                    String.format("Missing required field: '%s'", field));
        }
        return value.asText().trim();
    }

    protected String getText(JsonNode node, String field, String defaultValue) {
        if (node == null) return defaultValue;
        final JsonNode value = node.get(field);
        if (value == null || value.isNull() || value.asText().isBlank()) {
            return defaultValue;
        }
        return value.asText().trim();
    }

    protected Instant parseInstant(String timestamp) {
        if (timestamp == null || timestamp.isBlank()) {
            log.debug("No timestamp provided for source '{}', using current time",
                    getSourceName());
            return Instant.now();
        }
        try {
            final String normalized = timestamp.replace("+0000", "Z");
            return Instant.parse(normalized);
        } catch (DateTimeParseException e) {
            log.warn("Failed to parse timestamp '{}' from source '{}', " +
                    "using current time", timestamp, getSourceName());
            return Instant.now();
        }
    }

    protected String buildFingerprint(String... parts) {
        final StringBuilder sb = new StringBuilder(getSourceName());
        for (final String part : parts) {
            sb.append(":");
            // Locale.ROOT: the dedup fingerprint must not depend on the replica's default locale (backlog #0-323)
            sb.append(part != null ? part.toLowerCase(Locale.ROOT).trim() : "unknown");
        }
        return sb.toString();
    }

    protected boolean isMissingOrNotObject(JsonNode node) {
        return node == null || node.isNull() || !node.isObject();
    }
}