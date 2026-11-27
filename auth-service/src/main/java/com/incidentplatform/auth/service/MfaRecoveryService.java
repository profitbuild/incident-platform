package com.incidentplatform.auth.service;

import com.incidentplatform.auth.config.MfaRecoveryProperties;
import com.incidentplatform.auth.domain.AuthToken;
import com.incidentplatform.auth.domain.MfaRecoveryCloseReason;
import com.incidentplatform.auth.domain.MfaRecoveryRequest;
import com.incidentplatform.auth.domain.MfaRecoveryStatus;
import com.incidentplatform.auth.domain.MfaVerificationMethod;
import com.incidentplatform.auth.domain.Role;
import com.incidentplatform.auth.domain.User;
import com.incidentplatform.auth.repository.AuthTokenRepository;
import com.incidentplatform.auth.repository.MfaRecoveryRequestRepository;
import com.incidentplatform.auth.repository.TenantRepository;
import com.incidentplatform.auth.repository.UserRepository;
import com.incidentplatform.shared.audit.AuditEventPublisher;
import com.incidentplatform.shared.audit.AuditEventTypes;
import com.incidentplatform.shared.exception.BusinessException;
import com.incidentplatform.shared.exception.ErrorCodes;
import com.incidentplatform.shared.exception.ResourceNotFoundException;
import com.incidentplatform.shared.security.ReservedTenants;
import com.incidentplatform.shared.security.TenantIds;
import com.incidentplatform.shared.security.UserPrincipal;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.EnumMap;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.function.ToIntFunction;

/**
 * Operator-assisted MFA recovery of a customer tenant's only admin (backlog
 * #0-90).
 *
 * <h2>The problem</h2>
 * Since #0-88 a password reset never removes a second factor, and another
 * admin of the tenant resets it instead ({@link MfaService#resetMfaByAdmin}).
 * A customer tenant with one admin has nobody to do that: a factor someone
 * enrolled with the admin's stolen password, or a lost phone and lost backup
 * codes, locked the tenant's administration out for good, and the break-glass
 * command covers only {@code platform-operator}.
 *
 * <h2>The rule: delayed, announced, cancellable</h2>
 * As account recovery through a vendor works elsewhere (GitHub's 2FA recovery,
 * AWS root MFA, Okta and Entra super-admin recovery; NIST SP 800-63B: the
 * account is told of every recovery event), an operator admin of
 * {@code platform-operator} who passes {@code PlatformAccess} (JWT, MFA within
 * 12 h, factor older than 24 h) asks for the reset after verifying the person
 * outside the account's own channels, and records how
 * ({@link MfaVerificationMethod} and a note). Nothing changes then: the account
 * is emailed a notice with a cancel link, and only once the waiting period
 * ({@code platform.mfa-recovery.waiting-period}, 72 h) has passed since that
 * notice was actually sent does {@code MfaRecoveryScheduler} run the reset
 * ({@link #execute}). A request whose notice never went out expires
 * ({@link #expire}). The delay is the defence against the case this opens:
 * an operator talked into a reset by whoever stole the password would
 * otherwise remove the real owner's factor at once.
 *
 * <p>Only for an admin with MFA who is the tenant's only active admin (active,
 * invite accepted): with another one, that admin resets it (#0-88), and the
 * platform keeps out of a tenant that can help itself. Checked when asked and
 * again when run, together with the operator who asked: one who is no longer an
 * active operator admin (an account found compromised and deactivated) cancels
 * the request (review). A cancellation at that point is alerted
 * ({@code PlatformMfaRecoveryCancelledOnRecheck}): a second admin appearing
 * during the wait may be the attacker's. Not for reserved tenants: an operator admin has break-glass.
 *
 * <p>This is the one narrow exception to #0-80's "the platform never acts
 * inside a tenant once that tenant has an admin" ({@code TenantProvisioningService}).
 * Each step is audited in both tenants: the operator tenant's event carries
 * the operator's note, the customer tenant's only the method (the note may
 * name people or phone numbers). Requests count against the platform API's
 * limits ({@code PlatformRateLimiter}, in the controller); a new request is
 * alerted ({@code PlatformMfaRecoveryRequested}), and a cancellation by the
 * account even more so ({@code PlatformMfaRecoveryCancelledByAccount}: an
 * account that did not ask may mean the operator was deceived).
 *
 * <h2>What the account's mailbox can and cannot do</h2>
 * Its cancel link can only stop a reset, never cause one. It can stop every
 * one, though: whoever holds the mailbox (the attacker of the case that
 * motivated this, with the password, a factor and the mailbox) can cancel each
 * request, and whoever holds the admin session can add a second admin, after
 * which the platform keeps out ({@code OTHER_ADMIN_EXISTS}). Both are accepted:
 * each cancellation pages the operator, and from there the decision is a
 * person's, made through the verified channel (README "Infrastructure
 * Hardening", docs/tenant-provisioning.md).
 *
 * <h2>The reset</h2>
 * {@link MfaService#resetForRecovery}: the admin reset plus the password, so a
 * stranger who still knows the stolen password gets nothing; the owner sets a
 * new one from the completion email.
 *
 * <h2>Concurrency</h2>
 * Every change of status is one conditional UPDATE from PENDING
 * ({@link MfaRecoveryRequestRepository#close}); a cancellation and the
 * execution racing each other are decided by whichever UPDATE commits first,
 * the other updates no row and does nothing.
 */
