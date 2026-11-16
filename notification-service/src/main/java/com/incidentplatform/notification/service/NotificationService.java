package com.incidentplatform.notification.service;

import com.incidentplatform.notification.channel.NotificationException;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.notification.dto.NotificationRequest;
import com.incidentplatform.notification.repository.NotificationLogRepository;
import com.incidentplatform.notification.repository.NotificationQueueRepository;
import com.incidentplatform.notification.router.NotificationRouter;
import com.incidentplatform.shared.audit.AuditEventTypes;
import com.incidentplatform.shared.audit.AuditText;
import com.incidentplatform.shared.audit.UnrecordedAuditEvents;
import com.incidentplatform.shared.domain.Severity;
import com.incidentplatform.shared.security.TenantContext;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Set;
import java.util.UUID;

import static com.incidentplatform.notification.router.NotificationEventTypes.INCIDENT_ESCALATED;
import static com.incidentplatform.notification.router.NotificationEventTypes.INCIDENT_OPENED;

/**
 * Notification application service — two distinct responsibilities:
 *
 * <h2>1. Enqueue (called by Kafka consumer — fast path)</h2>
 * {@link #enqueue} writes a PENDING outbox entry to {@code notification_queue}
 * and returns immediately. The Kafka consumer acknowledges after this returns.
 * No HTTP calls, no external dependencies — just one DB INSERT. Still
 * {@code @Transactional} — a single fast operation with no external I/O
 * is exactly what that annotation is for; unlike {@link #processEntry}
 * below, there's nothing here to fix.
 *
 * <h2>2. Process (called by scheduler — slow path)</h2>
 * {@link #processEntry} reads a PENDING entry, resolves the current oncall
 * recipient via HTTP, sends notifications through each channel (Slack, Email,
 * SMS), and writes to the immutable {@code notification_log} audit trail.
 * This runs in a dedicated scheduled thread, completely decoupled from Kafka.
 *
 * <h2>Why recipient is resolved at process time, not enqueue time</h2>
 * The oncall schedule may rotate between enqueue and processing (typically
 * 30 seconds). Resolving at process time ensures the notification reaches
 * whoever is currently on duty — not the person who was on duty when the
 * Kafka event arrived.
 *
 * <h2>Fixed (backlog #42): {@code processEntry} no longer wraps external
 * I/O in an open transaction</h2>
 * See {@link NotificationPersistenceService}'s Javadoc for the full
 * account — {@code processEntry} previously carried {@code @Transactional}
 * on the whole method, including the oncall-service HTTP lookup and every
 * per-channel send (Slack/SMTP/SMS). Every database write below now goes
 * through {@code NotificationPersistenceService} instead, each in its own
 * short, independent transaction opened only after the corresponding
 * external call has already completed — matching the same fix already
 * applied to {@code EscalationScheduler} (backlog #39).
 */
@Service
public class NotificationService {

    private static final Logger log =
            LoggerFactory.getLogger(NotificationService.class);

    /**
     * Events that ask someone to act. Only these alert the operator when they
     * are undeliverable; for the others (acknowledged, resolved, closed) the
     * metric and the audit event are enough and an alert would only be noise.
     */
    private static final Set<String> ACTIONABLE_EVENTS =
            Set.of(INCIDENT_OPENED, INCIDENT_ESCALATED);

    /** The reason recorded for an exception no channel anticipated (backlog #0-93). */
    static final String UNEXPECTED_REASON = "UNEXPECTED";

    private final NotificationRouter router;
    private final NotificationLogRepository logRepository;
    private final NotificationQueueRepository queueRepository;
    private final NotificationPersistenceService persistenceService;
    private final OperatorAlertService operatorAlertService;
    private final MeterRegistry meterRegistry;
    private final UnrecordedAuditEvents unrecorded;

