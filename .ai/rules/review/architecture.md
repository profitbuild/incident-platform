# Review dimension: architecture

Owned by the maintainer; agents never edit it. Sections 2 and 3 were moved from
`.claude/agents/code-reviewer.md` on 2026-10-05 (with ids); sections 1 and 4 were new then. Rewritten as
invariants on 2026-10-26 (backlog #0-115): each rule says what is true of the code, and its "Check:" line what to look
for in a diff. No id changed its meaning. ARC-20 is retired: it was split into ARC-22…ARC-29, one rule per decided
pattern, so a finding names the pattern it is about. ARC-07 (an ADR for a decision CI enforces)
and ARC-43 (the log format) are new; section 4 gave its rules ids (ARC-40…ARC-43).
The `architect` agent reads this file too, before it plans an item.

Read by `review-architecture` (the whole file, for every change) and by the implementer, which reads this file
in full for every item; the architect's plan only adds emphasis to the rules at risk. For the implementer a rule is what
the code must be; for the reviewer, its "Check:" line is where a violation shows. When the diff touches a
path of the Owner-only list of `.ai/rules/protected-paths.md` (e.g. the AI factory, CI, the devcontainer, the
rules themselves), `review-architecture` also reads `factory.md` and judges that part by its `FAC-A` rules
(backlog #0-161).

**No rule is dropped for being general knowledge** (as in `security.md`): a blocking finding must cite a rule
(`_common.md`), and every rule here is this platform's own decision.
`_common.md` defines the two labels ("Enforced by", "Backed by"), the convention of every rule file decided with
this rewrite (#0-115).

Read `.ai/context/architecture.md`, the "Service Map" in `.ai/context/project.md`, and the ADRs whose area
the change touches (`.ai/decisions/README.md`). Judge the change as a part of the whole system: a change
can be locally correct and still make the system worse, with a second mechanism for a solved problem, a
responsibility in the wrong service, or a coupling nobody decided on.

## 1. Boundaries and responsibilities

- **ARC-01 A responsibility lives in the service the Service Map gives it.** One in another service has an ADR that
  puts it there (`NEEDS_HUMAN` if none exists). Check: a new class, endpoint, table, topic or consumer, and the
  service the Service Map names for what it does.
- **ARC-02 One mechanism per problem.** A retry helper, mapper, HTTP client wrapper, cache, scheduler pattern or
  error-handling style that the platform already has is reused, not written again; a second mechanism for a solved
  problem is a finding that names the existing one. Check: a new helper, wrapper or loop, and a search of the code
  for the one that already does it.
- **ARC-03 `shared` is platform-wide policy, not a utility bag.** Domain code of one service stays in that
  service, and a change to `shared` is right for all 7 services. Check: a new class or option in `shared` and how
  many services use it; a branch on one service's needs inside `shared`.
- **ARC-04 Services talk through events or a narrow pull.** An event goes through the outbox, or one service asks
  another over HTTP with a service token (ADR-0003). Reading another service's tables, replicating
  auth-service-owned data over Kafka (#0-30), or a new synchronous dependency in a hot path has an ADR. Check: a new
  client, topic, datasource or table name from another service.
- **ARC-05 A change keeps every ADR it touches.** A change that reverses one comes with a new ADR
  (`Supersedes ADR-NNNN`), otherwise `NEEDS_HUMAN`. Check: the ADRs whose area the diff touches
  (`.ai/decisions/README.md`), against what the diff does.
- **ARC-06 A rejected alternative stays rejected.** Spring State Machine, Kafka Streams, full CQRS and
  RS256/Keycloak were rejected on purpose (README "Design Decisions"); bringing one in is `NEEDS_HUMAN`. Check: a new
  dependency or design that is one of them.
- **ARC-07 A decision CI enforces across the platform has an ADR.** A new rule in a structural check
  (`.github/scripts/`, a CI step that fails the build) records its decision in an ADR in the same PR; #0-42 and
  #0-76 had one (ADR-0026, ADR-0027), #0-29 did not, and #0-137 got ADR-0028 only because review asked. It applies
  to the owner's PRs: no autopilot item changes `.github/` (`.ai/rules/protected-paths.md`). Check: a new or widened
  check, and whether it names an ADR or the PR adds one.

## 2. Shared security configuration (structure)

- **ARC-10 A service extends the shared `SecurityFilterChain`.** It does not fork it; a fork exists only with a
  reason the shared chain's contract cannot meet, because a fork silently takes over CORS and `PUBLIC_PATHS`. This
  is a recurring bug class (commits d80541f, ec4eae4): flag it even if the tests pass. Whether a fork widens access
  is `security`'s SEC-12; here the question is whether forking was needed at all. Check: a new or changed
  `SecurityFilterChain` bean.

## 3. Already-decided patterns

A change that needs retrying, scheduling, publishing or protection against double processing uses the pattern
the platform decided for it (`.ai/context/architecture.md`, "Patterns already decided").

- **ARC-20** retired: split into ARC-22…ARC-29, one rule per pattern, 2026-10-26 (#0-115).
- **ARC-21 Tenant status is locked in one order, with a bounded wait.** The tenant row is locked before token rows,
  everywhere (`TenantRepository.findByIdForUpdate`, `FOR NO KEY UPDATE`); a sign-in reads the status `FOR SHARE`
  (`findStatusForSignIn`) and waits at most `lock_timeout`; a sign-in that consumes a token checks the tenant before
  consuming it. Check: a new lock, a `FOR UPDATE`/`FOR SHARE` query, or a token consumed on a sign-in path, and the
  order it takes its locks in.
- **ARC-22 Lifecycle and audit events go through the outbox.** `incidents.lifecycle` through `IncidentEventOutbox`,
  audit events through `AuditOutbox` (`AuditEventPublisher`, only in a service that sets `audit.outbox.table`); no
  direct send. An event is written in the transaction of the action it records, so a refusal is audited after the
  rollback, not before a throw; an event about something already committed and irreversible (a delivered
  notification) is written after it, and a failure is counted in `audit.event.unrecorded`, not thrown. Check: a new
  `KafkaTemplate.send` or producer call, and an audit call followed by a throw in the same transaction.
- **ARC-23 A job that changes shared state runs under ShedLock.** A `@Scheduled` method that writes, sends or
  claims work takes its lock with `@SchedulerLock` or `LockingTaskExecutor.executeWithLock` (`PausedTenantsSync`). A
  job that must run on every replica says why in its Javadoc (`TenantWebSocketSessions`: sessions are per JVM;
  `OperatorTenantBootstrap.refreshPendingGauge`: a read-only gauge per replica). Check: a new or changed
  `@Scheduled` method, its lock, or the reason it has none.
- **ARC-24 A Kafka listener acknowledges only what it has finished.** It is `MANUAL_IMMEDIATE`, never
  `@Transactional`; it acknowledges a record once processed or once its dead-letter copy is acknowledged
  (`DeadLetterPublisher.deadLetterThenAcknowledge`), and `nack`s a transient failure (`KafkaFailures`). A `return`
  without acknowledging is no retry: the next record's acknowledgement commits the offset past it. The tenant of a
  record is SEC-04's. Check: a new or changed listener, every path out of it, and what each path acknowledges.
- **ARC-25 A mutable entity has an uninitialised `@Version Long`.** `= 0L` makes Spring Data treat a new entity as
  existing, so `save()` merges instead of persisting (#0-47). A row whose outcome writes are state-guarded
  conditional UPDATEs instead is ARC-29's. Check: a new entity or version field, and its initialiser.
- **ARC-26 A bulk update that clears the context also flushes it.** `@Modifying(clearAutomatically = true)` comes
  with `flushAutomatically = true`, or an earlier change to another table in the same transaction is silently
  discarded (ADR-0010, #0-83). Check: a new or changed `@Modifying` query.
- **ARC-27 An outbound notification is checked for idempotency first.** Keyed on incident, tenant, event type and
  escalation level (ADR-0017), before anything is sent. Check: a new send path in a notification channel, and the
  check before it.
- **ARC-28 A retried send is bounded by a deadline.** Retries of an outbound send stop at how long the request is
  worth sending, not after an attempt count: a backoff list whose last step repeats, the last attempt moved to the
  deadline (`AuthEmailRetryPolicy`, #0-52). Check: a new retry, and what ends it.
- **ARC-29 The outcome of an irreversible step on a one-way state machine is a state-guarded conditional UPDATE.** A
  write that records such an outcome (an email sent, a token used, a notification delivered or given up) is
  `UPDATE ... WHERE id = :id AND <tenant> AND status IN (<the states it may leave>)`, row count checked, never a
  `save()` of a loaded entity; a count of 0 means another writer got there first and is logged and counted, nothing
  else (the auth email outbox, `AuthToken.markUsedIfUnused`, `mfa_recovery_requests` #0-90, `notification_queue`
  #0-25). A row that several places change over time, other than by such outcome writes, carries `@Version`, and a
  bulk UPDATE of it bumps `version` (`EscalationTask`, `resumePendingTimers`); ADR-0059. Check: a new UPDATE or `save()` of an outbox or a
  state-machine row, who else writes it, and its guard. (Reworded 2026-11-16, ADR-0059: it said "an outbox row has
  one writer after its INSERT", which #0-25's `notification_queue`, written by the scheduler and the tenant
  resumption, did not fit; its "a request path never updates an existing row" is now this rule's guard: every writer,
  a request path included, changes such a row only by the guarded UPDATE.)

## 4. Platform configuration

Rules a check covers. One marked "Enforced by" is decided in full by its check (`_common.md`), so it has no
"Check:" line and is not reviewed by hand; a check that stops deciding it in full turns its label into "Backed by"
and the rule gets one. Dockerfile/Deployment pairs and Spring profiles in the overlays are `k8s`'s (K8S-01, K8S-04).

- **ARC-40 No Spring profile configuration ships in a jar.** Nothing under `*/src/main/resources` is a profile file,
  a profile-specific document or a key that switches a profile on; configuration reaches a deployed service from its
  environment (#0-81). Enforced by: `check-packaged-profiles.sh`. (A literal secret there is SEC-30's.)
- **ARC-41 Every service but auth-service asks auth-service for a tenant's status.** It sets
  `auth-service.base-url` from `${AUTH_SERVICE_URL}`; without it the service falls back to "every tenant has full
  access" (#0-82). Enforced by: `check-tenant-status-config.sh`.
- **ARC-42 No service has a default database password.** Every committed `spring.datasource.password` is exactly
  `${DB_PASSWORD}`, and every other datasource or Flyway password is a `${VAR}` with no default (#0-66). Enforced by:
  `check-db-password-config.rb`.
- **ARC-43 Every service logs one ECS JSON object per line.** The format is set by `shared`
  (`StructuredLoggingDefaults`) and nothing deployed changes it; `platform.logging.plain-text` is for a developer's
  gitignored `application-local.yml` only (#0-94, ADR-0023). Backed by: `StructuredLoggingGuard` (a service whose
  logs would not be ECS refuses to start; the switch itself it only logs as a WARN) and `check-structured-logging.sh`
  (the usual spellings of the switch, and a Logback file, in tracked files). Check: a tracked file or manifest that
  sets the switch in a spelling Spring binds and the check does not match, a new `logging.structured.*` key, or a
  service that leaves `shared`'s logging out.
- ArchUnit rules: none yet (backlog #0-108). Each rule added there is listed here.

## Output notes

For each finding: **What** (file and line), **Why it matters** (which part of the system gets worse, and
how a later change will trip over it), **Suggested fix** (the existing mechanism to use, or the ADR that
is needed).

## Calibration

Added only by `/apply-audit` from accepted audit recommendations. Empty until the first audit.
