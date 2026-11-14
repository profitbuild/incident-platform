# Execution queue — 2026-11-14

<!-- queue:start -->
| # | Item | Why here |
|---|---|---|
| 1 | #0-58 | ready; a guard: tests only, in `shared`, for the error path of all 7 services; Medium, Risk low |
| 2 | #0-25 | ready; Medium, notification-service, Risk low, no migration |
| 3 | #0-23 | ready; Low, notification-service right after #0-25, Complexity low |
| 4 | #0-245 | without an Autopilot line: the queue stops here until /ready; Medium bug in `shared`, its test goes into #0-58's new test class |
<!-- queue:end -->

## Items

### 1. #0-58 — `GlobalExceptionHandler` and `UnauthorizedEntryPoint` have no tests of their own in `shared`
Two new unit test classes, `GlobalExceptionHandlerTest` (`shared/exception`) and `UnauthorizedEntryPointTest`
(`shared/security`). They use JUnit 5 and Mockito, with no Spring context and no new dependency. They pin each handler's
status, error code, redaction, `requestId` source and body (AC1–AC12), and lift both classes above 60% LINE (AC13).
· Touches: shared (src/test: com.incidentplatform.shared.exception, com.incidentplatform.shared.security). Checked against
the code and unchanged: `GlobalExceptionHandler` is in `shared/src/main/.../shared/exception/`, and neither test class exists yet
(`shared/src/test/.../shared/exception/` has no files).
· Risk low / Complexity medium.
· First because it is a guard. Both classes sit on the error path of every service (every 4xx/5xx body, every 401), so
tests where they are defined protect every later item that touches error handling, #0-245 first among them. It is test
code only and Medium priority. It is also a first run for #0-238's AC5 in the build VM that already needs its rootless Docker:
its own tests use none, but the test gate runs `./mvnw verify` of all of `shared`, and `shared`'s tests include
Testcontainers ones (`DeadLetterPublisherKafkaIntegrationTest`, Kafka).

