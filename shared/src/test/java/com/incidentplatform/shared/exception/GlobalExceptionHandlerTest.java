package com.incidentplatform.shared.exception;

import com.incidentplatform.shared.dto.ErrorResponse;
import jakarta.validation.ConstraintViolation;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.ValidatorFactory;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.core.MethodParameter;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.validation.BeanPropertyBindingResult;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.tuple;

/**
 * {@link GlobalExceptionHandler} writes the body of every 4xx/5xx a controller
 * of any of the 7 services answers with. Until backlog #0-58 it had no test of
 * its own: only services' controller tests reached it, and JaCoCo counts a
 * module's own tests only (ADR-0018), so {@code shared} reported it uncovered
 * and a change to a status, an error code or the redaction went unseen here.
 *
 * <p>Each handler is called directly with a real Spring/Jakarta exception; no
 * Spring context. The {@code requestId} comes from the thread-bound MDC, so
 * every test clears it afterwards. The timestamp is never compared.
 */
@DisplayName("GlobalExceptionHandler")
class GlobalExceptionHandlerTest {

    private static final String REQUEST_ID = "req-123";

    private static ValidatorFactory validatorFactory;

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @BeforeAll
    static void startValidator() {
        validatorFactory = Validation.buildDefaultValidatorFactory();
    }

    @AfterAll
    static void closeValidator() {
        validatorFactory.close();
    }

    @AfterEach
    void clearMdc() {
        MDC.clear();
    }

    /** A real method, so that {@link MethodParameter} points at a real parameter. */
    @SuppressWarnings("unused")
    private void endpoint(UUID incidentId) {
        // never called: only its signature is used
    }

    private static MethodParameter endpointParameter() throws NoSuchMethodException {
        return new MethodParameter(
                GlobalExceptionHandlerTest.class.getDeclaredMethod("endpoint", UUID.class), 0);
    }

    /**
     * Two constraints, both violated by {@link #invalid()}. The messages are explicit, so the
     * test does not depend on the JVM's locale picking Hibernate Validator's English defaults.
     */
    private record CreateRequest(
            @NotBlank(message = "name is required") String name,
            @Min(value = 1, message = "count must be at least 1") int count) {
        static CreateRequest invalid() {
            return new CreateRequest("   ", 0);
        }
    }

