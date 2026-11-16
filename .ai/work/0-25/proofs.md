# Proofs: #0-25

Each acceptance criterion and the evidence that shows it (`.ai/rules/acceptance.md`). No pasted logs and
no secrets: the full output is in `.ai/runs/<item>/` (gitignored), named here.

| Criterion | Evidence | Kind |
|---|---|---|
| AC1 | `NotificationQueueStaleWriteIntegrationTest#noTransitionChangesATerminalRow` (4 writes x SENT/FAILED/UNDELIVERABLE, Testcontainers `postgres:16-alpine`) asserts the repository UPDATE's row count is 0, the JDBC-read row equals the one read before, and the persistence method returns `false`; `#eachTransitionChangesAPendingRow` asserts row count 1 and the stored status, `error_message`, `processed_at` or `first_lookup_failure_at` on a PENDING row; `#aTransitionWithAnotherTenantChangesNothing` asserts 0 for another tenant's id | test |
| AC2 | `NotificationQueueStaleWriteIntegrationTest#catchAllAfterCommittedUndeliverableLeavesItUndeliverable` drives a real `NotificationScheduler` without a test transaction; `processEntry` commits UNDELIVERABLE then throws; after the run the row (status, `error_message`, `processed_at`, `first_lookup_failure_at`) equals the JDBC read taken right after the UNDELIVERABLE, and `notification.queue.stale_write{operation=failed}` is 1 | test |
| AC3 | `NotificationPersistenceServiceTest#markUndeliverableOnAStaleRowWritesNoAuditEvent` (0 rows: `false`, no `AuditEventPublisher` call, `stale_write{undeliverable}` = 1); `NotificationPersistenceServiceTest#staleWriteIsCountedPerOperation` (sent/failed/lookup: 0 rows `false` and counted with that tag only, 1 row `true` and not counted); `NotificationServiceTest$Undeliverable#markUndeliverableOnAStaleRowRaisesNoOperatorAlert` (no operator alert, `notification.undeliverable` 0) | test |
| AC4 | `NotificationQueueStaleWriteIntegrationTest#recordLookupFailureKeepsAnExistingTimestamp` (returns `false`, stored value equals the earlier DB read); `#restartIsNotUndoneByAStaleSchedulerWrite` (entry loaded with T; after `restartLookupRetryWindows` a `recordLookupFailure` of the loaded entry stores a time after T, not T; after a second restart a `markSent` of it leaves `first_lookup_failure_at` NULL) | test |
| AC5 | `.ai/context/architecture.md` "Patterns already decided": the "An outbox row has one writer after its INSERT … so whichever commits first wins." sentence replaced by the criterion, naming the auth email outbox, `AuthToken.markUsedIfUnused`, `mfa_recovery_requests`, `notification_queue`, and `EscalationTask` with `resumePendingTimers` bumping `version` | docs |
| AC6 | `./mvnw -q verify -pl notification-service -am` ran locally on commit 2cbcde35 and finished without an error (jar and JaCoCo site written); the gate's run is authoritative | command |

Test run: `./mvnw -q verify -pl notification-service -am` — the implementer's run was not saved to a file (no output redirection in this session); the autopilot gate's log is `.ai/runs/0-25/tests-r0.log`.
