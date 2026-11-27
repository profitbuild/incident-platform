package com.incidentplatform.shared.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.incidentplatform.shared.domain.Severity;
import com.incidentplatform.shared.events.SourceType;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.Collections;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

@JsonIgnoreProperties(ignoreUnknown = true)
public record UnifiedAlertDto(

        @JsonProperty("alertId")
        @NotNull
        UUID alertId,

        @JsonProperty("tenantId")
        @NotBlank
        String tenantId,

        @JsonProperty("source")
        @NotBlank
        @Size(max = 100, message = "Source name must not exceed 100 characters")
        String source,

        @JsonProperty("sourceType")
        @NotNull
        SourceType sourceType,

        @JsonProperty("severity")
        @NotNull
        Severity severity,

        @JsonProperty("title")
        @NotBlank
        @Size(max = 255, message = "Title must not exceed 255 characters")
        String title,

        @JsonProperty("description")
        @Size(max = 5000, message = "Description must not exceed 5000 characters")
        String description,

        @JsonProperty("firedAt")
        @NotNull
        Instant firedAt,

        @JsonProperty("fingerprint")
        @NotBlank
        String fingerprint,

        @JsonProperty("metadata")
        Map<String, String> metadata,

        /**
         * Team responsible for this alert — resolved from the Integration
         * that authenticated the request (ApiKey → Integration → Team).
         *
         * <p>Null when:
         * <ul>
         *   <li>Alert sent with JWT (ROLE_INGESTOR) instead of Integration ApiKey</li>
         *   <li>Integration was created without a team assignment</li>
         * </ul>
         *
         * <p>Propagated to {@code Incident.team_id} by incident-service.
         * EscalationScheduler uses it to find the correct on-call engineer.
         */
        @JsonProperty("teamId")
        UUID teamId

) {
    public UnifiedAlertDto {
        if (alertId == null) alertId = UUID.randomUUID();
        if (title != null) title = title.trim();
        if (source != null) source = source.toLowerCase(Locale.ROOT);

        if (metadata != null) {
            metadata = Collections.unmodifiableMap(Map.copyOf(metadata));
        }
    }

    public boolean isSecurityAlert() {
        return SourceType.SECURITY.equals(sourceType);
    }

    public boolean isCritical() {
        return Severity.CRITICAL.equals(severity);
    }
}