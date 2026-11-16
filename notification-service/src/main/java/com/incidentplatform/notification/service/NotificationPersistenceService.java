package com.incidentplatform.notification.service;

import com.incidentplatform.notification.domain.NotificationLog;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.notification.repository.NotificationLogRepository;
import com.incidentplatform.notification.repository.NotificationQueueRepository;
import com.incidentplatform.shared.audit.AuditEventPublisher;
import com.incidentplatform.shared.audit.AuditEventTypes;
import com.incidentplatform.shared.audit.AuditText;
import io.micrometer.core.instrument.MeterRegistry;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

/**
 * Short, independent transactions for {@link NotificationQueueEntry} and
 * {@link NotificationLog} writes made while processing a notification —
 * backlog #42.
 *
 * <h2>Why this class exists</h2>
 * {@code NotificationService.processEntry(...)} previously carried
 * {@code @Transactional} on the whole method — including
 * {@code NotificationRouter.route(...)} (an HTTP call to oncall-service)
 * and, per routed channel, {@code channel.send(...)} (a further HTTP call
 * to Slack/SMTP/an SMS gateway) — holding a database connection open for
 * the combined duration of an oncall lookup plus up to three separate
 * external sends. Under a large backlog or a slow/degraded downstream
 * (any of oncall-service, Slack, the SMTP relay, or the SMS gateway),
 * this risked holding a connection for a long time per entry, potentially
 * exhausting the pool. The same class of problem already fixed in
 * {@code EscalationScheduler} (backlog #39) and present, in a smaller
 * form, in {@code NotificationScheduler}'s own catch block (also fixed
 * as part of backlog #42 — see that class's Javadoc).
 *
 * <p>Fixed by removing {@code @Transactional} from {@code processEntry}
 * entirely — every external call now happens with no open transaction,
 * and each database write goes through this class instead: a short,
 * independent transaction with no HTTP call in progress while it's open.
 *
 * <h2>Bonus correctness improvement, not just a style fix</h2>
 * Under the old single-transaction design, Hibernate's default flush
 * timing meant {@code NotificationLog} rows for channels already
 * successfully sent earlier in the same {@code processEntry} call were
 * not necessarily durable until the <em>whole</em> method's transaction
 * committed — so a crash partway through a multi-channel entry (e.g.
 * after Slack succeeded but before Email was attempted) could lose the
 * record of Slack's success along with everything else, causing the next
 * pickup of this still-PENDING entry to see no log row and resend via
 * Slack too — a duplicate notification. Each channel's outcome now
 * commits immediately in its own short transaction, so a crash partway
 * through only ever risks re-attempting channels that genuinely were
 * never confirmed sent.
 *
 * <h2>Audit events in the same transaction (backlog #0-84)</h2>
 * Each outcome that has an audit event ({@code NOTIFICATION_SENT},
 * {@code NOTIFICATION_FAILED}, {@code NOTIFICATION_UNDELIVERABLE}) writes it
 * to the service's audit outbox in the transaction of the row it records: the
 * {@code notification_log} row (or the queue entry's status) and its audit
 * event commit together or not at all. Before, the event was sent to Kafka
 * after the commit and without waiting, and was lost whenever Kafka was slow
 * or down. A failure to write it now fails the method, and the row with it.
 *
 * <h2>Queue writes are state-guarded (backlog #0-25, ADR-0059)</h2>
 * {@link #markSent}, {@link #markFailed}, {@link #markUndeliverable} and
 * {@link #recordLookupFailure} no longer change the entry and {@code save()}
 * it: that merge wrote the columns as the caller had loaded them, so a stale
 * writer (a run that outlived its ShedLock, an old pod in a rollout, the
 * scheduler's catch-all {@code markFailed} after a committed
 * {@code markUndeliverable}) overwrote a terminal status. Each is now one of
 * {@code NotificationQueueRepository}'s conditional UPDATEs from PENDING,
 * scoped by id and tenant, and returns whether it changed the row. A row that
 * did not change is logged and counted ({@code notification.queue.stale_write}),
 * and nothing else happens: no {@code NOTIFICATION_UNDELIVERABLE} event for an
 * entry someone else closed. The in-memory entry keeps what was loaded: the
 * scheduler's retry window, the one reader of a field written here, treats a
 * missing first failure as "now".
 */
