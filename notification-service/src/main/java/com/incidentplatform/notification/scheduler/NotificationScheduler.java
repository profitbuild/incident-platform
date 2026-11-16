package com.incidentplatform.notification.scheduler;

import com.incidentplatform.notification.channel.NotificationChannel;
import com.incidentplatform.notification.client.OncallLookupUnavailableException;
import com.incidentplatform.notification.client.SlackWorkspaceLookupUnavailableException;
import com.incidentplatform.notification.config.NotificationSchedulerProperties;
import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.UndeliverableReason;
import com.incidentplatform.notification.repository.NotificationQueueRepository;
import com.incidentplatform.notification.service.NotificationPersistenceService;
import com.incidentplatform.notification.service.NotificationService;
import com.incidentplatform.notification.slack.SlackMessageStore;
import com.incidentplatform.shared.audit.AuditText;
import com.incidentplatform.shared.pause.TenantWorkGuard;
import com.incidentplatform.shared.security.TenantContext;
import net.javacrumbs.shedlock.spring.annotation.SchedulerLock;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.data.domain.PageRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.List;

/**
 * Processes the notification outbox — picks up PENDING entries written by
 * the Kafka consumer and sends the actual notifications.
 *
 * <h2>Why this scheduler exists</h2>
 * The Kafka consumer ({@code IncidentEventConsumer}) writes a PENDING entry
 * to {@code notification_queue} and acknowledges immediately. This scheduler
 * is the only component that makes external HTTP calls (oncall-service, Slack,
 * email, SMS) — in a dedicated scheduled thread, completely decoupled from
 * Kafka consumer throughput.
 *
 * <h2>Pending threshold</h2>
 * Only entries older than {@code pendingThreshold} (default 30 seconds) are
 * processed. This prevents the scheduler from racing against the consumer —
 * a PENDING entry written 5 seconds ago by a consumer that just started is
 * left for the next scheduler run.
 *
 * <h2>ShedLock</h2>
 * Prevents concurrent execution across multiple notification-service instances.
 * Only one instance processes the outbox at a time — prevents duplicate
 * notifications.
 */
@Component
@EnableConfigurationProperties(NotificationSchedulerProperties.class)
public class NotificationScheduler {

    /** ShedLock {@code lockAtMostFor} of {@link #processPendingNotifications}; keep the two in step. */
    static final String LOCK_AT_MOST_FOR = "4m";
    static final Duration LOCK_AT_MOST_FOR_DURATION = Duration.ofMinutes(4);

    /**
     * Room left for the entry in flight when the budget runs out: its database
     * work and the channels that do not say how long they take; a channel that
     * does ({@link NotificationChannel#worstCaseSendTime}, Slack's retries) adds
     * its own on top (review of backlog #0-103).
     */
    static final Duration LOCK_MARGIN = Duration.ofSeconds(30);

    private static final Logger log =
            LoggerFactory.getLogger(NotificationScheduler.class);

    private final NotificationQueueRepository queueRepository;
    private final NotificationService notificationService;
    private final NotificationPersistenceService persistenceService;
    private final SlackMessageStore messageStore;
    private final TenantWorkGuard workGuard;
    private final Duration pendingThreshold;
    private final Duration lookupRetryWindow;
    private final Duration processingBudget;
    private final int batchSize;
    private final Duration slackMessageTsRetention;

    public NotificationScheduler(
            NotificationQueueRepository queueRepository,
            NotificationService notificationService,
            NotificationPersistenceService persistenceService,
            SlackMessageStore messageStore,
            TenantWorkGuard workGuard,
            NotificationSchedulerProperties properties,
            List<NotificationChannel> channels) {
        this.queueRepository = queueRepository;
        this.notificationService = notificationService;
        this.persistenceService = persistenceService;
        this.messageStore = messageStore;
        this.workGuard = workGuard;
        this.pendingThreshold = properties.pendingThreshold();
        this.lookupRetryWindow = properties.lookupRetryWindow();
        this.processingBudget = validated(properties.processingBudget(), worstCaseSends(channels));
        this.batchSize = properties.batchSize();
        this.slackMessageTsRetention = properties.slackMessageTsRetention();
    }

