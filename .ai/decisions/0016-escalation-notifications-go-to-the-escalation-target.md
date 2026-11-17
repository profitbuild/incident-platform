# ADR-0016: Escalation notifications go to the escalation target (backlog #0-1)

- **Status:** Accepted
- **Backlog:** #0-1
- **Source:** migrated verbatim from `.ai/context/project.md`, section "Known Invariants and
  Limitations" (2026-10-05). The text below is the original record; it was not rewritten into the
  Context / Decision / Consequences form. New ADRs use `_template.md`.

## Record

escalation-service resolves the SECONDARY / MANAGER user and sends it in
`IncidentEscalatedEvent.escalateTo`. notification-service stores it on its outbox entry (the
scheduler, not the consumer, resolves the recipient at send time). For `INCIDENT_ESCALATED`,
`NotificationRouter` looks that user up with `OncallClient.findCurrentByUserId` (oncall-service
`GET /api/v1/oncall/current/by-user/{userId}`) and notifies their email, Slack id and phone.

**Invariants (do not undo them):**
- Recipient order for an escalation: the target, then the tenant's PRIMARY on-call, then
  UNDELIVERABLE. Do not drop the PRIMARY step, and do not add a platform-wide fallback address.
- Tenant content (incident title, id, severity) may only reach members of that tenant. The
  contact details of an on-call entry are free text, not verified against tenant membership, so
  this is enforced by trust until backlog #0-24.
- Every event type's PRIMARY lookup (and the escalation fallback, when there is no target or it
  isn't found) is team-scoped since backlog #0-12: `teamId` flows from `Incident` through all 5
  `IncidentEvent` records (`shared`) and `NotificationQueueEntry` (V7), and `OncallClientImpl`
  passes it to oncall-service's `/current?teamId=...`, which was already team-aware (escalation-service's
  `OncallServiceClient` already called it that way). `null` (no team assignment) falls back to
  tenant-wide, same as before #0-12. Fixing this also surfaced that `IncidentOpenedEvent` never
  carried `teamId` at all, so `EscalationTask.teamId` was always null and the automatic
  SECONDARY/MANAGER escalation chain never resolved a real target — both are fixed together.
- The lookup is scoped to the entry's tenant as well as the user id (`escalateTo` is an unverified
  id from a Kafka payload), and the client ignores a response for a different user.
- A channel the contact has no address for is skipped, never replaced by a shared one. A Slack id
  is an address only if `SlackNotificationChannel.isSlackUserId` accepts it; the router and the
  channel share that predicate, because a DM the channel silently ignores would still be recorded
  as SENT.

When nobody in the tenant can be notified the queue entry becomes `UNDELIVERABLE` (V6; the reason
is in `error_message`) and nothing is sent. The tenant gets an audit event of its own type,
`NOTIFICATION_UNDELIVERABLE`, distinct from `NOTIFICATION_FAILED` (a failed send): an auditor
filtering by type must not get both meanings. For opened and escalated incidents the operator gets
a content-free email (identifiers and reason only) at `notification.operator-alert.email`, which has
no default; details of the rate limit and the metrics are in the code and the README.

