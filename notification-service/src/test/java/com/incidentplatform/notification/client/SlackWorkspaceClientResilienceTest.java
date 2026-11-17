package com.incidentplatform.notification.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.core.WireMockConfiguration;
import com.incidentplatform.shared.observability.ClientFallbackMetrics;
import com.incidentplatform.shared.security.ServiceNames;
import com.incidentplatform.shared.security.ServiceTokenProvider;
import com.incidentplatform.notification.support.ApplicationYml;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.springboot3.circuitbreaker.autoconfigure.CircuitBreakerAutoConfiguration;
import io.github.resilience4j.springboot3.retry.autoconfigure.RetryAutoConfiguration;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.autoconfigure.aop.AopAutoConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Import;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

/**
 * Proves the Resilience4j annotations on {@link SlackWorkspaceClientImpl}
 * actually run when the client is reached the way production reaches it —
 * through {@link CachingSlackWorkspaceClient} injected as
 * {@link SlackWorkspaceClient}.
 *
 * <h2>Why this test exists (backlog #0-21)</h2>
 * The first implementation called its own {@code @CircuitBreaker} method through
 * {@code this}, bypassing the AOP proxy, so the fallback never ran and a 5xx
 * escaped raw. Every Mockito/WireMock unit test built the client with
 * {@code new}, where there is no proxy either way — none of them could see the
 * difference. This one builds a minimal Spring context with only the AOP and
 * Resilience4j auto-configurations, so a regression to self-invocation (or a
 * {@code @Qualifier} that no longer points at the proxied bean) fails here.
 *
 * <h2>Reads the shipped application.yml (backlog #0-23)</h2>
 * It used to pin {@code max-attempts=1} and the breaker window itself, which
 * hid that the client's {@code @Retry} never fired. It now loads the service's
 * own {@code application.yml} ({@link ApplicationYml.Initializer}), so there is
 * no copy of the configuration to drift (third review of #0-104), and a 503
 * is asserted to make exactly one request. The breaker is reset before each
 * test because the shipped window (3 calls) would otherwise let the 503s of
 * earlier tests open it.
 */
@SpringJUnitConfig(classes = SlackWorkspaceClientResilienceTest.TestConfig.class,
        initializers = ApplicationYml.Initializer.class)
@DisplayName("SlackWorkspaceClient — Resilience4j proxy is really in the call path")
class SlackWorkspaceClientResilienceTest {

    private static final String TENANT_ID = "test-tenant";
    private static final String PATH = "/api/v1/internal/slack-workspace";

    // Started before the Spring context, which needs its port for the base URL.
    private static final WireMockServer WIRE_MOCK =
            new WireMockServer(WireMockConfiguration.options().dynamicPort());

    static {
        WIRE_MOCK.start();
    }

    @Autowired
    private SlackWorkspaceClient client;

    @Autowired
    private MeterRegistry meterRegistry;

    @Autowired
    private CircuitBreakerRegistry circuitBreakerRegistry;

    @BeforeEach
    void resetWireMock() {
        WIRE_MOCK.resetAll();
        circuitBreakerRegistry.circuitBreaker("slack-workspace").reset();
    }

    @AfterAll
    static void stopWireMock() {
        WIRE_MOCK.stop();
    }

    @Test
    @DisplayName("the injected SlackWorkspaceClient is the caching decorator")
    void primaryIsTheCachingDecorator() {
        assertThat(client).isInstanceOf(CachingSlackWorkspaceClient.class);
    }

    @Test
    @DisplayName("a 503 reaches the fallback: SlackWorkspaceLookupUnavailableException + fallback metric, not a raw 5xx")
    void serverErrorGoesThroughFallback() {
        WIRE_MOCK.stubFor(get(urlPathEqualTo(PATH)).willReturn(aResponse().withStatus(503)));
        // The Spring context (and its MeterRegistry) is shared by every test in
        // this class, so assert the increment, not the absolute count.
        final double before = serverErrorFallbacks();

        assertThatThrownBy(() -> client.getWorkspace(TENANT_ID))
                .isInstanceOf(SlackWorkspaceLookupUnavailableException.class);

        assertThat(serverErrorFallbacks() - before).isEqualTo(1.0);
        WIRE_MOCK.verify(1, getRequestedFor(urlPathEqualTo(PATH)));
    }

    @Test
    @DisplayName("the failure is not cached: the next call reaches auth-service again")
    void failureIsNotCached() {
        WIRE_MOCK.stubFor(get(urlPathEqualTo(PATH)).willReturn(aResponse().withStatus(503)));

        assertThatThrownBy(() -> client.getWorkspace("uncached-tenant"))
                .isInstanceOf(SlackWorkspaceLookupUnavailableException.class);
        assertThatThrownBy(() -> client.getWorkspace("uncached-tenant"))
                .isInstanceOf(SlackWorkspaceLookupUnavailableException.class);

        WIRE_MOCK.verify(2, getRequestedFor(urlPathEqualTo(PATH)));
    }

    @Test
    @DisplayName("a 404 does not go through the fallback — it is 'no workspace', not a failure")
    void notFoundIsNotAFailure() {
        WIRE_MOCK.stubFor(get(urlPathEqualTo(PATH)).willReturn(aResponse().withStatus(404)));

        assertThat(client.getWorkspace("slackless-tenant")).isEmpty();
        assertThat(meterRegistry.find(ClientFallbackMetrics.METRIC_NAME)
                .tag("client", "slack-workspace").tag("reason", "client_error").counter())
                .isNull();
    }

    private double serverErrorFallbacks() {
        return meterRegistry.counter(ClientFallbackMetrics.METRIC_NAME,
                "client", "slack-workspace", "target", "auth-service",
                "reason", "server_error").count();
    }

    @Configuration
    @ImportAutoConfiguration({
            AopAutoConfiguration.class,
            CircuitBreakerAutoConfiguration.class,
            RetryAutoConfiguration.class
    })
    @Import(CachingSlackWorkspaceClient.class)
    static class TestConfig {

        @Bean
        MeterRegistry meterRegistry() {
            return new SimpleMeterRegistry();
        }

        // Bean name must match the @Qualifier in CachingSlackWorkspaceClient —
        // that wiring is part of what this test checks.
        @Bean
        SlackWorkspaceClientImpl slackWorkspaceClientImpl(MeterRegistry meterRegistry) {
            final ServiceTokenProvider tokenProvider = mock(ServiceTokenProvider.class);
            given(tokenProvider.getToken(org.mockito.ArgumentMatchers.anyString(),
                    org.mockito.ArgumentMatchers.eq(ServiceNames.AUTH_SERVICE)))
                    .willReturn("test-token");

            final HttpClient httpClient = HttpClient.newBuilder()
                    .version(HttpClient.Version.HTTP_1_1)
                    .connectTimeout(Duration.ofSeconds(3))
                    .build();

            return new SlackWorkspaceClientImpl(
                    RestClient.builder()
                            .requestFactory(new JdkClientHttpRequestFactory(httpClient))
                            .build(),
                    new ObjectMapper(),
                    tokenProvider,
                    new ClientFallbackMetrics(meterRegistry),
                    "http://localhost:" + WIRE_MOCK.port());
        }
    }
}