    public NotificationService(NotificationRouter router,
                               NotificationLogRepository logRepository,
                               NotificationQueueRepository queueRepository,
                               NotificationPersistenceService persistenceService,
                               OperatorAlertService operatorAlertService,
                               MeterRegistry meterRegistry) {
        this.router = router;
        this.logRepository = logRepository;
        this.queueRepository = queueRepository;
        this.persistenceService = persistenceService;
        this.operatorAlertService = operatorAlertService;
        this.meterRegistry = meterRegistry;
        this.unrecorded = new UnrecordedAuditEvents(meterRegistry,
                AuditEventTypes.NOTIFICATION_SENT, AuditEventTypes.NOTIFICATION_FAILED);
    }

    /**
     * Writes a PENDING outbox entry for the given incident event.
     *
     * <p>Called by the Kafka consumer. Must be fast — no external HTTP calls,
     * no channel routing, no oncall lookup. Just one DB INSERT.
     *
     * <p>Idempotent — if an entry already exists for this
     * {@code incidentId + tenantId + eventType + escalationLevel}
     * combination (e.g. Kafka redeliver), the existing entry is left
     * unchanged and this call is a no-op.
     *
     * <h2>Fixed: level-2 escalation notifications were dropped</h2>
     * The key used to be {@code incidentId + eventType} only. Every
     * escalation — level 1 (SECONDARY) and level 2 (MANAGER) — is an
     * {@code IncidentEscalatedEvent} for the same incident, so everything
     * after the first was discarded here as a "duplicate" and never sent.
     * {@code escalationLevel} is now part of the key; it is {@code 0} for
     * every event type that is not an escalation, so their behaviour is
     * unchanged. A repeat escalation at the <em>same</em> level is still
     * deduplicated on purpose.
     *
     * @param eventType       the incident lifecycle event type
     * @param incidentId      the incident UUID
     * @param tenantId        the tenant that owns the incident
     * @param severity        the incident severity at the time of the event
     * @param title           the incident title for notification content
     * @param escalationLevel the escalation level, {@code 0} if the event is
     *                        not an escalation
     * @param escalateTo      the user the escalation is addressed to, or
     *                        {@code null}; stored on the entry because the
     *                        recipient is resolved at send time
     * @param teamId          the team the incident belongs to, or {@code null}
     *                        (backlog #0-12); stored on the entry, not part of
     *                        the idempotency key — same treatment as {@code
     *                        escalateTo}, it is routing data, not identity
     */
    @Transactional
    public void enqueue(String eventType,
                        UUID incidentId,
                        String tenantId,
                        Severity severity,
                        String title,
                        int escalationLevel,
                        UUID escalateTo,
                        UUID teamId) {
        if (queueRepository
                .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
                        incidentId, tenantId, eventType, escalationLevel)) {
            log.debug("Notification already queued (idempotency): " +
                            "incidentId={}, eventType={}, escalationLevel={}",
                    incidentId, eventType, escalationLevel);
            return;
        }

        final NotificationQueueEntry entry = NotificationQueueEntry.pending(
                incidentId, tenantId, eventType, severity, title,
                escalationLevel, escalateTo, teamId);
        queueRepository.save(entry);