An oncall-service outage is not "nobody on call" (backlog #0-19). `getCurrentOncall` and
`findCurrentByUserId` throw `OncallLookupUnavailableException`; the entry stays PENDING until the
lookup has been failing for `notification.scheduler.lookup-retry-window`, then becomes UNDELIVERABLE.
The window runs from the entry's first failed lookup (`first_lookup_failure_at`), not from its
creation, or a restart would park a whole backlog on one blip. These lookups carry no retry of their
own since backlog #0-23 (the `@Retry(name = "oncall")` never fired, behind a fallback that answers
every failure); the scheduler's PENDING retry is their retry.
`findBySlackUserId` still fails open. A scheduler run stops after `processing-budget` (PT2M30S),
which must stay below the 4-minute ShedLock (validated at startup), and loads at most `batch-size`
entries, oldest first. The budget is checked between entries, so the lock must also outlast the
entry in flight: a 30 s margin plus each channel's `NotificationChannel.worstCaseSendTime()`
(review of backlog #0-103: Slack's broadcast and DM, each 3 attempts of connect + read timeout plus
backoff, about 51 s; `SlackApiClient.worstCaseCall`), also validated at startup
(`NotificationSchedulerDefaultsTest` keeps `application.yml`'s defaults inside it). A new channel
that retries or waits long says so through `worstCaseSendTime()`. Slack is behind a circuit breaker
(`slack`, backlog #0-104): after network errors or 5xx (at least 5 calls in 60 s, half failing) it opens, Slack
calls fail at once as `SLACK_UNAVAILABLE` (`circuit_open`) and a trial call every 30 s decides when to
close it; the lock check still counts the closed breaker's worst case. It has no fallback of its own:
Resilience4j puts the retry outside the breaker, an open breaker's `CallNotPermittedException` is not in
the retry's list, and the retry's fallback classifies it (a fallback on the breaker would turn every
failure into a result before the retry sees it, the reason #0-23 removed the oncall and
slack-workspace retries). It ignores 4xx, 429 and `ok:false`,
so no tenant's workspace can open it for the others; that also leaves out Slack's own `ok:false` outage
codes and an unreadable 200, which answer at once. It registers no health indicator: a channel's outage
must not mark the service DOWN (as with mail). Accepted until #0-32: while it is open, Slack messages
are recorded FAILED without being tried and never resent, a whole batch's worth in one run. Alert
`SlackCircuitOpen` (high) is on refused calls (`resilience4j_circuitbreaker_not_permitted_calls_total`,
any in the last 10 minutes, held 5 minutes), not on the breaker's state: it turns half-open after 30 s
and waits for a real call, so with no traffic a state rule kept firing after Slack recovered. Every
refusal is a lost notification, so a short burst fires it too; a shorter window missed an outage whose
refusals were minutes apart (sparse Slack traffic). Email and SMS
still declare nothing and live inside the 30 s margin (#0-105).

Slack is per tenant (backlog #0-21): auth-service's `SlackWorkspace` holds each tenant's bot token
(AES-256-GCM under `slack.encryption-key`, deliberately not the MFA key), default channel and
broadcast flag (default false); one active workspace per tenant, admin-pasted token, no OAuth
install. notification-service reads it through `CachingSlackWorkspaceClient` (60 s TTL; caches
"no workspace", never a failure) wrapping `SlackWorkspaceClientImpl` (the Resilience4j proxy — keep
the cache outside it, a self-call bypasses the proxy). "No workspace" = skip Slack; auth-service
down = `SlackWorkspaceLookupUnavailableException`, the router skips only Slack, unless Slack was the
sole reachable channel (then PENDING/#0-19 window, reason `SLACK_WORKSPACE_UNAVAILABLE`). Not the
#0-19 "hold everything" pattern on purpose: this lookup picks a channel, not the recipient. No
channel send is retried later (backlog #0-32). Signing secret stays global (per Slack App), which
is exactly why messages have no ACK button now: a pasted token comes from the tenant's own App,
whose callbacks that secret can't verify. ACK via Slack returns with the OAuth "Add to Slack"
install (backlog #0-35) — Slack OAuth as a client for workspace install, unrelated to user login,
which stays on the platform's own JWTs (the README's rejection of Keycloak etc. is unaffected). oncall-service restricts the by-user endpoint to SERVICE and ADMIN; a
user with several concurrent entries gets the most recently started one, so only the contact
details are meaningful, not the role.

oncall-service endpoints that return contact data need their own URL-level SERVICE/ADMIN matcher in
`SecurityConfig`: the rule for `/api/v1/oncall/current` is an exact path and does not cover a
sub-path, which would otherwise fall through to `anyRequest().authenticated()`. A service token is
`ROLE_SERVICE`, so a `@PreAuthorize` RESPONDER/ADMIN rule on such an endpoint would reject it.
