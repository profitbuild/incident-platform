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
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import java.util.Optional;
import java.util.UUID;

/**
 * HTTP client for auth-service's internal Slack-workspace endpoint (backlog
 * #0-21/#0-30) — the first client in this codebase that calls auth-service.
 * Same shape as {@link OncallClientImpl#getCurrentOncall}: service token minted
 * for the <em>target's</em> audience ({@link ServiceNames#AUTH_SERVICE}),
 * a {@code @CircuitBreaker} with no retry of its own (backlog #0-23: the
 * scheduler's PENDING window is the lookup's retry, as in
 * {@link OncallClientImpl}), and a fallback that records
 * {@link ClientFallbackMetrics} and throws instead of pretending to have an
 * answer.
 *
 * <p>Not injected directly by callers — {@link CachingSlackWorkspaceClient}
 * ({@code @Primary}) wraps this bean. This class does HTTP only.
 *
 * <h2>Fixed (backlog #0-21): the circuit breaker and retry never ran</h2>
 * The first version put the cache and the HTTP call in one class:
 * {@code getWorkspace()} checked the cache and then called an annotated
 * {@code fetchAndCache()} through {@code this}. Resilience4j's annotations
 * are applied by a Spring AOP proxy, and a call from inside the object never
 * goes through its own proxy, so neither annotation ever ran: no retry, the
 * breaker never counted a failure, the fallback never fired (so no metric),
 * and a 5xx from auth-service escaped as a raw {@code RestClientException}
 * out of {@code NotificationRouter.route()} — failing the whole queue entry,
 * email and SMS included. The annotations are now on the public interface
 * method, called from another bean ({@link CachingSlackWorkspaceClient}),
 * so the call does pass through the proxy.
 *
 * <h2>Fixed (backlog #0-21): an outage is no longer read as "no workspace"</h2>
 * The fallback used to return {@code Optional.empty()}, the same value as a
 * 404 — see {@link SlackWorkspaceLookupUnavailableException} for why the two
 * must stay distinguishable and how callers handle each.
 */
@Component
public class SlackWorkspaceClientImpl implements SlackWorkspaceClient {

    private static final Logger log =
            LoggerFactory.getLogger(SlackWorkspaceClientImpl.class);

    private final RestClient restClient;
    private final ObjectMapper objectMapper;
    private final ServiceTokenProvider serviceTokenProvider;
    private final ClientFallbackMetrics fallbackMetrics;
    private final String authServiceBaseUrl;

    public SlackWorkspaceClientImpl(
            @Qualifier("notificationServiceRestClient") RestClient restClient,
            ObjectMapper objectMapper,
            ServiceTokenProvider serviceTokenProvider,
            ClientFallbackMetrics fallbackMetrics,
            @Value("${auth-service.base-url:http://localhost:8087}")
            String authServiceBaseUrl) {
        this.restClient = restClient;
        this.objectMapper = objectMapper;
        this.serviceTokenProvider = serviceTokenProvider;
        this.fallbackMetrics = fallbackMetrics;
        this.authServiceBaseUrl = authServiceBaseUrl;
    }

    @CircuitBreaker(name = "slack-workspace", fallbackMethod = "getWorkspaceFallback")
    @Override
    public Optional<SlackWorkspaceInfo> getWorkspace(String tenantId) {
        log.debug("Fetching Slack workspace: tenantId={}", tenantId);

        try {
            final String responseBody = restClient.get()
                    .uri(authServiceBaseUrl + "/api/v1/internal/slack-workspace")
                    .header("Authorization",
                            "Bearer " + serviceTokenProvider.getToken(tenantId, ServiceNames.AUTH_SERVICE))
                    .header("X-Tenant-Id", tenantId)
                    .retrieve()
                    .body(String.class);

            if (responseBody == null || responseBody.isBlank()) {
                return Optional.empty();
            }
            return Optional.of(parseWorkspace(responseBody));

        } catch (HttpClientErrorException.NotFound e) {
            // A 404 is auth-service's normal answer for "this tenant has no active
            // Slack workspace", not a failure. Caught here, inside the proxied
            // method, so the circuit breaker sees a successful call — otherwise a
            // burst of notifications for Slack-less tenants would open the breaker
            // and cut Slack off for every tenant that does have a workspace.
            log.debug("No active Slack workspace for tenant={}", tenantId);
            return Optional.empty();
        }
    }

    /**
     * Resilience4j fallback for {@link #getWorkspace} — a real failure
     * (unreachable, 5xx, a rejected service token, an unparseable body) or an
     * open circuit ({@code CallNotPermittedException}). Records the fallback
     * metric, then throws: the caller has to know this was "unknown", not
     * "not configured" (see {@link SlackWorkspaceLookupUnavailableException}).
     */
    @SuppressWarnings("unused")
    Optional<SlackWorkspaceInfo> getWorkspaceFallback(String tenantId, Exception e) {
        log.warn("auth-service unavailable — Slack workspace lookup failed: " +
                        "tenantId={}, error={}",
                tenantId, e.getMessage());
        fallbackMetrics.record("slack-workspace", "auth-service", e);
        throw new SlackWorkspaceLookupUnavailableException(
                "auth-service could not answer the Slack workspace lookup", e);
    }

    private SlackWorkspaceInfo parseWorkspace(String responseBody) {
        final JsonNode json = parseJson(responseBody);
        final String teamId = json.path("teamId").asText(null);
        return new SlackWorkspaceInfo(
                json.path("botToken").asText(null),
                json.path("defaultChannel").asText(null),
                json.path("broadcastEnabled").asBoolean(false),
                teamId == null ? null : UUID.fromString(teamId));
    }

    private JsonNode parseJson(String responseBody) {
        try {
            return objectMapper.readTree(responseBody);
        } catch (Exception e) {
            // Wrapped as unchecked so a malformed response propagates to the
            // @CircuitBreaker proxy as a real failure, same as
            // OncallClientImpl.parseJson's identical wrapping.
            throw new SlackWorkspaceResponseParsingException(
                    "Failed to parse auth-service Slack workspace response: " + e.getMessage(), e);
        }
    }

    static class SlackWorkspaceResponseParsingException extends RuntimeException {
        SlackWorkspaceResponseParsingException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