    /**
     * Fails at startup if the processing budget would let a run outlive the
     * ShedLock. A budget of 5 minutes, set through an environment variable, would
     * otherwise silently bring back the double processing across replicas that the
     * budget exists to prevent: another replica takes the lock while this run is
     * still walking the same PENDING entries.
     *
     * <p>The budget is checked between entries, so the lock must also outlast the
     * entry started just before the budget ran out: {@link #LOCK_MARGIN}, plus the
     * time the channels say a send can take at most. Review of backlog #0-103: once
     * Slack's retry ran on the send path, a Slack that hangs costs three attempts of
     * connect and read timeout per call, twice per entry (broadcast and DM), which
     * the fixed 30 s margin alone did not cover.
     *
     * @param worstCaseSends the longest the channels' sends of one entry can take
     *                       beyond {@link #LOCK_MARGIN}
     */
    static Duration validated(Duration budget, Duration worstCaseSends) {
        final Duration limit = LOCK_AT_MOST_FOR_DURATION.minus(LOCK_MARGIN).minus(worstCaseSends);
        if (budget.isZero() || budget.isNegative() || budget.compareTo(limit) > 0) {
            throw new IllegalArgumentException(
                    "notification.scheduler.processing-budget must be positive and at most " +
                            limit + " (the lock duration " + LOCK_AT_MOST_FOR_DURATION +
                            " minus a " + LOCK_MARGIN + " margin and the " + worstCaseSends +
                            " the channels' sends of the entry in flight can take, e.g. Slack's retries " +
                            "and timeouts), was " + budget);
        }
        return budget;
    }

    private static Duration worstCaseSends(List<NotificationChannel> channels) {
        return channels.stream()
                .map(NotificationChannel::worstCaseSendTime)
                .reduce(Duration.ZERO, Duration::plus);
    }

