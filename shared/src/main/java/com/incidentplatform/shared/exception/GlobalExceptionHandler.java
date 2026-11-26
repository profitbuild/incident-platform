package com.incidentplatform.shared.exception;

import com.incidentplatform.shared.dto.ErrorResponse;
import jakarta.validation.ConstraintViolationException;
import org.springframework.dao.OptimisticLockingFailureException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.List;
import java.util.Locale;
import java.util.Set;

@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    /**
     * Substrings of a field name whose rejected value a 400 {@code VALIDATION_FAILED} body replaces with
     * {@code [REDACTED]}: {@link #isSensitiveField} lower-cases the field name and looks for each entry in it.
     *
     * <h2>Fixed (backlog #0-245): every entry is lower-case</h2>
     * The set held {@code apiKey} and {@code privateKey}, mixed-case, so a lower-cased field name never
     * contained them and a field named {@code apiKey}, {@code privateKey} or {@code userApiKey} was echoed back
     * with its value. There is one comparison rule, the lower-cased name against lower-case entries, and
     * {@code GlobalExceptionHandlerTest} fails on an entry that is not lower-case.
     *
     * <p>The same item went through the services' request DTOs for secrets no entry matched: {@code totpCode}
     * and {@code backupCode} (auth-service's MFA requests, a one-time second factor) and {@code keyHash}
     * (auth-service's API key introspection, the SHA-256 the key is looked up by), hence {@code totp},
     * {@code backupcode} and {@code keyhash}. A bare {@code code} is not an entry: it would redact fields
     * such as an error or country code that hold no secret. The fields matched by an older entry, every
     * {@code *Password} and {@code *Token} ({@code mfaToken}, {@code refreshToken}, {@code botToken}), stay so.
     *
     * <p>Package-private for {@code GlobalExceptionHandlerTest}, which checks every entry.
     */
    static final Set<String> SENSITIVE_FIELD_NAMES = Set.of(
            "password", "secret", "token", "apikey", "api_key",
            "authorization", "credential", "privatekey",
            "totp", "backupcode", "keyhash"
    );

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleResourceNotFound(
            ResourceNotFoundException ex) {

        log.info("Resource not found: {} with id: {}",
                ex.getResourceType(), ex.getResourceId());

        return ResponseEntity
                .status(HttpStatus.NOT_FOUND)
                .body(ErrorResponse.of(
                        HttpStatus.NOT_FOUND.value(),
                        ErrorCodes.RESOURCE_NOT_FOUND,
                        ex.getMessage(),
                        getRequestId()
                ));
    }

    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<ErrorResponse> handleBusinessException(
            BusinessException ex) {

        log.warn("Business rule violation: errorCode={}, message={}",
                ex.getErrorCode(), ex.getMessage());

        return ResponseEntity
                .status(ex.getHttpStatus())
                .body(ErrorResponse.of(
                        ex.getHttpStatus().value(),
                        ex.getErrorCode(),
                        ex.getMessage(),
                        getRequestId()
                ));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidationErrors(
            MethodArgumentNotValidException ex) {

        final List<ErrorResponse.ValidationError> errors = ex.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(this::toValidationError)
                .toList();

        log.info("Validation failed for {} fields: {}",
                errors.size(),
                errors.stream().map(ErrorResponse.ValidationError::field).toList());

        return ResponseEntity
                .status(HttpStatus.BAD_REQUEST)
                .body(ErrorResponse.validationFailed(getRequestId(), errors));
    }

    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ErrorResponse> handleConstraintViolation(
            ConstraintViolationException ex) {

        final List<ErrorResponse.ValidationError> errors = ex.getConstraintViolations()
                .stream()
                .map(violation -> new ErrorResponse.ValidationError(
                        violation.getPropertyPath().toString(),
                        null,
                        violation.getMessage()
                ))
                .toList();

        log.info("Constraint violations: {}", errors.size());

        return ResponseEntity
                .status(HttpStatus.BAD_REQUEST)
                .body(ErrorResponse.validationFailed(getRequestId(), errors));
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ErrorResponse> handleTypeMismatch(
            MethodArgumentTypeMismatchException ex) {

        log.info("Type mismatch for parameter: {}", ex.getName());

        return ResponseEntity
                .status(HttpStatus.BAD_REQUEST)
                .body(ErrorResponse.of(
                        HttpStatus.BAD_REQUEST.value(),
                        ErrorCodes.INVALID_PARAMETER_TYPE,
                        String.format("Parameter '%s' has invalid type", ex.getName()),
                        getRequestId()
                ));
    }

    @ExceptionHandler(AuthenticationException.class)
    public ResponseEntity<ErrorResponse> handleAuthenticationException(
            AuthenticationException ex) {

        log.warn("Authentication failed: {}", ex.getMessage());

        return ResponseEntity
                .status(HttpStatus.UNAUTHORIZED)
                .body(ErrorResponse.of(
                        HttpStatus.UNAUTHORIZED.value(),
                        ErrorCodes.UNAUTHORIZED,
                        "Authentication required. Please provide a valid token.",
                        getRequestId()
                ));
    }

    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ErrorResponse> handleAccessDenied(
            AccessDeniedException ex) {

        log.warn("Access denied: {}", ex.getMessage());

        return ResponseEntity
                .status(HttpStatus.FORBIDDEN)
                .body(ErrorResponse.of(
                        HttpStatus.FORBIDDEN.value(),
                        ErrorCodes.FORBIDDEN,
                        "You do not have permission to perform this action.",
                        getRequestId()
                ));
    }

    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<ErrorResponse> handleOptimisticLocking(
            OptimisticLockingFailureException ex) {

        log.warn("Optimistic lock conflict: {}",
                ex.getMessage());

        return ResponseEntity
                .status(HttpStatus.CONFLICT)
                .body(ErrorResponse.of(
                        HttpStatus.CONFLICT.value(),
                        ErrorCodes.OPTIMISTIC_LOCK_CONFLICT,
                        "The resource was modified by another request. " +
                                "Please fetch the latest version and retry.",
                        getRequestId()
                ));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleUnexpectedException(Exception ex) throws NoResourceFoundException {

        // NoResourceFoundException is thrown by Spring's resource handler when
        // a URL doesn't match any endpoint. Re-throwing it allows Spring Boot's
        // default error handling to respond with 404 instead of 500.
        // This is especially important for the management port (8091) where
        // actuator endpoints are served by a separate context.
        if (ex instanceof NoResourceFoundException nrfe) {
            throw nrfe;
        }

        log.error("Unexpected error occurred, requestId: {}", getRequestId(), ex);

        return ResponseEntity
                .status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ErrorResponse.of(
                        HttpStatus.INTERNAL_SERVER_ERROR.value(),
                        ErrorCodes.INTERNAL_SERVER_ERROR,
                        "An unexpected error occurred. Please contact support " +
                                "with request id: " + getRequestId(),
                        getRequestId()
                ));
    }

    private String getRequestId() {
        final String requestId = MDC.get("requestId");
        return requestId != null ? requestId : "unknown";
    }

    private ErrorResponse.ValidationError toValidationError(FieldError fieldError) {
        final String fieldName = fieldError.getField();

        final String rejectedValue = isSensitiveField(fieldName)
                ? "[REDACTED]"
                : fieldError.getRejectedValue() != null
                ? fieldError.getRejectedValue().toString()
                : null;

        return new ErrorResponse.ValidationError(
                fieldName,
                rejectedValue,
                fieldError.getDefaultMessage()
        );
    }

    private boolean isSensitiveField(String fieldName) {
        if (fieldName == null) return false;
        // Locale.ROOT: under a Turkish default locale "API_KEY".toLowerCase() has a dotless i (backlog #0-245)
        final String lowerField = fieldName.toLowerCase(Locale.ROOT);
        return SENSITIVE_FIELD_NAMES.stream()
                .anyMatch(lowerField::contains);
    }
}