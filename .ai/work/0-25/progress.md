# #0-25 A stale `notification_queue` write can overwrite a terminal status

Append-only. One line per step: `- [<stage> r<round>] <result>` — never rewrite an earlier line. The
autopilot reads the last `NEXT:` line to resume an interrupted run.

- [picker] picked; branch `<prefix>/<item-id>-<slug>`; base `<sha>`
- [architect] plan: <one line>; ADR: <none | NNNN (Proposed)>
- [implementer r0] commits <sha>..<sha>; <n> files; tests: <classes>
- [tests r0] PASS | FAIL (exit <code>, log `.ai/runs/<item>/tests-r0.log`)
- [review r1] general APPROVE · architecture APPROVE · security CHANGES_REQUESTED (sec-7f3a) · …
- [implementer r1] fixed sec-7f3a in <sha>
- [acceptance] ACCEPT | REJECT (AC2 missing evidence) | NEEDS_HUMAN (<reason>)
NEXT: <stage>
- [start] started by start-item.sh; branch `refactor/0-25-notification-queue-stale-write-guard`; base `84f86049282cde6081dc1bf560bcde9b2ecafcc2`
NEXT: architect
- [architect] plan: four tenant-scoped conditional UPDATEs from PENDING in NotificationQueueRepository (AuthEmailOutboxRepository precedent), persistence methods return boolean, 0 rows logged and counted in notification.queue.stale_write{operation}, no audit/alert on a stale markUndeliverable, entity mutators removed, architecture.md criterion; ADR: 0059 (Proposed); modules: notification-service, root; rules: GEN-01, GEN-02, GEN-04, GEN-05, GEN-07, GEN-08, GEN-20, GEN-32, ARC-02, ARC-26, ARC-29, ARC-22, SEC-06, SEC-31, DOC-01, DOC-10, DOC-11, DOC-30
NEXT: implementer
- [implementer r0] commits 2cbcde35 + handoff commit; 11 code/doc files + handoff/proofs; tests: NotificationQueueStaleWriteIntegrationTest (new), NotificationPersistenceServiceTest, NotificationServiceTest, NotificationEscalationSchemaIntegrationTest, AuditOutboxPersistenceIntegrationTest; local `./mvnw -q verify -pl notification-service -am` finished without error
- [implementer rules] GEN-01: NotificationQueueStaleWriteIntegrationTest (each guard), NotificationPersistenceServiceTest#staleWriteIsCountedPerOperation, NotificationServiceTest$Undeliverable#markUndeliverableOnAStaleRowRaisesNoOperatorAlert
- [implementer rules] GEN-02: NotificationPersistenceServiceTest#staleWriteIsCountedPerOperation / #markUndeliverableOnAStaleRowWritesNoAuditEvent (0 rows)
- [implementer rules] GEN-04: NotificationQueueStaleWriteIntegrationTest, Testcontainers postgres:16-alpine
- [implementer rules] GEN-05: NotificationQueueStaleWriteIntegrationTest#aTransitionWithAnotherTenantChangesNothing
- [implementer rules] GEN-07: NotificationQueueStaleWriteIntegrationTest compares JDBC reads with JDBC reads; registry cleared and queue emptied per test
- [implementer rules] GEN-08: handoff.md "Tests changed and why"
- [implementer rules] GEN-20: Javadoc of NotificationQueueRepository's new UPDATEs (why not @Version), NotificationQueueEntry class Javadoc, NotificationPersistenceService class Javadoc
- [implementer rules] GEN-32: NotificationQueueRepository markSent/markFailed/markUndeliverable/recordLookupFailure WHERE status = 'PENDING'
- [implementer rules] ARC-02: shape of AuthEmailOutboxRepository/AuthEmailPersistenceService.recordSent (int row count, boolean return)
- [implementer rules] ARC-26: the four new @Modifying carry flushAutomatically = true with clearAutomatically = true
- [implementer rules] ARC-29: guard on status = 'PENDING', row count checked in NotificationPersistenceService.applied; second writer restartLookupRetryWindows covered by #restartIsNotUndoneByAStaleSchedulerWrite
- [implementer rules] ARC-22: NotificationPersistenceService.markUndeliverable publishes NOTIFICATION_UNDELIVERABLE in the same transaction, only after 1 row
- [implementer rules] SEC-06: AND e.tenantId = :tenantId in all four UPDATEs
- [implementer rules] SEC-31: NotificationPersistenceService.applied logs operation, entry id, incidentId, tenant only
- [implementer rules] DOC-01: .ai/context/architecture.md criterion; ADR-0059 present (Proposed) and indexed
- [implementer rules] DOC-10: grep "one writer after its INSERT", "two such exceptions", "can write its old value back": architecture.md and the repository Javadoc changed; ARC-29 (level A) replacement text in handoff.md
- [implementer rules] DOC-11: @return of the four persistence methods, restartLookupRetryWindows Javadoc, scheduler catch-all Javadoc and recordLookupFailure comment, NotificationService.markUndeliverable comment/Javadoc
- [implementer rules] DOC-30: architecture.md text states the criterion, not a history
NEXT: tests
- [implementer self-check] .ai/rules/review/migration.md: MIG-01..MIG-09 — nothing to fix: no migration file added or changed; the only entity change (NotificationQueueEntry) removes four mutator methods, no @Column/@Table/@Version/relation changed, so MIG-03 holds against the existing schema
- [implementer self-check] .ai/rules/review/performance.md: PERF-01, PERF-02, PERF-03, PERF-23, PERF-31 apply — nothing to fix: no new loop or per-element query (each UPDATE replaces a merge's SELECT+UPDATE with one statement per entry already processed); the four UPDATEs filter by the primary key id (plus tenant_id, status), served by the PK index; no new list query; markUndeliverable's audit event goes through the existing outbox (AuditEventPublisher, backlog #0-84), no remote call in the transaction; the stale_write counter has one closed tag (operation, four values); PERF-10..12, PERF-20..22, PERF-30, PERF-40 not applicable (no consumer, synchronized, executor, @Scheduled frequency/batch, findAll or outbound client changed)