    /**
     * Processes all PENDING outbox entries older than the pending threshold.
     *
     * <p>Each entry is processed independently — a failure on one entry
     * (e.g. oncall-service unavailable for one tenant) does not prevent
     * processing of other entries.
     *
     * <p>TenantContext is set per-entry and cleared in finally — no tenant
     * context leaks between entries even in the same scheduler run.
     *
     * <p>Backlog #0-82, step 2b: a suspended tenant's entries are held back,
     * not sent and not marked: left out by the query once the pause sync has
     * the tenant in {@code notification_paused_tenants}, and by
     * {@link TenantWorkGuard} before that. All are sent once it is resumed.
     *
     * <h2>Fixed (backlog #42): direct repository.save() in this catch
     * block</h2>
     * Previously called {@code queueRepository.save(entry)} directly here
     * — the one spot in this scheduler that broke the platform's
     * established convention (already followed by
     * {@code AuthEmailScheduler}, {@code PostmortemRetryScheduler}, and
     * {@code IncidentEventOutboxScheduler}) of never touching a
     * repository directly from a scheduler, always delegating through a
     * dedicated persistence service. Not a functional bug on its own —
     * this single call, outside any open transaction, got its own short
     * implicit one from Spring Data JPA regardless — but inconsistent
     * with how every other scheduler in this codebase handles the same
     * kind of write. Now delegates to
     * {@code NotificationPersistenceService.markFailed(...)}, wrapped in
     * the same defensive try/catch as before (a secondary failure
     * recording the failure must not prevent processing of the rest of
     * the batch — same reasoning as {@code EscalationScheduler}'s
     * {@code recordFailedAttemptSafely}, backlog #41).
     *
     * <h2>Backlog #0-25: the catch-all never overwrites a terminal status</h2>
     * {@code processEntry} can throw after it has already closed the entry
     * (an UNDELIVERABLE that committed, then a failing operator alert). The
     * {@code markFailed} below is a conditional UPDATE from PENDING, so it
     * then changes nothing: the entry stays UNDELIVERABLE with its reason and
     * time, and the stale write is logged and counted
     * ({@code notification.queue.stale_write}) by the persistence service.
     */
    @Scheduled(
            fixedDelayString = "${notification.scheduler.interval-ms:30000}",
            initialDelayString = "30000"
    )
    @SchedulerLock(
            name = "notification-service:processPendingNotifications",
            lockAtMostFor = NotificationScheduler.LOCK_AT_MOST_FOR,
            lockAtLeastFor = "10s"
    )
    public void processPendingNotifications() {
        final Instant threshold = Instant.now().minus(pendingThreshold);
        final List<NotificationQueueEntry> pending =
                queueRepository.findPendingOlderThan(threshold, PageRequest.of(0, batchSize));

        if (pending.isEmpty()) {
            log.debug("Notification outbox: no PENDING entries to process");
            return;
        }

        log.info("Notification outbox: found {} PENDING entries to process",
                pending.size());

        // One run must finish inside the ShedLock (lockAtMostFor = 4m): a run that
        // outlives it lets a second replica start on the same PENDING entries. So a
        // run stops after processingBudget and leaves the rest for the next cycle,
        // but always processes at least one entry so it can never stall on the budget.
        // The clock starts before the prefetch, which counts against the budget
        // (found in review: started after it, the prefetch's up to 10 s came out
        // of the margin left for the entry in flight when the budget runs out).
        final Instant deadline = Instant.now().plus(processingBudget);

        // Backlog #0-82 (review): the batch's tenants' statuses are looked up
        // together first, so the per-row guard reads the cache instead of waiting
        // tenant after tenant while auth-service is slow.
        workGuard.prefetch(pending.stream().map(NotificationQueueEntry::getTenantId).toList());
        int processed = 0;
        int leftPending = 0;

        for (final NotificationQueueEntry entry : pending) {
            if (processed > 0 && Instant.now().isAfter(deadline)) {
                log.warn("Notification outbox: processing budget of {} used up — " +
                                "{} of {} entries are left for the next cycle",
                        processingBudget, pending.size() - processed, pending.size());
                break;
            }
            processed++;

            // Inside the try: set refuses an invalid tenant id, and that must stay
            // this entry's failure, not end the batch (backlog #0-92).
            try {
                TenantContext.set(entry.getTenantId());
                // Backlog #0-82, step 2b: the query leaves out the tenants in
                // notification_paused_tenants; this covers a suspension the pause
                // sync has not seen yet (up to about 20 s). The entry stays PENDING,
                // untouched, and is sent when the tenant resumes.
                if (!workGuard.mayRun(entry.getTenantId())) {
                    continue;
                }
                notificationService.processEntry(entry);
            } catch (OncallLookupUnavailableException e) {
                if (handleLookupUnavailable(entry, e, "oncall-service",
                        UndeliverableReason.ONCALL_UNAVAILABLE)) {
                    leftPending++;
                }
            } catch (SlackWorkspaceLookupUnavailableException e) {
                // Backlog #0-21: only reaches here when Slack was the contact's sole
                // reachable channel (the router skips Slack otherwise), so holding the
                // entry delays nothing else. Same retry window as the on-call lookup.
                if (handleLookupUnavailable(entry, e, "auth-service",
                        UndeliverableReason.SLACK_WORKSPACE_UNAVAILABLE)) {
                    leftPending++;
                }
            } catch (Exception e) {
                // The exception with its stack trace, not its message spliced into
                // the line (backlog #0-93, review): the message may quote a
                // provider's text, and #0-94 has not made log lines safe yet.
                log.error("Unexpected error processing notification queue entry: " +
                                "incidentId={}, eventType={}",
                        entry.getIncidentId(), entry.getEventType(), e);

                try {
                    // Backlog #0-93: the exception's type only, as everywhere the
                    // platform records a failure it did not anticipate; its
                    // message may quote SQL, a URL or a response body.
                    persistenceService.markFailed(entry, AuditText.unexpected(e));
                } catch (Exception markFailedEx) {
                    log.error("Failed to mark queue entry as FAILED: " +
                                    "incidentId={}, error={}",
                            entry.getIncidentId(), markFailedEx.getMessage());
                }
            } finally {
                TenantContext.clear();
            }
        }

        if (leftPending > 0) {
            log.warn("Notification outbox: a routing lookup (oncall-service or " +
                            "auth-service) is unavailable — {} entries stay PENDING and are retried for up to {} " +
                            "from their first failed lookup",
                    leftPending, lookupRetryWindow);
        }
    }

