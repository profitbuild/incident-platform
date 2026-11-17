package com.incidentplatform.notification.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.incidentplatform.shared.observability.ClientFallbackMetrics;
import com.incidentplatform.shared.security.ServiceNames;
import com.incidentplatform.shared.security.ServiceTokenProvider;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

import java.util.Optional;
import java.util.UUID;

/**
 * HTTP client for oncall-service.
 *
 * <h2>Fixed: @CircuitBreaker never actually opened</h2>
 * Both methods previously wrapped their whole body in a
 * {@code try (RestClientException e) {...} catch (Exception e) {...}}
 * that returned {@code Optional.empty()} from inside the catch block —
 * with no {@code fallbackMethod} even declared on either
 * {@code @CircuitBreaker}. Resilience4j only records a failure when the
 * proxied method throws; a caught-and-swallowed exception is
 * indistinguishable from success to the proxy, so the "oncall" circuit
 * breaker's failure rate never moved and the breaker could never open —
 * same root cause independently found and fixed in
 * {@code IncidentAckClient} (this package) and
 * {@code DeduplicationService} (ingestion-service), using
 * {@code escalation-service}'s {@code OncallServiceClient} as the
 * reference pattern for what a correctly-wired circuit breaker looks
 * like in this codebase.
 *
 * <p>Both methods below now let {@code RestClientException} (and any
 * other real failure) propagate out to the proxy, with the fail-open
 * behavior moved to dedicated fallback methods instead of an inline
 * catch. {@link #parseOncallInfo} no longer declares a checked
 * {@code throws Exception} — {@code JsonProcessingException} is wrapped
 * as an unchecked {@link OncallResponseParsingException} so it also
 * propagates to the proxy cleanly, without forcing a checked-exception
 * catch back into the calling methods.
 *
 * <h2>Changed (backlog #0-23): no retry of its own</h2>
 * The three lookups used to carry {@code @Retry(name = "oncall")} outside the
 * {@code @CircuitBreaker}. Its fallback answers every failure
 * ({@link OncallLookupUnavailableException} is not in {@code retry-exceptions},
 * and {@code Optional.empty()} is a success), so the retry never saw an
 * exception and never fired. It is removed rather than repaired: the lookups'
 * retry is the scheduler's. An entry whose lookup failed stays PENDING and is
 * tried every cycle until {@code notification.scheduler.lookup-retry-window}
 * (a deadline, not an attempt count).
 *
 * <p>Not chosen: a {@code fallbackMethod} on the {@code @Retry} would double the
 * worst case on the scheduler thread, which runs under the 4-minute ShedLock;
 * listing the fallback exception in {@code retry-exceptions} would retry 4xx
 * answers and an open breaker.
 */
@Component
public class OncallClientImpl implements OncallClient {

    private static final Logger log =
            LoggerFactory.getLogger(OncallClientImpl.class);

    private final RestClient restClient;
    private final ObjectMapper objectMapper;
    private final ServiceTokenProvider serviceTokenProvider;
    private final ClientFallbackMetrics fallbackMetrics;
    private final String oncallServiceBaseUrl;

    public OncallClientImpl(
            @Qualifier("notificationServiceRestClient") RestClient restClient,
            ObjectMapper objectMapper,
            ServiceTokenProvider serviceTokenProvider,
            ClientFallbackMetrics fallbackMetrics,
            @Value("${oncall-service.base-url:http://localhost:8086}")
            String oncallServiceBaseUrl) {
        this.restClient = restClient;
        this.objectMapper = objectMapper;
        this.serviceTokenProvider = serviceTokenProvider;
        this.fallbackMetrics = fallbackMetrics;
        this.oncallServiceBaseUrl = oncallServiceBaseUrl;
    }

    @CircuitBreaker(name = "oncall", fallbackMethod = "getCurrentOncallFallback")
    @Override
    public Optional<OncallInfo> getCurrentOncall(String tenantId, UUID teamId, String role) {
        log.debug("Fetching current oncall: tenantId={}, teamId={}, role={}",
                tenantId, teamId, role);

        // teamId is routinely null (an incident with no team assignment) —
        // queryParamIfPresent leaves the param off the URI entirely in that
        // case. A plain .queryParam("teamId", teamId) would instead render a
        // literal "teamId=null" on the wire, which oncall-service's
        // @RequestParam(required = false) UUID would fail to parse.
        final String uri = UriComponentsBuilder
                .fromHttpUrl(oncallServiceBaseUrl)
                .path("/api/v1/oncall/current")
                .queryParamIfPresent("teamId", Optional.ofNullable(teamId))
                .queryParam("role", role)
                .toUriString();

        final String responseBody = restClient.get()
                .uri(uri)
                .header("Authorization",
                        "Bearer " + serviceTokenProvider.getToken(tenantId, ServiceNames.ONCALL_SERVICE))
                .header("X-Tenant-Id", tenantId)
                .retrieve()
                .body(String.class);

        if (responseBody == null || responseBody.isBlank()) {
            return Optional.empty();
        }

        return Optional.of(parseOncallInfo(responseBody));
    }

    /**
     * Resilience4j fallback for {@link #getCurrentOncall} — called both
     * on a real failure (HTTP error, connection issue, parsing failure)
     * and when the circuit is already OPEN (in which case {@code e} is a
     * {@link io.github.resilience4j.circuitbreaker.CallNotPermittedException}).
     */
    @SuppressWarnings("unused")
    Optional<OncallInfo> getCurrentOncallFallback(String tenantId, UUID teamId, String role,
                                                  Exception e) {
        log.warn("oncall-service unavailable — getCurrentOncall fallback: " +
                        "tenantId={}, teamId={}, role={}, error={}",
                tenantId, teamId, role, e.getMessage());
        fallbackMetrics.record("oncall", "oncall-service", e);
        // Backlog #0-19: not fail-open any more — see OncallLookupUnavailableException.
        throw new OncallLookupUnavailableException(
                "oncall-service could not answer getCurrentOncall", e);
    }