@Service
public class MfaRecoveryService {

    private static final Logger log = LoggerFactory.getLogger(MfaRecoveryService.class);

    static final int NOTE_MAX = 500;
    static final String SOURCE = "auth-service";
    static final String COUNTER = "platform.mfa_recovery";
    /** The actor the customer tenant's trail shows for an operator's step. */
    static final String CUSTOMER_SIDE_OPERATOR = "platform-operator";

    /** The {@code outcome} tag of {@link #COUNTER}. */
    enum Outcome {
        REQUESTED, CANCELLED_BY_ACCOUNT, CANCELLED_BY_OPERATOR, CANCELLED_ON_RECHECK, EXECUTED, EXPIRED
    }

    /**
     * Extra time, past the notice's retry deadline, before a request whose
     * notice was never sent expires: the email scheduler may still be on its
     * last attempt.
     */
    static final Duration NOTICE_EXPIRY_MARGIN = Duration.ofHours(1);

    private final MfaRecoveryRequestRepository requestRepository;
    private final UserRepository userRepository;
    private final TenantRepository tenantRepository;
    private final AuthTokenRepository tokenRepository;
    private final AuthTokenService authTokenService;
    private final AuthEmailRequestService emailRequests;
    private final MfaService mfaService;
    private final AuditEventPublisher auditEventPublisher;
    private final Duration waitingPeriod;
    private final Clock clock;
    private final Map<Outcome, Counter> counters = new EnumMap<>(Outcome.class);

    /** For Spring; the package-private one takes a clock for tests. */
    @Autowired
    public MfaRecoveryService(MfaRecoveryRequestRepository requestRepository,
                              UserRepository userRepository,
                              TenantRepository tenantRepository,
                              AuthTokenRepository tokenRepository,
                              AuthTokenService authTokenService,
                              AuthEmailRequestService emailRequests,
                              MfaService mfaService,
                              AuditEventPublisher auditEventPublisher,
                              MfaRecoveryProperties properties,
                              MeterRegistry meterRegistry) {
        this(requestRepository, userRepository, tenantRepository, tokenRepository, authTokenService,
                emailRequests, mfaService, auditEventPublisher, properties, meterRegistry, Clock.systemUTC());
    }

    MfaRecoveryService(MfaRecoveryRequestRepository requestRepository,
                       UserRepository userRepository,
                       TenantRepository tenantRepository,
                       AuthTokenRepository tokenRepository,
                       AuthTokenService authTokenService,
                       AuthEmailRequestService emailRequests,
                       MfaService mfaService,
                       AuditEventPublisher auditEventPublisher,
                       MfaRecoveryProperties properties,
                       MeterRegistry meterRegistry,
                       Clock clock) {
        this.requestRepository   = requestRepository;
        this.userRepository      = userRepository;
        this.tenantRepository    = tenantRepository;
        this.tokenRepository     = tokenRepository;
        this.authTokenService    = authTokenService;
        this.emailRequests       = emailRequests;
        this.mfaService          = mfaService;
        this.auditEventPublisher = auditEventPublisher;
        this.waitingPeriod       = properties.waitingPeriod();
        this.clock               = clock;
        for (final Outcome outcome : Outcome.values()) {
            counters.put(outcome, Counter.builder(COUNTER)
                    .description("Operator MFA recovery requests by outcome (backlog #0-90)")
                    .tag("outcome", outcome.name().toLowerCase(Locale.ROOT))
                    .register(meterRegistry));
        }
    }

