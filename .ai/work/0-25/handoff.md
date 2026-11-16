# Handoff: #0-25

Facts only. No reasoning about why the change is good: reviewers judge it themselves. Updated by the
implementer after every round.

## Changed
- `notification-service/.../repository/NotificationQueueRepository.java`: four new JPQL `@Modifying(flushAutomatically = true, clearAutomatically = true)` UPDATEs returning `int`, each `WHERE e.id = :id AND e.tenantId = :tenantId AND e.status = 'PENDING'`: `markSent(id, tenantId, now)`, `markFailed(id, tenantId, error, now)`, `markUndeliverable(id, tenantId, reason, now)` (`reason` is the `UndeliverableReason` name, stored in `error_message`), `recordLookupFailure(id, tenantId, now)` (also `AND e.firstLookupFailureAt IS NULL`). The paragraph of `restartLookupRetryWindows`' Javadoc that said a stale entry "can write its old value back" is rewritten.
- `notification-service/.../domain/NotificationQueueEntry.java`: `markSent()`, `markFailed(String)`, `markUndeliverable(UndeliverableReason)` and `recordLookupFailure()` removed; class Javadoc section on #0-25 / ADR-0059. No `@Column` change, no migration.
- `notification-service/.../service/NotificationPersistenceService.java`: constructor takes a `MeterRegistry`. `markSent`, `markFailed`, `markUndeliverable`, `recordLookupFailure` keep their parameters, call the repository UPDATE with `entry.getId()`, `entry.getTenantId()` and one `Instant.now()` taken in the method, and return `boolean`. On 0 rows: `log.info` with operation, entry id, incidentId, tenant; `notification.queue.stale_write{operation=sent|failed|undeliverable|lookup}` incremented; `false` returned. `markUndeliverable` publishes `NOTIFICATION_UNDELIVERABLE` only after an UPDATE of 1 row. Class Javadoc section on #0-25.
- `notification-service/.../service/NotificationService.java`: `markUndeliverable` returns early (no operator alert, no `notification.undeliverable` count) when the persistence call returns `false`; a write that throws keeps the previous behaviour (alert, rethrow, alert failure suppressed). Comments next to both `markSent` calls.
- `notification-service/.../scheduler/NotificationScheduler.java`: comments only (catch-all Javadoc section on #0-25; the comment above `recordLookupFailure`). Calls unchanged; their boolean is ignored.
- New metric: `notification.queue.stale_write` (tag `operation`).
- `.ai/context/architecture.md` ("Patterns already decided"): the sentence from "An outbox row has one writer after its INSERT" to "so whichever commits first wins." replaced by the criterion of ADR-0059.
- No endpoint, topic, migration or config key changed.

## How to verify
- `./mvnw -q test -pl notification-service -am -Dtest=NotificationQueueStaleWriteIntegrationTest` — Testcontainers Postgres: each write changes a PENDING row; no write changes a SENT/FAILED/UNDELIVERABLE row (row count 0, row unchanged, persistence method false); another tenant's id changes nothing; `recordLookupFailure` keeps a stored time; a restart is not undone; the scheduler's catch-all after a committed UNDELIVERABLE leaves the row as it was.
- `./mvnw -q test -pl notification-service -am -Dtest=NotificationPersistenceServiceTest,NotificationServiceTest` — stale write counted per operation; no audit event and no operator alert for a stale `markUndeliverable`.
- `./mvnw -q verify -pl notification-service -am` — ran locally, finished without an error (tests, JaCoCo check, jar packaged).

## Tests changed and why
All of these follow from AC1: every transition is now a conditional UPDATE, so the entity mutators are removed and the persistence methods return whether the row changed.
- `NotificationPersistenceServiceTest#marksSentAndPersists`, `#marksFailedAndPersists`, `#marksUndeliverableAndAudits`: asserted the in-memory entry's status and `queueRepository.save(entry)`. Now stub the repository UPDATE (by the entry's id and tenant, and the error/reason) to 1 and assert `true`, no `save`, no stale count; `#marksUndeliverableAndAudits` keeps its audit-event assertion unchanged. Constructor call takes a `SimpleMeterRegistry`. New: `#recordsLookupFailure`, `#staleWriteIsCountedPerOperation`, `#markUndeliverableOnAStaleRowWritesNoAuditEvent`.
- `NotificationEscalationSchemaIntegrationTest#queueStoresUndeliverableEntry`: reached UNDELIVERABLE through `entry.markUndeliverable(...)` + `saveAndFlush`; now saves a PENDING entry and calls `queueRepository.markUndeliverable(...)` (asserted to return 1). Same assertions on the reloaded row.
- `NotificationEscalationSchemaIntegrationTest#queueStoresTheFirstLookupFailureOnly`: used `entry.recordLookupFailure()` + `saveAndFlush` twice; now calls `queueRepository.recordLookupFailure(...)` (1, then 0 with a later time). Same assertions: the stored time is within 1 s of the one passed, and unchanged after the second call.
- `NotificationServiceTest$Undeliverable#parksAndAlertsForAnOpenedIncident`, `#alertsForAnEscalation`, `#noAlertForResolved`, `#markUndeliverableForOutage`: one stub added (`persistenceService.markUndeliverable(entry, reason)` returns `true`), because a mocked boolean returns `false`, which now means "stale, no alert". No assertion changed. New: `#markUndeliverableOnAStaleRowRaisesNoOperatorAlert`.
- `AuditOutboxPersistenceIntegrationTest.JpaSliceConfig`: a `SimpleMeterRegistry` `@Bean` added for the new constructor parameter. No test changed.
- `NotificationSchedulerTest`: not changed.

## Deliberately out of scope
- The persistence methods take no `Instant now` parameter (the plan's step 3 wording): each takes one `Instant.now()` itself, so the scheduler's and `NotificationService`'s calls and their existing tests keep their shape (plan step 5, `NotificationSchedulerTest` "stubs adjusted only if Mockito needs them").
- `.ai/rules/review/architecture.md` ARC-29 (level A, owner's file) still reads "An outbox row has one writer after its INSERT" and names only the auth email outbox and `AuthToken.markUsedIfUnused`. Proposed replacement text for the whole bullet:

  > - **ARC-29 The outcome of an irreversible step on a one-way state machine is a state-guarded conditional UPDATE.** A write that records such an outcome (an email sent, a token used, a notification delivered or given up) is `UPDATE ... WHERE id = :id AND <tenant> AND status IN (<the states it may leave>)`, row count checked, never a `save()` of a loaded entity; a count of 0 means another writer got there first and is logged and counted, nothing else (the auth email outbox, `AuthToken.markUsedIfUnused`, `mfa_recovery_requests` #0-90, `notification_queue` #0-25). A row that several places change over time carries `@Version`, and a bulk UPDATE of it bumps `version` (`EscalationTask`, `resumePendingTimers`); ADR-0059. Check: a new UPDATE or `save()` of an outbox or a state-machine row, who else writes it, and its guard.

- auth-service's `SlackWorkspace` Javadoc that cites #0-25 as a `@Version` case: backlog #0-246's, not touched.
- ADR-0059 stays `Proposed` as the architect wrote it.

## Noticed, not touched
- `.ai/audit/benchmark/patterns.md:60` (C-02) describes ARC-29 as "a row that has one writer"; it is benchmark data for the audits, not current documentation of the code — proposed backlog item: align C-02's wording with ADR-0059 when ARC-29 is reworded.

## Follow-up needed

## Disputed