### 2. #0-25 — A stale `notification_queue` write can overwrite a terminal status
The four writers of `NotificationQueueEntry` (`markSent`, `markFailed`, `markUndeliverable`, `recordLookupFailure`)
become state-guarded conditional `UPDATE ... WHERE status = 'PENDING'`s that return a row count. A count of 0 is
logged and counted in `notification.queue.stale_write`, and nothing else happens. There is no migration.
`.ai/context/architecture.md` gets the `@Version`-vs-conditional-UPDATE criterion (AC5).
· Touches: notification-service (domain, repository, service, scheduler; src/test), root (.ai/context/architecture.md).
Checked against the code and unchanged. The four methods and `restartLookupRetryWindows` are in `domain/NotificationQueueEntry`,
`repository/NotificationQueueRepository`, `service/NotificationPersistenceService`, `service/NotificationService`,
`scheduler/NotificationScheduler` and `scheduler/NotificationPausableWork`. The sentence AC5 replaces ("An outbox row has
one writer after its INSERT … the two such exceptions") is in `.ai/context/architecture.md:24`.
· Risk low / Complexity medium (Testcontainers `postgres:16-alpine`, so Docker in the VM).
· Second because it is Medium priority and restores a decided pattern. It does not conflict with ADR-0015, whose
outbox it copies. It comes before #0-23 because of priority, which outweighs small-before-large. Its new test runs on the build VM's
rootless Docker (Testcontainers Postgres), as the first run's gate already does with Kafka.

### 3. #0-23 — The `oncall` and `slack-workspace` `@Retry` never fires
The item removes `@Retry` from `OncallClientImpl`'s three lookups and from `SlackWorkspaceClientImpl`, and removes their
`resilience4j.retry.instances` from `application.yml`. A new proxy-level WireMock test runs the oncall client, and
`SlackWorkspaceClientResilienceTest` stops pinning `max-attempts`. The comments, README's "Resilience" row and
ADR-0016 are updated.
· Touches: notification-service (client; src/main/resources/application.yml; src/test), root (README.md "Resilience"
row, .ai/decisions/0016). Checked against the code and unchanged: `@Retry(name = "oncall")` is at `OncallClientImpl:75,127,178`
and `@Retry(name = "slack-workspace")` at `SlackWorkspaceClientImpl:77`. Both retry instances are in `application.yml`
(`:398`, `:414`). The README row is `README.md:199`, and ADR-0016's two lines are `:50` and `:64`.
· Risk low / Complexity low.
· Third: Low priority, and in the same module as #0-25, so it builds on the notification-service that #0-25 left in a reviewed
state. The two items touch different packages (client and config vs. domain, repository, service and scheduler), so
neither depends on the other. It is the third AC5 item.

### 4. #0-245 — Validation errors do not redact `apiKey` and `privateKey` fields
`GlobalExceptionHandler.isSensitiveField` lower-cases the field name but compares it with the mixed-case entries `apiKey` and
`privateKey`, so those values are echoed back in a 400 body. The fix lower-cases the set (or compares case-insensitively),
tests every entry in more than one case form, and checks the services' request DTOs for missing names.
· Touches (proposed, for `/ready`; not written, the item has no `**Autopilot:**` line): shared (exception; src/test:
com.incidentplatform.shared.exception), and, if AC2 finds a missing name, nothing else, because the set lives in `shared`.
Probably root (README.md "Infrastructure Hardening"), since it closes a gap in a security control (`ready.md` point 8).
`/ready` should settle that.
· Risk low or high is for `/ready`: the fix changes `shared` and so all 7 services, and it narrows what an error body shows
(a security control, not a contract) / Complexity low.
· After #0-58, because its test goes into `GlobalExceptionHandlerTest`, the class #0-58 creates. It is last because it is
**not ready** (no `**Autopilot:**` line, criteria without a Touches): the queue stops here until the owner runs
`/ready #0-245`. Putting it at row 2 would have stopped the queue before the two notification items that #0-238's AC5 needs.

## Not queued
- #0-2, #0-4, #0-5, #0-6, #0-14, #0-15, #0-17, #0-22, #0-28, #0-33, #0-34, #0-36, #0-38, #0-44, #0-45, #0-46,
  #0-62, #0-68, #0-70, #0-71, #0-72, #0-73, #0-74, #0-86, #0-99, #0-102, #0-105, #0-117, #0-133, #0-134, #0-135,
  #0-151, #0-218, #0-219, #0-229, #0-246: no `**Autopilot:**` line, so each needs `/ready` first. #0-245 was chosen
  ahead of them (Medium, it follows #0-58). Several of them are `.github/` work and would be human-only (#0-2, #0-62,
  #0-68, #0-70, #0-134, #0-135, #0-151). #0-15 is deferred to #0-35. #0-133 is an event contract change (Risk high).
  #0-28 (purging `notification_queue`) is a candidate after #0-25, in the same table. #0-229 (ingestion-service, Low)
  has a Touches but no Autopilot line. #0-246 says itself that it is not a guard and should be split by service first.
- #0-208: not-ready. Its approach (a)/(b)/(c) is still to decide, and it reaches five services plus `shared`, beyond
  `ready.md` point 4.
- #0-193: not-ready. Its Touches names `.ai/rules/review/security.md` (owner), and A or B is still to decide.
- #0-110: not-ready, Risk high (a new Maven Enforcer plugin in the root `pom.xml`).
- #0-111, #0-112: not-ready. Each is a CI check that needs a new `.github/` step, so human-only or an owner-first split.
- #0-159: not-ready. `**Risk:** medium` is not a value of the convention, and its approach is still to analyse.
- #0-190: not-ready. Its Touches is in protected paths (`scripts/factory/`, `.claude/`).
- #0-69, #0-108, #0-136, #0-152, #0-155, #0-156, #0-167, #0-171, #0-183, #0-188, #0-201, #0-204, #0-205, #0-210,
  #0-211, #0-212, #0-213, #0-214, #0-217, #0-221, #0-224, #0-225, #0-226, #0-227, #0-228, #0-230, #0-231, #0-232,
  #0-234, #0-236, #0-238, #0-239, #0-242, #0-243, #0-244: human-only. Most are factory or CI work in protected paths,
  and several are frozen as superseded by ADR-0055. #0-188 is a `shared` logging change for all 7 services. #0-238 is
  the owner's stage 2, which this queue serves (its AC5).
- #0-3, #0-13, #0-20, #0-24, #0-31, #0-32, #0-35, #0-37, #0-40, #0-41, #0-43, #0-48, #0-55, #0-56, #0-64, #0-65,
  #0-66, #0-67, #0-75, #0-77, #0-79, #0-85, #0-87, #0-94, #0-95, #0-97, #0-98, #0-101, #0-106, #0-107, #0-116,
  #0-139, #0-140, #0-143, #0-153, #0-158, #0-178, #0-202: type `design`. #0-116, #0-153, #0-158, #0-178 and #0-202
  are also human-only.

## Changes to BACKLOG.md in this proposal
- None. The Touches of #0-58, #0-25 and #0-23 (all written in `/ready` on 2026-11-14) agree with the code, and none of
  the three depends on another: #0-58 is `shared` tests, and #0-25 and #0-23 are separate packages of notification-service.
  #0-245 has no `**Autopilot:**` line, so there is no line to put a Touches or a `**Depends on:**` under. For `/ready #0-245`:
  its proposed Touches is above, and `**Depends on:** #0-58` is worth recording, because its AC1 test belongs in the
  `GlobalExceptionHandlerTest` that #0-58 creates.
- The open Renovate PRs (#165 apache/kafka 4, #166 eclipse-temurin 25, #171 postgres 18) change image tags, not the
  classes these items touch. The Testcontainers tests of #0-25 pin `postgres:16-alpine` in code, so #171 does not change them.