        log.info("Notification queued: incidentId={}, eventType={}, " +
                        "escalationLevel={}, tenant={}",
                incidentId, eventType, escalationLevel, tenantId);
    }

    /**
     * A channel is skipped when the on-call user has no address for it (for
     * example no phone, so no SMS for an escalation). It is never replaced by a
     * shared destination, so it must not be silent: a WARN and a
     * {@code notification.channel_skipped{channel,event_type}} count (no tenant tag).
     */
    private void reportSkippedChannels(List<String> skippedChannels,
                                       NotificationQueueEntry entry) {
        for (final String channel : skippedChannels) {
            log.warn("On-call user has no address for channel {} — skipped: " +
                            "incidentId={}, tenantId={}, eventType={}",
                    channel, entry.getIncidentId(), entry.getTenantId(),
                    entry.getEventType());
            meterRegistry.counter("notification.channel_skipped",
                    "channel", channel,
                    "event_type", entry.getEventType()).increment();
        }
    }

    /**
     * Parks {@code entry} as UNDELIVERABLE: nobody in the tenant could be
     * notified (backlog #0-18). Persists the state, counts it in
     * {@code notification.undeliverable{event_type,reason}} (no tenant tag:
     * that would explode the metric's cardinality), records an audit event for
     * the tenant, and for the events that need someone to act tells the
     * operator with a content-free alert.
     *
     * <p>Also called by {@code NotificationScheduler} when oncall-service has
     * been unavailable for longer than the retry window (backlog #0-19).
     *
     * <p>Backlog #0-25: when the entry was no longer PENDING (the conditional
     * UPDATE changed nothing), none of the above happens.
     */
    public void markUndeliverable(NotificationQueueEntry entry,
                                  UndeliverableReason reason) {
        final UUID incidentId = entry.getIncidentId();
        final String tenantId = entry.getTenantId();
        final String eventType = entry.getEventType();

        // The status and its NOTIFICATION_UNDELIVERABLE audit event commit
        // together (backlog #0-84). The operator is told whether or not that
        // write succeeds (found in review: a failed write used to skip the
        // alert, though nobody had been notified either way); the alert is
        // content-free and rate-limited, so a retried entry does not repeat it.
        // A failed write is rethrown after the alert, never replaced by an
        // alert failure (found in review: a finally block could do that).
        // Backlog #0-25: a write that changed nothing (the entry was no longer
        // PENDING: another writer closed it first) is not an undeliverable
        // notification of this run. No alert and no count; the persistence
        // service has logged it and counted it in notification.queue.stale_write.
        RuntimeException writeFailure = null;
        boolean parked = false;
        try {
            parked = persistenceService.markUndeliverable(entry, reason);
        } catch (RuntimeException e) {
            writeFailure = e;
        }
        if (writeFailure == null && !parked) {
            return;
        }
        if (ACTIONABLE_EVENTS.contains(eventType)) {
            try {
                operatorAlertService.undeliverable(
                        incidentId, tenantId, eventType, reason);
            } catch (RuntimeException alertFailure) {
                if (writeFailure == null) {
                    throw alertFailure;
                }
                writeFailure.addSuppressed(alertFailure);
            }
        }
        if (writeFailure != null) {
            throw writeFailure;
        }

        meterRegistry.counter("notification.undeliverable",
                "event_type", eventType,
                "reason", reason.name()).increment();
    }

    /**
     * Processes a single PENDING outbox entry — resolves oncall, sends
     * notifications through each routed channel, writes audit log entries.
     *
     * <p>Called by {@code NotificationScheduler} in a dedicated scheduled
     * thread. May make HTTP calls to oncall-service, Slack API, SMTP, etc.
     * Never called from the Kafka consumer thread.
     *
     * <p>Marks the queue entry {@code SENT} if all channels were processed
     * (individual channel failures are logged to {@code notification_log}
     * with status FAILED but do not prevent other channels from being tried).
     * Marks {@code FAILED} only if an unexpected exception prevents processing
     * entirely — that happens in {@code NotificationScheduler}'s catch
     * block, not here, since this method no longer catches its own
     * top-level failures (removing {@code @Transactional} means there's no
     * longer a transaction boundary here to protect with a catch).
     *
     * @param entry the PENDING outbox entry to process
     */
    public void processEntry(NotificationQueueEntry entry) {
        final UUID incidentId = entry.getIncidentId();
        final String tenantId = entry.getTenantId();
        final String eventType = entry.getEventType();
        final int escalationLevel = entry.getEscalationLevel();

        // Ensure TenantContext is set — scheduler sets it per-entry but
        // this method may also be called directly in tests.
        TenantContext.set(tenantId);

        log.info("Processing notification queue entry: incidentId={}, " +
                        "eventType={}, tenant={}",
                incidentId, eventType, tenantId);

        // Resolve oncall and build channel requests — HTTP call to
        // oncall-service. Happens here (scheduler thread), with no
        // database transaction open (backlog #42).
        final var routing = router.route(
                eventType, incidentId, tenantId,
                entry.getSeverity(), entry.getTitle(), entry.getEscalateTo(),
                entry.getTeamId());

        reportSkippedChannels(routing.skippedChannels(), entry);

        // Backlog #0-18: nobody in the tenant can be notified. The incident text
        // is not sent anywhere else; the entry is parked and the operator told.
        if (routing.isUndeliverable()) {
            markUndeliverable(entry, routing.undeliverableReason());
            return;
        }

        final var channelRequests = routing.requests();

        if (channelRequests.isEmpty()) {
            log.debug("No channels configured for event: {}", eventType);
            // Result ignored: a stale write is logged and counted there (backlog #0-25).
            persistenceService.markSent(entry);
            return;
        }

        for (final var channelRequest : channelRequests) {
            final var channel = channelRequest.channel();
            final var request = channelRequest.request();

            // Per-channel idempotency — skip if already sent for this event.
            // Guards against duplicate sends if the scheduler runs twice
            // before marking the entry as SENT. Plain read, outside any
            // transaction — gets its own short, auto-committing one from
            // Spring Data JPA, same as every other read-only repository
            // call in this codebase's schedulers.
            if (logRepository
                    .existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevelAndChannel(
                            incidentId, tenantId, eventType, escalationLevel,
                            channel.channelName())) {
                log.info("Notification already sent (idempotency check): " +
                                "channel={}, incidentId={}, eventType={}, " +
                                "escalationLevel={}",
                        channel.channelName(), incidentId, eventType,
                        escalationLevel);
                continue;
            }

            try {
                channel.send(request);
            } catch (NotificationException e) {
                // Backlog #0-93: recorded by its reason, the platform's words;
                // the provider's own error is the cause, logged here only. WARN
                // when the tenant has something to change (a rejected address,
                // a channel the bot is not in), ERROR when it is the platform's.
                recordFailed(entry, channel.channelName(), request, e.reason().name(), e.recordedText());
                final String line = "Notification failed: channel={}, recipient={}, incidentId={}, reason={}";
                if (e.reason().permanent()) {
                    log.warn(line, channel.channelName(), request.recipient(), incidentId, e.recordedText(),
                            e.getCause());
                } else {
                    log.error(line, channel.channelName(), request.recipient(), incidentId, e.recordedText(),
                            e.getCause());
                }
                continue;
            } catch (Exception e) {
                // Recorded by its type only: the message of an exception the
                // channel did not anticipate may quote a URL with a token, a
                // host name or a response body, and notification_log and the
                // audit trail are the tenant's to read (backlog #0-84, found
                // in review). The full exception is in the log line below.
                recordFailed(entry, channel.channelName(), request, UNEXPECTED_REASON, AuditText.unexpected(e));

                log.error("Unexpected error sending notification: " +
                                "channel={}, incidentId={}",
                        channel.channelName(), incidentId, e);
                continue;
            }

            // Delivered. Recorded outside the send's try (backlog #0-84,
            // found while moving the audit event into this write): a failure
            // to record it used to land in the catch above and log a
            // delivered notification as a failed one.
            recordDelivered(entry, channel.channelName(), request);
        }

        // Mark the queue entry as processed — all channels attempted.
        // Individual channel failures are recorded in notification_log
        // but do not prevent the entry from being marked SENT here. Only a
        // PENDING entry becomes SENT; a stale write is logged and counted by
        // the persistence service (backlog #0-25).
        persistenceService.markSent(entry);

        log.info("Notification queue entry processed: eventType={}, " +
                        "channels={}, incidentId={}, tenant={}",
                eventType, channelRequests.size(), incidentId, tenantId);
    }

    /**
     * {@code notification.channel.failed{channel,reason}} (backlog #0-93): a
     * failed send by its reason, a {@code NotificationFailureReason} or
     * {@link #UNEXPECTED_REASON}, so a closed set of tags (no tenant, no
     * provider code). Counted whether or not its record is then written.
     */
    private Counter failedSends(String channelName, String reason) {
        return meterRegistry.counter("notification.channel.failed", "channel", channelName, "reason", reason);
    }

    /**
     * Records a failed send: its {@code notification_log} row and
     * {@code NOTIFICATION_FAILED} audit event, in one transaction (backlog
     * #0-84). A failure of that write is logged and counted
     * ({@code audit.event.unrecorded}), not thrown (found in review): thrown,
     * it left the loop and the remaining channels untried, for a record of a
     * send that had already failed.
     */
    private void recordFailed(NotificationQueueEntry entry,
                              String channelName,
                              NotificationRequest request,
                              String reason,
                              String error) {
        failedSends(channelName, reason).increment();
        try {
            persistenceService.recordChannelFailed(
                    entry.getIncidentId(), entry.getTenantId(), entry.getEventType(),
                    entry.getEscalationLevel(), channelName, request.recipient(), reason, error);
        } catch (RuntimeException e) {
            unrecorded.increment(AuditEventTypes.NOTIFICATION_FAILED);
            // "Audit event not recorded" is what the AuditEventUnrecorded alert
            // tells the operator to search for (found in review).
            log.error("Audit event not recorded: eventType={}, a failed notification missing from "
                            + "notification_log too: channel={}, recipient={}, incidentId={}, tenant={}, "
                            + "notificationEventType={}, escalationLevel={}, error={}",
                    AuditEventTypes.NOTIFICATION_FAILED, channelName, request.recipient(), entry.getIncidentId(), entry.getTenantId(),
                    entry.getEventType(), entry.getEscalationLevel(), error, e);
        }
    }

    /**
     * Records a delivered notification: its {@code notification_log} row and
     * {@code NOTIFICATION_SENT} audit event, in one transaction (backlog
     * #0-84).
     *
     * <p>When that write fails (the database unreachable, or the audit event
     * refused as unstorable, a programming error) the message has already
     * reached its recipient and cannot be taken back. It is not recorded as a
     * failed send, which it was not, and the entry is not failed with it, so
     * the remaining channels are still tried and the entry is still marked
     * processed: failing it would leave the other recipients unnotified, as a
     * FAILED entry is never picked up again. The delivery is then missing from
     * {@code notification_log} and the audit trail, so it is logged at ERROR
     * with everything needed to reconstruct it and counted in
     * {@code audit.event.unrecorded}, which the {@code AuditEventUnrecorded}
     * alert watches.
     */
    private void recordDelivered(NotificationQueueEntry entry,
                                 String channelName,
                                 NotificationRequest request) {
        try {
            persistenceService.recordChannelSent(
                    entry.getIncidentId(), entry.getTenantId(), entry.getEventType(),
                    entry.getEscalationLevel(), channelName, request.recipient(),
                    request.subject(), request.message());
        } catch (RuntimeException e) {
            unrecorded.increment(AuditEventTypes.NOTIFICATION_SENT);
            log.error("Notification delivered but not recorded in notification_log or the audit "
                            + "trail: channel={}, recipient={}, incidentId={}, tenant={}, eventType={}, "
                            + "escalationLevel={}",
                    channelName, request.recipient(), entry.getIncidentId(), entry.getTenantId(),
                    entry.getEventType(), entry.getEscalationLevel(), e);
            return;
        }

        log.info("Notification sent: channel={}, recipient={}, " +
                        "incidentId={}, tenant={}",
                channelName, request.recipient(),
                entry.getIncidentId(), entry.getTenantId());
    }
}