    // ── Request ───────────────────────────────────────────────────────────

    /**
     * An operator asks for the reset. The request, its notice (in the auth
     * email outbox) and both audit events commit together.
     *
     * @throws BusinessException 400 for a reserved or malformed tenant id or
     *         an unusable note; 409 if the user is not an active admin with
     *         MFA, the tenant has another active admin, or the user already has
     *         an open request
     * @throws ResourceNotFoundException if the tenant or the user does not exist
     */
    @Transactional
    public MfaRecoveryRequest request(String tenantId, UUID userId, MfaVerificationMethod method,
                                      String note, UserPrincipal operator) {
        if (!TenantIds.isValid(tenantId)) {
            throw new BusinessException(ErrorCodes.VALIDATION_FAILED,
                    "tenantId must be 3-63 lowercase letters, digits or hyphens", HttpStatus.BAD_REQUEST);
        }
        if (ReservedTenants.isReserved(tenantId)) {
            throw new BusinessException(ErrorCodes.VALIDATION_FAILED,
                    "Tenant '" + tenantId + "' is reserved: an operator admin's MFA is reset by another "
                            + "operator admin or the break-glass command", HttpStatus.BAD_REQUEST);
        }
        if (method == null) {
            throw new BusinessException(ErrorCodes.VALIDATION_FAILED,
                    "verificationMethod is required", HttpStatus.BAD_REQUEST);
        }
        final String checkedNote = checkedNote(note);
        if (!tenantRepository.existsById(tenantId)) {
            throw new ResourceNotFoundException("Tenant", tenantId);
        }
        final User user = userRepository.findByIdAndTenantId(userId, tenantId)
                .orElseThrow(() -> new ResourceNotFoundException("User", userId));
        final String notApplicable = notApplicableBecause(user);
        if (notApplicable != null) {
            throw new BusinessException(ErrorCodes.BUSINESS_RULE_VIOLATION,
                    "MFA recovery is only for an active admin with MFA: " + notApplicable, HttpStatus.CONFLICT);
        }
        if (hasOtherActiveAdmin(user)) {
            throw new BusinessException(ErrorCodes.BUSINESS_RULE_VIOLATION,
                    "The tenant has another active admin, who can reset this user's MFA "
                            + "(POST /api/v1/users/{id}/mfa-reset)", HttpStatus.CONFLICT);
        }
        if (requestRepository.findPendingByUserId(userId).isPresent()) {
            throw pendingExists();
        }

        final MfaRecoveryRequest request = MfaRecoveryRequest.open(
                tenantId, userId, operator.userId(), method, checkedNote, clock.instant());
        try {
            requestRepository.saveAndFlush(request);
        } catch (DataIntegrityViolationException e) {
            // The partial unique index: another request for the user won a race.
            throw pendingExists();
        }
        emailRequests.requestMfaRecoveryNotice(user, request.getId());

        final Map<String, Object> operatorSide = metadata(request);
        operatorSide.put("tenantId", tenantId);
        operatorSide.put("userId", userId.toString());
        operatorSide.put("verificationNote", checkedNote);
        auditEventPublisher.publishAuth(operator.userId(), ReservedTenants.PLATFORM_OPERATOR,
                AuditEventTypes.MFA_RECOVERY_REQUESTED, SOURCE, operator.userId().toString(),
                "MFA recovery of a customer tenant's only admin requested", operatorSide);
        auditEventPublisher.publishAuth(userId, tenantId,
                AuditEventTypes.MFA_RECOVERY_REQUESTED, SOURCE, CUSTOMER_SIDE_OPERATOR,
                "The platform operator was asked to reset this admin's MFA; it runs after the waiting "
                        + "period unless cancelled", metadata(request));

        countAfterCommit(Outcome.REQUESTED);
        log.warn("MFA recovery requested: request={}, tenant={}, user={}, by operator={}, method={}",
                request.getId(), tenantId, userId, operator.userId(), method);
        return request;
    }

    /** The configured waiting period, counted from the send of a request's notice. */
    public Duration waitingPeriod() {
        return waitingPeriod;
    }

    /** A tenant's requests, newest first, for the operator. */
    @Transactional(readOnly = true)
    public Page<MfaRecoveryRequest> list(String tenantId, Pageable pageable) {
        return requestRepository.findByTenantIdOrderByCreatedAtDesc(tenantId, pageable);
    }

