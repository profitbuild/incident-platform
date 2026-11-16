package com.incidentplatform.notification.repository;

import com.incidentplatform.notification.domain.NotificationQueueEntry;
import com.incidentplatform.notification.domain.NotificationQueueStatus;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Repository
public interface NotificationQueueRepository
        extends JpaRepository<NotificationQueueEntry, UUID> {

    /**
     * The paused-tenants table {@link #findPendingOlderThan} names (backlog
     * #0-82, step 2b); {@code NotificationPausableWork} reports it, and startup
     * fails unless it is {@code tenant-pause.table}, the table the sync writes.
     */
    String PAUSED_TABLE = "notification_paused_tenants";

    /**
     * Finds PENDING outbox entries older than {@code pendingThreshold}.
     *
     * <p>The threshold (e.g. 30 seconds after creation) gives the scheduler
     * a safety margin to avoid racing against a consumer that just wrote the
     * entry and is still within the same scheduler cycle.
     *
     * <p>Oldest first and capped by {@code pageable} (backlog #0-10, the same
     * shape as {@code EscalationScheduler}'s {@code scheduler-batch-size}, backlog
     * #39). Since an entry now stays PENDING while oncall-service is unavailable
     * (backlog #0-19), the list would otherwise grow with the outage and be
     * re-read whole every cycle, and under the run's processing budget an
     * unordered scan could leave the same tail entries unprocessed run after run.
     * Served by the partial index {@code idx_notification_queue_status_created
     * (status, created_at) WHERE status = 'PENDING'}.
     *
     * <h2>Backlog #0-82, step 2b: a suspended tenant's entries are left out</h2>
     * Here, in the query, not skipped in the scheduler: they are the oldest, so
     * skipped after the LIMIT they would fill every batch and hold up every
     * other tenant's notifications. They wait, in order, and are all sent once
     * the tenant is resumed. Native, because the paused table
     * ({@link #PAUSED_TABLE}, which must be {@code tenant-pause.table}) is
     * {@code shared}'s, written over JDBC, and has no entity.
     */
    @Query(value = "SELECT e.* FROM notification_queue e "
            + "WHERE e.status = 'PENDING' "
            + "AND e.created_at < :pendingThreshold "
            + "AND NOT EXISTS (SELECT 1 FROM " + PAUSED_TABLE
            + " p WHERE p.tenant_id = e.tenant_id) "
            + "ORDER BY e.created_at ASC",
            nativeQuery = true)
    List<NotificationQueueEntry> findPendingOlderThan(
            @Param("pendingThreshold") Instant pendingThreshold,
            Pageable pageable);

    /**
     * The tenants with a PENDING entry, paused or not: the candidates the pause
     * sync asks auth-service about (backlog #0-82, step 2b).
     */
    @Query(value = "SELECT DISTINCT e.tenant_id FROM notification_queue e WHERE e.status = 'PENDING' "
            + "ORDER BY e.tenant_id", nativeQuery = true)
    List<String> findTenantsWithPendingEntries();

    /**
     * On resumption (backlog #0-82, step 2b): a PENDING entry whose routing
     * lookup had failed before the pause starts its retry window (backlog
     * #0-19) again. The window runs from the first failed lookup, and it ran on
     * while the entry was held, so the first failure after the resumption would
     * otherwise give it up as UNDELIVERABLE at once. A new window only ever
     * makes it longer, as the scheduler's own comment on recording the failure
     * says.
     *
     * <p>A second writer of a queue entry besides the scheduler: the scheduler
     * reads no row of a paused tenant, and this runs in the transaction that
     * ends the pause, before the scheduler can read the rows again. An entry the
     * scheduler loaded before the tenant was paused and is still processing
     * when the tenant is resumed again (within one run) cannot undo the restart
     * (backlog #0-25, ADR-0059): the scheduler writes a row only through the
     * conditional UPDATEs below, none of which writes
     * {@code first_lookup_failure_at} back from what it loaded, and
     * {@link #recordLookupFailure} stores the time of its own call, so the
     * window it starts is a new one.
     *
     * @return the entries whose window starts again
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query(value = """
            UPDATE notification_queue
               SET first_lookup_failure_at = NULL
             WHERE tenant_id = :tenantId
               AND status = 'PENDING'
               AND first_lookup_failure_at IS NOT NULL
            """, nativeQuery = true)
    int restartLookupRetryWindows(@Param("tenantId") String tenantId);

    // ── Backlog #0-25 (ADR-0059): every change of an existing row ──────────
    //
    // After its INSERT an entry changes only through the state-guarded
    // conditional UPDATEs below (and restartLookupRetryWindows above), never
    // through a save() of a loaded entity: a merge writes every mapped column
    // as it was loaded, so a stale writer (a run that outlived its ShedLock,
    // an old pod in a rollout, the scheduler's catch-all after markUndeliverable
    // had committed) overwrote a terminal status. Each UPDATE applies only to
    // a PENDING row of the given tenant and returns the number of rows changed:
    // 0 means another writer got there first, and the caller records nothing
    // more. Not @Version: the outcome is already decided by whoever won, so
    // there is nothing to retry, and a version column would need a migration
    // and an OptimisticLockingFailureException path in every caller (the auth
    // email outbox's shape, AuthEmailOutboxRepository, backlog #0-52). Flush
    // before, clear after (ADR-0010): markUndeliverable writes its audit event
    // in the same transaction.

    /**
     * SENT once every routed channel has been tried (backlog #0-25,
     * ADR-0059): only while the entry is still PENDING.
     *
     * @return 1 if the entry was PENDING and is now SENT, 0 otherwise
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("UPDATE NotificationQueueEntry e SET e.status = 'SENT', e.processedAt = :now "
            + "WHERE e.id = :id AND e.tenantId = :tenantId AND e.status = 'PENDING'")
    int markSent(@Param("id") UUID id, @Param("tenantId") String tenantId,
                 @Param("now") Instant now);

    /**
     * FAILED after an unexpected error in processing (backlog #0-25,
     * ADR-0059): only while the entry is still PENDING, so the scheduler's
     * catch-all never overwrites an UNDELIVERABLE (or SENT) that already
     * committed.
     *
     * @return 1 if the entry was PENDING and is now FAILED, 0 otherwise
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("UPDATE NotificationQueueEntry e SET e.status = 'FAILED', e.errorMessage = :error, "
            + "e.processedAt = :now "
            + "WHERE e.id = :id AND e.tenantId = :tenantId AND e.status = 'PENDING'")
    int markFailed(@Param("id") UUID id, @Param("tenantId") String tenantId,
                   @Param("error") String error, @Param("now") Instant now);

    /**
     * UNDELIVERABLE, nobody in the tenant could be notified (backlog #0-18;
     * guarded by backlog #0-25, ADR-0059): only while the entry is still
     * PENDING.
     *
     * @param reason the {@code UndeliverableReason}'s name, stored as the
     *               entry's {@code error_message}
     * @return 1 if the entry was PENDING and is now UNDELIVERABLE, 0 otherwise
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("UPDATE NotificationQueueEntry e SET e.status = 'UNDELIVERABLE', e.errorMessage = :reason, "
            + "e.processedAt = :now "
            + "WHERE e.id = :id AND e.tenantId = :tenantId AND e.status = 'PENDING'")
    int markUndeliverable(@Param("id") UUID id, @Param("tenantId") String tenantId,
                          @Param("reason") String reason, @Param("now") Instant now);

    /**
     * Records the first failed recipient lookup (backlog #0-19; guarded by
     * backlog #0-25, ADR-0059): only while the entry is still PENDING and has
     * none recorded, so a later failure never moves the start of the retry
     * window, and a scheduler that loaded the entry before
     * {@link #restartLookupRetryWindows} ran writes the time of its own call,
     * not the one it loaded.
     *
     * @return 1 if the time was stored, 0 if the entry is no longer PENDING or
     *         already has one
     */
    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("UPDATE NotificationQueueEntry e SET e.firstLookupFailureAt = :now "
            + "WHERE e.id = :id AND e.tenantId = :tenantId AND e.status = 'PENDING' "
            + "AND e.firstLookupFailureAt IS NULL")
    int recordLookupFailure(@Param("id") UUID id, @Param("tenantId") String tenantId,
                            @Param("now") Instant now);

    /**
     * Idempotency check — prevents duplicate queue entries for the same
     * incident + event + escalation level combination. Called by the
     * consumer before enqueue.
     *
     * <p>{@code escalationLevel} is part of the key because every
     * escalation is an {@code IncidentEscalatedEvent} for the same
     * incident; keyed on incident + event type alone, the level-2 entry was
     * discarded as a duplicate of level 1. It is {@code 0} for every event
     * type that is not an escalation. {@code tenantId} keeps the check
     * tenant-scoped like every other query in this service.
     */
    boolean existsByIncidentIdAndTenantIdAndEventTypeAndEscalationLevel(
            UUID incidentId, String tenantId, String eventType,
            int escalationLevel);
}