    @CircuitBreaker(name = "oncall", fallbackMethod = "findBySlackUserIdFallback")
    @Override
    public Optional<OncallInfo> findBySlackUserId(String tenantId, String slackUserId) {
        log.debug("Looking up user by slackUserId: {}, tenant: {}", slackUserId, tenantId);

        final String uri = UriComponentsBuilder
                .fromHttpUrl(oncallServiceBaseUrl)
                .path("/api/v1/oncall/by-slack/{slackUserId}")
                .buildAndExpand(slackUserId)
                .toUriString();

        final String responseBody = restClient.get()
                .uri(uri)
                .header("Authorization",
                        "Bearer " + serviceTokenProvider.getToken(tenantId, ServiceNames.ONCALL_SERVICE))
                .header("X-Tenant-Id", tenantId)
                .retrieve()
                .body(String.class);

        if (responseBody == null || responseBody.isBlank()) {
            log.warn("No user found for slackUserId: {}", slackUserId);
            return Optional.empty();
        }

        final JsonNode json = parseJson(responseBody);
        final OncallInfo info = new OncallInfo(
                json.path("userId").asText(null),
                json.path("userName").asText(null),
                null,
                null,
                json.path("slackUserId").asText(null),
                null
        );

        log.debug("User found for slackUserId={}: userId={}",
                slackUserId, info.userId());
        return Optional.of(info);
    }

    /** Resilience4j fallback for {@link #findBySlackUserId} — see {@link #getCurrentOncallFallback}. */
    @SuppressWarnings("unused")
    Optional<OncallInfo> findBySlackUserIdFallback(String tenantId, String slackUserId,
                                                   Exception e) {
        log.warn("oncall-service unavailable — findBySlackUserId fallback: " +
                        "slackUserId={}, tenant={}, error={}",
                slackUserId, tenantId, e.getMessage());
        fallbackMetrics.record("oncall", "oncall-service", e);
        return Optional.empty();
    }

    @CircuitBreaker(name = "oncall", fallbackMethod = "findCurrentByUserIdFallback")
    @Override
    public Optional<OncallInfo> findCurrentByUserId(String tenantId, String userId) {
        log.debug("Fetching current oncall by user: userId={}, tenantId={}",
                userId, tenantId);

        // userId is a template variable, not concatenated into the string:
        // RestClient encodes it as one path segment, so an id containing '/',
        // '?', '#' or '..' cannot change the path or the query.
        final String responseBody = restClient.get()
                .uri(oncallServiceBaseUrl + "/api/v1/oncall/current/by-user/{userId}",
                        userId)
                .header("Authorization",
                        "Bearer " + serviceTokenProvider.getToken(tenantId, ServiceNames.ONCALL_SERVICE))
                .header("X-Tenant-Id", tenantId)
                .retrieve()
                .body(String.class);

        if (responseBody == null || responseBody.isBlank()) {
            // 204: the user is not on call right now
            return Optional.empty();
        }

        final OncallInfo info = parseOncallInfo(responseBody);

        // Defence in depth: oncall-service matches tenant and user id together,
        // so this cannot happen today. If a regression there ever returned
        // another user's entry, notifying that person would leak the incident
        // to someone who was never escalated to; treat it as "not found".
        if (!userId.equals(info.userId())) {
            log.warn("oncall-service returned a different user than requested — " +
                            "ignoring the response: tenantId={}, requested={}, returned={}",
                    tenantId, userId, info.userId());
            return Optional.empty();
        }

        return Optional.of(info);
    }

    /** Resilience4j fallback for {@link #findCurrentByUserId} — see {@link #getCurrentOncallFallback}. */
    @SuppressWarnings("unused")
    Optional<OncallInfo> findCurrentByUserIdFallback(String tenantId, String userId,
                                                     Exception e) {
        log.warn("oncall-service unavailable — findCurrentByUserId fallback: " +
                        "userId={}, tenantId={}, error={}",
                userId, tenantId, e.getMessage());
        fallbackMetrics.record("oncall", "oncall-service", e);
        // Backlog #0-19: not fail-open any more — see OncallLookupUnavailableException.
        throw new OncallLookupUnavailableException(
                "oncall-service could not answer findCurrentByUserId", e);
    }

    private OncallInfo parseOncallInfo(String responseBody) {
        final JsonNode json = parseJson(responseBody);
        return new OncallInfo(
                json.path("userId").asText(null),
                json.path("userName").asText(null),
                json.path("email").asText(null),
                json.path("phone").asText(null),
                json.path("slackUserId").asText(null),
                json.path("role").asText(null)
        );
    }

    private JsonNode parseJson(String responseBody) {
        try {
            return objectMapper.readTree(responseBody);
        } catch (Exception e) {
            // Wrapped as unchecked so it propagates to the @CircuitBreaker
            // proxy the same way an HTTP-level RestClientException does,
            // instead of forcing every caller to declare/catch a checked
            // Exception just to satisfy this one internal parsing step.
            throw new OncallResponseParsingException(
                    "Failed to parse oncall-service response: " + e.getMessage(), e);
        }
    }

    static class OncallResponseParsingException extends RuntimeException {
        OncallResponseParsingException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}