    // ── Cancel ────────────────────────────────────────────────────────────

    /**
     * The account cancels with the link of its notice. The token says which
     * user and tenant; a request that has already ended leaves nothing to do.
     *
     * @return whether an open request was cancelled
     * @throws BusinessException 401 if the token is invalid, expired or used
     */
    @Transactional
    public boolean cancelByAccount(String rawToken) {
        final AuthToken token = authTokenService.consumeToken(rawToken, AuthToken.Type.MFA_RECOVERY_CANCEL);
        final UUID userId = token.getUser().getId();
        final Optional<MfaRecoveryRequest> pending = requestRepository.findPendingByUserId(userId);
        if (pending.isEmpty() || !pending.get().getTenantId().equals(token.getTenantId())) {
            log.info("MFA recovery cancel link used with no open request: user={}, tenant={}",
                    userId, token.getTenantId());
            return false;
        }
        return close(pending.get(), MfaRecoveryStatus.CANCELLED, MfaRecoveryCloseReason.CANCELLED_BY_ACCOUNT,
                userId, new Actor(userId.toString(), userId.toString()), Outcome.CANCELLED_BY_ACCOUNT);
    }

    /**
     * An operator cancels a request (no rate limit: the safe direction, like
     * revoking keys in #0-89).
     *
     * @throws ResourceNotFoundException if there is no such request
     * @throws BusinessException 409 if it has already ended
     */
    @Transactional
    public void cancelByOperator(UUID requestId, UserPrincipal operator) {
        final MfaRecoveryRequest request = requestRepository.findById(requestId)
                .orElseThrow(() -> new ResourceNotFoundException("MFA recovery request", requestId));
        if (!close(request, MfaRecoveryStatus.CANCELLED, MfaRecoveryCloseReason.CANCELLED_BY_OPERATOR,
                operator.userId(), new Actor(operator.userId().toString(), CUSTOMER_SIDE_OPERATOR),
                Outcome.CANCELLED_BY_OPERATOR)) {
            throw new BusinessException(ErrorCodes.BUSINESS_RULE_VIOLATION,
                    "The request has already ended", HttpStatus.CONFLICT);
        }
    }

    // ── Scheduler ─────────────────────────────────────────────────────────

    /** Requests whose waiting period has passed, oldest first. */
    @Transactional(readOnly = true)
    public List<MfaRecoveryRequest> findDue(int limit) {
        return requestRepository.findDue(clock.instant().minus(waitingPeriod), PageRequest.of(0, limit));
    }

    /** Requests whose notice was never sent within its retry deadline. */
    @Transactional(readOnly = true)
    public List<MfaRecoveryRequest> findUndelivered(int limit) {
        final Instant cutoff = clock.instant()
                .minus(emailRequests.securityNotificationDeadline())
                .minus(NOTICE_EXPIRY_MARGIN);
        return requestRepository.findUndeliveredBefore(cutoff, PageRequest.of(0, limit));
    }

