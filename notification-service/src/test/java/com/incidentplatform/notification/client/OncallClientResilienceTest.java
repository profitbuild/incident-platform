package com.incidentplatform.notification.client;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.tomakehurst.wiremock.WireMockServer;
import com.github.tomakehurst.wiremock.core.WireMockConfiguration;
import com.incidentplatform.notification.support.ApplicationYml;
import com.incidentplatform.shared.observability.ClientFallbackMetrics;
import com.incidentplatform.shared.security.ServiceNames;
import com.incidentplatform.shared.security.ServiceTokenProvider;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.retry.RetryRegistry;
import io.github.resilience4j.springboot3.circuitbreaker.autoconfigure.CircuitBreakerAutoConfiguration;
import io.github.resilience4j.springboot3.retry.autoconfigure.RetryAutoConfiguration;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.aop.support.AopUtils;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.ImportAutoConfiguration;
import org.springframework.boot.autoconfigure.aop.AopAutoConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.UUID;

import static com.github.tomakehurst.wiremock.client.WireMock.aResponse;
import static com.github.tomakehurst.wiremock.client.WireMock.get;
import static com.github.tomakehurst.wiremock.client.WireMock.getRequestedFor;
import static com.github.tomakehurst.wiremock.client.WireMock.urlPathEqualTo;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

/**
 * Runs {@link OncallClientImpl} through its real Spring proxies with the
 * service's own {@code application.yml} (backlog #0-23).
 *
 * <p>The three lookups used to carry a {@code @Retry} that never fired, behind
 * a circuit-breaker fallback that answers every failure. They no longer have
 * one: a 503 makes exactly one request, and the lookup's retry is the
 * scheduler's PENDING window. {@code WIRE_MOCK.verify(1, ...)} goes red if a
 * retry comes back. Same minimal context as
 * {@link SlackWorkspaceClientResilienceTest}.
 */
@SpringJUnitConfig(classes = OncallClientResilienceTest.TestConfig.class,
        initializers = ApplicationYml.Initializer.class)
@DisplayName("OncallClient — one request per 503 through the Resilience4j proxy")
class OncallClientResilienceTest {

    private static final String TENANT_ID = "test-tenant";
    private static final String CURRENT_PATH = "/api/v1/oncall/current";

    // Started before the Spring context, which needs its port for the base URL.
    private static final WireMockServer WIRE_MOCK =
            new WireMockServer(WireMockConfiguration.options().dynamicPort());

    static {
        WIRE_MOCK.start();
    }

    @Autowired
    private OncallClient client;

    @Autowired
    private MeterRegistry meterRegistry;

    @Autowired
    private CircuitBreakerRegistry circuitBreakerRegistry;

    @Autowired
    private RetryRegistry retryRegistry;

    @BeforeEach
    void reset() {
        WIRE_MOCK.resetAll();
        // application.yml's breaker opens after 3 calls at 50%, and all three
        // lookups share it; the context is shared by every test in this class.
        circuitBreakerRegistry.circuitBreaker("oncall").reset();
    }

    @AfterAll
    static void stopWireMock() {
        WIRE_MOCK.stop();
    }

    @Test
    @DisplayName("the injected OncallClient is a Spring AOP proxy")
    void clientIsProxied() {
        assertThat(AopUtils.isAopProxy(client)).isTrue();
    }

    @Test
    @DisplayName("getCurrentOncall: a 503 throws OncallLookupUnavailableException after one request")
    void getCurrentOncallServerErrorMakesOneRequest() {
        WIRE_MOCK.stubFor(get(urlPathEqualTo(CURRENT_PATH)).willReturn(aResponse().withStatus(503)));
        final double before = serverErrorFallbacks();

        assertThatThrownBy(() -> client.getCurrentOncall(TENANT_ID, UUID.randomUUID(), "PRIMARY"))
                .isInstanceOf(OncallLookupUnavailableException.class);

        WIRE_MOCK.verify(1, getRequestedFor(urlPathEqualTo(CURRENT_PATH)));
        assertThat(serverErrorFallbacks() - before).isEqualTo(1.0);
    }

    @Test
    @DisplayName("findBySlackUserId: a 503 returns empty after one request")
    void findBySlackUserIdServerErrorMakesOneRequest() {
        final String path = "/api/v1/oncall/by-slack/U123";
        WIRE_MOCK.stubFor(get(urlPathEqualTo(path)).willReturn(aResponse().withStatus(503)));
        final double before = serverErrorFallbacks();

        assertThat(client.findBySlackUserId(TENANT_ID, "U123")).isEmpty();

        WIRE_MOCK.verify(1, getRequestedFor(urlPathEqualTo(path)));
        assertThat(serverErrorFallbacks() - before).isEqualTo(1.0);
    }

    @Test
    @DisplayName("findCurrentByUserId: a 503 throws OncallLookupUnavailableException after one request")
    void findCurrentByUserIdServerErrorMakesOneRequest() {
        final String path = "/api/v1/oncall/current/by-user/user-1";
        WIRE_MOCK.stubFor(get(urlPathEqualTo(path)).willReturn(aResponse().withStatus(503)));
        final double before = serverErrorFallbacks();

        assertThatThrownBy(() -> client.findCurrentByUserId(TENANT_ID, "user-1"))
                .isInstanceOf(OncallLookupUnavailableException.class);

        WIRE_MOCK.verify(1, getRequestedFor(urlPathEqualTo(path)));
        assertThat(serverErrorFallbacks() - before).isEqualTo(1.0);
    }

    @Test
    @DisplayName("application.yml configures no retry instance for oncall or slack-workspace")
    void noRetryInstanceConfigured() {
        assertThat(retryRegistry.find("oncall")).isEmpty();
        assertThat(retryRegistry.find("slack-workspace")).isEmpty();
    }

    private double serverErrorFallbacks() {
        return meterRegistry.counter(ClientFallbackMetrics.METRIC_NAME,
                "client", "oncall", "target", "oncall-service",
                "reason", "server_error").count();
    }

    @Configuration
    @ImportAutoConfiguration({
            AopAutoConfiguration.class,
            CircuitBreakerAutoConfiguration.class,
            RetryAutoConfiguration.class
    })
    static class TestConfig {

        @Bean
        MeterRegistry meterRegistry() {
            return new SimpleMeterRegistry();
        }

        @Bean
        OncallClientImpl oncallClientImpl(MeterRegistry meterRegistry) {
            final ServiceTokenProvider tokenProvider = mock(ServiceTokenProvider.class);
            given(tokenProvider.getToken(org.mockito.ArgumentMatchers.anyString(),
                    org.mockito.ArgumentMatchers.eq(ServiceNames.ONCALL_SERVICE)))
                    .willReturn("test-token");

            final HttpClient httpClient = HttpClient.newBuilder()
                    .version(HttpClient.Version.HTTP_1_1)
                    .connectTimeout(Duration.ofSeconds(3))
                    .build();

            return new OncallClientImpl(
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