    private static void assertBody(ResponseEntity<ErrorResponse> response, HttpStatus status,
                                   String errorCode) {
        assertThat(response.getStatusCode()).isEqualTo(status);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().status()).isEqualTo(status.value());
        assertThat(response.getBody().errorCode()).isEqualTo(errorCode);
    }

    @Test
    @DisplayName("ResourceNotFoundException: 404 RESOURCE_NOT_FOUND with the exception's message")
    void resourceNotFound() {
        final ResourceNotFoundException ex = new ResourceNotFoundException(
                "Incident", UUID.fromString("00000000-0000-0000-0000-000000000042"));

        final ResponseEntity<ErrorResponse> response = handler.handleResourceNotFound(ex);

        assertBody(response, HttpStatus.NOT_FOUND, ErrorCodes.RESOURCE_NOT_FOUND);
        assertThat(response.getBody().message())
                .isEqualTo("Incident with id '00000000-0000-0000-0000-000000000042' was not found")
                .isEqualTo(ex.getMessage());
        assertThat(response.getBody().validationErrors()).isNull();
    }

    @Test
    @DisplayName("BusinessException: the exception's own status and error code, not a fixed 400")
    void businessException() {
        final BusinessException ex = new BusinessException(
                ErrorCodes.SCHEDULE_OVERLAP, "The schedule overlaps another one", HttpStatus.CONFLICT);

        final ResponseEntity<ErrorResponse> response = handler.handleBusinessException(ex);

        assertBody(response, HttpStatus.CONFLICT, ErrorCodes.SCHEDULE_OVERLAP);
        assertThat(response.getBody().message()).isEqualTo("The schedule overlaps another one");
    }

    @Test
    @DisplayName("MethodArgumentNotValidException: 400, one entry per field error, sensitive values redacted")
    void validationErrors() throws NoSuchMethodException {
        final BeanPropertyBindingResult bindingResult =
                new BeanPropertyBindingResult(new Object(), "request");
        bindingResult.addError(fieldError("password", "fake-password-value", "too short"));
        bindingResult.addError(fieldError("userPassword", "fake-user-password-value", "too weak"));
        bindingResult.addError(fieldError("clientSecret", "fake-secret-value", "invalid secret"));
        bindingResult.addError(fieldError("refreshToken", "fake-token-value", "malformed token"));
        bindingResult.addError(fieldError("api_key", "fake-key-value", "unknown key"));
        bindingResult.addError(fieldError("email", "not-an-email", "must be a well-formed email address"));
        bindingResult.addError(fieldError("title", null, "must not be null"));

        final ResponseEntity<ErrorResponse> response = handler.handleValidationErrors(
                new MethodArgumentNotValidException(endpointParameter(), bindingResult));

        assertBody(response, HttpStatus.BAD_REQUEST, ErrorCodes.VALIDATION_FAILED);
        assertThat(response.getBody().validationErrors())
                .extracting(ErrorResponse.ValidationError::field,
                        ErrorResponse.ValidationError::rejectedValue,
                        ErrorResponse.ValidationError::message)
                .containsExactly(
                        tuple("password", "[REDACTED]", "too short"),
                        tuple("userPassword", "[REDACTED]", "too weak"),
                        tuple("clientSecret", "[REDACTED]", "invalid secret"),
                        tuple("refreshToken", "[REDACTED]", "malformed token"),
                        tuple("api_key", "[REDACTED]", "unknown key"),
                        tuple("email", "not-an-email", "must be a well-formed email address"),
                        tuple("title", null, "must not be null"));
    }

    private static FieldError fieldError(String field, Object rejectedValue, String message) {
        return new FieldError("request", field, rejectedValue, false, null, null, message);
    }

    @Test
    @DisplayName("ConstraintViolationException: 400 with each violation's path and message, no rejected value")
    void constraintViolation() {
        final Validator validator = validatorFactory.getValidator();
        final Set<ConstraintViolation<CreateRequest>> violations = validator.validate(CreateRequest.invalid());
        assertThat(violations).as("the fixture violates both constraints").hasSize(2);

        final ResponseEntity<ErrorResponse> response =
                handler.handleConstraintViolation(new ConstraintViolationException(violations));

        assertBody(response, HttpStatus.BAD_REQUEST, ErrorCodes.VALIDATION_FAILED);
        assertThat(response.getBody().validationErrors())
                .extracting(ErrorResponse.ValidationError::field,
                        ErrorResponse.ValidationError::rejectedValue,
                        ErrorResponse.ValidationError::message)
                .containsExactlyInAnyOrder(
                        tuple("name", null, "name is required"),
                        tuple("count", null, "count must be at least 1"));
    }

    @Test
    @DisplayName("MethodArgumentTypeMismatchException: 400 INVALID_PARAMETER_TYPE naming the parameter only")
    void typeMismatch() throws NoSuchMethodException {
        final MethodArgumentTypeMismatchException ex = new MethodArgumentTypeMismatchException(
                "not-a-uuid-VALUE", UUID.class, "incidentId", endpointParameter(),
                new IllegalArgumentException("Invalid UUID string: not-a-uuid-VALUE"));

        final ResponseEntity<ErrorResponse> response = handler.handleTypeMismatch(ex);

        assertBody(response, HttpStatus.BAD_REQUEST, ErrorCodes.INVALID_PARAMETER_TYPE);
        assertThat(response.getBody().message())
                .isEqualTo("Parameter 'incidentId' has invalid type")
                .doesNotContain("not-a-uuid-VALUE");
    }

    @Test
    @DisplayName("AuthenticationException: 401 UNAUTHORIZED with a fixed message, no exception text")
    void authentication() {
        final String internal = "user lookup failed for x-distinct-auth-detail";

        final ResponseEntity<ErrorResponse> response =
                handler.handleAuthenticationException(new BadCredentialsException(internal));

        assertBody(response, HttpStatus.UNAUTHORIZED, ErrorCodes.UNAUTHORIZED);
        assertThat(response.getBody().message())
                .isEqualTo("Authentication required. Please provide a valid token.");
        assertThat(response.getBody().toString()).doesNotContain("x-distinct-auth-detail");
    }

    @Test
    @DisplayName("AccessDeniedException: 403 FORBIDDEN with a fixed message, no exception text")
    void accessDenied() {
        final String internal = "role check failed for x-distinct-denied-detail";

        final ResponseEntity<ErrorResponse> response =
                handler.handleAccessDenied(new AccessDeniedException(internal));

        assertBody(response, HttpStatus.FORBIDDEN, ErrorCodes.FORBIDDEN);
        assertThat(response.getBody().message())
                .isEqualTo("You do not have permission to perform this action.");
        assertThat(response.getBody().toString()).doesNotContain("x-distinct-denied-detail");
    }

    @Test
    @DisplayName("OptimisticLockingFailureException: 409 OPTIMISTIC_LOCK_CONFLICT with a fixed message")
    void optimisticLocking() {
        final String internal = "Row was updated or deleted by another transaction: x-distinct-lock-detail";

        final ResponseEntity<ErrorResponse> response =
                handler.handleOptimisticLocking(new OptimisticLockingFailureException(internal));

        assertBody(response, HttpStatus.CONFLICT, ErrorCodes.OPTIMISTIC_LOCK_CONFLICT);
        assertThat(response.getBody().message()).isEqualTo(
                "The resource was modified by another request. Please fetch the latest version and retry.");
        assertThat(response.getBody().toString()).doesNotContain("x-distinct-lock-detail");
    }

    @Test
    @DisplayName("any other exception: 500 INTERNAL_SERVER_ERROR without its internal message")
    void unexpected() throws NoResourceFoundException {
        final String internal = "ERROR: relation \"incidents_x_distinct\" does not exist";

        final ResponseEntity<ErrorResponse> response =
                handler.handleUnexpectedException(new IllegalStateException(internal));

        assertBody(response, HttpStatus.INTERNAL_SERVER_ERROR, ErrorCodes.INTERNAL_SERVER_ERROR);
        assertThat(response.getBody().message())
                .isEqualTo("An unexpected error occurred. Please contact support with request id: unknown");
        assertThat(response.getBody().toString()).doesNotContain("incidents_x_distinct");
    }

    @Test
    @DisplayName("NoResourceFoundException is rethrown as the same instance, not answered with 500")
    void noResourceFoundRethrown() {
        final NoResourceFoundException ex =
                new NoResourceFoundException(HttpMethod.GET, "/no/such/path");

        assertThatThrownBy(() -> handler.handleUnexpectedException(ex)).isSameAs(ex);
    }

    @Test
    @DisplayName("every handler takes the requestId from the MDC")
    void requestIdFromMdc() throws Exception {
        MDC.put("requestId", REQUEST_ID);

        final List<ErrorResponse> bodies = everyHandlerBody();

        assertThat(bodies).hasSize(9).extracting(ErrorResponse::requestId).containsOnly(REQUEST_ID);
        assertThat(handler.handleUnexpectedException(new IllegalStateException("boom")).getBody().message())
                .isEqualTo("An unexpected error occurred. Please contact support with request id: " + REQUEST_ID);
    }

    @Test
    @DisplayName("every handler answers requestId \"unknown\" when the MDC has none")
    void requestIdUnknown() throws Exception {
        final List<ErrorResponse> bodies = everyHandlerBody();

        assertThat(bodies).hasSize(9).extracting(ErrorResponse::requestId).containsOnly("unknown");
    }

    private List<ErrorResponse> everyHandlerBody() throws Exception {
        final BeanPropertyBindingResult bindingResult =
                new BeanPropertyBindingResult(new Object(), "request");
        bindingResult.addError(fieldError("email", "not-an-email", "must be a well-formed email address"));
        final Set<ConstraintViolation<CreateRequest>> violations =
                validatorFactory.getValidator().validate(CreateRequest.invalid());

        return List.of(
                handler.handleResourceNotFound(new ResourceNotFoundException("Incident", "INC-1")).getBody(),
                handler.handleBusinessException(new BusinessException(
                        ErrorCodes.BUSINESS_RULE_VIOLATION, "rule broken", HttpStatus.UNPROCESSABLE_ENTITY))
                        .getBody(),
                handler.handleValidationErrors(
                        new MethodArgumentNotValidException(endpointParameter(), bindingResult)).getBody(),
                handler.handleConstraintViolation(new ConstraintViolationException(violations)).getBody(),
                handler.handleTypeMismatch(new MethodArgumentTypeMismatchException(
                        "x", UUID.class, "incidentId", endpointParameter(), null)).getBody(),
                handler.handleAuthenticationException(new BadCredentialsException("bad")).getBody(),
                handler.handleAccessDenied(new AccessDeniedException("denied")).getBody(),
                handler.handleOptimisticLocking(new OptimisticLockingFailureException("stale")).getBody(),
                handler.handleUnexpectedException(new IllegalStateException("boom")).getBody());
    }
}
