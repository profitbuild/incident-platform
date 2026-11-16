# ADR-0059: The outcome of an irreversible step on a one-way state machine is a state-guarded conditional UPDATE; a row changed over time from several places carries `@Version`

- **Status:** Proposed
- **Backlog:** #0-25
- **Date:** 2026-11-16
- **Author:** architect agent (autopilot run 20261116-191910)
- **Reversible:** yes — no migration; the guard lives in repository queries and can be replaced by a
  `@Version` column later (a new migration, an ADR superseding this one)

## Context

notification-service's `NotificationQueueEntry` had no guard against a stale write.
`NotificationPersistenceService.markSent`, `markFailed`, `markUndeliverable` and `recordLookupFailure` mutated a
detached entity and `save()`d it: a merge that writes every mapped column as it was loaded. Only ShedLock kept two
writers apart; a run that outlives `lockAtMostFor`, an old pod in a rollout, or the scheduler's own catch-all
(`markFailed` after `markUndeliverable` had committed in the same `processEntry`) could overwrite a terminal status.
A second writer exists: `NotificationQueueRepository.restartLookupRetryWindows`, the bulk UPDATE run on a tenant's
resumption, whose Javadoc admitted a stale scheduler entry "can write its old value back".

`.ai/context/architecture.md` listed `@Version` on mutable entities as the decided pattern, with the auth email outbox
(ADR-0015) and `AuthToken.markUsedIfUnused` as "the two such exceptions" using conditional UPDATEs, and
`mfa_recovery_requests` (#0-90) as a several-writer case of the same. escalation-service's `EscalationTask` uses
`@Version`, and its bulk `resumePendingTimers` bumps `version` so a stale `saveAndFlush` loses.

## Decision

The criterion, written into `.ai/context/architecture.md` ("Patterns already decided"):

- A write that **records the outcome of an irreversible step on a row of a one-way state machine** (the email was
  sent, the token was used, the notification was delivered or given up) is a **state-guarded conditional UPDATE**:
  `UPDATE ... WHERE id = :id AND <tenant> AND status IN (<the states it may leave>)`, `@Modifying(flushAutomatically =
  true, clearAutomatically = true)`, returning the row count. A count of 0 means another writer got there first: the
  caller does nothing more (no audit event, no alert) and the case is logged and counted. A field the write sets only
  once is guarded too (`... AND first_lookup_failure_at IS NULL`).
- A row that **several places change over time** (a timer, a level, edited fields) carries an uninitialised
  `@Version Long`, and a bulk UPDATE of it bumps `version` (`EscalationTaskRepository.resumePendingTimers`).

For `notification_queue`: `markSent`, `markFailed`, `markUndeliverable` and `recordLookupFailure` are such UPDATEs from
`PENDING`, scoped by id and tenant; the four `NotificationQueueEntry` mutators are removed, so no code path reaches a
merge of an existing row. A 0 is logged at info and counted in `notification.queue.stale_write{operation}` (`sent`,
`failed`, `undeliverable`, `lookup`). No migration.

## Alternatives considered

- **`@Version` on `NotificationQueueEntry`** (CLAUDE.md's default, `EscalationTask`'s shape): needs a migration and an
  `OptimisticLockingFailureException` path in every caller, and makes `restartLookupRetryWindows` bump `version`. It
  would also make a stale `markFailed` throw where the right answer is "someone already finished this row": the
  outcome is already decided, there is nothing to retry. Lost to the auth email outbox's precedent (#0-52), which is
  the same shape.
- **A row lock (`SELECT ... FOR UPDATE`) before each save**: two statements per transition and a lock held across the
  audit write, for what one UPDATE decides atomically.
- **Mapping the mutable columns `updatable = false`** so a stray `save()` writes nothing: silent (no row count, no
  counter), and it changes JPA semantics in a way a later reader would not expect. Removing the mutators closes the
  same path visibly.

Neither guard prevents a duplicate *send* (detected after the fact); ShedLock stays the guard against that.

## Consequences

- A new UPDATE of an outbox or state-machine row is judged by this criterion; a merge-based `save()` of an existing
  outbox row is a finding.
- The auth email outbox, `AuthToken.markUsedIfUnused`, `mfa_recovery_requests` and `notification_queue` are the
  conditional-UPDATE cases; `EscalationTask` (and auth-service's `SlackWorkspace`) the `@Version` cases.
- `.ai/rules/review/architecture.md` ARC-29 still says "An outbox row has one writer after its INSERT"; aligning its
  text with this criterion is the owner's (level A), proposed in the item's handoff.
- auth-service's `SlackWorkspace` Javadoc still cites #0-25 as a `@Version` case; corrected when that class is next
  changed (backlog #0-246).