@Service
public class NotificationPersistenceService {

    private static final Logger log =
            LoggerFactory.getLogger(NotificationPersistenceService.class);

    private static final String SERVICE_NAME = "notification-service";

    /** A queue write that changed nothing, by operation (backlog #0-25). */
    static final String STALE_WRITE_METRIC = "notification.queue.stale_write";
    static final String OPERATION_SENT = "sent";
    static final String OPERATION_FAILED = "failed";
    static final String OPERATION_UNDELIVERABLE = "undeliverable";
    static final String OPERATION_LOOKUP = "lookup";

    private final NotificationQueueRepository queueRepository;
    private final NotificationLogRepository logRepository;
    private final AuditEventPublisher auditEventPublisher;
    private final MeterRegistry meterRegistry;

    public NotificationPersistenceService(
            NotificationQueueRepository queueRepository,
            NotificationLogRepository logRepository,
            AuditEventPublisher auditEventPublisher,
            MeterRegistry meterRegistry) {
        this.queueRepository = queueRepository;
        this.logRepository = logRepository;
        this.auditEventPublisher = auditEventPublisher;
        this.meterRegistry = meterRegistry;
    }

    /**
     * Marks {@code entry} SENT and commits immediately. Used both for the
     * "no channels configured" early-return case and the normal
     * end-of-processing case in {@code NotificationService.processEntry} —
     * both are the exact same state transition.
     *
     * @return whether the entry was still PENDING and is now SENT (backlog
     *         #0-25: {@code false} is logged and counted here)
     */
    @Transactional
    public boolean markSent(NotificationQueueEntry entry) {
        return applied(queueRepository.markSent(
                entry.getId(), entry.getTenantId(), Instant.now()), OPERATION_SENT, entry);
    }

    /**
     * Marks {@code entry} FAILED and commits immediately — used by
     * {@code NotificationScheduler}'s catch block when
     * {@code processEntry} itself throws an unexpected exception (as
     * opposed to an individual channel failure, which is recorded via
     * {@link #recordChannelFailed} and does not fail the whole entry).
     *
     * @return whether the entry was still PENDING and is now FAILED (backlog
     *         #0-25: {@code false}, e.g. after an UNDELIVERABLE that already
     *         committed, is logged and counted here and changes nothing)
     */
    @Transactional
    public boolean markFailed(NotificationQueueEntry entry, String errorMessage) {
        return applied(queueRepository.markFailed(
                entry.getId(), entry.getTenantId(), errorMessage, Instant.now()), OPERATION_FAILED, entry);
    }

    /**
     * Records the first failed recipient lookup on {@code entry} and commits
     * immediately (backlog #0-19); later failures leave the timestamp alone.
     *
     * @return whether the entry was still PENDING with no failure recorded and
     *         now has this one (backlog #0-25: {@code false} is logged and
     *         counted here)
     */
    @Transactional
    public boolean recordLookupFailure(NotificationQueueEntry entry) {
        return applied(queueRepository.recordLookupFailure(
                entry.getId(), entry.getTenantId(), Instant.now()), OPERATION_LOOKUP, entry);
    }

    /**
     * Marks {@code entry} UNDELIVERABLE (backlog #0-18): nobody in the tenant
     * could be notified. Its {@code NOTIFICATION_UNDELIVERABLE} audit event is
     * written in the same transaction (backlog #0-84), and only when the
     * status changed (backlog #0-25): an entry another writer already closed
     * gets no second outcome in the audit trail.
     *
     * @return whether the entry was still PENDING and is now UNDELIVERABLE
     */
    @Transactional
    public boolean markUndeliverable(NotificationQueueEntry entry,
                                     UndeliverableReason reason) {
        if (!applied(queueRepository.markUndeliverable(
                entry.getId(), entry.getTenantId(), reason.name(), Instant.now()),
                OPERATION_UNDELIVERABLE, entry)) {
            return false;
        }

        auditEventPublisher.publishIncident(
                entry.getIncidentId(), entry.getTenantId(),
                AuditEventTypes.NOTIFICATION_UNDELIVERABLE, SERVICE_NAME,
                "Notification undeliverable: nobody in the tenant could be "
                        + "notified (" + reason + ")",
                Map.of("eventType", entry.getEventType(), "reason", reason.name()));
        return true;
    }

