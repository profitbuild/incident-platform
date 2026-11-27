package com.incidentplatform.ingestion.normalizer;

import com.fasterxml.jackson.databind.JsonNode;
import com.incidentplatform.shared.domain.Severity;
import com.incidentplatform.shared.dto.UnifiedAlertDto;
import com.incidentplatform.shared.events.SourceType;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * <h2>Fixed: fingerprint was built from {@code title} alone</h2>
 * Unlike {@link PrometheusNormalizer} ({@code alertName + instance}) and
 * {@link WazuhNormalizer} ({@code ruleId + agentId}), this normalizer's
 * fingerprint used to be {@code buildFingerprint(title)} — nothing else.
 * Two genuinely unrelated alerts sharing an identical title (e.g. "Disk
 * full" fired independently for two different hosts, sent by the same
 * tenant through the generic webhook) got the exact same fingerprint,
 * and {@code DeduplicationService} would wrongly treat the second as a
 * duplicate of the first and drop it.
 *
 * <p>Fixed by accepting an optional {@code resource} field in the
 * payload — the generic format's equivalent of Prometheus's
 * {@code instance} or Wazuh's {@code agentId}: whatever identifies
 * <em>which specific thing</em> this alert is about (hostname, service
 * name, container ID, etc.). When present, it's included in the
 * fingerprint, giving the same disambiguation the other two normalizers
 * already have. When absent, the fingerprint falls back to
 * {@code title} alone — deliberately unchanged from before, rather than
 * e.g. substituting a literal {@code "unknown"} placeholder, which would
 * have altered the fingerprint format (and therefore silently reset
 * in-flight deduplication state) for every existing generic integration
 * that doesn't send {@code resource}, on the very next deploy. Since the
 * generic format has no schema-guaranteed identity field the platform
 * can rely on unconditionally (unlike Prometheus/Wazuh, whose vendor
 * formats define one), correctly disambiguating same-titled alerts is
 * opt-in: integrators who send multiple distinct alerts under
 * potentially identical titles should supply {@code resource} to get
 * correct deduplication; those who don't get today's exact,
 * already-relied-upon behavior.
 */
@Component
public class GenericNormalizer extends BaseNormalizer {

    private static final String SOURCE = "generic";

    @Override
    public NormalizationResult normalize(JsonNode rawPayload, String tenantId,
                                         UUID teamId) {
        log.debug("Normalizing generic alert for tenant: {}", tenantId);

        final String title = getTextOrThrow(rawPayload, "title");

        final Severity severity = parseSeverity(
                getTextOrThrow(rawPayload, "severity")
        );

        final String source = getText(rawPayload, "source", SOURCE);
        final SourceType sourceType = parseSourceType(
                getText(rawPayload, "sourceType", "OPS")
        );
        final String description = getText(rawPayload, "description", null);
        final Instant firedAt = parseInstant(getText(rawPayload, "firedAt", null));
        final Map<String, String> metadata = extractMetadata(rawPayload);

        log.info("Generic alert normalized: source={}, severity={}, tenant={}",
                source, severity, tenantId);

        // Fixed: see this class's Javadoc. resource is optional — when a
        // caller supplies it, the fingerprint correctly disambiguates
        // between distinct alerts that happen to share a title; when
        // absent, this preserves the exact pre-existing single-component
        // fingerprint rather than changing the format for everyone.
        final String resource = getText(rawPayload, "resource", null);
        final String fingerprint = resource != null
                ? buildFingerprint(title, resource)
                : buildFingerprint(title);

        return NormalizationResult.firingOnly(List.of(new UnifiedAlertDto(
                UUID.randomUUID(),
                tenantId,
                source,
                sourceType,
                severity,
                title,
                description,
                firedAt,
                fingerprint,
                metadata,
                teamId
        )));
    }

    @Override
    public String getSourceName() {
        return SOURCE;
    }

    private Severity parseSeverity(String rawSeverity) {
        try {
            return Severity.fromString(rawSeverity);
        } catch (IllegalArgumentException e) {
            // Backlog #0-96 (found in review): the reason goes into the
            // dead-letter copy and the log, so it names the field, not the
            // sender's value (the copy keeps the payload itself).
            throw new NormalizationException(SOURCE,
                    String.format("Invalid severity. Allowed values: %s",
                            java.util.Arrays.toString(Severity.values())));
        }
    }

    private SourceType parseSourceType(String sourceType) {
        try {
            // Locale.ROOT: under a Turkish default an "i" upper-cases to "İ" and matches no constant (backlog #0-323)
            return SourceType.valueOf(sourceType.toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            log.warn("Unknown sourceType '{}', defaulting to OPS", sourceType);
            return SourceType.OPS;
        }
    }

    private Map<String, String> extractMetadata(JsonNode payload) {
        final JsonNode metadataNode = payload.get("metadata");
        if (metadataNode == null || !metadataNode.isObject()) return Map.of();

        final Map<String, String> metadata = new HashMap<>();

        metadataNode.properties().forEach(entry -> {
            if (metadata.size() < 20) {
                final String value = entry.getValue().asText();
                metadata.put(
                        entry.getKey(),
                        value.length() <= 500 ? value : value.substring(0, 500)
                );
            }
        });

        return metadata;
    }
}