    /**
     * Backlog #0-19: oncall-service could not answer the lookup that decides who
     * is notified. The lookup runs before anything is sent, so the entry is
     * untouched: it stays PENDING and the next cycle tries it again, until the
     * lookup has been failing for {@code lookupRetryWindow}. After that it is
     * parked as UNDELIVERABLE and the operator is told.
     *
     * <p>The window runs from the entry's <em>first failed lookup</em>, not from
     * its creation. Measured from creation, an entry that had already waited
     * longer than the window (a restart, a long outage) was parked by a single
     * transient failure, and a whole backlog at once: the escalation denial this
     * item set out to remove, with a longer horizon.
     *
     * <p>Before #0-19, the outage was read as "nobody on call": the entry was
     * marked SENT and never retried.
     *
     * <p>Backlog #0-21 reuses the same window for auth-service's Slack-workspace
     * lookup, in the one case the router lets it through (Slack was the only
     * reachable channel). Both share {@code first_lookup_failure_at}: one entry
     * waits on at most one lookup per cycle, and reusing the column avoids a
     * migration for a second, parallel window.
     *
     * @param dependency   the service that could not answer, for logs only
     * @param giveUpReason recorded when the window is used up
     * @return true if the entry was left PENDING for another attempt
     */
    private boolean handleLookupUnavailable(NotificationQueueEntry entry,
                                            RuntimeException cause,
                                            String dependency,
                                            UndeliverableReason giveUpReason) {
        // Only the first failure is recorded; the entry loaded on later cycles already
        // has it, and writing again would cost a transaction per entry per cycle for
        // nothing. The UPDATE itself also stores a time only where none is set and the
        // entry is still PENDING (backlog #0-25), so a stale entry never moves the
        // window. The entry in memory is not updated: the window below then runs from
        // now, which a just-recorded failure would give too.
        if (entry.getFirstLookupFailureAt() == null) {
            try {
                persistenceService.recordLookupFailure(entry);
            } catch (Exception e) {
                // Not recorded: the next cycle records it again. That only ever makes
                // the window longer, never shorter.
                log.error("Failed to record the failed lookup on the queue entry: " +
                                "incidentId={}, error={}",
                        entry.getIncidentId(), e.getMessage());
            }
        }

        final Instant since = entry.getFirstLookupFailureAt() != null
                ? entry.getFirstLookupFailureAt() : Instant.now();
        final Duration failingFor = Duration.between(since, Instant.now());

        if (failingFor.compareTo(lookupRetryWindow) < 0) {
            log.debug("{} unavailable — entry stays PENDING: " +
                            "incidentId={}, eventType={}, failingFor={}, error={}",
                    dependency, entry.getIncidentId(), entry.getEventType(), failingFor,
                    cause.getMessage());
            return true;
        }

        log.error("{} still unavailable after the retry window — " +
                        "giving up: incidentId={}, eventType={}, failingFor={}",
                dependency, entry.getIncidentId(), entry.getEventType(), failingFor);

        try {
            notificationService.markUndeliverable(
                    entry, giveUpReason);
        } catch (Exception e) {
            log.error("Failed to mark queue entry as UNDELIVERABLE: " +
                            "incidentId={}, error={}",
                    entry.getIncidentId(), e.getMessage());
        }
        return false;
    }

    /**
     * Deletes {@code slack_message_ts} rows older than
     * {@code slackMessageTsRetention} (default 7 days).
     *
     * <p>Most rows are removed immediately after a successful Slack ACK
     * update ({@code SlackMessageStore.removeAllForIncident}, called from
     * {@code SlackActionService}). This job only catches the remainder:
     * incidents acknowledged some other way (e.g. the web UI instead of
     * the Slack button), whose rows would otherwise accumulate forever.
     *
     * <p>Runs once per hour by default — far less frequently than the
     * outbox processor, since this is pure housekeeping with no latency
     * requirement. Uses the same ShedLock instance name pattern as
     * {@link #processPendingNotifications} to prevent concurrent cleanup
     * across replicas (harmless if it did run concurrently — DELETE is
     * naturally idempotent — but avoids redundant work).
     */
    @Scheduled(
            fixedDelayString = "${notification.scheduler.slack-ts-cleanup-interval-ms:3600000}",
            initialDelayString = "60000"
    )
    @SchedulerLock(
            name = "notification-service:cleanupOldSlackMessageTs",
            lockAtMostFor = "4m",
            lockAtLeastFor = "10s"
    )
    public void cleanupOldSlackMessageTs() {
        final Instant threshold = Instant.now().minus(slackMessageTsRetention);
        final int deleted = messageStore.deleteOlderThan(threshold);

        if (deleted > 0) {
            log.info("Slack message ts cleanup: deleted {} entries older than {}",
                    deleted, slackMessageTsRetention);
        } else {
            log.debug("Slack message ts cleanup: nothing to delete");
        }
    }
}