    /**
     * Whether the conditional UPDATE changed the entry (backlog #0-25). A 0
     * means another writer closed it first, or for a lookup failure that one
     * is already recorded: logged at INFO (ids and tenant only, never the
     * error text) and counted in
     * {@code notification.queue.stale_write{operation}}, a closed set of tags.
     */
    private boolean applied(int rows, String operation, NotificationQueueEntry entry) {
        if (rows == 1) {
            return true;
        }
        log.info("Notification queue entry not changed, no longer PENDING (or its lookup failure already "
                        + "recorded): operation={}, entry={}, incidentId={}, tenant={}",
                operation, entry.getId(), entry.getIncidentId(), entry.getTenantId());
        meterRegistry.counter(STALE_WRITE_METRIC, "operation", operation).increment();
        return false;
    }

    /**
     * Records a delivered notification in {@code notification_log}, with its
     * {@code NOTIFICATION_SENT} audit event in the same transaction (backlog
     * #0-84).
     */
    @Transactional
    public void recordChannelSent(UUID incidentId, String tenantId,
                                  String eventType, int escalationLevel,
                                  String channelName, String recipient,
                                  String subject, String message) {
        logRepository.save(NotificationLog.sent(
                incidentId, tenantId, eventType, escalationLevel,
                channelName, recipient, subject, message));

        auditEventPublisher.publishIncident(
                incidentId, tenantId,
                AuditEventTypes.NOTIFICATION_SENT, SERVICE_NAME,
                String.format("Notification sent via %s to %s", channelName, recipient),
                Map.of("channel", channelName,
                        "recipient", recipient,
                        "eventType", eventType));
    }

    /**
     * Records a failed send in {@code notification_log}, with its
     * {@code NOTIFICATION_FAILED} audit event in the same transaction (backlog
     * #0-84). Every failed send has one now, a channel's own failure and an
     * unexpected error alike: before, only the first was audited. The audit
     * event carries the error through {@link AuditText#error} (one line, at
     * most 500 characters; found in review: an unbounded message could make
     * the event too large to store, and fail this write with it).
     *
     * <p>Backlog #0-93: both the error and the reason are the platform's own
     * text: a channel's failure is its {@code NotificationFailureReason} and
     * the text built from it, never a provider's message; the reason is also a
     * field of its own in the audit event, for a reader that filters on it.
     *
     * @param reason       the {@code NotificationFailureReason}'s name, or
     *                     {@code UNEXPECTED} for an exception no channel
     *                     anticipated; {@code null} is recorded as "unknown"
     * @param errorMessage why the send failed, written by the platform (the
     *                     caller passes {@link AuditText#unexpected} for an
     *                     exception it did not anticipate, never that
     *                     exception's message); {@code null} is recorded as
     *                     "unknown" ({@code Map.of} refuses a null value)
     */
    @Transactional
    public void recordChannelFailed(UUID incidentId, String tenantId,
                                    String eventType, int escalationLevel,
                                    String channelName, String recipient,
                                    String reason, String errorMessage) {
        final String error = errorMessage != null ? errorMessage : "unknown";
        logRepository.save(NotificationLog.failed(
                incidentId, tenantId, eventType, escalationLevel,
                channelName, recipient, error));

        final String auditError = AuditText.error(error);

        auditEventPublisher.publishIncident(
                incidentId, tenantId,
                AuditEventTypes.NOTIFICATION_FAILED, SERVICE_NAME,
                String.format("Notification failed via %s to %s: %s", channelName, recipient, auditError),
                Map.of("channel", channelName,
                        "recipient", recipient,
                        "reason", reason != null ? reason : "unknown",
                        "error", auditError));
    }
}