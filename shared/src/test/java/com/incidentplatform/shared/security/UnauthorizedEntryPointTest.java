package com.incidentplatform.shared.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.incidentplatform.shared.dto.ErrorResponse;
import com.incidentplatform.shared.exception.ErrorCodes;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.BadCredentialsException;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link UnauthorizedEntryPoint} writes the 401 of every unauthenticated
 * request in all 7 services, before any controller or
 * {@code GlobalExceptionHandler} is reached. Until backlog #0-58 it had no
 * test of its own: JaCoCo counts a module's own tests only (ADR-0018), so
 * {@code shared} reported it uncovered and its {@code requestId} resolution
 * (header, then MDC, then {@code "unknown"}) was pinned nowhere.
 *
 * <p>The body is read back with a real {@link ObjectMapper}, as
 * {@code ApiKeyAuthFilterTest} does. The MDC is thread-bound, so every test
 * clears it afterwards.
 */
@DisplayName("UnauthorizedEntryPoint")
class UnauthorizedEntryPointTest {

    private final ObjectMapper objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());
    private final UnauthorizedEntryPoint entryPoint = new UnauthorizedEntryPoint(objectMapper);
    private final MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/incidents");
    private final MockHttpServletResponse response = new MockHttpServletResponse();

    @AfterEach
    void clearMdc() {
        MDC.clear();
    }

    private ErrorResponse commence() throws Exception {
        entryPoint.commence(request, response, new BadCredentialsException("Full authentication is required"));
        return objectMapper.readValue(response.getContentAsString(), ErrorResponse.class);
    }

    @Test
    @DisplayName("writes a JSON 401 UNAUTHORIZED ErrorResponse in UTF-8")
    void writesJson401() throws Exception {
        final ErrorResponse body = commence();

        assertThat(response.getStatus()).isEqualTo(401);
        assertThat(response.getCharacterEncoding()).isEqualTo("UTF-8");
        final MediaType contentType = MediaType.parseMediaType(response.getContentType());
        assertThat(contentType.getType()).isEqualTo("application");
        assertThat(contentType.getSubtype()).isEqualTo("json");
        assertThat(body.status()).isEqualTo(401);
        assertThat(body.errorCode()).isEqualTo(ErrorCodes.UNAUTHORIZED);
        assertThat(body.message()).isEqualTo("Authentication required. Please provide a valid JWT token.");
        assertThat(body.validationErrors()).isNull();
    }

    @Test
    @DisplayName("requestId comes from the X-Request-Id response header first")
    void requestIdFromHeader() throws Exception {
        response.setHeader("X-Request-Id", "hdr-1");
        MDC.put("requestId", "mdc-1");

        assertThat(commence().requestId()).isEqualTo("hdr-1");
    }

    @Test
    @DisplayName("requestId comes from the MDC when the response has no X-Request-Id")
    void requestIdFromMdc() throws Exception {
        MDC.put("requestId", "mdc-1");

        assertThat(commence().requestId()).isEqualTo("mdc-1");
    }

    @Test
    @DisplayName("requestId is \"unknown\" when neither the header nor the MDC has one")
    void requestIdUnknown() throws Exception {
        assertThat(commence().requestId()).isEqualTo("unknown");
    }

    @Test
    @DisplayName("a blank X-Request-Id falls back to the MDC")
    void blankHeaderFallsBackToMdc() throws Exception {
        response.setHeader("X-Request-Id", "   ");
        MDC.put("requestId", "mdc-1");

        assertThat(commence().requestId()).isEqualTo("mdc-1");
    }

    @Test
    @DisplayName("the body holds no text of the AuthenticationException")
    void bodyHoldsNoExceptionText() throws Exception {
        entryPoint.commence(request, response,
                new BadCredentialsException("JWT signature does not match x-distinct-entry-detail"));

        assertThat(response.getStatus()).isEqualTo(401);
        assertThat(response.getContentAsString())
                .contains("\"errorCode\":\"UNAUTHORIZED\"")
                .doesNotContain("x-distinct-entry-detail")
                .doesNotContain("JWT signature does not match");
    }
}