    /**
     * Runs a due request: the checks again (the tenant may have gained an
     * admin, the user lost the role or the factor), then the reset. A request
     * that no longer applies is cancelled with the reason; one that has ended
     * meanwhile is left alone.
     *
     * @return whether the reset ran
     */
    @Transactional
    public boolean execute(UUID requestId) {
        final Optional<MfaRecoveryRequest> found = requestRepository.findById(requestId);
        if (found.isEmpty() || found.get().getStatus() != MfaRecoveryStatus.PENDING) {
            return false;
        }
        final MfaRecoveryRequest request = found.get();
        final Instant now = clock.instant();
        if (request.getNoticeSentAt() == null || request.getNoticeSentAt().plus(waitingPeriod).isAfter(now)) {
            // Defence in depth: findDue selects only requests past their waiting period.
            log.error("MFA recovery request not due, not run: request={}, noticeSentAt={}",
                    requestId, request.getNoticeSentAt());
            return false;
        }

        // Locked (FOR NO KEY UPDATE NOWAIT, security review): no change to the
        // target's role, status or factor can slip in between these checks and
        // the reset. A busy row fails this run, which the scheduler counts and
        // retries. A second admin accepting an invite in the same milliseconds
        // is not serialised; they could reset the factor themselves anyway.
        final Optional<User> user = userRepository.findByIdAndTenantIdForUpdate(
                request.getUserId(), request.getTenantId());
        final MfaRecoveryCloseReason refused = !operatorStillAdmin(request.getRequestedBy())
                ? MfaRecoveryCloseReason.OPERATOR_NO_LONGER_ADMIN
                : user.isEmpty() || notApplicableBecause(user.get()) != null
                ? MfaRecoveryCloseReason.NO_LONGER_APPLICABLE
                : hasOtherActiveAdmin(user.get()) ? MfaRecoveryCloseReason.OTHER_ADMIN_EXISTS : null;
        if (refused != null) {
            close(request, MfaRecoveryStatus.CANCELLED, refused, null, null, Outcome.CANCELLED_ON_RECHECK);
            return false;
        }

        if (requestRepository.close(requestId, MfaRecoveryStatus.EXECUTED, null, null, now) != 1) {
            log.info("MFA recovery request ended before it could run: request={}", requestId);
            return false;
        }
        // close() cleared the persistence context: work on a fresh copy.
        final User target = userRepository.findByIdAndTenantId(request.getUserId(), request.getTenantId())
                .orElseThrow(() -> new IllegalStateException("user vanished in its own transaction"));
        // Security review: a reset link someone requested just before (with the
        // stolen password and the mailbox) must not outlive the recovery; the
        // completion email creates the only valid one when it is sent.
        tokenRepository.invalidateValidTokens(request.getUserId(), AuthToken.Type.PASSWORD_RESET, now);
        final int keysRevoked = mfaService.resetForRecovery(target, request.getTenantId());
        tokenRepository.invalidateValidTokens(request.getUserId(), AuthToken.Type.MFA_RECOVERY_CANCEL, now);

        final Map<String, Object> details = metadata(request);
        details.put(ApiKeyService.AUDIT_PERSONAL_KEYS_REVOKED, String.valueOf(keysRevoked));
        publishBoth(request, AuditEventTypes.MFA_RECOVERY_EXECUTED, null,
                "MFA, password and sessions of the tenant's only admin reset after the waiting period", details);
        countAfterCommit(Outcome.EXECUTED);
        log.warn("MFA recovery executed: request={}, tenant={}, user={}, personalApiKeysRevoked={}",
                requestId, request.getTenantId(), request.getUserId(), keysRevoked);
        return true;
    }

    /**
     * Gives up a request whose notice was never sent: a reset the account was
     * not told about must not happen.
     *
     * @return whether the request was still open and is now EXPIRED
     */
    @Transactional
    public boolean expire(UUID requestId) {
        final Optional<MfaRecoveryRequest> request = requestRepository.findById(requestId);
        if (request.isEmpty() || request.get().getNoticeSentAt() != null) {
            return false;
        }
        // The UPDATE repeats "notice not sent" (review): a notice recorded
        // between the read above and this statement keeps the request open.
        return close(request.get(), MfaRecoveryStatus.EXPIRED, MfaRecoveryCloseReason.NOTICE_NOT_DELIVERED,
                null, null, Outcome.EXPIRED,
                now -> requestRepository.expireIfUndelivered(requestId, MfaRecoveryCloseReason.NOTICE_NOT_DELIVERED, now));
    }

    // ── private ───────────────────────────────────────────────────────────

    /**
     * Ends an open request, invalidates its cancel link and audits it in both
     * tenants. {@code actor} null = the platform itself.
     */
    private boolean close(MfaRecoveryRequest request, MfaRecoveryStatus status, MfaRecoveryCloseReason reason,
                          UUID closedBy, Actor actor, Outcome outcome) {
        return close(request, status, reason, closedBy, actor, outcome,
                now -> requestRepository.close(request.getId(), status, reason, closedBy, now));
    }

    /** The same, with the conditional UPDATE given by the caller; it returns the rows it changed. */
    private boolean close(MfaRecoveryRequest request, MfaRecoveryStatus status, MfaRecoveryCloseReason reason,
                          UUID closedBy, Actor actor, Outcome outcome, ToIntFunction<Instant> update) {
        final Instant now = clock.instant();
        if (update.applyAsInt(now) != 1) {
            return false;
        }
        tokenRepository.invalidateValidTokens(request.getUserId(), AuthToken.Type.MFA_RECOVERY_CANCEL, now);
        final Map<String, Object> details = metadata(request);
        details.put("reason", reason.name());
        publishBoth(request, status == MfaRecoveryStatus.EXPIRED
                        ? AuditEventTypes.MFA_RECOVERY_EXPIRED : AuditEventTypes.MFA_RECOVERY_CANCELLED,
                actor, "MFA recovery request ended without a reset: " + reason.name(), details);
        countAfterCommit(outcome);
        log.warn("MFA recovery request {}: request={}, tenant={}, user={}, reason={}, by={}",
                status, request.getId(), request.getTenantId(), request.getUserId(), reason,
                actor == null ? "platform" : actor.operatorSide());
        return true;
    }

    private void publishBoth(MfaRecoveryRequest request, String type, Actor actor, String detail,
                             Map<String, Object> details) {
        final Map<String, Object> operatorSide = new HashMap<>(details);
        operatorSide.put("tenantId", request.getTenantId());
        operatorSide.put("userId", request.getUserId().toString());
        if (actor == null) {
            auditEventPublisher.publishAuthSystem(request.getRequestedBy(), ReservedTenants.PLATFORM_OPERATOR,
                    type, SOURCE, detail, operatorSide);
            auditEventPublisher.publishAuthSystem(request.getUserId(), request.getTenantId(),
                    type, SOURCE, detail, details);
        } else {
            auditEventPublisher.publishAuth(request.getRequestedBy(), ReservedTenants.PLATFORM_OPERATOR,
                    type, SOURCE, actor.operatorSide(), detail, operatorSide);
            auditEventPublisher.publishAuth(request.getUserId(), request.getTenantId(),
                    type, SOURCE, actor.customerSide(), detail, details);
        }
    }

    /** What both tenants' events carry: never the operator's note. */
    private static Map<String, Object> metadata(MfaRecoveryRequest request) {
        final Map<String, Object> metadata = new HashMap<>();
        metadata.put("requestId", request.getId().toString());
        metadata.put("verificationMethod", request.getVerificationMethod().name());
        return metadata;
    }

    /** Why the user cannot be recovered this way, or null if they can. */
    private static String notApplicableBecause(User user) {
        if (!user.isActive()) {
            return "the user is deactivated";
        }
        if (!user.getRoleNames().contains(Role.ROLE_ADMIN.name())) {
            return "the user is not an admin";
        }
        if (user.getPasswordHash() == null) {
            return "the user has not accepted their invite";
        }
        if (!user.isMfaEnabled()) {
            return "the user has no second factor";
        }
        return null;
    }

    /**
     * Whether the operator who asked is still an active admin of the operator
     * tenant (security review of #0-90): a request filed from a session that
     * was later found compromised, and its account deactivated or demoted,
     * must not still run when its waiting period ends.
     */
    private boolean operatorStillAdmin(UUID operatorId) {
        return userRepository.findByIdAndTenantId(operatorId, ReservedTenants.PLATFORM_OPERATOR)
                .filter(User::isActive)
                .filter(operator -> operator.getPasswordHash() != null)
                .filter(operator -> operator.getRoleNames().contains(Role.ROLE_ADMIN.name()))
                .isPresent();
    }

    private boolean hasOtherActiveAdmin(User user) {
        return userRepository.countActiveAcceptedUsersWithRoleExcluding(
                user.getTenantId(), Role.ROLE_ADMIN, user.getId()) > 0;
    }

    /** The note goes into the operator tenant's audit trail and the log of the request: no forged lines. */
    private static String checkedNote(String note) {
        if (note == null || note.isBlank() || note.strip().length() > NOTE_MAX
                || note.codePoints().anyMatch(MfaService::isUnsafeInLog)) {
            throw new BusinessException(ErrorCodes.VALIDATION_FAILED,
                    "verificationNote is required: what was checked, at most " + NOTE_MAX
                            + " characters, without control, line-separator or formatting characters",
                    HttpStatus.BAD_REQUEST);
        }
        return note.strip();
    }

    /**
     * Who a step is attributed to in each tenant's trail. The customer tenant
     * sees an operator only as {@link #CUSTOMER_SIDE_OPERATOR}, never the
     * operator account's id (security review): which operator acted is the
     * operator tenant's record.
     */
    private record Actor(String operatorSide, String customerSide) {
    }

    /** Counts an outcome once its transaction has committed (no critical alert on a rollback). */
    private void countAfterCommit(Outcome outcome) {
        CommittedCounters.incrementAfterCommit(counters.get(outcome));
    }

    private static BusinessException pendingExists() {
        return new BusinessException(ErrorCodes.ALREADY_EXISTS,
                "The user already has an open MFA recovery request", HttpStatus.CONFLICT);
    }
}
