# Backlog: done

Finished backlog items, with the PR that delivered each, so that every `backlog #N` reference in code,
Javadoc and commits stays resolvable. Open items are in [`BACKLOG.md`](BACKLOG.md).

Moved here from `BACKLOG.md` on 2026-10-05: the agents that pick work read `BACKLOG.md` on every run,
and finished items there only cost context and invite re-doing them. The `shipper` agent and the
`/ship` skill append a row here and move the item's section from `BACKLOG.md` to the end of "Details" below, in the
PR that finishes it (its row links to it), so the history of its decisions stays readable without costing the
agents that read `BACKLOG.md`; an
item delivered by the autopilot also carries the `autopilot` label on its PR. An item closed without
being implemented is recorded here too, with the decision instead of a PR, so its number stays
resolvable.

| # | Title | Delivered in |
|---|---|---|
| 0-1 | Escalations notify the `escalateTo` user, falling back to the tenant's PRIMARY, then to the configured addresses (the addresses were removed by #0-18) | PRs #411, #413, #414, #415 |
| 0-18 | Tenant content only reaches members of the tenant: no fallback address, `UNDELIVERABLE` status (V6), content-free rate-limited operator alert by email, a `NOTIFICATION_UNDELIVERABLE` audit event type of its own (`shared`), skipped channels reported, Slack shared-channel broadcast off by default, a Slack id the channel would ignore is no address | PR #416 |
| 0-19 | An oncall-service outage is no longer read as "nobody on call": the two decisive lookups throw, the entry stays PENDING until the lookup has been failing for a retry window (from its first failed lookup), then UNDELIVERABLE; a scheduler run stops after a processing budget | PR #416 |
| 0-10 | `NotificationScheduler` loads a capped page of PENDING entries, oldest first (`notification.scheduler.batch-size`, default 200), and a run stops after a processing budget validated against the ShedLock | PR #416 |
| 0-11 | Service tokens were rejected by `JwtAuthFilter`: per-tenant, per-audience service tokens, `ServicePrincipal`, real-token filter tests, fallback metric, tenant-id validation, escalation client timeouts, correct oncall URL default | PR #413 |
| 0-12 | `teamId` now flows through all 5 `IncidentEvent` records (`shared`) and `NotificationQueueEntry` (V7); the PRIMARY on-call lookup (every event type, and the escalation fallback) is team-scoped via oncall-service's already-team-aware `/current?teamId=...`. Also fixed the dead SECONDARY/MANAGER escalation chain found along the way: `IncidentOpenedEvent` never carried `teamId`, so `EscalationTask.teamId` was always null and `EscalationScheduler` always skipped team-scoped on-call routing | PR #417 |
| 0-27 | CLAUDE.md's "Between teams of one tenant the default is also 'no'" sentence is now true — closed by #0-12 | PR #417 |
| 0-26 | `NOTIFICATION_OPERATOR_ALERT_EMAIL` patched in the app-config ConfigMap for every overlay: dev mirrors docker-compose's `operator@incident-platform.local` (mailhog); staging/prod get a placeholder `ops@incident-platform.local` (this repo has no real domain anywhere), commented to replace before a real deployment | PR #417 |
| 0-21 | Slack is per tenant: each tenant connects its own workspace (`SlackWorkspace`, V17, one active per tenant via a partial unique index, bot token AES-256-GCM under a separate `slack.encryption-key`, admin API `/api/v1/slack-workspace`, manual token paste). notification-service reads it through `CachingSlackWorkspaceClient` (60 s TTL, bounded, Micrometer `cache.*` meters) over `SlackWorkspaceClientImpl` (Resilience4j, fallback throws). The global bot token/channel/broadcast config is gone. An auth-service outage skips only Slack, except when Slack was the only channel (PENDING, then `SLACK_WORKSPACE_UNAVAILABLE`). ACK via Slack is off until the OAuth install: #0-35. Follow-ups: #0-32, #0-33, #0-34 | PR #422 |
| 0-30 | Decided and implemented: a service that needs auth-service-owned tenant data pulls it over a narrow HTTP call with a service token `aud=auth-service`, accepted on exactly one `ROLE_SERVICE` endpoint (`GET /api/v1/internal/slack-workspace`), cached briefly by the caller. Kafka replication was rejected for a single consumer. Decision recorded in `.ai/context/project.md` and CLAUDE.md; the identity/config split it raised is #0-31 | PR #422 |
| 0-9 | `NotificationLog`'s `@Index` list named V1's three indexes, dropped by V2 (and V5 replaced one of V2's); it now mirrors V2/V5 and says the migrations are the source of truth. A check against the real schema is #0-36 | PR #424 |
| 0-16 | Alert sources authenticate with Integration API keys (A1): ingestion-service runs `ApiKeyAuthFilter` (`ApiKey`/`Bearer ipl_…`) and introspects the key's SHA-256 in auth-service with a tenant-less purpose token accepted on that one route only (deny by default elsewhere); 60 s cache = revocation window; 401 = definite "no", 503 + `Retry-After` = can't check; per-IP failed-auth limiter before the lookup; `hasRole('SERVICE')` removed from ingest, and ingestion accepts no service tokens. Platform alerts out of band (B3): Watchdog to a dead man's switch, critical to operator email, all to the reserved `platform-operator` tenant (invite-bootstrapped admin). Alertmanager/Prometheus pinned, rules/routes validated in CI. The 30-day `system` token, its refresher and script are gone. Only TENANT keys introspect as active (a personal key gets `active:false`). Decision in `.ai/context/project.md`. Follow-ups: #0-37..#0-46. Rejected then: a cross-tenant "create tenant" endpoint (the operator tenant bootstraps itself, `OperatorTenantBootstrap`); reversed narrowly for customer tenants by #0-80 | PR #425 |
| 0-47 | Creating a user by invite failed on a real database (bug since `e7290db1`, exposed by #0-16's `OperatorTenantBootstrap`, which crashed auth-service at startup): `User.version` and `SlackWorkspace.version` were initialised to `0L`, so Spring Data saw a new entity as existing, `save()` merged instead of persisting and `UserService.createUser` kept the transient instance (`TransientPropertyValueException AuthToken.user -> User`). Both fields are now left `null` until persist; a Testcontainers test saves a new `User` + `AuthToken` the way production does. Unit tests mock repositories and V1_1 seeds users by SQL, so nothing caught it | PR #426 |
| 0-50 | Accept-invite, reset-password and refresh-token rotation failed with `LazyInitializationException` on a real database (bug since `f3d05fd`): `AuthTokenRepository.markUsedIfUnused` had `clearAutomatically = true`, so `consumeToken` detached the token and its lazy `User` proxy before every caller used `token.getUser()`. The single-row claim no longer clears the persistence context; `consumeToken` sets the same `usedAt` in memory. Testcontainers tests now drive accept-invite, reset-password and refresh rotation through the real services; MFA goes through the same `consumeToken` path (service unit tests mock the repositories, and #0-47 had kept anyone from reaching accept-invite) | PR #428 |
| 0-51 | MFA login failed with a 500 on a real database (bug since `372ac32`/`efe96a9`): `chk_auth_token_type` (V2/V6) allowed only INVITE, PASSWORD_RESET and REFRESH, while `AuthToken.Type` also has `MFA_SESSION` and `MFA_SETUP_REQUIRED`, so neither token could be stored. V18 widens the constraint to all five types. `AuthRepositoryIntegrationTest` now stores a token of every `AuthToken.Type` (a new type without a migration fails CI) and drives MFA verification with a TOTP code through the real `MfaService` | PR #430 |
| 0-49 | The operator admin invite could be lost for good (email permanently failed while SMTP was down, or the 7-day token expired unaccepted): `OperatorTenantBootstrap` did nothing once the tenant had any user and `resend-invite` needs an admin. It is now a reconciler (`@Scheduled` + ShedLock, ~30 s after start, then hourly) that checks for an admin who can log in, re-invites the configured admin through `ResendInviteService` when the latest invite permanently failed or no valid token is left, leaves an invite in flight alone, and never creates a second admin or deletes a user (an unexpected state is an ERROR for a human). Gauge `platform.operator.admin.pending` + alert `OperatorAdminNotActivated` (critical, 1 h, promtool-tested). Rejected: re-invite only at startup, never giving up on INVITE emails, a manual reinvite flag. Outbox retry policy for all emails: #0-52 | PR #431 |
| 0-52 | Auth emails (invite, password reset) no longer give up after 3 attempts 5 minutes apart. The outbox (V19, recreated) records the intent to send: the request path only INSERTs through `AuthEmailRequestService`, and `AuthEmailScheduler` is the only writer after that. Per attempt it closes entries no longer worth sending (SUPERSEDED: newer request, accepted invite, missing user; PERMANENTLY_FAILED: deadline passed), otherwise invalidates the user's earlier tokens of the type and creates the token it sends, so no raw token is ever stored and the link is valid for its full lifetime from sending. Failed sends are retried on `AuthEmailRetryPolicy`'s backoff (1m, 5m, 30m, 2h, then every 6h) until the deadline (7 days / 15 minutes); two lanes with their own batches, a processing budget checked against the ShedLock at startup, state-guarded conditional UPDATEs instead of `@Version` (one writer), a daily purge of terminal rows. Counters `auth.email.send{type,outcome}` and `auth.email.permanently_failed{type,reason}`, alerts `AuthEmailDeliveryFailing` (critical) and `AuthEmailPermanentlyFailed` (high), promtool-tested. Fixed with it: resend-invite / forgot-password over a FAILED entry returned 500 (unique index) or, with a concurrent scheduler write, 409 instead of forgot-password's 202 — they no longer touch existing rows. The table was dropped rather than migrated (not in production); from the first production release, schema changes must stay compatible with the previous release | PR #432 |
| 0-54 | Closed by #0-52's redesign rather than by encryption: the outbox no longer stores the raw token at all — the scheduler creates the token when it sends the email and only its SHA-256 is kept, in `auth_tokens` | PR #432 |
| 0-53 | `AuthEmailOutboxRepository.findLatestByUserIdAndType` returned `Optional` from an unlimited `ORDER BY` query, so the second resend of an invite or a repeated password reset threw `IncorrectResultSizeDataAccessException` (500). Replaced by the derived `findFirstByUserIdAndEmailTypeOrderByCreatedAtDesc`; Testcontainers test with two entries | PR #431 |
| 0-57 | No coverage rule had ever run: surefire's explicit `<argLine>` replaced the `argLine` property set by `jacoco:prepare-agent`, so the agent never attached, no `jacoco.exec` was written and `jacoco:report`/`jacoco:check` skipped themselves in every module, locally and in CI. `<argLine>` now starts with `@{argLine}`. The PR comment (`madrapps/jacoco-report`) never failed a job either (its thresholds only pick an emoji), and was never posted (read-only `GITHUB_TOKEN`, error hidden by `continue-on-error`); it now writes to the job summary, keeping the job's token read-only. A new CI step runs `diff-cover` (pinned) over the JaCoCo XML and fails a PR when under 60% of its changed Java lines are covered, and a missing report fails it too. `report` now has the same excludes as `check`. Measured at the fix: every module above 60% LINE (`shared` lowest, 67.8%); `shared`'s tenant classes: #0-58 | PR #433 |
| 0-59 | Every workflow declares its `GITHUB_TOKEN` scope instead of inheriting the repository setting: `contents: read` at workflow level, and only the jobs that need more widen their own token (`detect-changes` adds `pull-requests: read` for `dorny/paths-filter`; both Snyk jobs add `security-events: write` for the SARIF upload, which used to be granted to the whole workflow). Follow-ups: #0-60, #0-61, #0-62 | PR #434 |
| 0-60 | Every `uses:` in `.github/workflows/` names a full commit SHA with its tag in a comment, pinned to the commit each tag pointed at (no version change); Renovate keeps both current through `helpers:pinGitHubActionDigests` (the old "pin to SHA" rule pinned nothing); every `actions/checkout` sets `persist-credentials: false`, so no later step can read `GITHUB_TOKEN` from `.git/config`; the repository setting "Require actions to be pinned to a full-length commit SHA" is not part of the PR: it was turned on manually on 2026-09-29, after the PR merged and the run on `main` was green | PR #437 |
| 0-61 | The Snyk CLI in both `snyk.yml` jobs is the standalone binary at a version pinned in the workflow's `env`, checked against a SHA-256 kept next to it (`sha256sum --check --strict`) before it runs, instead of `npm install -g snyk` (unpinned, a Node wrapper with an unbundled `@sentry/node ^7` range); `SNYK_TOKEN` reaches only the scan step as an environment variable, with no `snyk auth` writing it to argv and a config file; version and checksum are bumped by hand, since Renovate cannot compute the checksum. README's hardening section became `## Infrastructure Hardening` | PR #440 |
| 0-63 | The k8s base ConfigMap set `SPRING_PROFILES_ACTIVE: "dev"`, inherited by every overlay: the rendered prod and staging manifests started incident-service with the dev profile, enabling `DevSecurityConfig` and the unauthenticated `GET /dev/token` (an ADMIN JWT for any tenant, accepted by all seven services through the shared HS512 secret) — not routed by the Ingress, but reachable from any pod since there is no NetworkPolicy; `DevTokenController`'s startup guard could not catch it, as it only rejects a missing dev profile. The base now sets no profile, `k8s/overlays/dev` adds it, and the `validate-k8s-manifests` CI job fails if the rendered staging or prod overlay sets any Spring profile (env var, property or flag form). Found in the 2026-09-30 infrastructure security audit | PR #441 |
| 0-78 | The services' database role `incident_app` was a Postgres superuser (checked on a running database: `rolsuper = t`): the image's `POSTGRES_USER` created it, so SQL injection in any service was command execution in the database container (`COPY ... TO PROGRAM`). Now `POSTGRES_USER` is the admin, used by no service, and `k8s/base/infrastructure/postgresql-init.sh` (one file, mounted by docker-compose, generated into a ConfigMap by Kustomize) creates `incident_app` with `NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS` as owner of the database and the `public` schema; it reads its values with psql `\getenv`, so no password is on a command line, and refuses `APP_DB_USER` = `POSTGRES_USER`. No migration needed superuser rights (the extensions are trusted). The role's password and the services' `DB_PASSWORD` have one source: `docker/.env` (both database passwords now required, no default) or each overlay's `app-secrets`, now wired to the six Deployments; the admin comes from a per-overlay `postgresql-admin` Secret, and the base `postgresql-secret` with its committed password is gone (part of #0-66). No name is hard-coded: probes, CI and the migration read `POSTGRES_USER`. Probes: the init-phase server listens on its socket only, so a socket check reported ready before the role existed (reproduced); compose's healthcheck and the k8s readiness and startup probes now use TCP, liveness the socket after the startup probe. CI: the smoke test checks the role's attributes, that it is a member of no role and that `COPY ... TO PROGRAM` is refused; a new job runs `.github/scripts/test-postgres-roles.sh` against the real image (init with a hostile password and a non-default admin, the guard, the migration). An existing database cannot be demoted in place (`incident_app` is the bootstrap role, which must stay superuser), so `docs/database-roles.md` and `docs/database-roles-migrate.sql` give the procedure: rename it to the admin, create a new `incident_app`, move ownership, in one transaction with a completeness check, passwords from the database container's environment. Because the services' role owns `public` and could plant a trigger, rule, default, view or function that runs as whoever fires it, the superuser never touches anything outside `pg_catalog` in the database: the guide's "Working as the admin" routes service data, backups and restores through an `incident_app` login (`SET ROLE` is no boundary, planted code can `RESET ROLE`; the CI job shows both cases), and the admin's `search_path` is `pg_catalog` as a second line of defence; the migration itself runs with `search_path = pg_catalog` and only `ALTER ... OWNER`, after a preflight that refuses to run while an event trigger or an extra superuser exists (it is for databases not suspected of compromise; those are restored); CI also runs the guide's backup/restore commands as `incident_app`. Not covered: the role still owns every table, so grants and RLS do not separate services (#0-67) | PR #443 |
| 0-80 | Every new database got a `ROLE_ADMIN` account `admin@incidentplatform.com` / `changeme` in tenant `default` from the Flyway Java migration `V1_1__seed_admin_user` (no deployment set `ADMIN_PASSWORD`; login returned 200, and the Ingress routes `/api/v1/auth`). `V1_1` now creates nothing (the class stays for Flyway's history); `V20__archive_default_seed_admin` archives that account and invalidates its tokens where its password still verifies as `changeme`, and leaves a changed one with a WARN. Customer tenants are now provisioned by a platform operator: `tenants` table (V21, backfilled from existing users), `POST /api/v1/platform/tenants` creates the tenant and invites its first admin in one transaction, `POST .../{tenantId}/admin-invite` reissues a lost or expired first invite (sharing `TenantAdminReconciler` with `OperatorTenantBootstrap`, #0-49, which now also records the operator tenant's row), `GET` shows one tenant's or lists tenants' metadata. Only an admin of `platform-operator` with a JWT gets in (`PlatformAccess`, in the filter chain and on every method; API keys, service and purpose tokens refused); audited as `TENANT_PROVISIONED` / `TENANT_ADMIN_REINVITED` (`shared`). This narrowly reverses #0-16's "no cross-tenant create tenant endpoint". The reissue never creates a user (an archived first admin is not revived; reopening is #0-82), provisioning refuses an id that has users, archived ones included, and V20 also revokes the account's API keys. Testcontainers tests of V20, V21 and provisioning (incl. rollback when the admin insert fails), security tests with real tokens. Guide: `docs/tenant-provisioning.md`; suspension and offboarding: #0-82 | PR #445 |
| 0-83 | The platform API (#0-80) accepted an operator admin's password alone and had no rate limit. `PlatformAccess` now also requires that the access token's session completed MFA within 12 h (`platform.mfa.max-session-age`) with a factor whose MFA_ENABLED notice was sent at least 24 h ago (`platform.mfa.enrolment-grace`): recorded on the session (`auth_tokens.mfa_verified_at`, V22) when a login finishes with a TOTP or backup code, carried unchanged by refresh rotation, cleared when the user disables MFA, and checked server-side per request (a live session only, so logout ends access at once). The grace period, plus an email to the account on every MFA enable/disable (outbox types `MFA_ENABLED` / `MFA_DISABLED`, V23) with the grace period counted from when that notice was sent (`users.mfa_enabled_notice_sent_at`, kept on the user because the outbox purges sent rows after 30 days), a password reset by email that removes a factor still within the grace period (interim, replaced by an admin reset in #0-88) and kills unfinished logins (MFA session / setup tokens), enrolment only from a live session, and existing factors enabled at least 24 h before the deploy backfilled as established by V23 (a newer one gets the grace period like any other, and an operator admin's factor never: operators re-enrol once), answers a review finding: enabling MFA needs only a password, so a password thief could enrol their own factor. Also fixed on the way: bulk UPDATEs in `AuthTokenRepository`, `ApiKeyRepository` and `MfaBackupCodeRepository` (and the new one in `UserRepository`) cleared the persistence context without flushing it, silently dropping earlier changes to other tables in the transaction. Decided against an `amr` JWT claim: only auth-service needs it, so `shared` and the token format stay unchanged; `amr` remains the path if another service needs step-up. A refusal names the failed MFA condition (`PlatformAccessDeniedHandler`). Writes are limited per operator and in total (`PlatformRateLimiter`, bucket4j + Redis, default 20/h per operator and 50/h for the platform, `@CircuitBreaker` opened by any failure), fail-closed (503) unlike ingestion's fail-open #67, with a lazy Redis connection so auth-service starts without Redis. Critical alerts `PlatformTenantProvisioningSpike` and `PlatformApiRateLimited`, high `PlatformApiRateLimitUnavailable`, with promtool tests | PR #446 |
| 0-88 | Since #0-83 a password reset by email removed a second factor still within the grace period, the only way then to undo a factor someone else enrolled with the owner's password, but one that let a mailbox alone undo MFA. A password reset now never touches MFA (NIST SP 800-63B; Okta, Entra ID, Google keep MFA on reset); `MfaService.removeFactorEnrolledWithinGrace` is gone. Instead an admin of the tenant resets another user's MFA (`POST /api/v1/users/{id}/mfa-reset`, `MfaService.resetMfaByAdmin`): factor, pending setup, backup codes and the sessions' MFA marks cleared, every session and unfinished login ended, audited as `MFA_RESET_BY_ADMIN` (`shared`, distinct from the self-service `MFA_DISABLED`). Any other user of the tenant that is not archived (deactivated ones too, so a stranger's factor goes before reactivation), admins included, never one's own account; only from the admin's own session passing the platform API's MFA rule (`MfaSessionStatusService.check`: MFA within 12 h, a factor whose MFA_ENABLED notice went out at least 24 h ago; a weaker "completed MFA" rule was found in review to let a password thief enrol a factor and reset everyone at once, or a 30-day refresh chain act weeks later), so an admin's password, a fresh factor or an API key gets 403. Resets are limited per admin and per tenant (`MfaResetRateLimiter`, fail-closed like the platform API's limiter, counted only for a reset about to happen, 429/503 with Retry-After, alerts `AdminMfaResetRateLimited` / `AdminMfaResetRateLimitUnavailable`; shared `RateLimitDecision` / `RedisTokenBuckets` with `PlatformRateLimiter`). Audit records now carry `X-Tenant-Id` from the event's tenant (`AuditEventKafkaSender`; most had none, the rest is #0-91), and the producer interceptor no longer appends a second, context-derived one. `publishAuthConfirmed` refuses to run on a request thread. The user is emailed with a notice of its own (`MFA_RESET`, V24), so a reset they did not ask for stands out from disabling MFA themselves. The MFA_ENABLED email now says: reset the password, then ask an administrator to reset MFA (in that order, or the old password's holder could enrol again). A single platform operator has no second admin: a one-off break-glass command of auth-service (`BreakGlassMfaResetRunner`, `--break-glass.mfa-reset.*`, started only by the subcommand `break-glass-mfa-reset` as the first argument (the options alone, or an environment variable left in a deployment, start nothing), no web server, no scheduled jobs (runner and scheduling share one marker condition, `BreakGlassCommand`), admins of `platform-operator` only, actor and reason without control, line-separator or formatting characters) runs the same reset, emailed, and audited as `MFA_RESET_BREAK_GLASS` with the operator's name, reason and `executedOn` (OS user and host of the process) through `AuditEventPublisher.publishAuthConfirmed` (`shared`), which waits for Kafka's acknowledgement inside the transaction, so a break-glass reset never happens unaudited; chosen over a SQL procedure, which could neither email nor audit. The platform API's grace period (#0-83) stays. A customer tenant's only admin has no remedy yet: #0-90; the admin reset's audit moves to #0-84's outbox. Testcontainers tests of the reset, the break-glass reset and its rollback without an audit acknowledgement, and a password reset that keeps a fresh factor | PR #447 |
| 0-89 | A personal API key created with a stolen password outlived the owner's recovery, and in auth-service any API key was a full session of its owner: no route checked a scope, so an admin's personal key could invite a second admin, create a tenant key or an integration, change roles or the tenant's MFA policy, each a foothold that no reset takes back. Now an API key reaches only the routes `SecurityConfig` lists for keys, with the scope each names (`/api/v1/teams` with `teams:read` / `teams:write`, the role checks kept), and every other route refuses it (`ApiKeyAccess`, deny by default like the purpose token of #0-16; MFA setup already needed a live session). A password reset, an admin MFA reset and the break-glass reset revoke the user's personal keys in the same transaction (OWASP: recovering a compromised account ends every session and credential), the count in the action's audit event (`personalApiKeysRevoked`, also on archive) and the MFA_RESET email says so; a password change does it only on request (`revokePersonalApiKeys`, OWASP ASVS 3.3.3 "gives the option"; a routine change keeps them). Creating a key emails the account through the auth email outbox (`API_KEY_CREATED`, V25): a personal key its owner, a tenant key (an integration's too) the admin who created it, one email per key showing its id (the row names the key, `api_key_id`; not the prefix, part of the secret), never merged or superseded (OWASP ASVS 2.2.3; review: a 15-minute merge let a key made right after the owner's own hide behind its notice); the name, typed by the creator, is not shown. A user may create at most 20 keys per hour, revoked and integration keys included (`ApiKeyCreationLimit`, counted in Postgres on V26's index, 429 with Retry-After; review: the creator's user row is locked first, `FOR NO KEY UPDATE NOWAIT` (not `FOR UPDATE`, which the foreign-key locks of a login or a reset in flight would have turned into spurious 429s), so one user's parallel requests cannot all pass this limit and the active-key caps with a read-then-insert check, and one finding the row busy gets a 429 at once rather than waiting on a pooled connection; the creation and bulk revocation audit events are sent after commit on a bounded executor private to `AfterCommit` (alerted by `AuditEventsDropped` when its queue drops events; a bulk revoke that revoked nothing publishes nothing), as the connection was measured to be still held inside `afterCommit`, so neither the lock nor a connection waits on Kafka), which bounds those emails against a create-and-revoke loop. Tenant and integration keys are meant to outlive their creator, so a reset keeps them (found in review: one an intruder made would survive); instead every key records who created it and from which login session (V26, personal keys backfilled from their owner), the key list filters by creator (`GET /api/v1/api-keys?createdBy=`), an admin revokes every key a user created since a given time (`POST /api/v1/api-keys/revoke-created-by`, integrations with their keys, one audit event listing them; same rights as revoking one key, so no step-up or limit: revoking is the safe direction, and a tenant without MFA must be able to clean up), the admin MFA reset can do the same in its transaction (`revokeKeysCreatedSince`), and its email counts all the tenant keys the account created that still work (an archive records the same count, `unownedApiKeysKept`; both only count keys with a recorded creator). Tenant and integration keys from before V26 have no recorded creator and are revoked one by one; V26's backfill of personal keys is not covered by a test (the test database migrates from empty). An integration revoked in bulk, through the endpoint or the MFA reset, is also audited as `INTEGRATION_REVOKED`, and the MFA reset lists the revoked key and integration ids. Not done, on purpose: a step-up (MFA) to create a key, of little use once a key cannot create anything and the creator is told. Testcontainers tests that a creation is refused at once while the creator's row is locked, that parallel creations never exceed the limit, that the creation audit is published after commit off the request thread (a stalled publish holds no connection) and not at all on rollback; MockMvc test of every route with an admin's key holding every scope (HEAD, trailing slash and dot segments included), Testcontainers tests of the revocations, the creator columns and the outbox rows | PR #448 |
| 0-84 | Audit events no longer go to Kafka from inside the action's transaction, fire-and-forget. Every service that records them (auth-, incident-, notification-, escalation-, postmortem-service) writes each event to its own outbox table (`<service>_audit_outbox`; auth V27, incident V14, notification V8, escalation V7, postmortem V5) in the transaction of the change it records, and `AuditOutboxRelay` (`shared`, ShedLock per table) sends committed rows, waiting for Kafka's acknowledgements batch by batch, retrying a failed row with backoff (5 s doubling to 5 min) and never giving it up; the relay pauses after Kafka itself failed, asks without a lock whether anything is due before taking its ShedLock lock (taking it is a write to the shared `shedlock` table), purges SENT rows after 7 days in chunks, at most 100 chunks a run. `AuditEventMessage.eventId` is new; incident-service's consumer deduplicates on `(tenant_id, event_id)` (V12, V13 built `CONCURRENTLY`), resolves the tenant header first, and sends any other unstorable record to `incidents.dead-letter` (`audit.events.rejected`, alert `AuditEventsRejected`). `AuditEventPublisher` exists only where `audit.outbox.table` is set (a bean of `AuditOutboxConfiguration`), so a service that injects it without an outbox does not start; the direct send (`AuditEventKafkaSender.send`, which lost an event whenever Kafka was slow or down) is gone, with `publishAuthConfirmed`, `AfterCommit` (#0-89's interim) and the inert `@Retryable`. The publisher refuses an event the trail cannot store (no tenant or resource, a field over its column, a metadata key naming a secret, a payload over 256 KiB), failing the action. A refusal whose transaction rolls back (`MFA_VERIFY_FAILED`) is audited after the rollback. In notification-service the `notification_log` row (or the UNDELIVERABLE status) and its audit event are one transaction; every failed send is now audited, not only a channel's own failure, and a delivered notification whose record cannot be written is no longer recorded as a failed send. In escalation-service `ESCALATION_SCHEDULED` is written with the level-2 task; `ESCALATION_FIRED` and `ESCALATION_NOTIFICATION_FAILED` follow a change already committed (or none), so a failure to write them, like a delivered notification's, is logged and counted (`audit.event.unrecorded`, alert `AuditEventUnrecorded`) rather than thrown. `max.block.ms` is 5 s in the producers of auth-, incident-, notification- and postmortem-service, so `send()` cannot hold the relay for Kafka's default 60 s; escalation-service keeps the default on purpose, as its escalation event is sent once and not retried (#0-4) and a shorter block would turn a brief outage into a lost escalation; its relay runs on its own virtual thread. `delivery.timeout.ms` is left at its default: the relay waits `send-timeout` for an acknowledgement, and a record delivered after that is resent and deduplicated by `eventId`. Table names are checked (plain lower-case, at most 45 characters, so the relay's lock name fits `shedlock.name`) in `AuditOutbox` itself as well as in its properties. Alerts `AuditOutboxBacklog` (oldest pending event over 10 min), `AuditEventsRejected`, `AuditEventUnrecorded`, all critical and emailed to the operator. An error goes into an event cut to 500 characters on one line, an unexpected exception by its type only (`AuditText`), a failed Gemini call as a fixed text: the trail is the tenant's to read, and a client library's message can quote a token-bearing URL or a response body. A failed send whose record cannot be written no longer stops the remaining channels, and an undeliverable notification alerts the operator even when its status write fails. The counters behind `AuditEventUnrecorded` and `AuditEventsRejected` exist at zero from startup (`UnrecordedAuditEvents`), so each alert fires on the first failure, not the second. Testcontainers tests per service (the migration takes the shared SQL; through the real service, the change and its audit event commit or roll back together, under the action's tenant) and a wiring test with Spring Boot's own Kafka beans. Log injection through the tenant header found in review: #0-92 | PRs #449, #450 |
| 0-91 | A Kafka record's tenant header has one writer. `TenantRecords.forTenant` (`shared`) builds every tenant record (audit, alert, incident event, dead-letter), its tenant a required, checked argument written to `X-Tenant-Id`; the payload's `tenantId` is the record's tenant and the header its copy. Incident events had no header of their own until then: `IncidentEventKafkaSender` relied on `TenantKafkaProducerInterceptor`, which stamped it from the thread's `TenantContext` (CLAUDE.md said otherwise). The interceptor now writes nothing: registered in every service that produces (oncall has no Kafka), it counts a record without a valid header (`kafka.records.produced.tenant.invalid`, registered at zero, alert `KafkaRecordsWithoutTenant`), dead-letter records marked as tenant-less excepted (`TenantRecords.withoutTenant`, marker `X-Tenant-Unresolved`; the topic name alone used to exempt any record). `DeadLetterPublisher` heads a record with its resolved tenant, or with none (a `null` field, `_none` in the key) where consumers used to pass the string `"unknown"`, itself a valid tenant id; its reason goes on one line. Consumers no longer set a placeholder tenant | PR #452 |
| 0-92 | Every tenant id is a slug of 3-63 `[a-z0-9-]` (`TenantIds`, moved from auth-service to `shared`): a `CHECK` on every table with a `tenant_id`, in every service (auth V28, reversing V21's "backfilled ids kept as they are"; incident V15, notification V9, escalation V8, postmortem V6, oncall V7; the platform holds no data to keep; each service's integration test fails for a new table without one), checked when a token is issued (`JwtUtils`, user tokens too, the looser 1-100 rule of #0-11 gone) and read (`JwtAuthFilter`), on the `X-Tenant-Id` header of auth-service's public endpoints (400), by `TenantContext.set`, `DevTokenController`, `AuditEventPublisher`, the STOMP `CONNECT` and `ApiKeyAuthFilter` (a lookup returning an invalid tenant is a 401, not a 500). Every loop that sets `TenantContext` from a row (5 scheduler classes: incident outbox, notification, escalation, auth email and postmortem retry with its two loops; and `AuditOutboxRelay`) does it inside the row's `try`: one such row used to end the batch for every tenant (found in review). `TenantKafkaRecordResolver` takes the payload's tenant, which must be valid, and refuses a header that is missing, invalid or names another tenant (`TenantResolutionException` → dead-letter, `kafka.records.tenant.rejected{reason}` registered at zero, alert `KafkaRecordsTenantRejected`), never quoting either value; it used to take the raw header first, checked only for blankness. `TenantKafkaRecordInterceptor` puts only a valid header into the MDC (`_missing` / `_invalid` otherwise), and `kafka.records.received` lost its `tenant` tag (found in the end-to-end test: a forged but well-formed header, read before the record's tenant is resolved, opened a series per value, so any producer could add series without bound; no dashboard used the tag). `UnrecognizedSeverityException` and the JSON-parse message no longer quote the payload; poison-pill logs and dead-letter reasons are one line (`AuditText.error`). `IncidentEscalationEventConsumer`, which acknowledged a poison pill without keeping it, dead-letters it like every other consumer. Log injection through other fields, and structured logs: #0-94 | PR #452 |
| 0-90 | A customer tenant with one admin had nobody to reset that admin's MFA (since #0-88 a password reset keeps the factor and another admin resets it), so a factor enrolled with a stolen password, or a lost phone and lost backup codes, locked the tenant out for good; break-glass covers only `platform-operator`. Now an operator admin who passes `PlatformAccess` asks for an MFA recovery (`POST /api/v1/platform/tenants/{id}/mfa-recovery`, `PlatformMfaRecoveryController`, counted by `PlatformRateLimiter`), the narrow exception to #0-80's "never inside a tenant with an admin": only for an active admin with MFA and an accepted invite who is the tenant's only one, with the verification outside the account recorded (`MfaVerificationMethod`, a one-line note), at most one open request per user (V29's partial unique index). Nothing changes then (as GitHub's 2FA recovery, AWS root MFA, Okta/Entra super-admin recovery; NIST SP 800-63B: tell the account): the account is emailed `MFA_RECOVERY_REQUESTED` with a single-use cancel link (`AuthToken.Type.MFA_RECOVERY_CANCEL`, public `POST /api/v1/auth/mfa-recovery/cancel`), and `MfaRecoveryScheduler` (ShedLock) runs the reset only once `platform.mfa-recovery.waiting-period` (72 h, 24 h to 7 days) has passed since that email was actually sent (`notice_sent_at`, as #0-83's notice); a request whose notice is not sent within the security-notice deadline expires. Before the reset the checks run again (another admin appeared → `OTHER_ADMIN_EXISTS`; no longer an admin with MFA → `NO_LONGER_APPLICABLE`). The reset (`MfaService.resetForRecovery`) is the admin reset plus the password, replaced by the hash of random bytes nobody keeps (not null: a null password means "invite pending" and would have made the tenant look admin-less), as a stranger with a factor may still know the stolen password; `MFA_RECOVERY_COMPLETED` carries a password-reset link. Every status change is one conditional UPDATE from PENDING, so a cancellation racing the execution is decided by the database. Audited in both tenants (`MFA_RECOVERY_REQUESTED` / `_CANCELLED` / `_EXECUTED` / `_EXPIRED`, `shared`; the operator's note only in the operator tenant), alerted on every request and every cancellation by the account (`PlatformMfaRecoveryRequested`, `PlatformMfaRecoveryCancelledByAccount`, critical, content-free). Added in review: the execution also rechecks the operator who asked (no longer an active operator admin → `OPERATOR_NO_LONGER_ADMIN`), so a request filed from an account later found compromised does not run; a cancellation on that final check is alerted (`PlatformMfaRecoveryCancelledOnRecheck`, critical: a second admin added during the wait may be the attacker's); a request the scheduler keeps failing on is counted and alerted (`PlatformMfaRecoveryJobFailing`), as the oldest is retried first and could hold the batch back; expiry repeats "notice not sent" in its UPDATE; a closed request without a reset must name its reason (V29 CHECK); the entity is `Persistable`, so a new request is inserted, not merged. Second review: the waiting period may not be set under 24 h (a variable must not shrink the defence to seconds), the execution also invalidates earlier password-reset links, an executed request carries no close reason (CHECK), and each half of the scheduler run survives the other's failed query. Third review: the customer tenant's trail names an operator only as `platform-operator`; the outcome counters count after commit (no critical alert on a rollback); the execution locks the target's row before its checks; an expired request is alerted (`PlatformMfaRecoveryExpired`); a notice's "not before" counts from its send attempt; that the mailbox holder can cancel every request and the session holder can add a second admin is documented as an accepted limit. Public token endpoints without a request limit: #0-99. Prevention: tenant settings return `activeAdmins` and `singleAdmin`. One definition of an active admin (active, invite accepted) now also in the "last admin" guard, which counted a pending invite and so let the last admin who could log in be removed (found while designing this). Not done: verifying the person by the platform itself: #0-98. Testcontainers tests of the whole flow (notice, waiting period, reset, cancel link, recheck, expiry, index, constraints) | PR #454 |
| 0-96 | A consumer acknowledged a poison pill before its dead-letter copy was written (`DeadLetterPublisher.publish`, fire-and-forget, 15 call sites): a failed send lost it, a refused forged record's evidence included, with only an ERROR line. The fire-and-forget path is gone: a consumer hands such a record to `DeadLetterPublisher.deadLetterThenAcknowledge`, which acknowledges it once Kafka has the copy and `nack`s it otherwise (the way `AuditEventConsumer` already did, #0-84); the copy names its `sourcePartition` and `sourceOffset`, so one stored twice (at least once) can be told apart. Three more of the same kind were found and fixed: a transient failure was "not acknowledged, Kafka redelivers", which in `MANUAL_IMMEDIATE` mode it does not, the next record's acknowledgement commits the offset past it (shown on a real broker by `DeadLetterPublisherKafkaIntegrationTest`, Testcontainers Kafka) — every consumer now `nack`s it (`redeliverLater`, 5 s, `kafka.records.redelivery.requested{reason}`); a record without `X-Event-Type` was acknowledged and dropped (notification, escalation, postmortem, `IncidentEscalationEventConsumer`) and is now dead-lettered; and the rule for "transient" (#47: `TransientDataAccessException` only) took a database outage for a poison pill, since Spring gives it as `DataAccessResourceFailureException` (non-transient) or `CannotCreateTransactionException` (no `DataAccessException`), so escalation and postmortem dead-lettered every event while the database was down. One rule in `shared` now, `KafkaFailures`, for all six consumers; anything else is dead-lettered, as #47 decided (notification-service and `IncidentKafkaConsumer` used to call every exception transient). `IncidentEscalationEventConsumer`'s listener was `@Transactional` and acknowledged inside the transaction, before the commit where the `@Version` conflict of #40 is thrown: the write moved to `IncidentCommandService.recordEscalationLevel`, committed before the acknowledgement. ingestion-service waits for an alert's dead-letter copy and answers 503 with `Retry-After` (`INGESTION_UNAVAILABLE`) when Kafka does not take it. Bounds added in review, so that no record holds a partition, every tenant on it, for ever: a copy waits at most 5 s in all (`DeadLetterPublisher.deadLetterTemplate`, a producer of its own with a 2 s metadata block — escalation-service's producer keeps Kafka's 60 s on purpose, #0-84); each consumer refuses to start unless `max.poll.records` such waits fit in half of `max.poll.interval.ms` (raised from 30 s to 120 s in incident, escalation and postmortem; a `nack`'s delay pauses the partition, `pausedForNack` in spring-kafka 3.3, and does not count); a record failing past `kafka.consumer.redelivery-deadline` (30 min, `RecordRedeliveries`) is dead-lettered, counted (`kafka.records.redelivery.gave_up`) and alerted (`KafkaRecordRedeliveryGaveUp`, critical; `KafkaRecordRedeliveryStuck`, high, after 15 min of nacks); a copy's payload is cut to 128 KiB (UTF-8, marked `originalPayloadTruncated`) so it always fits in a record; a dead-letter reason and its log line keep a message only when the platform wrote it content-free (`KafkaFailures.reason`: a refused tenant, an unknown severity, `UnreadableRecordException`), any other exception by type and the platform's frame (a parser's message quotes the record; `GenericNormalizer` no longer quotes an invalid severity). ingestion-service's producer blocks at most 5 s (was Kafka's 60 s, on the request thread), a request's copies are awaited together under one deadline, a payload is copied once however many of its alerts fail to serialize, and the dedup keys of alerts a lost copy was to keep are released, or the sender's retry was answered as a duplicate and the alert lost; the copies' deadline counts from the wait and no copy starts after one failed (second review). Accepted: a database outage longer than the deadline dead-letters one record per partition per deadline (an audit event then missing from the trail until replayed, #0-97, raising both `AuditEventsRejected` and `KafkaRecordRedeliveryGaveUp`). A record without `X-Event-Type` keeps its tenant in the copy when it has a trustworthy one (`TenantKafkaRecordResolver.trustedTenantOrNull`, not counted). Real-broker test `DeadLetterPublisherKafkaIntegrationTest`, Postgres test `IncidentEscalationLevelIntegrationTest`. `DefaultErrorHandler` and a dead-letter replay: #0-97 | PR #453 |
| 0-39 | Closed by #0-91/#0-92: every producer writes the header (through `TenantRecords`), the resolver dead-letters a record whose header and payload tenant differ, and `AuditEventConsumer` resolves through it like every consumer | PR #452 |
| 0-81 | `application-test.yml` sat in `src/main/resources` of auth-, incident- and ingestion-service, so it shipped in every jar and image, the auth and incident copies with a hard-coded `jwt.secret` and auth's with a valid `mfa.encryption-key`, applied wherever the `test` profile was switched on. No test activated that profile any more (its only user, `BaseIntegrationTest`, went with backlog #45; tests set their keys with `@TestPropertySource`), so the three files are deleted rather than moved to `src/test/resources`. A CI step in "Build, Test & Coverage" (`.github/scripts/check-packaged-profiles.sh`, its cases in `test-packaged-profiles.sh` run first) fails on any committed `application-<profile>.{yml,yaml,properties}` under `*/src/main/resources` or its `config/`, on a profile document (a `spring.config.activate.on-profile` key, nested or dotted, not the words in a comment) in a base `application.*`, on a base `application.*` that switches a profile on (`spring.profiles.active` / `include` / `default` / `group`: in the jar it would apply in every environment, past #0-63's check of the manifests), and (review) on a key ending in `secret`, `encryption-key`, `private-key` or `api-key` (any case, kebab or camelCase) in a base `application.*` that is not a `${VAR}` placeholder without default, quoted or not, since a key written straight into the base file ships just the same (postmortem-service's `gemini.api-key` lost its `your-api-key-here` default for it; compose and every overlay set `GEMINI_API_KEY`); it has no allow-list (review: an empty, untested one), so a profile in a jar needs a backlog decision and a change to the script. This closes what #0-63's manifest check could not (a run outside the manifests). The developer's gitignored `application-local.yml` in locally built jars: #0-100 | PR #455 |
| 0-82 | Nothing ended a tenant (split out of #0-80). An operator now suspends and resumes a tenant, `FULL` or `READ_ONLY`, enforced in auth-service (step 1), in every service and on STOMP (2a), and in the background work of notification-, escalation- and postmortem-service (2b); every auth-service table holding a tenant's data has a foreign key to `tenants` (last part). Full record of the decisions: [the item](#0-82-suspend-and-offboard-a-tenant). Offboarding: #0-101; the pause at scale: #0-102 | PRs #456, #457, #458, #459 |
| 0-93 | A notification channel's failure was recorded with a message built from the mail library's or the Slack client's (an SMTP server's reply, the relay's host and port, a Slack response body) in `notification_log` and the tenant-readable `NOTIFICATION_FAILED` audit event. Now `NotificationException` carries a `NotificationFailureReason` (email: recipient rejected, transport unavailable, authentication failed, other; Slack: rejected, rate-limited, unavailable, workspace missing or unreadable, nothing posted), each marked permanent or not, and at most a provider code checked as `[a-z0-9_]{1,64}` (Slack's `error`, `http_<status>`); its message is built from those alone and the provider's error is only its cause, logged where it is caught (WARN when permanent, the tenant's to fix; ERROR otherwise). The audit event gets a `reason` field; `notification.channel.failed{channel,reason}` counts failed sends (`UNEXPECTED` for an exception no channel anticipated). Found while doing it: Slack answers most failures with HTTP 200 and `"ok": false`, which was read as a delivery, so a message to a channel the bot is not in, or with a revoked token, was recorded SENT; both `chat.postMessage` and `chat.update` now check `ok`. Also: the scheduler's catch-all recorded an unexpected exception's message on the queue entry, now its type. In review: only an SMTP refusal naming the address (enhanced `5.1.x`, or 550/551/553 without one) is the tenant's rejected address, so a relay or policy refusal ("550 5.7.1 Relaying denied") stays the platform's, logged at ERROR; an exception that is not the HTTP client's, rethrown by the Slack fallback, fails only its channel on the ACK update path instead of leaving the loop (`SlackActionService.tryUpdateMessage`); a Slack error that is not a plain code leaves a DEBUG trace. Second review: an `ok:false` without an `error` is `SLACK_REJECTED` (it threw a NullPointerException); a token Slack no longer accepts is `SLACK_AUTH_FAILED`, at ERROR; a refused broadcast no longer stops the on-call DM (before #0-93 it passed as a success, so the DM always went), and the send counts as delivered when the DM went; `send()` classifies an HTTP error itself, as it calls `postIncidentMessage` past the retry proxy (found then, #0-103); a malformed address or a 5xx counts as the tenant's only when it is the recipient's, on `RCPT`. Third review: a refused broadcast is counted (`channel="SLACK_BROADCAST"`) as well as logged. Accepted: a bare 550 without an enhanced code is read as the recipient's (a relay answering a bare "550 Relaying denied" is missed); a Slack answer that cannot be read is a failure, not retried, though Slack may have posted the message (its API always answers JSON, so this is a proxy or an outage). No migration (`error_message` is text). The classification stays in notification-service; auth-service's #0-55 can share it. Per-channel retry by permanence: #0-32 | PR #460 |
| 0-103 | `SlackNotificationChannel.send()` called `postIncidentMessage` on `this`, past Spring's proxy, so its `@Retry` (3 attempts, backoff from 500 ms, on network errors and 5xx) and fallback never ran for an incident notification: one dropped connection or one Slack 5xx failed the channel at once (found in the second review of #0-93). The two Slack Web API calls moved to a bean of their own, `SlackApiClient` (`postMessage`, `updateMessage`, `@Retry` + fallback, `requireOk` and the #0-93 classification), which the channel calls through the proxy, the split #0-21 made for the same mistake. Found while doing it: the Slack client had no timeout (built from the bare `RestClient.Builder`, no read timeout), so a Slack that never answered held the scheduler's thread and, never throwing, was never retried; it now has its own, `notification.channels.slack.connect-timeout` / `read-timeout` (3 s / 5 s, positive, apart from `notification.client.*`; the read timeout also cuts a body that trickles in). The fallbacks no longer log: the send path's caller already did, and the ACK path (`SlackActionService.tryUpdateMessage`) now logs a failed update itself, WARN or ERROR by permanence. Accepted: `chat.postMessage` takes no idempotency key, so a post retried after a read timeout or a 5xx may show twice; a duplicate beats a lost incident message. In review: with the retry running, a hanging Slack costs about 25 s per call and 51 s per entry (broadcast and DM), and the scheduler checks its budget only between entries, so an entry started just before the budget ran out could outlive the 4-minute ShedLock and a second replica send the same notifications; the scheduler now refuses to start unless budget + 30 s + each channel's `worstCaseSendTime()` fits the lock (`SlackApiClient.worstCaseCall`, from the `slack` retry's own config), the default budget went from PT3M to PT2M30S and the read timeout from the 10 s first chosen to 5 s. `SlackApiClientResilienceTest` goes through Spring's proxy from `send()` (WireMock: 5xx, a read timeout and a trickling body retried or cut, 401 and `ok:false` not, the ACK update retried); the standalone-`Retry` tests it replaces could not see the bypass. `NotificationSchedulerDefaultsTest` keeps `application.yml`'s defaults inside the lock, with the retry Resilience4j's auto-configuration builds from the file. Second review: the client never follows a redirect, pinned rather than left to the JDK's default (the request carries the tenant's bot token). Email and SMS declaring their own worst case: #0-105. No circuit breaker yet: #0-104. Per-channel retry across scheduler runs is still #0-32 | PR #461 |
| 0-104 | Since #0-103 a Slack call that times out is retried, so while Slack accepted connections and did not answer, every entry with a Slack channel cost about 51 s: the scheduler sent about three entries per run, every other tenant's email and SMS waited, Slack got three times the requests, and the ACK updates held `slackTaskExecutor`'s threads as long. `SlackApiClient`'s two calls are now behind a circuit breaker, `slack` (time-based 60 s window, at least 5 calls, 50%, 30 s open, one trial call, no health indicator: a channel's outage must not mark the service DOWN), the service's other breakers' idea but without a fallback of its own: Resilience4j puts the retry outside it, an open breaker's `CallNotPermittedException` is not retried, and the retry's fallback classifies it as `SLACK_UNAVAILABLE` with its own code, `circuit_open` (it would have been recorded as UNEXPECTED). Only network errors and 5xx count; 4xx, 429 and `ok:false` are ignored, so no tenant's workspace can open it for the others (Slack's own `ok:false` outage codes and an unreadable 200 with them: they answer at once). One breaker for every tenant (Slack's API is one service; one per workspace would multiply breakers and series and not help when Slack is down). Accepted until #0-32: while it is open, Slack messages are recorded FAILED without being tried and never resent, a run's whole batch at once (noted in #0-32). The scheduler's lock check (#0-103) still counts the closed breaker's worst case. Alert `SlackCircuitOpen` (high): the breaker refused calls (`not_permitted_calls_total`) within the last 10 minutes, held 5 minutes; in review it moved off the breaker's state, which stays half-open with no traffic and kept the alert up after Slack recovered, and from a 3-minute window to 10 minutes, as every refusal is a lost notification and refusals minutes apart (sparse traffic) slipped through the shorter one (promtool tests: sustained, sparse, a burst that fires and resolves, idle, another breaker, another job). `SlackApiClientResilienceTest` through the proxy, on `application.yml`'s own settings (opened by 5xx and by timeouts and failing fast without calling Slack, the ACK update too, not opened by 401/429/`ok:false`, closed by a successful trial and reopened by a failed one); `SlackResilienceConfigTest` checks `application.yml`'s breaker (every setting) and retry as Resilience4j builds them. Rejected: a deadline passed into the send (bounds only the last entry, does not spare Slack), Slack in a pool of its own (changes when an entry counts as sent, close to #0-32) | PR #462 |
| 0-94 (step 1) | Every service logs one JSON object per line in ECS (Spring Boot's structured logging, set for all seven by `shared`'s `StructuredLoggingDefaults`), so every value is escaped and the MDC keys are fields; plain text only in a developer's `application-local.yml`. Steps 2 (collection) and 3 (tracing) stay open: [the item](BACKLOG.md#0-94-logs-are-plain-text-with-no-structure-escaping-or-collection) | PR #463 |
| 0-94 (step 2) | The platform's container logs are collected in docker-compose: `docker-socket-proxy` (GET on containers and networks only) → Alloy → Loki, 15 days, read in Grafana; `service`/`container`/`level` labels, tenant, request, user and Kafka message ids as structured metadata; alerts `LogPipelineDown`, `LogPipelineRestarting`, `LogPipelineNotScraped`, `LogsNotFlowing`, `LogDiscoveryFailing`, `LogsDropped`; Loki and Alloy on an internal network of their own with Grafana and Prometheus, Loki's delete API off; the smoke test checks the lines arrive parsed, the proxy stays read-only and Loki and Alloy cannot be reached from the services; Grafana off the services' network, on `127.0.0.1` with a required admin password and a pinned image; the proxy, Loki and Alloy read-only with no capabilities (Alloy not root); a level outside TRACE..ERROR stored as `OTHER`; Docker logs rotated. k8s: #0-106, alerts on content: #0-107; step 3 (tracing) stays open: [the item](BACKLOG.md#0-94-logs-are-plain-text-with-no-structure-escaping-or-collection) | PR #464 |
| — | Register a default no-op `TokenRevocationChecker` so incident-service starts (unblocked CI on `main`) | PR #410 |
| — | Key notification idempotency on tenant + escalation level; stop dropping level-2 escalations | PR #411 |
| — | Align README/CLAUDE.md with the code; add LICENSE; scrape auth-service in Prometheus | PR #409 |
| 0-114 | Run two autopilot items at the same time — **closed, not implemented**: the autopilot stays strictly sequential, each item built on a reviewed `main` (`.ai/rules/planning.md`) | decision 2026-10-09 |
| 0-8 | Removed the dead `IncidentEventPublisher.publishEscalated` (and its test); `IncidentEscalationEventConsumer` and `Incident#recordEscalation` Javadoc now name escalation-service's `EscalationScheduler` as the only producer of `IncidentEscalatedEvent` | PR #472 |
| 0-7 | `IncidentEscalationEventConsumer` validates `escalationLevel` (JSON integer 1..2) instead of `asInt(0)`; an invalid level is dead-lettered under its tenant with a content-free reason | PR #475 |
| 0-122 | The paths no agent writes have one list, `.ai/rules/protected-paths.md`, read from the base commit by `changed-paths.sh`, `next-item.sh`, `check-queue.sh` and `check-factory-guards.sh` rule 6; an item whose Touches names one (or a bare `ci`) never starts; the deny rules, the shell hook (now also `.ai/audit/decisions.md`) and CODEOWNERS are checked against it in CI; `state.sh` records a BLOCKED item's stop stage and draft PR. Found when #0-42 ended BLOCKED (draft PR #477). Decision history kept in [the section #0-122 below](#0-122-protected-paths-one-list-a-touches-gate-and-the-stop-stage) | PR #478 |
| 0-123 | The read-only agents are told which tool to use (Read for files, `git grep -n -e … -- <paths>` to search, one git command per call, `git status --short` for new files) and every refusal of `readonly-bash.sh` they can hit names it, per mode; allow-list unchanged. The architecture reviewer went from over 14 minutes and four refusals to 66 s. Decision history kept in [the section #0-123 below](#0-123-reviewers-are-told-which-tool-to-use-and-every-hook-refusal-names-it) | PR #479 |
| 0-120 | Closed as a duplicate of #0-29 (staging and prod overlays swapped), opened by `/ready #0-42` without searching the backlog; its one new point, a CI assertion on each overlay's rendered namespace, was moved to #0-29 | duplicate of #0-29 |
| 0-42 | Dev on Kubernetes catches mail in Mailpit (dev overlay only, ClusterIP, non-root and read-only, the compose image) with the compose SMTP auth/STARTTLS overrides in dev's app-config; base `MAIL_HOST` is a placeholder (`smtp.incident-platform.local:587`) and staging/prod have no catcher or override; the dev JVM patches target `component=backend` only; `check-k8s-mail.rb` (8 rules, 22-case mutation test) enforces it in CI. ADR-0026. Decision history kept in [the section #0-42 below](#0-42-kubernetes-mail_host-points-at-a-mailhog-that-does-not-exist) | PR #480 |
| 0-124 | notification-service requires STARTTLS before sending SMTP credentials (`mail.smtp.starttls.required: true`, as auth-service); docker-compose sets the `false` dev override for notification-service like the k8s dev overlay; `SmtpTlsDefaultsTest` checks the default and the override | PR #482 |
| 0-125 | `/ready` lists in Touches the files a convention makes a change write — README "Infrastructure Hardening" for a security control or a closed gap (CLAUDE.md "Security inventory"), `.ai/context/` or an ADR for new knowledge or a decision — in `ready.md` point 8 and the ready-checker's draft; every checker question gets an answer, a "no" with its reason in the PR's "Ready check". Found when `/ready #0-124` missed README and PR #482 recorded `backlog-estimate-off`; the case is in #0-121 "Collected cases" | PR #483 |
| 0-121 | A pipeline audit (`audit.js` target `pipeline`, default `all` with the reviewers' audit): `audit-data.sh` derives the cases from what the pipeline records (BLOCKED, extra rounds, scope that points at a stage, acceptance, owner labels, BLOCKED runs without a PR, escape markers added in the period) with each item's merged `/ready` PR; the read-only `audit-pipeline` agent traces each case from the stage that introduced it to the one that detected it, with an escape class per stage between, and recommends to the cheapest stage; owner labels `human:introduced-<stage>`. Decision history kept in [the section #0-121 below](#0-121-a-pipeline-audit-traces-problems-to-the-stage-that-introduced-them) | PR #484 |
| 0-127 | The pipeline audit gives the introducing stage a cause with its actor (ready-checker vs owner, planner vs owner); `audit-data.sh` counts only real escape markers, and an unparsable one is an `escaped:unparsed` case | PR #486 |
| 0-126 | The audits count a `human:*` label only when the repository owner added it: `audit-data.sh` reads each PR's label events and keeps `verifiedLabels` / `unverifiedLabels` (human labels stripped from the raw `labels`, any case), failing closed (another account, no event, owner unreadable; and no label at all while an autopilot PR is authored by the owner's login). Agents read labels only from that data; `audit.js` puts what did not count in every report. The autopilot's shell guard (`gh_label_unsafe`) allows only the shipper's labels on `gh pr\|issue create\|new\|edit` in every form, plus deny rules. Beyond the item's ACs and Touches (found in `/research` and four review rounds): every `human:*` label incl. `human:agree`, the audit agents, `audit.js`, `ship-record`, `docs/ai-factory.md`; follow-ups #0-129, #0-130 | PR #489 |
| 0-128 | Factory guards fails a backlog line that tries to be an escape marker but is not one the audits can read (no `**Fixes:** #0-<digits>`, another case, not bold), with file and line (`check-escape-markers.sh` + test); the marker is defined and parsed once, in `scripts/factory/_marker.sh` | PR #491 |
| 0-129 | The audits count an escape marker only when the commit that first added the marker itself is in a PR merged into `main` and opened by the owner (`audit-data.sh`, `gh api commits/<sha>/pulls`); the rest go to `unverifiedEscapes` with a reason, failing closed (owner unknown, lookup failed, shallow clone, autopilot on the owner's login). Traced by the marker, not its line; new only when its origin is in the period; history read without replace refs, grafts or textconv. Known limit #0-131. Decision history kept in [the section #0-129 below](#0-129-the-pipeline-audit-counts-only-escape-markers-the-owner-added) | PR #491 |
| 0-130 | The shell guards refuse a command when their own check fails: `git_grep_unsafe` and `gh_label_unsafe` answer may run / refused / failed (non-zero), and `guard-protected-bash.sh` and `readonly-bash.sh` refuse on a non-zero status; matching with bash's own `[[ =~ ]]` in the C locale and `case`, every `sed`/`tr` step `|| return 2`. Beyond the item (four review rounds): a newline inside a quoted word, `git grep` behind a program, an assignment, a path or a glob, and a glob as the git subcommand (`git gr?p`) are refused, all bypasses also on `main`. Follow-up #0-132 (the guard's own checks, `json_get`). Decision history kept in [the section #0-130 below](#0-130-a-shell-guard-that-fails-refuses-the-command-instead-of-allowing-it) | PR #492 |
| 0-119 | postmortem-service's `IncidentEventConsumer` validates `durationMinutes` (JSON integer >= 0 that fits an `int`; 0 is valid) instead of `asInt(0)`, and a malformed `occurredAt`/`openedAt` is a named poison pill, each dead-lettered with a content-free reason; `openedAt` is counted back from `occurredAt` instead of `Instant.now()`. The exact `openedAt` in the event is #0-133 | PR #493 |
| 0-76 | The k8s job's validation inputs are pinned (ADR-0027): kubeconform 0.8.0 by SHA-256, downloaded into `RUNNER_TEMP` and checked before it is unpacked (the Snyk CLI's pattern, #0-61), instead of `releases/latest` piped into `tar`; its schemas from a pinned commit of `yannh/kubernetes-json-schema` instead of `master`; one `KUBERNETES_VERSION` (1.36.5) for the kubectl that renders (was 1.31.0) and the schemas. Beyond the item: the schemas, which the item's approach left on `master`. Follow-ups #0-134 (`diff-cover` hashes), #0-135 (kubectl signature), #0-136 (security review rule) | PR #494 |
| 0-29 | The staging and prod k8s overlays carry their own bodies again (they had held each other's since the first commit, so "prod" deployed staging images at staging's size into `incident-platform-staging`); new CI check `check-k8s-environments.rb` with its mutation test: every overlay renders into `incident-platform-<overlay>`, no prod image untagged or `latest`, no prod service tagged with an environment's name. Beyond the item: #0-79's figures and `docs/database-roles.md` relabelled, CI rules renumbered in `.ai/context/infrastructure.md`. Follow-ups #0-137 (overlay replicas vs HPA), #0-71 (tags stay mutable), #0-136 (environment-separation rule, cluster-scoped kinds) | PR #495 |
| 0-137 | The HPAs own the services' replica counts (ADR-0028): no Deployment sets `spec.replicas`, each overlay patches its HPAs' `minReplicas`/`maxReplicas` (prod auth 2–3, incident and ingestion 3–5, the other four 2–2; staging incident and ingestion 2–3; dev 1–1), so prod's floors hold and `kubectl apply` no longer resets an HPA-scaled count; `check-k8s-environments.rb` rules 4 and 5 (HPA per service, no `spec.replicas`, floor ≤ ceiling, prod floor ≥ 2). Beyond the item: auth-service ran one pod in prod; the Kubernetes password migration restarts with `kubectl scale --replicas=1`. Follow-ups #0-138 (PodDisruptionBudget, topology spread), #0-139 (HPA on memory) | PR #496 |
| 0-138 | A PodDisruptionBudget and a spread over nodes protect every service's replica floor (ADR-0029): `k8s/base/<service>/pdb.yml` for all seven (`maxUnavailable: 1`, never `minAvailable`, which at the floor blocks every drain; `unhealthyPodEvictionPolicy: AlwaysAllow`), in base for every overlay; each pod template spreads over `kubernetes.io/hostname` (`ScheduleAnyway`, `matchLabelKeys: [pod-template-hash]`); `check-k8s-environments.rb` rule 6 in every render. Follow-up #0-140 (zones, rebalancing after scale-down) | PR #497 |
| 0-141 | One 502 from Maven Central failed the image builds: Maven now builds the services once and the images only package the jar (ADR-0030). The Dockerfiles are JRE-only and package `<service>/target/<service>-*.jar`, layered (`jarmode=tools extract`, `JarLauncher`, files root-owned); `.dockerignore` is an allowlist of those jars; build-and-test uploads the tested jars (`service-jars`) and the smoke test builds the images from them, the per-service `docker-build` matrix removed; the Maven cache is `actions/cache` restored by prefix within the month and saved on `main` only (snyk and OWASP restore it); `.mvn/maven.config` retries 429/5xx; the smoke test proves `break-glass-mfa-reset` still reaches `main`; `make dev-up` builds the jars first. Full record, with the design it replaced: [the section #0-141 below](#0-141-one-502-from-maven-central-fails-the-image-builds). Follow-ups: #0-142, #0-143 | PR #498 |
| 0-100 | A locally built jar no longer contains the developer's `application-local.yml`: the root POM's `maven-jar-plugin` excludes `application-local.*` and `application-secrets.*` from every jar, `shared` included (since #0-141 local images package a locally built jar); CI plants both in every module and `check-no-local-config-in-jars.sh` (with its own cases) checks every service jar and the `shared` jar nested in it | PR #498 |
| 0-144 | `.gitignore` no longer ignores the tracked `docker/.env.example` template, which search tools (ripgrep, Claude Code's Grep, the review agents) skipped and `git add` would have refused once recreated; `docker/.env` stays ignored by `*.env` | PR #498 |
| 0-142 | The Maven distribution `./mvnw` runs is pinned and checked (ADR-0031): `distributionSha256Sum` in `.mvn/wrapper/maven-wrapper.properties` (Central has no `.sha256`; the value comes from a zip matched against `downloads.apache.org`'s `.sha512`); `check-maven-wrapper-sum.sh` (29 offline cases) checks it against Apache's SHA-512 on every miss, since Renovate writes the sum of what it downloaded, unchecked; `~/.m2/wrapper` has its own exact-key cache (properties + checker, no `restore-keys`, saved on `main` only, restored by snyk and OWASP), because mvnw never checks a distribution it finds unpacked; the repository cache holds `~/.m2/repository` only, under the new prefix `maven-repo-`. Beyond the item: the six unpinned per-module wrappers from the first commit, which unpacked into the same directory, are removed. Follow-up #0-145 (nothing checks that the cache key copies stay equal) | PR #500 |
| 0-145 | The Maven caches are written in one place and CI enforces it (ADR-0031): `.github/actions/restore-maven-caches` (month, both restores, outputs) for the four jobs that run `./mvnw`, `save-maven-caches` (both saves) for build-and-test on a push to `main`; the distribution's key also hashes both actions; `check-maven-caches.rb` (tenth structural rule, 31 cases) refuses a cache of `~/.m2` outside the actions (OWASP's data excepted) or setup-java `cache: maven`, `~/.m2/wrapper` with another path or `restore-keys`, `~`/`~/.m2` in the actions, a save to another path than the restore's, a key without its four files. Done more broadly than the item's Approach (a key-equality check): the copies are gone and #0-142's rules are enforced too. Follow-up #0-146 (actionlint in CI) | PR #501 |
| 0-146 | CI lints the workflows (ADR-0032): job `lint-workflows`, always run, actionlint on every workflow (expressions, `needs`, untrusted input inline, how a workflow calls a local action) with every workflow `run:` block through shellcheck; both pinned by version and SHA-256 in the job's `env` and checked before unpacking (actionlint's sum where its `checksums.txt` and GitHub's digest agree, shellcheck's from GitHub's digest), never `download-actionlint.bash` nor the runner's shellcheck; no baseline, the repository is clean. Not the composite actions' own steps nor the `.sh` scripts (checked; #0-149). Follow-ups #0-147 (zizmor), #0-148 (main-guard and fork PRs), #0-149 | PR #502 |
| 0-148 | main's CI result is a push to this repository only: `main-guard.yml`'s job also requires `workflow_run.event == 'push'` and `head_repository` == this repository, and the preflight reads `gh run list --event push`. `branches: [ main ]` and `--branch main` match a run's head branch (confirmed on the run history), so a fork pull request from a branch named `main` could open the `autopilot-stop` issue, stop the preflight, or hide a red main from it. Done more broadly than the item (main-guard only): the preflight had the same flaw; it now also takes "no run" explicitly and stops on a status gh does not document. `test-preflight.sh` (10 cases, gh stubbed) in Factory guards; `ci.yml`'s `on:` names both consumers for a new trigger (#0-113) | PR #503 |
| 0-147 | Every CI tool downloaded from a GitHub release (Snyk CLI, kubeconform, actionlint, shellcheck, zizmor) is a pin Renovate bumps (`# renovate:` comment + `<NAME>_VERSION` + `<NAME>_SHA256`, one `customManagers` regex, 7 days) and CI checks against its publisher (ADR-0033): `check-pinned-tools.sh` in Lint Workflows (GitHub's digest, then attestation / Snyk's GPG signature / `CHECKSUMS` / digest; also in both Snyk jobs with `--expect 1`, before the CLI and the build), one installer `install-pinned-tool.sh`; zizmor audits the workflows and actions (offline, regular persona), `main-guard.yml` permissions per job. Follow-ups #0-150, #0-151, #0-152 | PR #504 |
| 0-149 | Lint Workflows shellchecks every tracked `.sh` file and every composite action's bash/sh step with the job's pinned shellcheck (`check-shell.rb`, ADR-0032 amended): every severity (SC2086 is a note), `--norc` (a `.shellcheckrc` silenced it and is on no protected list), libraries followed, `${{ }}` replaced, findings at their line in `action.yml`; the 99 findings resolved, the meant ones disabled at their line with the reason above, one real bug fixed (`test-hooks.sh`'s setup could commit in the developer's repository). `check-downloads.rb` enforces ADR-0033's one installer: curl, wget, a release asset's URL or `gh release download` in a `run:` block fail unless the line ends `# not-a-download: <why>` (a tripwire, not a boundary). `run-blocks.rb`: one reader of `run:` blocks and one annotation escaper | PR #505 |
| 0-113 | What guards `main` is files in `.github/repository-settings/` (ADR-0034), applied by the owner with `repository-settings.rb apply` and compared with GitHub by Lint Workflows on every PR and push (`check`; main's files on a PR that does not change them). One ruleset `main`: a PR with the owner's approval of the last push (stale approvals dismissed), every `ci.yml` job and Factory guards as required checks pinned to GitHub Actions, no force-push or deletion; one bypass, the admin role at merge only, never for a Claude Code session (`.claude/settings.json` denies it and every write to the ruleset); `delete_branch_on_merge` on, `allow_auto_merge` off until phase 3, the admins listed and compared; `CODEOWNERS` catch-all for shadow mode. The check also refuses a required check no job reports, a job no ruleset requires, a name two workflows share, a check without its app, and a token that may write checks or statuses or declares no permissions. Verified 2026-10-18: direct push to `main` refused, a bot PR with a red check refused after the owner's approval (AC1), a bot PR touching `.ai/rules/` refused without it (AC2). Follow-ups #0-153, #0-154 | PR #506 |
| 0-109 | Every commit a pull request adds (`base..head`) or a push brings to `main` (`before..after`) is scanned for secrets by the required job "Secret Scan" (ADR-0036): betterleaks v1.9.0, not gitleaks, with its default rules, pinned by a new `verify=release` method in `check-pinned-tools.sh` (`gh release verify-asset`), installed by `install-pinned-tool.sh`. Commits, not the tree (a secret added and deleted is caught, so is one written in a merge's conflict resolution); findings are annotations without the value; `secret-scan.sh` refuses a root config or ignore file the scanned PR could widen, so a finding that is no secret takes `gitleaks:allow` and its reason on its line, and each commit adding or removing one is named in a warning. The 1170 commits on `main` were scanned once: nothing to rotate. Verified 2026-10-19: a PR adding a made-up `generic-api-key` failed Secret Scan and was blocked (AC1, PR #509, closed). Follow-up #0-156 (scan before the push) | PR #508 |
| 0-154 | `SNYK_TOKEN` and `NVD_API_KEY` are no repository secrets any more but secrets of the environment `scans`, whose branch policy allows `main` only, with no admin bypass (ADR-0035); every Snyk and OWASP job reading one runs in it (`deployment: false`) and also has `if: github.ref == 'refs/heads/main'`. The environment is a file, `.github/repository-settings/environments/scans.json`, applied by the owner and compared by `repository-settings.rb check`, which also fails a repository secret, a secret a job reads outside an environment holding it, `toJSON(secrets)`, `secrets: inherit` and a secret read by a job a pull request triggers. The Snyk token, expired since 2026-10-18 (SNYK-0005), was replaced by a new one set in the environment only. Verified 2026-10-20: dispatches of `snyk.yml` and `owasp-dependency-check.yml` on throwaway branches with the `if:` removed were refused by the environment before any step ran (AC1; both branches deleted). Follow-up #0-155 (a scan that cannot run alerts no one) | PR #507 |
| 0-150 | The OWASP scan no longer passes the NVD key on Maven's command line: the root `pom.xml` sets the plugin's `nvdApiKeyEnvironmentVariable` to `NVD_API_KEY`, which the scan step gets as an environment variable from the environment `scans` (with #0-154, ADR-0035) | PR #507 |
| 0-118 | An out-of-order `IncidentEscalatedEvent` no longer lowers a recorded level: `Incident.recordEscalation` ignores a level not higher than the recorded one (`updatedAt` unchanged), `IncidentCommandService.recordEscalationLevel` saves only a raised level and returns `RAISED` / `NOT_HIGHER` / `INCIDENT_NOT_FOUND`, the consumer acknowledges `NOT_HIGHER` as processed. The order holds in the ordinary flow (keyed by incident id, level 2 only after level 1); it does not on a dead-letter replay (#0-40), added partitions or reset offsets. A conditional `UPDATE` was rejected (a second write path past the entity and its `@Version`) | PR #511 |
| 0-157 | Tomcat 10.1.61 in every service: the root POM sets `tomcat.version` (Spring Boot 3.5.16, the last 3.5 release, brings 10.1.55; Apache still patches 10.1), fixing the six Snyk issues of 2026-10-20 (CVE-2026-68525, -68569, -68763, -76183, -77791, -79677; only the two WebSocket DoS were reachable, in incident-service). The four Tomcat ignores in `.snyk` (resting on a false "all endpoints require JWT" claim; already fixed in 10.1.55/.56) and the seven expired `tomcat-embed-*` OWASP suppressions are removed: no Tomcat CVE is ignored. The override goes with Spring Boot 4 (#0-158); bumping and checking it is by hand until #0-159 | PR #512 |
| 0-160 | What a reviewer could not verify is checked: the reviewers get the test gate's artifact (`gate-r<round>.json`: tested HEAD, tests and JaCoCo per module, `dependency:tree`; `/review` runs the gate with `--working-tree`), and a `verifier` agent that never sees the diff checks their `unverified` claims from that artifact and an allow-list of six advisory and release prefixes (WebFetch only for it, a session-level hook on `agent_type`; it reads only the gate's files). Refuted blocks, unverifiable stops the item for the owner, every verdict is in the PR (ADR-0037). Decision history kept in [the section #0-160 below](#0-160-what-a-reviewer-could-not-verify-is-never-checked) | PRs #513, #514 |
| 0-161 | The AI factory has its own review rules: `.ai/rules/review/factory.md` (`FAC-S` for review-security, `FAC-A` for review-architecture), read only when the diff touches a path of the Owner-only list of `protected-paths.md` (`/review` decides it from the list on `main`; unreadable list = rules apply); the architect reads every rule file but this one (ADR-0038). Decision history kept in [the section #0-161 below](#0-161-no-review-rule-covers-the-ai-factory-itself) | PR #515 |
| 0-162 | Every hook of the AI factory fails closed, in two layers: each hook turns any failure it can see into exit 2 (an `EXIT` trap, a guarded load of `_lib.sh`, `json_get` telling a parser failure from no field; a fail-closed table in `test-hooks.sh`, PR #516), and every hook entry of both settings files and the agents' frontmatter says `"onFailure": "block"`, so Claude Code blocks a call whose hook cannot start or times out; Factory guards checks every entry (`check-hook-entries.rb`), and the autopilot's preflight refuses Claude Code older than 2.1.295, which ignores the field silently (ADR-0039, PR #517). Decision history kept in [the section #0-162 below](#0-162-a-hook-that-cannot-load-its-helper-lets-the-call-through) | PRs #516, #517 |
| 0-166 | CI's Lint Workflows and Factory guards jobs run locally in about 50 s instead of 428 s: `.github/scripts/ci-local.sh` runs the workflows' own `run:` steps (`ci-local-steps.rb`, no list of its own) in an image `FROM ruby:<.ruby-version>-slim` cached per platform, both jobs native with only the pinned x86_64 linters emulated, the tree as a tar of the files git does not ignore (no mount; refused with a stash, credentials in git config, inside a container); Ruby is pinned in CI like Java and Python (`.ruby-version` 4.0.9, `.github/actions/setup-ruby`, `check-ruby-setup.rb`, ADR-0040), after a newer json gem on the runner changed a check's result. Decision history kept in [the section #0-166 below](#0-166-checking-cis-linux-steps-locally-takes-seven-minutes) | PRs #518, #519 |
| 0-164 | Every agent's guard runs in two layers: its frontmatter and a session-level twin in both settings files (`<hook> --agent <names>`, keyed on `agent_type` through `applies_to_agent`), since Claude Code does not promise frontmatter hooks to a Workflow's agents; `check-hook-entries.rb` keeps the twins equal to the frontmatter and checks that the session-wide guards stay wired (ADR-0041). Decision history kept in [the section #0-164 below](#0-164-the-agents-guards-rely-on-frontmatter-hooks-that-workflow-agents-are-not-promised) | PR #520 |
| 0-165 | The owner's review trusts nothing of the branch it reviews: `/review` and `/accept` pre-approve exact commands only, reviewers read `.ai/rules/review/` from `refs/remotes/origin/main` (a reviewer that cannot read one answers `NEEDS_HUMAN`), and the owner reads a foreign branch's `.claude/`, `CLAUDE.md` and `.ai/context/` changes before `/review` (ADR-0042); the session-level hook moved to #0-167. Decision history kept in [the section #0-165 below](#0-165-the-owners-review-session-trusts-the-branch-it-reviews) | PR #521 |
| 0-163 | The autopilot workflow's logic is tested: `.github/scripts/test-autopilot-workflow.mjs` evaluates `backlog-autopilot.js` as the runtime does, with a fake `agent()`, and tests its helpers (the verifier's fail-closed paths, `acceptUnverifiable` by id) and whole runs (every stage's stop, the checks of `args`), 32 mutations killed; Node pinned like Ruby for it (`.node-version`, `.github/actions/setup-node`, `check-runtime-setup.rb`, ADR-0043). Decision history kept in [the section #0-163 below](#0-163-the-autopilot-workflows-logic-has-no-tests) | PRs #522, #523 |
| 0-168 | The protected-path copies are checked against the one list both ways: `check-protected-paths.sh` fails when a deny (as `Edit(./…)`/`Write(./…)`, no other spelling) or an alternative of the hook's flat `protected=` line protects a path the list lacks; the autopilot's runtime state (`.git/`, `.ai/runs/LOCK`, `.ai/runs/state.json`, `.ai/STOP`) is the list's third section, so its copies are checked too. Decision history kept in [the section #0-168 below](#0-168-a-copy-of-the-protected-paths-can-run-ahead-of-the-one-list) | PR #524 |
| 0-131 | The autopilot pushes only its own run's branch: the workflow records it in `.ai/runs/LOCK` (`state.sh branch`, once, bound to `<type>/<item>-…` and on resume to the owner's branch) and `guard-git-push.sh` pushes nothing else; only `factory-ops` runs `scripts/factory/`; git's `--output`/`--ext-diff`/`--textconv` count as writes to protected paths. Spliced option words remain #0-167, factory-ops' binding to its task #0-169. Decision history kept in [the section #0-131 below](#0-131-the-autopilot-pushes-only-the-branch-of-its-own-item) | PR #525 |
| 0-132 | The shell guards' own checks refuse when they fail: they match with `finds` (bash's own regex over the whole command, no grep), so a failing or missing grep, or a multi-line command past an anchored allow pattern, no longer lets a call through; `shell_words` answers by exit status (the text shim is gone); one list of wrapper programs. Decision history kept in [the section #0-132 below](#0-132-the-shell-guards-own-checks-refuse-when-they-fail) | PR #526 |
| 0-170 | `/seed-bugs` tells a run that measured nothing from a result: a refused seeder answers `blocked` and the run ends FAILED with the refusal, a skip without a reason and an unusable ground truth (not this run's `seed/` branch, no file, line or rule) end it FAILED; the seeder is told how commands run in an autopilot session. AC3 (a real run records a row) is the rerun of #0-115's "after" measure. Decision history kept in [the section #0-170 below](#0-170-seed-bugs-measured-nothing-the-seeders-commands-were-refused-and-reported-as-a-skip) | PR #528 |
| 0-173 | `/seed-bugs` no longer switches the shared working tree to the merged commit: `scripts/factory/seed-branch.sh` builds the seed branch from `main` (the change's code reverted, then back; protected paths, `CLAUDE.md` and Markdown never replayed), `seed-check.sh` confirms the tree after the seeder before the panel runs, and every run ends on `main` or says where it left the tree; the result row is written on `main` (ADR-0044). AC3 (a real run records a row) is the owner's rerun of #0-115's "after" measure. Decision history kept in [the section #0-173 below](#0-173-seed-bugs-switches-the-shared-working-tree-to-an-old-commit) | PR #529 |
| 0-174 | `/seed-bugs` starts from its own command (`/seed-bugs <pattern> <commit> <run id>`, one string, read as the three args and checked by `SAFE`), and the factory scripts' answers have typed schemas with `additionalProperties: false`, so `factory-ops` can no longer answer in strings or wrap the JSON; review rule FAC-A06. AC3 (a real run records a row) is the owner's P-10 rerun, with #0-173's. Decision history kept in [the section #0-174 below](#0-174-seed-bugs-cannot-start-from-its-own-command-and-reads-strings-from-factory-ops) | PR #530 |
| 0-176 | `/seed-bugs` types the panel's verdicts (`VERDICT`/`FINDING` as `backlog-autopilot.js`'s, held in step by a test both ways, only `issue` required of a finding) and ends on `main` after any error: every step after the branch runs in `measure()`, `backToMain()` never throws, and a measure whose row cannot be written is kept; FAC-A06 covers any agent's answer a workflow reads; P-12's row recorded by hand. AC4 (a run that reaches the panel records its row) is the owner's P-10 or P-11 rerun. Decision history kept in [the section #0-176 below](#0-176-seed-bugs-reads-the-panels-verdicts-untyped-and-an-error-strands-the-tree-on-the-seed-branch) | PR #531 |
| 0-177 | A `/seed-bugs` series needs no commit on `main` between runs: `scripts/factory/seed-record.sh` writes each row to the gitignored `.ai/runs/benchmark/results.md` (typed `{appended}`, a recorded run id refused; `audit-synthesis` no longer writes it), and a series' rows land in `.ai/audit/benchmark/results.md` in one PR. The panel cannot tell a measure from a review: the branch is `review/<8 hex>`, the base says `Revert "<subject>"`, and `scripts/factory/seed-fold.sh` folds the seeder's commit into the change's and drops the run's reflog entries; the catalogue stays readable on purpose (ADR-0044 decisions 5 and 6, with the P-10..P-12 transcripts as evidence). Decision history kept in [the section #0-177 below](#0-177-seed-bugs-asks-for-a-commit-on-main-between-runs-and-its-panel-can-tell-it-is-measured) | PR #533 |
| 0-182 | No reviewer renders or validates the Kubernetes manifests: `readonly-bash.sh` has no `--k8s` mode and refuses an unknown mode, `review-k8s` runs the plain read-only guard in its frontmatter and the plain twin of both settings files, and no allow rule names `kubectl` or `kubeconform`; CI renders and validates (ADR-0045). A guard of `kubectl kustomize`'s forms was built first and bypassed in both review rounds; a tracked-only render is #0-183. Decision history kept in [the section #0-182 below](#0-182-the-k8s-reviewers-guard-lets-kubectl-kustomize-and-kubeconform-take-any-option) | PR #547 |
| 0-115 | The eight review rule files are invariants, each rule with a "Check:" line or retired with its reason, ids never reused, the labels defined once in `_common.md`: `performance.md` (pilot), `security.md`, `architecture.md`, `general.md`, `migration.md`, `docs.md`, `k8s.md`, `factory.md`. Each was measured on `main` by seeded defects (`.ai/audit/benchmark/results.md`): every planted pattern caught and blocked by its dimension, P-15 after GEN-08 was sharpened. Not measured: P-19 (waits #0-172), P-22 (no host), FAC-S (its hosts are what `/review` runs under); the caveats of the runs are #0-179 (a relayed command), #0-181 (one-line scoring) and #0-185 (the original in reach). Decision history kept in [the section #0-115 below](#0-115-rewrite-the-review-rules-as-invariants) | PRs #527, #532, #534 to #546, #548, #549 |
| 0-184 | What the review rule files claim is checked (`.github/scripts/check-rule-claims.rb`, Factory guards, ADR-0046): every script, test or guard a label names exists; an "Enforced by" check runs in a required job of `rulesets/main.json` on a pull request (not under a push-only or `false` `if:`, not continuing on error, on a real run line, outside the owner's step); no rule file but `factory.md` names the seeded-defect measure; every pattern cites a live id of its dimension's file (`FAC-S`/`FAC-A` in `factory.md`). Backticked names only; a required job gated on changed paths and two rule gaps are left to review (ADR-0046) | PR #550 |
| 0-185 | A seed run's original change is in reach of the panel (`main` holds it, the revert's patch holds its lines): the 122 reviewer transcripts of the 20 `/seed-bugs` runs before #0-115's F1 were scanned by hand, no expected reviewer reached it, arch-after-p07's "Also caught by" is marked. ADR-0044 decision 6: each series is scanned before its rows land, `.ai/rules/audit.md` reads a marked row as an upper bound, a measure by hand commits the plant and gives the panel the autopilot prompt saying that `factory.md` applies; a clone without the change's history waits for an expected reviewer that reaches it. `seed-record.sh` and `seed-bugs.js` take `FAC-A02` | PR #551 |
| 0-172 | The defect-seeder is held to its seed run's change and commits nothing (ADR-0047). Its Bash is the reviewers' read-only `readonly-bash.sh`, so it cannot switch, commit or redirect. Its Edit runs `write-scope.sh --seed`, which allows exactly the change's kept files, read from the run's record `.ai/runs/SEED` (written by `seed-branch.sh`, removed by `return-to-main.sh`). Both guards are in its frontmatter and in twins in both settings files. On the run's branch `guard-migrations.sh` compares with the run's base (`migration_base_ref`), so a migration the change added can be planted with Edit and P-19 is no longer refused. `seed-check.sh` and `seed-fold.sh` check and commit the uncommitted edit. Left open: #0-186 (an agent with no guard in either layer). Decision history kept in [the section #0-172 below](#0-172-the-defect-seeder-writes-and-commits-with-no-write-scope) | PR #552 |
| 0-179 | No `/seed-bugs` run's panel is told it is a measure. The session starts a run from a notification turn, which relays no user message. `scripts/factory-admin/seed-scan.sh` reports, per reviewer, a relayed message that names the run, a read of the merged change and a read of the answer key. It helps the owner's hand reading, refuses a transcript shape it does not know, and is tested in Factory guards (ADR-0044 decision 6, amended). Checked against the 20 runs on disk, where it found reads the hand scans had missed. P-01, P-03, P-04 and P-05 were re-run blind: three held, and `sec-p04-blind` was caught but not blocked (#0-187). Decision history kept in [the section #0-179 below](#0-179-the-workflow-tool-shows-the-panel-the-seed-bugs-command-that-started-the-run) | PRs #553, #554 |
| 0-187 | SEC-31's "Check:" judges a log line by what it is built from: a message the platform did not write (a database, driver, parser or client exception's, or one wrapped in the platform's own) is a source, the line is the finding whatever it carries today, and the platform's own content-free messages are kept, as `KafkaFailures.reason` and `describe` do (#0-96). The logged throwable is #0-188. P-04 re-run blind (`sec-p04-blind-r2`), same plant at the same line: blocked by security under SEC-31, where `sec-p04-blind` approved it. Decision history kept in [the section #0-187 below](#0-187-sec-31-is-weighed-by-what-a-log-line-holds-today-not-by-what-it-is-built-from) | PRs #555, #556 |
| 0-186 | Factory guards fails an agent that holds Bash or a file tool and has no guard of that kind in its frontmatter: rule 6 of `check-hook-entries.rb`. Bash needs `readonly-bash.sh` or `factory-ops-bash.sh`, and the file tools need `write-scope.sh` on a matcher with each of them. A `tools:` naming none means every tool, and two definitions with one `name:` fail. The autopilot's implementer, implementer-light, picker and shipper are named exceptions with their reasons, and a stale exception fails (ADR-0041 amended). Left open: an agent with `Agent`/`Task` in `tools:`, and skills' `allowed-tools`. Decision history kept in [the section #0-186 below](#0-186-factory-guards-cannot-see-an-agent-with-bash-or-edit-and-no-guard) | PR #558 |
| 0-180 | `/seed-bugs` measures false alarms too: a `C-` pattern plants a rule's deliberate exception (C-01 ARC-23, C-02 ARC-29, C-03 SEC-08 in `patterns.md`), and a dimension that stops it at the plant under the pattern's rule is a false alarm, a stop under another rule is raised. The rule and dimension come from the pattern's row (`seed-check.sh`), the rows go to `.ai/audit/benchmark/clean.md` (`seed-record.sh --clean`, `audit-data.sh` `seededClean`), and `NEEDS_HUMAN` at the plant counts as blocking in a defect run (ADR-0044 decision 7). First series: `clean-c01-r2` no false alarm, its control `arch-p07-ctl` caught and blocked. Decision history kept in [the section #0-180 below](#0-180-seed-bugs-measures-catches-never-false-alarms) | PRs #559, #560, #561 |
| 0-181 | `/seed-bugs` scores a catch on the seeder's whole edit, not one line: `seed-check.sh` returns its hunks, a finding within 5 lines of any of them is at the plant, and at most two unedited places the seeder names in `also` count too (`onlyAtAlso` in the outcome, ADR-0044 decision 8). The plant is compiled before the panel: `seed-compile.sh`, offline `test-compile` of the edit's modules (`-amd` for `shared`; skipped for a POM or no Java), a plant that does not build is FAILED with the compiler's first error, and the outcome says whether it was compiled (decision 9); `run-tests.sh`'s hardened Maven call is `_common.sh`'s `factory_mvn`. AC3: `docs-p17-r2` caught and blocked by docs with no hand reading. Decision history kept in [the section #0-181 below](#0-181-seed-bugs-scores-a-catch-by-one-line-and-never-compiles-the-plant) | PRs #562, #563, #564 |
| 0-191 | incident-service and ingestion-service each walk every route of `RequestMappingHandlerMapping` through their real `SecurityConfig` (`IncidentDenyByDefaultTest`, `IngestionDenyByDefaultTest`): no header 401, purpose token 401/403, unknown API key 401, with a negative case, a known-route lower bound and a literal exempt set; ADR-0048, README "Infrastructure Hardening" | PR #572 |
| 0-192 | notification-service, oncall-service and postmortem-service each walk every route of `RequestMappingHandlerMapping` through their real `SecurityConfig` (`NotificationDenyByDefaultTest`, `OncallDenyByDefaultTest`, `PostmortemDenyByDefaultTest`): no header 401, purpose token 401/403, unknown API key 401, with a negative case, a known-route lower bound, a literal exempt set and a positive control; notification also checks an unmapped path and the Slack route through the real signature verifier; README "Infrastructure Hardening" | PR #576 |
| 0-199 | `buildCommonSecurity` applies CORS (`.cors(withDefaults())`) and the `OPTIONS /** permitAll` rule is gone: a valid preflight is answered by `CorsFilter` before authorization, every other `OPTIONS` is 401 like any method, `TRACE` stays 400; the shared `corsConfigurationSource` bean backs off only for a bean of that name; ADR-0049, README "Infrastructure Hardening", auth-service `CorsPreflight` test | PR #583 |
| 0-200 | Each of incident-, ingestion-, notification-, oncall- and postmortem-service pins its CORS preflight against its real `SecurityConfig` (`CorsPreflight` nested test: allowed preflight 200 with `Access-Control-Allow-Origin`, bare `OPTIONS` 401); README "Infrastructure Hardening" names them | PR #584 |
| 0-196 | incident-service's `IncidentDenyByDefaultTest` gets #0-192's shape: a positive control (a valid user token is past authentication), every `RequestMethod` for a mapping with no method condition, and the `/ws/**` exempt entry removed (a REST mapping under `/ws/` is reported, `WsRoute` test); README "Infrastructure Hardening" | PR #586 |
| 0-198 | ingestion-service's `IngestionDenyByDefaultTest` gets #0-192's shape: a positive control (a valid user token is past authentication), a verify that the mocked key lookup was asked for the unknown key in both the `ApiKey` and `Bearer` forms, rule-3 `isExempt` matching, and every `RequestMethod` for a mapping with no method condition; README "Infrastructure Hardening" | PR #587 |
| 0-197 | auth-service's `ApiKeyDenyByDefaultTest` and `IntrospectionTokenDenyByDefaultTest` walk every route against a literal exempt set keyed by `<METHOD> <pattern>` with a reason per entry (no `PUBLIC_PATHS`, no `startsWith`), send every method to a method-less mapping, pin the key's team routes as exact patterns, and have a negative case; README and ADR-0048 updated | PR #590 |
| 0-206 | An agent that ends without its answer (its `maxTurns` spent) stops the item through `stopItem` (lock released, state recorded with the stage, draft PR, notification) instead of ending the workflow: `as()` catches the `agent()` exception and keeps the reason; the picker answers `failed`, distinct from `none`, and stops at `pick`; `foreground-bash.sh` refuses `run_in_background` for the implementers | PR #592 |
| 0-203 | Every autopilot commit carries the `Co-Authored-By` trailer, by one rule in the committing agents' definitions: `readonly-bash.sh --architect` allows only `git commit -m "<subject>"` with that trailer (`-F`, `-C`, `-a` and every other form refused); the "which run and agent wrote a commit" extension is #0-212 | PR #592 |
| 0-209 | The workflow starts an item in code: `scripts/factory/start-item.sh` (through factory-ops, after the picker and before `state.sh branch`) creates the branch from the base commit, copies the whole work template, sets the status field and commits; a refusal leaves no branch. It reads the item through `backlog_json`, and `next-item.sh` skips a ready item that is not Open. The picker only checks the item and names its branch (Read, Grep, Glob, Bash); the `mkdir`/`cp` allow rules are gone. Decision history kept in [the section #0-209 below](#0-209-the-picker-copies-the-work-template-itself-through-an-allow-rule) | PR #595 |
| 0-215 | The picker only reads: `readonly-bash.sh --picker` (read-only git, one whole-command `gh pr list` form, `ls .ai/work/0-<n>` that resolves to itself) in its frontmatter and both settings twins, out of `UNGUARDED`; a resumed run switches to the owner's branch in code (`scripts/factory/resume-item.sh` through factory-ops, before the picker), its arguments checked first and a refusal stopped at `pick`; `clean_main_at` shared by `start-item.sh` and `resume-item.sh`; ADR-0051. Decision history kept in [the section #0-215 below](#0-215-the-picker-writes-nothing-yet-its-bash-may-still-write) | PR #596 |
| 0-189 | `OncallScheduleRepository.findByTenantIdAndOptionalStatus` has a Testcontainers (`postgres:16-alpine`) repository test: with a status and with `null`, two tenants each holding ACTIVE, SUPERSEDED and CANCELLED rows, tenant filter, status filter and page-of-one ordering and total asserted (test-only) | PR #601 |
| 0-207 | The agents name the command forms their session allows: a "How commands run here" section in `picker.md`, `implementer.md` (and so `implementer-light.md`) and `shipper.md`, each form in a marked list that Factory guards' `check-agent-commands.rb` runs through the agent's hooks and the autopilot settings' rules, refusing the families Claude Code overrides (ADR-0050); the guard names a refused command as it is. Two autopilot runs' pickers had no refused call (PRs #590, #601). Decision history and the closing run's cases kept in [the section #0-207 below](#0-207-the-picker-spends-its-turns-on-commands-its-session-refuses) | PRs #588, #589, #593, #602 |
| 0-194 | The autopilot's preflight refuses a run outside the devcontainer (`FACTORY_DEVCONTAINER`), not the bot's (`FACTORY_BOT_LOGIN` against `GIT_*` names, noreply emails and `gh`'s login), with the firewall not refusing `example.com`, or in a session that did not load `main`'s `settings.autopilot.json` and `settings.json` (`env.FACTORY_SETTINGS_SHA256`, computed by `scripts/factory/settings-hash.sh`, kept by Factory guards' `check-settings-hash.sh`, compared after the fast-forward); the three limits have no default; ADR-0052. Decision history, cases and spike kept in [the section #0-194 below](#0-194-the-autopilots-preflight-does-not-refuse-a-session-outside-the-devcontainer-or-without-its-settings) | PR #605 |
| 0-216 | The rule of an item's branch has one copy per language: `ITEM_BRANCH_RE` in `scripts/factory/_common.sh` (item as the first group) for `start-item.sh` and `resume-item.sh`, one `ITEM_BRANCH` in `backlog-autopilot.js` for the resume's arguments and the picker's branch; `test-autopilot-workflow.mjs` fails when the two differ in text or in what bash and JavaScript accept; ADR-0051 records the choice | PR #606 |
| 0-222 | The implementer's test and verify forms take `-am`, so `shared` is built from the branch, not taken from `~/.m2` (none in the devcontainer, maybe older on the owner's machine); `shared/pom.xml` sets surefire's `failIfNoSpecifiedTests=false` for `shared` alone, so `-am -Dtest=<Class>` builds while a service's misspelt class still fails (not the command-line property, which would hide it under `-q`); `/ship`, CLAUDE.md's one-class commands and `foreground-bash.sh`'s refusal take `-am` too. No check compares the prescribed Maven form across agents, hooks and skills (review rule gap, not filed) | PR #607 |
| 0-223 | `implementer.md` (and so implementer-light) and `picker.md` search with `git grep` and list with `git ls-files` (the picker: `git grep` on the base commit), as #0-123 decided, not the Grep and Glob tools that no autopilot run gave an agent with Bash (31 runs); both say that a "No such tool" message suggesting `grep` via Bash does not apply, as that command is refused. Whether Grep and Glob can reach a secret is #0-225. Evidence kept in [the section #0-223 below](#0-223-the-implementers-are-told-to-use-a-grep-tool-their-session-may-not-have) | PR #608 |
| 0-195 | An autopilot item's branch prefix comes from its `**Type:**` on the base commit: `BRANCH_PREFIX_OF` in `scripts/factory/_backlog.sh` is the one table (`performance` → `perf/`, new), `next-item.sh` hands it to the workflow, which composes `<prefix>/<item>-<slug>` with the picker's `slug` (its own `branch` is not used outside resume); `start-item.sh` refuses another prefix, and `next-item.sh` and `check-queue.sh` an item whose type has none; ADR-0051. Decision history kept in [the section #0-195 below](#0-195-the-workflow-does-not-check-the-branch-prefix-the-picker-gives-an-item) | PR #609 |
| 0-175 | `/backlog-autopilot` (`#0-N`, `#0-N <branch>`), `/audit` (`<since> <date> [target] [dimension…]`) and `/docs-audit` (`<date>`) start from their command's words, read as `/seed-bugs`' (#0-174) and checked as the object's values, a count they cannot read starting nothing; `audit.js` checks dimensions and `docs-audit.js` the date in both forms (AC1). Every factory-ops answer a workflow reads has a closed, typed schema (`answerOf`, `ERROR_FIELDS`, `failureOf`, compared across workflows), checked against the keys each script prints (AC2). Decision history kept in [the section #0-175 below](#0-175-the-other-workflows-cannot-start-from-their-commands-and-read-untyped-factory-ops-answers) | PRs #571, #610, #611 |
| 0-220 | A pipeline case's `readyPr` is the newest `/ready` PR merged before its run started (`Autopilot run <runId>`; the stop for a BLOCKED run without a PR, the shipping run for an escape; `readyBound` says which), and a `/ready` PR's items are those its merge made or changed and left ready or human-only (`readied_items`, `_backlog.sh`; the branch name only when the merge is not in the history), not its title; `acceptance.md` no longer makes `Risk: high` a `NEEDS_HUMAN`, so a risk-high PR is no case by construction. Decision history kept in [the section #0-220 below](#0-220-the-pipeline-audits-data-attaches-the-wrong-ready-pr-to-a-case) | PR #612 |
| 0-169 | `factory-ops-bash.sh` allows one call per factory-ops run, the first that passes its other rules, and refuses every later one of the same `agent_id` (a symlink `.ai/runs/ops-calls/<agent_id>` → `<tool_use_id>` by `ln -sn --`, so the hook's frontmatter copy and session twin of one call both pass; a mark that is not a symlink refuses; a refused call does not use it up; no `agent_id` or `tool_use_id` refuses), ADR-0053, after a spike of `agent_id` in a Workflow run. Gaps filed as #0-233 and #0-234. Decision, spike and live check kept in [the section #0-169 below](#0-169-a-factory-ops-call-is-not-bound-to-the-command-the-workflow-named) | PR #617 |
| 0-233 | `.ai/runs/ops-calls/`, the marks that give a factory-ops run its one call (#0-169), is on the runtime list of `.ai/rules/protected-paths.md`, with `Edit`/`Write` denies in `settings.autopilot.json` and an alternative in `guard-protected-bash.sh` (matched without the trailing `/`, so the directory itself counts), as `.ai/runs/LOCK` is; another agent's Bash can no longer delete, repoint or pre-create a mark. Code run through `./mvnw` still reaches it (#0-116), and so does a command that removes the marks through their parent `.ai/runs` (#0-235) | PR #618 |
| 0-235 | No allow rule of an autopilot session runs a program that can remove a path it does not name: rule 4 of `check-agent-commands.rb` holds every Bash allow rule (both settings files, a preloaded skill's `allowed-tools`) to `SAFE_PREFIXES` or a reasoned `EXEMPT_RULES` entry (`./mvnw`, `scripts/factory/`, git's commands on the working tree), no shell operator in a rule (ADR-0054); `git_runtime_unsafe` refuses git's plain forms as a heuristic; the shell guard resolves `//` and `/./`. The git route stays open until #0-236. Decision history kept in [the section #0-235 below](#0-235-the-shell-guard-does-not-see-a-protected-runtime-path-removed-through-its-parent) | PR #619 |
| 0-237 | Migration stage 1 (ADR-0055): the repository moved to the organisation `profitbuild`; the owner is read from `repository.json` (`scripts/factory/owner-login.sh`) by the audits and Factory guards, and only the owner's approval counts; the ruleset's bypass list, emptied by the transfer, restored; `dismissal_restriction` written; the bot's classic token pushes there. 2FA in the organisation is the owner's step left; the findings and the rollback are in [the section #0-237 below](#0-237-migration-stage-1-the-organisation-profitbuild-and-the-transfer-of-incident-platform) | PRs #623, #624 |
| 0-240 | The build VM no longer reaches the Mac's loopback services: its Docker is rootless (code a test runs is `factory`, not root, in the VM) and root's `FACTORY-EGRESS` rejects the gateway (`host.lima.internal`), the VM's network and link-local for every uid from 1000 up, behind an allow-list; `create.sh` checks it after creation and after a reboot (ADR-0057); details in [the section](#0-240-the-build-vm-reaches-the-macs-loopback-services) | PR #632 |

Items completed before `BACKLOG.md` existed are not listed.

## Details

The full sections of finished items: the decisions, their reversals, the review rounds, the findings. The first 42,
kept in `BACKLOG.md` until then, moved here unchanged on 2026-11-13 in order of their number; later ones are appended
as they close. Earlier finished items have only their row above.

### 0-42. Kubernetes `MAIL_HOST` points at a `mailhog` that does not exist

**Type:** bug · **Priority:** Low · **Status:** Done, PR #480 (built by hand after the autopilot blocked it, draft PR #477). Kept in
full for the decision history; ADR-0026 records the result.
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** — (#0-16 is Done)
**Touches:** k8s (overlays/dev, base/infrastructure/app-config.yml), ci (.github/scripts, .github/workflows/ci.yml), notification-service (application.yml comments only), root (README.md "Infrastructure Hardening", .ai/context/infrastructure.md)

**Problem.** `k8s/base/infrastructure/app-config.yml` sets `MAIL_HOST: "mailhog"` and the dev overlay's comment says
the operator email is "caught by the same mailhog", but no manifest deploys a mail server. auth-service also requires
SMTP auth and STARTTLS (`mail.smtp.auth: true`, `starttls.required: true`) and notification-service requires auth,
so neither can send to a plain dev catcher. docker-compose had both gaps until backlog #0-16 added Mailpit and
overrode those properties with `SPRING_MAIL_PROPERTIES_*` environment variables for the compose stack.

**Work.** Deploy Mailpit in the dev overlay with the same overrides (or point `MAIL_HOST` at a real relay per
overlay), so dev on Kubernetes delivers invites and operator emails.

**Autopilot run (2026-10-10): BLOCKED** at the implementer, draft PR #477. AC9 needs a new `.github/` check
script and workflow step, which the autopilot may not write; the item was marked ready with `Risk: high` as if
that were enough. Now `human-only` (the owner builds it, from the architect's plan and Proposed ADR 0026 on
the branch of #477); the gap that let it through is closed by backlog #0-122 (the protected-path gate in
`next-item.sh`, `.ai/rules/ready.md` point 3).

**Decided (owner, `/ready #0-42`, 2026-10-10).**
- Mailpit runs in the dev overlay only, as a file in `k8s/overlays/dev/` listed in `resources`. Never in base,
  because its unauthenticated UI shows invite and password-reset links.
- The mail overrides are the compose ones (#0-16): `SPRING_MAIL_PROPERTIES_MAIL_SMTP_AUTH`, `..._STARTTLS_ENABLE`
  and `..._STARTTLS_REQUIRED` set to `"false"`, added to the dev `app-config` patch (`op: add`). Mailpit is not
  given a certificate or SMTP auth.
- Staging and prod get no relay. Base `MAIL_HOST` becomes a clearly commented placeholder, "replace before a
  real deployment", as #0-26 did for the operator address.
- The dev overlay's blanket Deployment patches are narrowed to `labelSelector: app.kubernetes.io/component=backend`
  (the 7 services carry it), so Mailpit and Redis stop receiving 768Mi and the 90/120 s probe delays.
- The Mailpit pod gets `allowPrivilegeEscalation: false`, drops `ALL` capabilities, uses `seccompProfile:
  RuntimeDefault`, and has resource requests and limits. `runAsNonRoot` and `readOnlyRootFilesystem` are set
  only if the image is verified to run with them. Probes are `httpGet` or `tcpSocket`.

**Acceptance criteria.**
AC1. The rendered dev overlay has a `Deployment` and a `ClusterIP` `Service`, both named `mailpit`, in
`incident-platform-dev`. The Service exposes 1025 (SMTP) and 8025 (HTTP), and its selector matches the pod labels.
AC2. In the rendered dev `app-config`, `MAIL_HOST` is the Mailpit Service name and `MAIL_PORT` is its SMTP port.
AC3. The rendered dev `app-config` sets `SPRING_MAIL_PROPERTIES_MAIL_SMTP_AUTH`,
`SPRING_MAIL_PROPERTIES_MAIL_SMTP_STARTTLS_ENABLE` and `SPRING_MAIL_PROPERTIES_MAIL_SMTP_STARTTLS_REQUIRED` to `"false"`.
AC4. The rendered base, staging and prod contain no `mailpit` resource and no `SPRING_MAIL_PROPERTIES_*` key, and
base `MAIL_HOST` is a commented placeholder to replace before a real deployment.
AC5. The Mailpit image has an explicit version tag (never `latest`), equal to the tag in `docker/docker-compose.yml`.
AC6. The rendered dev contains no `mailhog`. The dev overlay comments and notification-service's `application.yml`
comments name Mailpit.
AC7. No Ingress and no Service other than `ClusterIP` exposes port 8025 in any overlay.
AC8. The dev overlay's blanket Deployment patches target only `app.kubernetes.io/component=backend`, and the
rendered Mailpit and Redis Deployments get neither the 768Mi memory nor the 90/120 s probe delays.
AC9. `.github/scripts/check-k8s-mail.sh` checks AC1–AC8 in the `validate-k8s-manifests` job, and its test
shows that a fixture breaking a rule fails it. `kubectl kustomize` and `kubeconform -strict` pass for base and
all three overlays.
AC10. README "Infrastructure Hardening" and `.ai/context/infrastructure.md` (the CI rules list) describe
Mailpit in dev on Kubernetes, the missing relay in staging and prod, and the new check.

---

### 0-82. Suspend and offboard a tenant

**Type:** design · **Priority:** Medium · **Status:** Done, PRs #456, #457, #458, #459 (split out of #0-80; offboarding moved to #0-101). Kept in full as
the record of the decisions, which the code and the other docs refer to.

**Problem.** (As written before step 1.) Since #0-80 a platform operator creates tenants
(`POST /api/v1/platform/tenants`), but nothing ends one. A customer who stops paying, breaches terms or leaves keeps logging in, its
Integration API keys keep filing alerts, and its data stays in all seven services. Today the only
lever is archiving its users one by one in the database.

**Two different things.**
- **Suspend** (reversible): the tenant's users cannot log in or refresh, its API keys introspect as
  inactive, and its incidents stop notifying, while its data stays. Enforcement points:
  - auth-service login, refresh, accept-invite and password reset: refuse when the tenant is suspended;
  - API key introspection (ingestion-service, 60 s cache) and auth-service's own API key lookup:
    `active:false`;
  - access tokens already issued live up to 15 minutes, and `JwtAuthFilter` in `shared` knows nothing
    about tenant status. Either accept that window, or carry status to every service (a revocation
    entry per tenant in the Redis check `TokenRevocationChecker` already does; ties into #0-3, which
    decides which services check revocation at all);
  - Kafka: alerts already accepted keep flowing; decide whether incident-service drops them or
    notification-service suppresses them.
- **Offboard** (irreversible): export the tenant's data on request, then delete or anonymize it in
  every service's tables (incidents, audit, notifications, on-call, postmortems, users, teams, keys,
  Slack workspace) and in Redis. Needs an orchestrated, resumable job across services, a retention
  decision for the audit log, and the same PII considerations as #0-48.

**Approach.** (The original sketch; what was decided, and what step 1 did, follows below under
**Decided** and **Progress**.) Design first. Add a `status` column to `tenants` (V21 deliberately has none) with
`ACTIVE` / `SUSPENDED` / `OFFBOARDING` / `OFFBOARDED`, operator endpoints under
`/api/v1/platform/tenants/{id}` with the same `PlatformAccess` rule, audit events in the operator
tenant, and the enforcement points above. Suspension first; offboarding is larger and can follow.

**Decided (2026-10-04, from the enterprise pattern: Azure tenant life cycle, AWS SaaS Lens).** Two
suspension modes, `FULL` (a taken-over tenant, a terms breach) and `READ_ONLY` (a billing hold: reads,
account security), with a reason and a note; background work of a suspended tenant is paused and
resumed, not dropped; three steps: (1) the status, the operator API and enforcement in auth-service
plus a shared filter every chain carries; (2) enforcement everywhere: the other services read the
status (a cached pull from auth-service, like notification-service's Slack workspace; last known value
when auth-service is down), `TenantStatusFilter` closes the access-token window, Kafka consumers park a
suspended tenant's records in a table and replay them on resume (a record cannot be held without
blocking its partition), schedulers skip the tenant, STOMP connections close; (3) offboarding, its own
item: #0-101.

**Progress.** Step 1: PR #456 (V30, `TenantLifecycleService`, `TenantAccessService`,
`TenantStatusFilter`; see the README "Tenant suspension" control). Decided in the review of step 1: a
`SECURITY` suspension must be `FULL` (400 in `TenantLifecycleService`, CHECK
`chk_tenants_security_suspension_full` in V30), since read-only keeps an intruder's sessions and the
account-security writes it allows (others' MFA, deactivation). In step 1 already: a read-only
tenant's alerts are paused, not refused: introspection answers `paused:true` and ingestion-service
503 + `Retry-After` (Alertmanager retries 5xx, drops 4xx), as a successful answer so its circuit
breaker is not tripped for every tenant; a full suspension's alerts got 401 (403 `TENANT_SUSPENDED` since
2a). Left for step 2 (or a
foreign key): a tenant with users but no `tenants` row has full access and cannot be suspended — none
should exist; it is counted, alerted (`PlatformTenantStatusRowMissing`) and logged once (closed by the foreign keys
in the last part, below). Also left for
step 2 (found in the review of step 1; all done in 2a, below): a key ingestion-service cached in the minute before a full
suspension still files alerts for the rest of that minute; a fully suspended tenant's key is answered
like a revoked one, so its sender's retries count against the IP's failed-authentication limit (a
shared NAT could throttle others); a sign-in refused for suspension is neither audited nor counted;
`findByIdForUpdate` (suspend, resume) waits without a `lock_timeout` (sign-ins are bounded at 3 s); the other services will need a short-lived cache
of the status (5-10 s), not a lookup per request; a short cache (5-10 s) of ingestion's paused
introspection answers, so a sender that ignores Retry-After cannot turn every alert into an
auth-service call; a sign-in that loses a deadlock to a suspension's session cleanup gets a 500,
not 503 + Retry-After.

**Step 2, decided (2026-10-05).** Split in two PRs. A decision of step 1 changed: Kafka consumers do **not**
park and replay a suspended tenant's records. notification-, escalation- and postmortem-service's consumers
only write a row (a queue entry, an escalation task, a GENERATING postmortem); their schedulers do the
outbound work. So 2b pauses the schedulers instead: a per-service `paused_tenants` table, excluded in the
schedulers' SQL (not in Java, where a suspended tenant's rows would fill every batch and starve the others),
in both modes, with delivery and escalation deadlines not running while paused; intake goes on, so the state
is consistent on resume. `AuditEventConsumer` is never paused. When auth-service cannot answer: the last known
status however old (static stability; the first version gave FULL an hour after the last answer, changed in the
review of 2a because that abandoned a known suspension, for good when the service token is rejected), FULL only
for a tenant never answered for (fail-open), counted and alerted; a rejected token is its own critical alert.

**Step 2a: PR #457.** Every other service reads the status (`AuthServiceTenantStatusProvider` in `shared`,
`GET /api/v1/internal/tenant-status`, cache 10 s, one call per tenant at a time, last known status during an
outage, FULL only for a tenant never answered for, alerts `TenantStatusLookupFailing` /
`TenantStatusLookupRejected`, CI check that every service sets `auth-service.base-url`), so `TenantStatusFilter` closes the access-token window in all of them; STOMP
`CONNECT` refused and open sessions closed (incident-service, `TenantWebSocketSessions`). The step-1 review
items: a full suspension's keys answer `suspended:true` → 403 in ingestion-service, not counted by the IP
limiter, and the 60 s positive cache window is closed by the status filter (ingestion's read-only refusal is
503 + Retry-After there, `tenant-status.read-only.retry-after`); paused and suspended introspection answers
are cached 5 s; a sign-in refused for suspension is audited (`USER_SIGN_IN_REFUSED_TENANT_SUSPENDED`, after the
rollback) and counted, at most a few times per user per window (then 429, no event: a refusal rolls back,
so its invite or reset token could be replayed without end);
suspend/resume wait at most 5 s for a lock; a lost lock (deadlock, timeout) in
auth-service is 503 + Retry-After, not 500. Still open from step 1 then: the missing `tenants` row (closed below).

**Step 2b: PR #458.** Decided (2026-10-06) after a `/research`: a table per service
(`<service>_paused_tenants`: notification V10, escalation V9, postmortem V7) rather than a set held in memory (lost on
restart, different per replica, and escalation-service needs when the pause began) or a status on every work row
(new states in three state machines, and the consumers' cancel paths would have to know them). `PausedTenantsSync`
(`shared`, ShedLock, every 10 s) asks auth-service only about the tenants with work waiting plus the paused ones,
with the existing tenant-scoped endpoint (no tenant-less list, so no second purpose token), and changes a tenant only
on auth-service's own answer (`TenantStatusProvider.confirmedStateOf`): an outage right after a restart resumes no
one, and a tenant never answered for is not paused (fail-open, as in 2a). The schedulers' queries leave the paused
tenants out (`NOT EXISTS`, native, the table a constant checked at startup against `tenant-pause.table`);
`TenantWorkGuard` holds a row back (`accessOf`, not the cache-only `knownAccessOf`: found by E2E, that answers FULL
for an uncached tenant, so after a restart a suspended tenant's oldest rows went out in the first cycle) until the
sync pauses the tenant. The pause is measured from the suspension's own time: auth-service's answer now carries
`since` (`suspended_at`, kept across a change of mode), and `paused_at` takes it (decided in the second review: first
a fixed 20 s allowance before the sync's own time, which a late sync, a used-up budget or a failing run outran, and a
task held by the guard meanwhile still escalated at once on resumption; the time of the event, recorded by its
owner, as Jira's SLA clocks and Kubernetes' `lastTransitionTime` do, not the time it was noticed; one database, one
clock). Resumption is one transaction with the service's hook: escalation-service moves every PENDING timer on by the
pause (`now - GREATEST(suspended_at, timer start)`; a task already due at the suspension is left as it is; `version`
bumped), notification-service restarts the routing lookups' retry windows (#0-19); the end of the pause is when the
sync sees the resumption, which only ever lengthens a timer. Notifications are all sent on resumption, none dropped
for age (the tenant's alerts were refused at intake meanwhile). Candidates (paused, or with waiting work) are asked
in tenant id order, each run continuing after where the last one's budget ran out (third review: paused tenants used
to go first, and enough of them in an auth-service outage starved new suspensions). escalation- and postmortem-service got
processing budgets like notification-service's (review: a batch of slow status lookups during an auth-service outage
could outlive a ShedLock), and each scheduler looks up its batch's tenants together before the loop, 8 at a time
(`TenantWorkGuard.prefetch`; fourth review: one after another, 60 tenants at ~3 s in an outage delayed the last
ones' escalations by a cycle or more), its budget started before the prefetch so the prefetch cannot eat the
margin below the lock (fifth review). A prefetched answer lasts one status TTL; a longer loop asks row by row
again, accepted (the sync has paused a suspended tenant by then). A timer is never moved earlier (`GREATEST(interval '0', ...)`). The Slack ACK path (no message carries the button since #0-21; #0-35 brings it back)
reaches incident-service with notification-service's token, past the status filter, so `SlackActionService` now
refuses a suspended tenant's acknowledgement itself, counted (`slack.ack.refused`), fail-open like the filter. Alerts
`TenantPauseSyncFailing` and `TenantPauseSyncStalled` (no instance completed a run in 5 minutes). Scale limits (a lookup per tenant per sync in each service, candidate and backlog scans
without `tenant_id` in the indexes): #0-102.

**Last part: the missing `tenants` row, PR #459.** A tenant id with data but no `tenants` row had full access and
could not be suspended (counted, alert `PlatformTenantStatusRowMissing`). Decided (2026-10-06): a foreign key to
`tenants`, `ON DELETE RESTRICT`, on every auth-service table holding a tenant's data (users, user_roles, teams,
tenant_settings, auth_tokens, api_keys, integrations, slack_workspaces, mfa_recovery_requests). V31 first records
any id without a row as ACTIVE, named after itself (as V21 did for users: refusing would stop a deployment over a
gap the row closes), and adds the keys `NOT VALID`; V32 validates them, under a lock that lets reads and writes go
on. Not on `auth_email_outbox` / `auth_audit_outbox`: queues of work about covered rows, whose events must never be
refused for their tenant. Not in the other six services: a foreign key across services would tie their schemas to
auth-service's (#0-85). A tenants row is never deleted (offboarding ends in the `OFFBOARDED` tombstone, #0-101).
The missing-row answer stays FULL with its counter and alert, now a tripwire: auth-service has no data for such a
tenant, so only a token minted outside its sign-in (`/dev/token`; elsewhere, something holding the JWT secret)
can name one. Provisioning's check of users without a row (`UserRepository.existsAnyByTenantId`, found in the
review of #0-80) went, unreachable; the operator tenant's bootstrap now stops its run (FAILED, gauge unchanged)
when it cannot record the row, since inviting the admin without it could only fail on the foreign key. A
structural test (`AuthRepositoryIntegrationTest.everyTenantIdColumnReferencesTenants`) fails on a table with a
`tenant_id` and no validated foreign key; `TenantForeignKeysMigrationTest` runs V31/V32 on orphaned data.
Added in review: a write refused by one of these keys is 403, not the shared catch-all's 500
(`UnrecordedTenantHandler`, only the nine constraint names, which a test compares with the schema); V31 names each
id it adopts in a WARNING (a reserved one flagged: adopted rather than refused, as refusing would stop the
deployment and being reserved grants nothing), and waits at most 5 s for a lock (`lock_timeout`; its nine ALTERs
hold their locks until it commits); V32's header says what to do if validation ever fails; the migration test seeds
an orphan in each of the nine tables and checks the window between V31 and V32. Second review: V31 locks the ten
tables before its backfill, so no orphan can be written between the backfill and the constraints; the 403 body is
the shared handler's own wording, not a hint that the tenant is unknown; a write failing only at commit is shown to
reach the handler as well.

---

### 0-115. Rewrite the review rules as invariants

**Type:** docs · **Priority:** Medium · **Status:** Done, PRs #527, #532, #534 to #546, #548, #549 (kept for the
decision history of each rule file and its measure; owner's decision below, 2026-10-25)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —

**Problem.** The ~90 rules in `.ai/rules/review/*.md` came from the former review agents and are written
as questions to a reviewer (`SEC-01` "Could this code path return, log, or leak data across tenant
boundaries?", `ARC-01` "Does each new responsibility live in…?"). Since 2026-10-09 the implementer reads
them too — `general`, `architecture` and `security` in full, the others as the architect selects them —
and a question to a reviewer is a weak instruction to the one who writes the code. Some rules are
general knowledge the model has without the file; some will be enforced by tests (#0-108, #0-112) and
need no one to remember them.

**Approach** (owner's work: `.ai/rules/` is human-owned; an agent may draft, the owner decides).
1. One file per PR, so the audit can compare review rounds and findings before and after it.
2. Each rule as an invariant — what is true of the code — with one line "Check:" under it, e.g.
   `**SEC-03** A tenant comes from authentication; it is never read from a request body, a path parameter
   or an unsigned header. Check: every new tenant read traces to the security context or a signed token.`
3. Ids stay stable (verdicts and audits cite them). A removed rule keeps its id as `retired — <why>`.
4. Drop what is generic (the model knows it without this file); mark what a test enforces
   ("Enforced by: ArchUnit rule …"), so reviewers skip it.
5. Aim at 10–15 rules per file; the core files (`general`, `architecture`, `security`) are read for every
   item, so every line there costs on every run.

**Gap to add to `architecture.md` (found in the review of #0-137, 2026-10-15).** No rule says that a platform-wide
infrastructure decision enforced by a CI check needs an ADR. #0-42 and #0-76 got one (ADR-0026, ADR-0027), #0-29 did
not, and #0-137 got ADR-0028 only because the architecture reviewer asked; the reviewer could report it as a rule gap,
not cite it. E.g. "A decision that CI enforces across the platform (a structural check in `.github/scripts/`) is
recorded in an ADR in the same PR. Check: a new rule in a check script points to an ADR, or the PR adds one."

**Decided (owner, 2026-10-25, after `/research`).** One file per PR (A), the pilot first: `performance.md` (13
rules, outside the core files the implementer reads on every item, benchmark patterns P-10…P-12). The form (F1 with a
title, like `factory.md`): `**<ID> <the invariant as a title>.** <what is true of the code>. Check: <what to look for in
a diff>.`; `factory.md` gets its "Check:" lines last. The measure (M2): `/seed-bugs` on the dimension's patterns once the
file is on main (the reviewers read the rules from `refs/remotes/origin/main`, #0-165), not the audit — with four
autopilot PRs so far, an audit's before and after would be noise. No "before" run (the owner, 2026-10-25): one sample
per pattern compares little, and the question is whether the new rules catch, not whether they catch more. An agent drafts
each file, the owner decides and copies it (`.ai/rules/` is the owner's). Then: `security`, `architecture` (with the ADR rule
above), `general`, `migration`, `docs`, `k8s` (ids first), `factory.md`.

**Decided for `security.md` (owner, 2026-10-26, after `/research`).** A′: every rule rewritten as an invariant with a
"Check:" line, ids unchanged, none retired for being general knowledge (a blocking finding must cite a rule, so a class
without one could not be blocked: #0-136's case), only SEC-32 retired into SEC-30 (the named secrets are a case of it).
The 10–15 rules of point 5 are not the aim here, on purpose: the file is shorter to act on, not shorter. A rule a check
already covers says "Backed by: <check>" and its "Check:" names what that check misses; it is still reviewed (a check
sees the known form, not a new one). D: P-01 and P-05 reworded so they can be planted in code that exists and still
reverts on `main`: of the revertible changes only `8ea7a120` touches a native query (`UserRepository`), so P-01 now
names any `@Query` or derived query (`47b95294`'s JPQL counts too); no revertible change touches a `SecurityConfig`, so
P-05 also counts a dropped `@PreAuthorize` (review round 1 corrected "no native query exists", which was wrong); hosts:
P-01, P-03 and P-05 on `47b95294`, P-02 on `fc368943`, P-04 on `8ea7a120`. The measure needs #0-177 (merged) and a new
session.
#0-136 (CI supply chain) stays its own item, not part of this file's PR (owner, 2026-10-26): it is several rules
(downloads, privileged triggers, secret-holding steps, a scanner the change can reconfigure, environment separation),
may change `check-k8s-environments.rb`, and leaves open whether CI rules belong in `security.md`, which the implementer
reads for every item though no autopilot item may touch `.github/`, or in a file read only for such diffs.
For `architecture.md` (review round 1): `security.md` now says a rule a check backs is still reviewed ("Backed by:"),
while `architecture.md` section 4 and `factory.md` section 3 say "enforced by checks, do not review by hand"; the
implementer reads both. Choose one convention when `architecture.md` is rewritten, and apply it to the others.

**Decided for `architecture.md` (owner, 2026-10-26, after `/research`).** A1 + B2 + C3 + D1–D3 + E1:
- A1: the form of `security.md`; ids unchanged, none dropped as general knowledge.
- B2: ARC-20, eight patterns under one id, is retired and split into ARC-22…ARC-29, one per pattern. With one id the
  seeded patterns P-06, P-07 and P-08 gave one number, and the audit could not tell which pattern the panel misses.
  P-06 is now ARC-22, P-07 ARC-23 and P-08 ARC-25 in `patterns.md`.
- C3, the convention for every rule file: "Enforced by: <check>" when the check decides the whole invariant (not
  reviewed, no "Check:" line), "Backed by: <check>" when it sees only the known form (reviewed). `security.md`
  already fits. `factory.md` section 3 takes the labels when it is rewritten.
- D1: ARC-07, the ADR rule above. D2: ShedLock only on a job that changes shared state, taken by `@SchedulerLock` or
  `executeWithLock`; a job that runs on every replica says why in its Javadoc (ARC-23). "ShedLock on every
  `@Scheduled`" did not match the code. `TenantWebSocketSessions` and
  `OperatorTenantBootstrap.refreshPendingGauge` are per replica on purpose. `PausedTenantsSync` and
  `AuditOutboxRelay` (`relay`, `purge`) lock programmatically. CLAUDE.md, `.ai/context/architecture.md` and
  `TenantWebSocketSessions`' Javadoc now say so (review round 1). P-07 is reworded so it is never planted
  in such a job. D3: ARC-43, the ECS log format, until now the one invariant of CLAUDE.md with no review rule. It is
  "Backed by", not "Enforced by": `check-structured-logging.sh` matches the usual spellings, and the guard only warns
  about the switch.
- Section 4 gave its rules ids (ARC-40…ARC-43). The Dockerfile/Deployment pair and the overlays' profiles left it:
  they are K8S-01's and K8S-04's.
- E1: P-06 on `fc368943` (`IncidentCommandService` or the escalation consumer), P-07 on `aace4118`
  (`OperatorTenantBootstrap.scheduledReconcile`), P-08 on `fc368943` (`Incident`), P-09 on `82baa5dd` (the API-key
  introspection clients). Each run is started by a message that names nothing (#0-179).

**Decided for `general.md` (owner, 2026-10-26, after `/research`).** A1 + B1 + C1 + D + E + F:
- A1: the form of `security.md` and `architecture.md`; ids unchanged, none dropped as general knowledge.
- B1: GEN-09 is retired. It told the reviewer not to quote coverage, which contradicts #0-160: the test gate's
  artifact gives a module's coverage, and `_common.md` says a number it shows is not `unverified`. How a reviewer
  reports a check is `_common.md`'s, which already has "Never report a check you could not run".
- C1: GEN-22 matches the repository. `<Class>Test`, `<Class>IntegrationTest` for a real database or broker (12
  such files), an aspect suffix (`<Class>SecurityTest`), Spring's `*ApplicationTests`, and helpers without a
  `Test` suffix. Read literally, the old "`<Class>Test`" was a false alarm on correct files, like ARC-23's ShedLock.
- D: "Backed by" on GEN-01 (JaCoCo's `check` and diff-cover count lines executed, not checked) and GEN-08
  (`check-factory-guards.sh`: a deleted test, a new `@Disabled`, fewer assertion lines; `guard-tests.sh`: skip
  options). GEN-08's reason may be in the PR as well as in `handoff.md`, which only the autopilot writes. "What a
  linter catches" now reads "the compiler, the test gate and CI's checks": the POMs have no Java linter.
- E: CLAUDE.md's "Surefire's `<argLine>` keeps `@{argLine}` first, or the JaCoCo agent is dropped and both coverage
  checks silently skip" has no review rule anywhere. It is a POM rule, so it goes to `k8s.md` when that file is
  rewritten, not here.
- F: P-15 on `fc368943` (`IncidentEscalationEventConsumerTest` or `IncidentCommandServiceTest`) and P-16 on
  `82baa5dd` (`RemoteApiKeyLookupServiceTest` or `CachingApiKeyIntrospectionClientTest`), each run started by a
  message that names nothing (#0-179).
- Review round 1: GEN-23 names the backlog item "when one applies", as CLAUDE.md "Conventions" already asks. That
  is a rule now, so a commit without it can be cited. GEN-08's reason outside the autopilot is in the commit
  message, not the PR: a manual `/review` runs before the PR exists and cannot read it. The two labels ("Enforced
  by", "Backed by") are now defined in `_common.md`, which every reviewer reads; `general.md` points there.
  `security.md` and `architecture.md` keep their own definitions until `factory.md`'s rewrite, which points all of
  them to `_common.md`.
- Review round 2: a manual `/review` reads uncommitted changes, so GEN-08's commit message and GEN-23's
  `git log` do not exist yet there. GEN-08 is then `NEEDS_HUMAN`, the owner gives the reason; GEN-23 says so
  instead of a finding. `_common.md`'s `NEEDS_HUMAN` condition names the commit message too. "Enforced by" said
  "if CI is red on it, the autopilot stopped before you were called", which was wrong: before the panel the
  autopilot runs only the path gate and the Maven test gate, and the checks run in required CI jobs on the PR
  (`build-and-test`, `postgres-roles`). Fixed in `_common.md` and in `architecture.md`, where it was already on
  main. Left for `factory.md`'s rewrite: a check that a label's claim about when its check runs matches the
  workflow, and where a manual `/review` takes the reasons and messages these rules ask for.

**Decided for `migration.md` (owner, 2026-10-26, after `/research`).** A1 + B1 + C1 + D + E:
- A1: the form of the other rewritten files; ids unchanged, none dropped as general knowledge. "If nothing
  migration-related changed, `APPROVE`" stays in the introduction as an instruction, not a rule.
- B1, changed on review (round 1, architecture's arc-5e1c): MIG-02 is "Backed by", not "Enforced by".
  `check-factory-guards.sh` flags a migration that exists in the base and was modified or deleted, but
  `factory-guards.yml` passes it when the owner wrote the PR or approved its head commit. So on the owner's own PRs
  the check decides nothing, and the hook fails open without both `jq` and `python3`, or without a base ref.
  `_common.md` and `architecture.md` now say that such a check is at most "Backed by", naming the step that has the
  bypass (review round 2); `factory.md` section 3 no longer lists `check-factory-guards.sh`'s items as unreviewed on
  the owner's PRs. P-14 is still retired: it cannot be planted. `seed-check.sh` lets the seeder touch only the
  change's files. A migration the change adds is not on the panel's base (`main` with the change reverted), so editing
  it is no MIG-02 defect, and a migration from before the change is out of the seeder's reach.
- C1: new pattern P-19 for MIG-05: a `FOREIGN KEY` or `UNIQUE` constraint added to an existing table in one step.
  This is the risk of locking a table and failing on its rows that `NOT VALID` plus a later `VALIDATE` avoids, as
  auth-service's V31 and V32 do. The rule text names no file, so it does not point a reviewer at P-19's host.
- D: "Backed by" on MIG-03 (the smoke test starts every service with `ddl-auto: validate`; the rule leaves nullability
  and length to the review rather than claiming what the validation skips, review round 1) and MIG-06 (the smoke test
  migrates as `incident_app`; Testcontainers connect as a superuser). MIG-07 has no check: 10 migrations (29 lines)
  carry the slug `CHECK`, and no test asks for it on a new table.
- E: MIG-04 keeps one id. Unlike ARC-20, its points are one invariant: rows that already exist survive.
- Measure: P-13 on `5af2fd55` (escalation-service V6 adds columns to the existing `escalation_tasks`) and P-19 on
  `aace4118` (auth-service V31 adds `NOT VALID` foreign keys to existing tables), each run started by a message
  that names nothing (#0-179).

**Decided for `docs.md` (owner, 2026-10-27, after `/research`).** A1 + B1 + C1 + D + E + F:
- A1: the form of the other rewritten files; ids unchanged, none dropped as general knowledge. No rule has a check
  behind it, so none carries a label; the introduction says so.
- B1: level A of the levels table copied part of the Owner-only list (`.ai/rules/**`, `AGENTS.md`), so a drift in
  documentation under `.claude/` or `.github/` fell to level D. The row now points to the Owner-only list of
  `.ai/rules/protected-paths.md` as it is on `main`, the one list (FAC-A01), plus CLAUDE.md outside its
  `agent-editable` blocks and the Service Map, which that list does not hold.
- C1: DOC-10 exempts the Context and history of an accepted ADR: they record what was true when it was decided. A
  change to the decision itself is ARC-05's. This settles the question of `.ai/audit/2026-10-10-pipeline.md` (PR #482,
  `human:fp-docs`, the third collected case of #0-121's audit).
- D: DOC-20 and DOC-40 are invariants too; DOC-40 points to GEN-20 for what a comment must say.
- E: DOC-01 keeps one id. Like MIG-04, its homes are one invariant: a new fact lands where it is documented.
- F: P-17 on `fc368943` (a Javadoc `@return` in `Incident`) and P-18 on `82baa5dd` (ingestion-service's
  introspection client and its `application.yml`), each run started by a message that names nothing (#0-179). Both
  checked with `git apply -R --check` on `87ae8ca2`.

**Decided for `k8s.md` (owner, 2026-10-27, after `/research`).** A1 + B1 + C1 + D1 + E1 + F1:
- A1: the form of the other rewritten files; ids unchanged, none dropped as general knowledge. The ids came with the
  move of 2026-10-05, so "ids first" of the approach was already done.
- B1: "Enforced by" only where the check decides the whole rule: K8S-03 (validate-k8s-manifests renders and
  validates against the pinned version and schemas; the rule's old local command had no pins, #0-76). "Backed by",
  each "Check:" naming the gap: K8S-01 (the cross-check greps `name: <service>`, so a `Service` or a budget of that
  name passes without a Deployment), K8S-02 and K8S-07 (the smoke test; a service left out of the health checks
  passes), K8S-04 (the regex misses a profile in nested YAML), K8S-05 (`check-tenant-status-config.sh` reads only
  `application.yml`; nothing checks the ports), K8S-08 (`check-factory-guards.sh`, passed on the owner's PRs),
  K8S-09 (the `.dockerignore` allowlist and the build; a JDK base, `--chown` or a missing `USER` build fine).
- C1: new K8S-10, `@{argLine}` first in every surefire `<argLine>` (`general.md`'s E above): without it the JaCoCo
  agent is dropped and both coverage checks skip silently, and no check sees it (`check-factory-guards.sh` looks
  for skips, excludes and the coverage limits, not `argLine`).
- D1: the rules a check decides in full get ids and "Enforced by", as `architecture.md` section 4: K8S-20 (each
  overlay's namespace), K8S-21 (prod's image tags), K8S-22 (the HPAs own the replicas), K8S-23 (a budget and a
  spread per service; all `check-k8s-environments.rb`), K8S-24 (Mailpit in dev only, `check-k8s-mail.rb`).
- E1: K8S-06 holds for every service's Deployment, not only a new one: a change never drops a probe or the
  resources. K8S-05 keeps one id: a Deployment agrees with its service's configuration (ports and
  `AUTH_SERVICE_URL`).
- F1: `patterns.md` had no k8s pattern, so AC3 would have measured nothing. New P-20 (K8S-08, a repository or
  plugin added to a POM) and P-21 (K8S-10, `@{argLine}` dropped) on `62d4fdb1` (the root POM's Tomcat bump), P-22
  (K8S-06, a probe or the resources removed) on `4e608067` (every service's Deployment and budget); both revert on
  `a9dac425`. No revertible change touches a Dockerfile (`89f91e82`, #0-141, no longer applies), so K8S-01, K8S-02
  and K8S-09 have no pattern yet. The seed panel had no k8s reviewer, and its scripts refused a digit in a
  dimension or a rule id (`k8s`, `K8S-08`): `seed-bugs.js` and `seed-record.sh` take `k8s` and both forms, with
  tests (owner, 2026-10-27: in this PR). Each run then has seven reviewers, k8s included even when the change
  touches no manifest, as migration already does.
- Review round 1: the comment over `PANEL` says the autopilot differs (it adds migration and k8s only when their
  paths change), the seed test names each reviewer, k8s included, not only how many, and one test compares the four
  copies of the dimension list (`PANEL`, `seed-record.sh`'s `DIMENSIONS`, `audit.js`'s `ALL`, the rule files of
  `backlog-autopilot.js`'s `RULE_FILE_OF`); a mutation of each fails it.
- Review round 2: the test that the panel's verdicts are typed loops over `PANEL` instead of a fifth hand-written
  list, so `review-k8s` gets the same schema too. Security found that `readonly-bash.sh --k8s` passes any option to
  `kubectl kustomize` and `kubeconform` (code this change does not touch, now run on every seed branch): #0-182, listed in
  README "Infrastructure Hardening"'s known gaps.

**Decided for `factory.md` (owner, 2026-10-28, after `/research`).** A1 + B1 + C1 + D1 + E1 + F1:
- A1: the form of the other rewritten files; ids unchanged (FAC-S01…S06, FAC-A01…A06), none retired, a "Check:" line
  under each.
- B1: section 3 ("Enforced by checks — do not review by hand") is gone. Each check moved into the rule it backs as
  "Backed by": `check-web-access.sh` (FAC-S02, FAC-S03, FAC-A01), `test-hooks.sh` (FAC-S02, FAC-S04),
  `check-hook-entries.rb` (FAC-S03, FAC-S04, FAC-A04), `check-protected-paths.sh` (FAC-A01), `test-autopilot-workflow.mjs`
  (FAC-A02, FAC-A06).
  No check decides a whole FAC rule, so none is "Enforced by". `check-factory-guards.sh` left the file: it passes on
  the owner's PRs, the only ones this file judges, and what it looks for is GEN-08's, MIG-02's and K8S-08's. The
  linters of Lint Workflows back no rule here (CI's supply chain is #0-136) and are named in one paragraph without
  an id. FAC-S06 says that `repository-settings.rb check` compares GitHub's settings, not the session's denies.
  ADR-0038, whose decision named section 3, carries an amendment note.
- C1: `security.md`, `architecture.md` and `general.md` point to `_common.md` for the two labels instead of defining
  them. The implementer reads `_common.md`'s blocking criteria, where the definition is (`implementer.md`).
- D1: every PR this file judges is merged through the ruleset's bypass, which skips the required checks too
  (`rulesets/main.json`: `bypass_mode: pull_request`). The file's introduction says that "Enforced by" holds there
  because the owner merges on green or names the red job; CLAUDE.md "Working style" now says the session gives the
  `--admin` command only then (owner), and README "Infrastructure Hardening" records it.
- E1: the checks this series kept finding by hand (a label's claim about its check, the benchmark named in a rule file,
  a pattern's live id) are one new item, #0-184.
- "Where a manual `/review` takes the reasons and messages these rules ask for" (left from `general.md`'s round 2):
  no FAC rule asks for a reason in `handoff.md` or a commit message (FAC-A05's reason is in the ADR and README, files
  of the diff), so nothing is left to do for this file.
- F1: `seed-bugs` cannot measure this file: `seed-branch.sh` refuses a change to an Owner-only path, and every host of
  a FAC rule is one. Measured by hand in a second PR: two patterns for rules no check decides, FAC-A02 and FAC-A06, on
  a host that changes only `.claude/workflows/` or `scripts/factory/` (not a hook, a setting, an agent, a skill or a
  rule, which `/review` runs under), checked with `git apply -R --check`; the owner applies the plant (sessions may
  not write those paths) and runs `/review 23`. The FAC-S rules' hosts are hooks and settings, the reviewers' own
  tools, so they are not measured; that limit is recorded with the rows. #0-115 is Done after that PR.
- Review round 1 (security, docs, performance; no blocking finding): FAC-S03 keeps "a widened scope, or a scope
  dropped from one of its places, is a finding" in the rule, not only in its "Check:" line, where a widening could be
  argued past as needed; the introduction says no FAC rule is "Enforced by" and on what one would hold; FAC-S04's
  `check-hook-entries.rb` names the frontmatter of subdirectories too.
- Review round 2 (security, docs, performance; no blocking finding): FAC-S02 states again in the rule that a host the
  firewall opens is open by IP to every site on the same addresses (its "Check:" asks which); CLAUDE.md and README
  say that an "Enforced by" in `factory.md`, should one be added, would rest on the merge on green, since none is.

**Progress.**
- `performance.md`: rewritten (13 rules, ids unchanged, none retired; PERF-10's startup check and PERF-22's budget
  validation named where they live). `/seed-bugs` on main (2026-10-25): P-12 caught and blocked by performance
  (`perf-after-p12` on `47b95294`, under PERF-30, not PERF-02; general, architecture, security and docs blocked too;
  row recorded by hand, #0-176). P-10 skipped on `76379e806fb4` (no lazy collection in the change; the pattern's
  wording predated the rewritten PERF-01, reworded with #0-176). P-10 on `47b95294` (`perf-after-p10`): caught and
  blocked by performance under PERF-01 at the planted line (a repository call per element in
  `OncallScheduleService.getAllCurrentOncall`). P-11 on `fc368943` (`perf-after-p11`): caught and blocked by
  performance under PERF-23 (a direct `KafkaTemplate.send` inside `@Transactional` `recordEscalationLevel`), also
  blocked by general, architecture (ARC-20) and security. AC3 holds for `performance.md`: each of P-10…P-12 caught
  by its dimension. Both runs recorded their rows themselves, which also shows #0-173's and #0-174's AC3 and #0-176's
  AC4.
- `security.md`: drafted (26 ids, SEC-32 retired into SEC-30), with P-01 and P-05 reworded in `patterns.md`; the owner
  copies both (`.ai/rules/` and the patterns are the owner's). On main with PR #534. `/seed-bugs` series on main
  (2026-10-26, the first one run on #0-177, with no commit between runs): security caught and blocked each pattern:
  P-01 (`sec-after-p01` on `47b95294`, SEC-06), P-02 (`sec-after-p02` on `fc368943`, SEC-04), P-03 (`sec-after-p03` on
  `47b95294`, SEC-03), P-04 (`sec-after-p04` on `aace4118`, SEC-31) and P-05 (`sec-after-p05` on `47b95294`, SEC-10).
  general also caught all five. P-04 was planned on `8ea7a120`, but `seed-branch.sh` refused it: that merge of PR #459
  changes `CLAUDE.md`, the evaluator. `aace4118` is the same PR's code commit. Only P-02 was blind. The reviewers of the
  other four were also shown the owner's `/seed-bugs` command, pattern included: the Workflow tool puts the message that
  started a run at the head of each agent's prompt. P-02 was started by the session's own turn, with no message of the
  owner's to relay. The leak is #0-179, which also re-runs those four. No reviewer's tool calls or text name a seed, the
  run or the catalogue, but their thinking is not in the transcripts. AC3 holds for `security.md` with that
  qualification, recorded with the rows.
- `architecture.md`: rewritten (22 ids: ARC-01…07, 10, 20…29, 40…43, of them ARC-20 retired into ARC-22…29), with
  P-06, P-07 and P-08 renamed in `patterns.md` and P-07 reworded; copied by the owner. The packaged-secret part of old
  section 4 moved to SEC-30's "Backed by" (`check-packaged-profiles.sh`, review round 1). `/review` rounds 1 and 2:
  no blocking finding. On main with PR #536. `/seed-bugs` series on main (2026-10-26), each run started by the owner's
  "dalej" (#0-179's workaround). Every reviewer's first message relayed only that word, so the series was blind.
  Architecture caught and blocked each pattern:
  - P-06 (`arch-after-p06` on `fc368943`, ARC-22): a direct send instead of the outbox.
  - P-07 (`arch-after-p07` on `aace4118`, ARC-23): the lock dropped from `scheduledReconcile`. Architecture blocked it
    as a job that writes shared state, not for a missing annotation; the per-replica `refreshPendingGauge` beside it
    was left alone.
  - P-08 (`arch-after-p08` on `fc368943`, ARC-25): `@Version Long version = 0L` in `Incident`.
  - P-09 (`arch-after-p09` on `82baa5dd`, ARC-02): a hand-written retry loop in `RemoteApiKeyLookupService`. The
    existing Resilience4j `@Retry` was named.
  general also caught all four. AC3 holds for `architecture.md`.
- `general.md`: drafted (17 ids: GEN-01…09, 20…24, 30…32, of them GEN-09 retired). `patterns.md` is unchanged:
  P-15 and P-16 keep GEN-03 and GEN-08; copied by the owner, with `_common.md`'s label definition (review round 1).
  On main with PR #538.
- `general.md` measure: `/seed-bugs` on main (2026-10-26), each run started by "dalej", blind:
  - P-16 (`gen-after-p16` on `82baa5dd`, GEN-08): general answered `NEEDS_HUMAN` and blocked the bare `@Disabled` on
    `CachingApiKeyIntrospectionClientTest#refreshedAfterTtl`; architecture and security caught it too.
  - P-15 (`gen-after-p15` on `fc368943`, GEN-03): general saw the removed state assertion in
    `IncidentCommandServiceTest#recordsLevel` but approved, as other tests still pin the level. GEN-08 wants a reason
    whatever else covers it. GEN-08's "Check:" now says so (copied by the owner). AC3 does not hold for `general.md`
    yet: P-15 is run again on that rule (`gen-after-p15-r2`) once it is on main. Done (PR #539 on main): the seeder
    planted the same edit at the same line, and general answered `NEEDS_HUMAN` with it listed as blocking under GEN-08.
    AC3 holds for `general.md`.
  - Found while drafting that fix: `architecture.md`'s header (PR #536) said "a seeded result", in the file
    architecture reads on every run, so the P-06…P-09 runs had it. No reviewer's transcript acts on it. It is
    reworded (copied by the owner), and ADR-0044 records the residual: a rule file must not mention the benchmark.
- `migration.md`: drafted (9 ids, none retired; MIG-02 "Backed by", review round 1), with P-14 retired and P-19
  added in `patterns.md`; copied by the owner.
  Left for `factory.md`'s rewrite (review round 3): section 3's heading still says "Enforced by checks — do not
  review by hand", while its `check-factory-guards.sh` bullet now says those items are reviewed on the owner's
  PRs. Under C3 that section's items take the two labels, which settles the heading.
- `migration.md` measure: on main with PR #541, each run started by "dalej", blind:
  - P-13 (`mig-after-p13` on `40bf2ef6`, MIG-04): migration blocked a `NOT NULL` column without a default added to
    the existing `user_roles` in V8; general and docs caught it too. It also raised MIG-01 ("V8, but the highest is
    V32"), which is an artifact of an old host: on the seed branch an old migration reads as a new one below the
    highest number. A host's migration should be its service's newest.
  - P-19 (`mig-after-p19` on `aace4118`, MIG-05): not measured. `guard-migrations.sh` refused the seeder's Edit of
    V31, which is on `origin/main` like every migration of a merged change (#0-172's Also). P-13 got through only
    because the seeder wrote with Bash. AC3 for `migration.md` waits for #0-172; P-19 runs then.
  - The first host chosen for P-13, `5af2fd55`, was refused: "the change no longer applies to main".
    `seed-branch.sh` reverts with `git apply -R`, which needs exact context, and the hosts had been checked with
    `git merge-tree`, a three-way merge that accepts more. A host is checked with
    `git diff --binary <parent> <sha> -- <code> | git apply -R --check`.
- `docs.md`: drafted (7 ids, none retired; level A points to the Owner-only list, DOC-10 exempts an accepted ADR's
  Context); `patterns.md` is unchanged: P-17 and P-18 keep DOC-11 and DOC-01. Copied by the owner.
- `docs.md` measure: on main with PR #543, blind:
  - P-17 (`docs-after-p17` on `fc368943`, DOC-11): docs blocked the stale `@return`-style Javadoc of
    `Incident.minutesBetween` under DOC-11, at the Javadoc's line 257. The row says "no": the ground truth is the
    code's line 266, and the Record phase counts only findings within 5 lines (#0-181). Read by hand: caught and
    blocked. general (GEN-30) and architecture caught it at the code's line.
  - P-18 (`docs-after-p18` on `82baa5dd`, DOC-01): docs blocked the required `application.yml` key with no README
    "Step 2" line, at the planted line; general caught it too.
  AC3 holds for `docs.md`, P-17 with that reading, recorded with the rows.
- `k8s.md`: drafted (15 ids: K8S-01…10, 20…24, none retired), with P-20…P-22 added to `patterns.md`; copied by the
  owner. The seed panel takes k8s.
- `k8s.md` measure: on main with PR #545, k8s on the panel for the first time, each run started by "dalej", blind:
  - P-20 (`k8s-after-p20` on `62d4fdb1`, K8S-08): k8s answered `NEEDS_HUMAN`, listing the HTTP snapshot repository
    added to the root `pom.xml` as blocking; general, architecture, security and docs caught it too.
  - P-21 (`k8s-after-p21` on `62d4fdb1`, K8S-10): k8s blocked `${argLine}` in place of `@{argLine}` at the planted
    line; general, architecture and docs caught it too.
  - P-22 (K8S-06) not measured: `seed-branch.sh` refused `4e608067`, which also changes `check-k8s-environments.rb`,
    its test and `ci.yml` (the evaluator), and no other revertible change touches a Deployment. It runs on the first
    change to a Deployment that touches no evaluator path, like K8S-01, K8S-02 and K8S-09, which have no pattern yet.
  AC3 holds for `k8s.md` on P-20 and P-21; P-22 waits for a host.
  - Lesson: a host is checked twice, `git diff --binary <parent> <sha> -- <code> | git apply -R --check` and no
    file of the change on `seed-branch.sh`'s evaluator list (the protected paths and `CLAUDE.md`). P-04 on
    `8ea7a120` and P-22 on `4e608067` passed the first and failed the second.

- `factory.md`: drafted (12 ids, none retired; section 3 moved into the rules' "Backed by"), with `security.md`,
  `architecture.md` and `general.md` pointing to `_common.md` for the labels and CLAUDE.md's merge-on-green sentence;
  copied by the owner. The measure (F1) is the second PR.
- `factory.md` measure (F1, 2026-10-28). The plants were made by hand, because `seed-branch.sh` refuses every host:
  the workflows are Owner-only. Each host's code was reverted on `review/<8 hex>`, replayed with the plant left
  uncommitted, and reviewed with `/review 27`; no prompt named the plant:
  - P-23 (`fac-after-p23` on `0fabc93a`, FAC-A02): at `backlog-autopilot.js:482`, `!pinned ||` became `pinned &&`.
    Architecture blocked it at that line under FAC-A02. Security blocked it there too, under FAC-S03 (the one pin of
    the run's branch, which #0-131's push guard rests on). The verifier could not settle the claim that a test fails,
    because it reads only the gate's Maven artifact. The session ran the test itself, and
    `test-autopilot-workflow.mjs` failed ("the run's branch is recorded in the lock before any agent works on it, or
    the run stops").
  - P-24 (`fac-after-p24` on `3f13958f`, FAC-A06): `unverifiedEscapes` was left out of `audit.js:36`'s schema, and the
    field is read at `:50`. Architecture blocked it at the planted line under FAC-A06. Security named it non-blocking
    and passed it to architecture.
  - In both runs both reviewers reached the original: the defect was the tree's only difference from `main` (P-23), or
    one `git show` of the revert away (P-24). This is #0-185.
  - FAC-S has no pattern: its hosts are hooks, settings and agents, which are what `/review` runs under.
  - ruleGaps:
    - Both runs: no check types `audit.js`'s or `backlog-autopilot.js`'s `factory-ops` answers. This is #0-175's AC2.
    - Architecture: the manual gate runs no Factory guards test on a diff that changes only workflows.
    - Security: no FAC-S rule covers the integrity of a control file a guard trusts (the lock's branch).
  AC3 holds for `factory.md` on P-23 and P-24, with #0-185's caveat; FAC-S is not measured.

**Acceptance criteria.**
AC1. Every rule of the rewritten file is an invariant with a "Check:" line, or retired with a reason.
AC2. No id was reused or renumbered.
AC3. Once each rewritten file is on main, `/seed-bugs` on its dimension's patterns has the panel catch each of them
(reworded by the owner, 2026-10-25: the audit had too few autopilot PRs to compare, and a before-and-after of one
sample per pattern compares little).

### 0-121. A pipeline audit traces problems to the stage that introduced them

**Type:** design · **Priority:** Medium · **Status:** Done, PR #484 (owner's decision 2026-10-10, after #0-42). Kept in full
for the decision (one pipeline analyst, phase containment) and the first collected cases.

**Problem.** The only audit target is `reviewers` (`.claude/workflows/audit.js`): one analyst per review
dimension, which fits seven parallel reviewers with one verdict format. The stages before and after the panel
— `/ready` with `ready-checker`, the planner, the picker, the architect, the implementer, acceptance and the
shipper — run in sequence, and a problem in one usually shows up in a later one. #0-42 was introduced in
`/ready` (an AC needing `.github/`), passed the architect (`Risk: high` let it through) and was detected only
by the implementer (draft PR #477). No analyst looks at that chain: the reviewers' audit sees nothing (no
review ran), and an audit per agent would see each stage acting correctly on its own.

**Decided (owner, 2026-10-10).** Not one auditor per agent: one analyst for the whole pipeline beside the
`reviewers` audit. It measures phase containment — for each item that did not go through cleanly (BLOCKED,
extra rounds, `backlog-estimate-off`, an escape) the stage where the problem was introduced and the stage where
it was detected — pools cases across stages (so the ≥3-case rule of `.ai/rules/audit.md` is reachable) and
addresses each recommendation to the stage that should have caught it. A stage gets its own analyst only when
the data shows it produces most of the cases.

**Data already recorded** (backlog #0-122): the stop stage and draft PR of a BLOCKED item in
`.ai/runs/state.json`, the "Ready check" section of a `/ready` PR, and the hard-fact rule for deterministic
contradictions in `audit.md`.

**Work.** A target `pipeline` in `audit.js`, an `audit-pipeline` agent definition, its data in
`scripts/factory/audit-data.sh` (the `/ready` PRs, `handoff.md` of BLOCKED items), and its section in
`.ai/rules/audit.md`. Human-only: every file is a protected path. Worth starting once a few BLOCKED or
reworked items exist to measure.

**Delivered.** `audit-data.sh` derives the cases (BLOCKED, rounds > 1, a scope category that points at a stage, acceptance
other than ACCEPT, owner labels `human:fp-*` / `human:missed-*` / `human:introduced-*`, BLOCKED runs without a PR)
and attaches each item's `/ready` PR, tested by `test-audit-data.sh`; a new read-only agent `audit-pipeline` traces
each case through every stage with one escape class per stage passed (no rule, rule not applied, rule allowed it,
no data) and recommends to the cheapest stage; `audit.js` gains the target `pipeline`, and `all` (the default)
runs it with the reviewers' audit on the same cadence; `audit.md` "Pipeline audit"; `audit-synthesis` writes its
report; owner labels `human:introduced-<stage>` (optional confirmation, set back on PR #477 and #482). Also:
both audit agents read text as data, not instructions; `/apply-audit` names its branch after the report file
(one report per target per audit); the `**Escaped from:**` convention takes any stage. The list below is the
history of the first cases; from now on they are derived, not written by hand.

**Collected cases** (stage introduced → stage detected; recorded here so the audit, once built, starts with them):
1. #0-42 — an acceptance criterion needed a new `.github/` check the autopilot may not write. Introduced in `/ready`
   (and passed by the architect), detected at `implement`: BLOCKED, draft PR #477. Fixed by #0-122.
2. #0-124 — README "Infrastructure Hardening" missing from Touches although the item adds a security control; the
   checker had asked, the answer dismissed it. Introduced in `/ready` (PR #481), detected at the scope comparison:
   `backlog-estimate-off` in PR #482 (the implementer added it, correctly). Fixed by #0-125.
3. PR #482 — DOC-10 on the Context section of an accepted ADR (ADR-0026), which records the state when it was
   decided; owner label `human:fp-docs`. Introduced and detected in review (docs dimension) — a reviewers-audit case.
4. #0-199 — the item's premise (a method-less mapping runs its handler for an anonymous `OPTIONS`) was false: Spring
   MVC answers that `OPTIONS` itself. Introduced by PR #576's review panel (security SEC-12, general GEN-24,
   architecture, non-blocking), passed by `/ready #0-199` (PR #578, three manual `/review` rounds; the library facts
   checked in the jars' bytecode covered CORS and Spring Security, not MVC's request matching), detected at `plan`:
   the architect BLOCKED the item (run 20261102-113931, draft PR #581). Fixed by the correction in #0-199's criteria.

---

### 0-122. Protected paths: one list, a Touches gate and the stop stage

**Type:** bug · **Priority:** High · **Status:** Done, PR #478 (found by #0-42's autopilot run, 2026-10-10). Kept in
full as the record of why the protected paths have one list; code comments cite `backlog #0-122`.
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** ci (scripts/factory, .github/scripts, .github/workflows/factory-guards.yml), root (README.md, CLAUDE.md, AGENTS.md, .ai/rules, .claude)

**Problem.** #0-42 was marked `ready` with `Risk: high` and an acceptance criterion needing a new
`.github/` check. The architect let it through (`Risk: high` items proceed), and only the implementer, which
may not write `.github/`, stopped it (draft PR #477) — one wasted run. Behind it: `ready.md` read "Risk: high
or not ready" without saying when, `ready-checker` pushed criteria toward new CI scripts, no code checked an
item against the paths the autopilot may not write, and that list existed in about ten places that had
drifted apart (the shell hook did not cover `.ai/audit/decisions.md`; one copy treated all of `CLAUDE.md` as
protected). The run state recorded the block with no PR and no stage, so an audit could not see where it
was stopped.

**Decided (owner, 2026-10-10).** One list, `.ai/rules/protected-paths.md`, read by the scripts (from the base
commit, failing closed) and by every agent that needs it; the deny rules, the shell hook and CODEOWNERS keep
literal copies, checked in CI. The gate reads **Touches only** (a criterion may name an existing check) and
treats a bare `ci` as protected. `Risk: high` only says who merges. A deterministic contradiction of rules is
a hard fact in `audit.md` (one case is enough for a missing-gate recommendation). One pipeline auditor
later, #0-121.

**Delivered.** `_protected.sh` reading the list; `next-item.sh` / `check-queue.sh` refuse such an item;
`changed-paths.sh` and `check-factory-guards.sh` rule 6 read the same list (from the base);
`check-protected-paths.sh` (deny rules, hook, CODEOWNERS by GitHub's last-match rule) with its test; the hook covers `.ai/audit/decisions.md`; `state.sh` records the stop stage and draft PR (`prArg`
keeps the record when a URL is odd); `ready.md`, `ready-checker`, the architect, `/ready` (a "Ready check"
section in its PR), the implementer, the reviewers' `_common.md`, `AGENTS.md`, `CLAUDE.md`, README and
`docs/ai-factory.md` point at the list; #0-42 is `human-only`.

---

### 0-123. Reviewers are told which tool to use, and every hook refusal names it

**Type:** bug · **Priority:** High · **Status:** Done, PR #479 (found in the manual `/review` of #0-42, 2026-10-10). Kept
in full for the decision (tell, do not loosen) and the reverted first draft.
**Autopilot:** human-only · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** root (.claude/hooks/readonly-bash.sh, .claude/hooks/test-hooks.sh, .claude/skills/review-procedure, .claude/agents, README.md)

**Problem.** The review agents (and `ready-checker`, `acceptance-reviewer`, the auditors) run Bash through
`readonly-bash.sh`, an allow-list of one read-only git command per call. `review-procedure` told them only to read
`git diff HEAD`, not how to read a file or search, so they reached for `cat`, chained commands, `git -C` and
`git grep -E "a|b"`; each was refused with a message that said what was forbidden but not what to use. In one
review the architecture reviewer was refused four times and ran for over 14 minutes; the performance reviewer
stopped reading after a refusal and reviewed half the change; `git diff HEAD` also hides new, untracked files,
which the owner had to list by hand for every round.

**Decided (owner, 2026-10-10).** Tell, do not loosen (option A): a "Tools" section in `review-procedure` (Read for
files, `git grep -n -e … -e … -- <paths>` to search and `git ls-files` to list, one command per call,
`git status --short` for new files, never stop reading) and every refusal a reading agent can hit names the
alternative, per hook mode. The first draft pointed agents at the Grep and Glob tools; the architecture review
(arc-3c7e) showed it contradicted `_common.md` and `implementation.md` (those tools do not exist in every Claude
Code version — that reviewer had only Read and Bash), so `git grep` stays the search, as decided there. The allow-list stays as it
is: `cat` would bypass the Read deny rules that keep secrets out of reach, and parsing quotes in the hook to allow
`|` inside them is a classic bypass (a parser that disagrees with the shell). Rejected: loosening the hook
(option B), adding `git -C` (option C, no need once the working directory is stated).

**Delivered.** `readonly-bash.sh` refusals (separators, git options, unsafe `git grep`, `git branch`, anything off
the list) carry a hint naming Read and `git grep -e`, plus the mode's extra commands (`--k8s`, `--gh-read`,
`--architect`); `test-hooks.sh` replays the forms reviewers tried (each refused with the hint; `git diff HEAD`,
`git status --short` and `git grep` with several `-e` pass); `review-procedure` "Tools" and the manual-review step
for untracked files; one line in `ready-checker`, `acceptance-reviewer`, `audit-reviewers`, `planner` and
`architect`, which do not preload the procedure; README "Least privilege per agent". Measured on the first review
with it: the architecture reviewer finished in 66 s, against more than 14 minutes and four refusals before.

---

### 0-129. The pipeline audit counts only escape markers the owner added

**Type:** security · **Priority:** Medium · **Status:** Done, PR #491 (split from #0-126 at its `/ready`, 2026-10-10).
Kept in full for the decisions (the PR opener vouches, nothing else does) and what three review rounds changed.
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** — (#0-126 is Done; do in one PR with #0-128)
**Touches:** ci (scripts/factory/audit-data.sh, scripts/factory/_marker.sh, .github/scripts/test-audit-data.sh, .claude/workflows/audit.js, .claude/agents/audit-pipeline.md, .claude/agents/audit-reviewers.md), root (.ai/rules/audit.md, README.md "Infrastructure Hardening", docs/ai-factory.md)

**Problem.** `audit-data.sh` makes a case of every `**Fixes:** #0-N · **Escaped from:** <stage>` marker added to
`BACKLOG.md`/`BACKLOG-DONE.md` in the period, whoever's commit added it: a branch, or an agent steered by injected
text, could plant a case or a "hard fact" that raises an audit's confidence (`audit.md`, the confidence table). #0-126
closes the same hole for `human:*` labels; markers are a different source (commit history, not PR timelines).

**Approach.** Count a marker only when GitHub vouches for who wrote it: the commit that added it reached `main`
through a PR opened by the owner's login (a signature does not vouch, see AC2). Not enough on their
own: the commit's author or committer (free, unsigned text; the owner and the bot share the container) and a merge by
the owner (in shadow mode the owner merges every autopilot PR, so a planted line in a long diff would pass). Report
the others as unverified, never as cases. Same owner source as #0-126 (`gh repo view --json owner`). Do it together
with #0-128, whose CI check reads the same `MARKER` (`scripts/factory/_marker.sh`, AC10).

**Acceptance criteria.**
AC1. A marker whose adding commit belongs to a PR merged into `main` and opened by the owner's login is a case in
the audit data.
AC2. A marker whose commit names the owner only as author or committer (name or email), e.g. pushed straight to
`main` with no PR, is reported `unverified` and is not a case; a GitHub signature does not vouch for it either (this
narrows the Approach's "or a verified signature": the owner signs nothing, and the web-flow signature on merge
commits is GitHub's, not the owner's).
AC3. A marker in a PR opened by anyone other than the owner (the bot included) is `unverified`, even if the owner
merged that PR.
AC4. The PR is looked up with `gh api repos/<repo>/commits/<sha>/pulls`; when it returns several PRs the marker counts
only if one of them is merged into `main` and opened by the owner; a failed call makes the marker `unverified`.
AC5. `unverified` markers are listed in the output (count and lines), so the auditor sees what was dropped.
AC6. The owner login comes from `gh repo view --json owner`, as in #0-126; a failed lookup makes every marker
`unverified` (fail closed).
AC7. The raw `escaped` list read by the reviewers audit is filtered by the same rule (its adding commit found with
`git log -S`), its unverified markers reported separately.
AC8. README "Infrastructure Hardening" lists the control.
AC9. `.ai/rules/audit.md` states that a marker counts only when vouched for, and its confidence table no longer
treats an unverified marker as a hard fact.
AC10. `MARKER` is defined once, in `scripts/factory/_marker.sh`, which `audit-data.sh` and #0-128's check both
source (decided when building it, 2026-10-12: a shared definition like `_protected.sh`, rather than a check mode in
`audit-data.sh` or a check that parses the line out of it), and the vouching applies to that pattern.
AC11. While any autopilot PR of the period is authored by the owner's login, every marker is `unverified` — the
`ownerIsAutopilot` rule of #0-126: the autopilot then opens its PRs with the owner's token, so the opener proves
nothing (added when building it, 2026-10-12).
AC1–AC7, AC10 and AC11 are checked by `.github/scripts/test-audit-data.sh`; AC8–AC9 are judged by review-docs.

**Review round 1 (2026-10-13).** A marker sits on its item's `**Type:** … · **Status:** …` line, and the first build
traced and dated it by that whole line: a status change made the changer its author (the owner's edit vouched for
the bot's marker, the bot's close unvouched the owner's) and a new marker of the period. It is now traced by the
marker itself (`marker_span` in `_marker.sh`, which also reads the item and stage, so `audit-data.sh` has no second
pattern), and the found commit must add exactly that marker (`git log -S` matches substrings). Also: the history is
read without replace refs or grafts, `pulls_verdict` vouches with an explicit `OK`, and #0-128's check catches the
marker in any case, bold or not. Kept as a known limit, its own item: a commit pushed onto the owner's PR branch by
another account is in the owner's PR (#0-131).

**Review round 2 (2026-10-13).** A marker was new in a period when its lines there were added more often than
removed, but vouched by its first commit: the bot copying an old owner-vouched line, the original left in place,
made it a vouched case again. It is now new only when its origin commit is in the period. And the history is read
without textconv or external diff drivers (`.git/config` could rewrite what `-S`, `-p` and `show` see), and a
shallow clone vouches for no marker (its boundary commits show their whole files as added).

**Review round 3 (2026-10-13).** The period's history is read with `--since-as-filter`: `--since` stops at the
first older commit, so one back-dated commit hid every marker behind it. Each marker line reaches jq as its own
value (a tab in a marker split the old tab-separated records), and the commands in the vouching loop read
`/dev/null`, not the loop's input. `audit.md` states that the `ownerIsAutopilot` limit is wider for markers (any
earlier period); no such marker exists, the autopilot has always run as its own account.

---

### 0-130. A shell guard that fails refuses the command instead of allowing it

**Type:** security · **Priority:** Low · **Status:** Done, PR #492 (found by the security review of #0-126, 2026-10-10).
Kept in full for the decisions (option B, `readonly-bash.sh` in scope) and what four review rounds changed.
**Autopilot:** human-only · **Risk:** medium · **Complexity:** low · **Depends on:** —
**Touches:** root (.claude/hooks/guard-protected-bash.sh, .claude/hooks/readonly-bash.sh, .claude/hooks/_lib.sh, .claude/hooks/test-hooks.sh, README.md "Infrastructure Hardening")

**Problem.** `guard-protected-bash.sh` runs `why=$(git_grep_unsafe "$cmd")` and `why=$(gh_label_unsafe "$cmd")` and
lets the command through when `why` is empty. A runtime error inside either function (an unset variable, a failed
`sed`) also leaves `why` empty, so the guard fails open. The impact is bounded — the audit's own actor check is the
control for labels (#0-126), and the commit gates and PR checks for the rest — but a guard should fail closed.
`readonly-bash.sh` (the reviewers' allow-list) calls `git_grep_unsafe` the same way.

**Approach.** Both functions end every path with an explicit `return 0` (allowed) or print-and-return (refused), and
the caller refuses when the function's exit status is non-zero (`why=$(…) || block "the … check failed"`), with a
test that a forced error in each is refused.

**Decided (owner, 2026-10-14).** Every failure refuses, not only one that aborts the function (option B): a step that
fails without aborting — `grep -q … || return 0` taking grep's error (2) for "no match", a `sed`/`tr` that fails and
leaves an empty word list — returns 2 too. Matching moved from grep on a here-string to bash's own `[[ =~ ]]` and
`case`, which have no such failure (a here-string bash cannot write fails with exit 1, grep's "no match"); the
`sed`/`tr` substitutions keep the tools and end in `|| return 2`. `readonly-bash.sh` is in scope (the same pattern).
Left out, for its own item: `guard-protected-bash.sh`'s own grep checks (secrets, mvnw, protected paths, writes)
and `json_get` (a failing jq leaves an empty command, which exits 0) fail open the same way.
Review round 1 (2026-10-14), fixed here: a newline inside a quoted word split one argument into two words for both
checks, which read `shell_words`' output one word per line (`git grep 'x<newline>--' --untracked …` passed, also on
`main`: sec-4e1a) — a `git grep` or `gh` command with a newline in it is now refused (multi-line commit messages still
pass; a multi-line PR body goes in `--body-file`); and `matches` runs in the C locale, where a byte that is not valid
UTF-8 cannot turn a match into "no match" (sec-9c27). Review round 2, fixed here: `git grep` run behind something passed
the check, which starts at word 1 (`env`/`command`/`sh -c git grep`, `GIT_DIR=x git grep`, `/usr/bin/git grep`, a glob
such as `/usr/bin/gi[t]`; also on `main`, stopped in practice by the autopilot's allow-list) — refused now, as
`gh_label_unsafe` does for gh. Review round 4, fixed here: a glob where the subcommand goes (`git gr?p`, `git g[r]ep`,
`git *`, also behind git options) became grep once a file of that name existed — refused; the first filter also lets
through a glob made only of grep's letters, so an ordinary `git add src/*.java` is not touched.

---

### 0-131. The autopilot pushes only the branch of its own item

**Type:** security · **Priority:** Medium · **Status:** Done, PR #525 — found by the security review of #0-128/#0-129
(2026-10-13); owner's decision below. Kept in full for the decisions (the branch in the lock, the review rounds' bindings)
**Autopilot:** human-only · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** root (.claude/hooks/guard-git-push.sh, .claude/hooks/test-hooks.sh, README.md "Infrastructure Hardening", .ai/rules/audit.md)

**Problem.** `guard-git-push.sh` lets an autopilot session run `git push -u origin <type>/<name>` for any feature
branch, so it can fast-forward a branch of the owner's open PR. #0-129 counts an escape marker when its commit is in
a PR the owner opened and merged into `main`; a marker the bot pushed onto that branch is in the owner's PR, and
counts once the owner merges it without noticing the extra commit. The same push could slip any change into a PR
the owner believes is only theirs.

**Approach.** The push guard allows only the branch the picker created for the item of the current run (recorded
in the run's working files), and refuses every other branch, with a test per form (another item's branch, the
owner's branch, a branch that does not exist yet). Branch protection (#0-113) cannot express "this account only
its own branches" on a personal repository, so the hook is the control; the owner still reads the commits of
their own PR before merging. Remove the known limit from README and `audit.md` when done.

**Decided (owner, 2026-10-25, after `/research`).** Option A: the branch is recorded in `.ai/runs/LOCK`, not in the
run's working files (an agent can change those; no agent writes the lock: the autopilot's denies,
`guard-protected-bash.sh`, checked both ways since #0-168; code run through `./mvnw` can, #0-116). Review round 1
added two bindings: only the factory-ops agent runs `scripts/factory/` (`guard-factory-scripts.sh`, on `agent_type`;
before, any agent could `state.sh unlock`, `preflight.sh` and `state.sh branch <another>`), and the workflow binds
the picker's branch to `<type>/<item>-…` and, on resume, to the owner's `args.branch` before recording it. Round 2:
only a single read-only `git grep|diff|log|show|ls-files|blame` may name `scripts/factory/` for other agents (not a
match on how a script is run); `factory-ops` not being bound to its task's command is #0-169. Round 3: git's
`--output`, `--ext-diff`, `--textconv` count as writes in `guard-protected-bash.sh` (an allow-listed `git log` could
write the lock), in their plain form; a word spliced with quotes or a backslash is #0-167's, which now names the
autopilot's sessions and the lock too. `state.sh branch <name>` writes it as the lock's third
field, once per run (a second call, no lock or a name that is not a feature branch is refused); the workflow calls it
right after validating the picker's answer, on resume too, and stops the run when it fails. `guard-git-push.sh`
lets through only `git push -u origin <that branch>`; no lock, or no branch in it, refuses every push.

---

### 0-132. The shell guards' own checks refuse when they fail

**Type:** security · **Priority:** Low · **Status:** Done, PR #526 — found while fixing #0-130 (2026-10-14); owner's
decision below. Kept in full for the decisions (A1-E1, the whole-text match)
**Autopilot:** human-only · **Risk:** medium · **Complexity:** low · **Depends on:** #0-130
**Touches:** root (.claude/hooks/guard-protected-bash.sh, .claude/hooks/readonly-bash.sh, .claude/hooks/guard-git-push.sh, .claude/hooks/guard-factory-scripts.sh, .claude/hooks/factory-ops-bash.sh, .claude/hooks/_lib.sh, .claude/hooks/test-hooks.sh, README.md "Infrastructure Hardening")

**Problem.** #0-130 made `git_grep_unsafe` and `gh_label_unsafe` refuse when they fail. The guard's own checks
still read a failure as "nothing found": `printf … | grep -Eq "$secrets"` (a secret file), the `mvnw` write check,
`grep -Eq "$protected" || exit 0` (no protected path, so allowed) and the `writes` check take grep's error (2) for
"no match", and `json_get` returns an empty command when jq fails on the input, which the hooks answer with
`exit 0` (that part moved to #0-162 by the owner, 2026-10-24). Other hooks (`readonly-bash.sh`, `guard-git-push.sh`, `guard-factory-scripts.sh`, `factory-ops-bash.sh`)
read the command the same way. Bounded like #0-130: the deny rules, the commit gates and the PR checks stay.

**Approach.** The same contract as #0-130: matching with bash's own `[[ =~ ]]` / `case` where it can, a tool's
failure is a refusal (`json_get` telling "no such field" from "could not parse": #0-162). A test
per check with the tool broken, as in #0-130's. `shell_words` moves to the same three-way contract (refused = exit 0
and a reason, failed = non-zero), which removes `shell_words_refusal`, the shim that tells the two apart by the text
`REFUSE` (architecture review of #0-130), and refuses a newline inside a quoted word itself, as both its callers now
do separately because they read its output one word per line (architecture review round 2 of #0-130).
Also from #0-130's review round 3: the program list that `git_grep_unsafe` and `gh_label_unsafe` refuse a command
behind (`sh|bash|…|time`) is one copy each — one shared definition; and two forms neither check sees, an interpreter
run by its path or off the list (`/bin/sh -c "git grep --untracked …"`, `ksh -c`, `perl -e`) and a git alias
(`git -c alias.g='grep --untracked' g`). Both are stopped today by the autopilot's `dontAsk` allow-list and by
`readonly-bash.sh`'s first-two-words check; decide here whether the guard should refuse them too (e.g. any first word
that is a path, with a standalone `-c`/`-e`) or keep naming the allow-list as the control.
A known side effect to keep or narrow here: since #0-130 the first filter of `git_grep_unsafe` also lets through a
command with a glob and the word grep, so `./mvnw test -Dtest='Foo*' | grep FAIL` is refused ("a command with grep and
a glob") in every session the guard covers (architecture review round 4 of #0-130; grep is not on the autopilot's
allow-list, so it changes little there).

**Decided (owner, 2026-10-25, after `/research`).** A1 + B1 + C + D1 + E1, in one PR.
- **A1.** The guards' checks match with `finds` (`_lib.sh`, on `matches`: bash's own regex in the C locale, an
  invalid expression refuses) instead of `printf … | grep -Eq` (`guard-protected-bash.sh`, `guard-git-push.sh`,
  `guard-tests.sh`, `guard-factory-scripts.sh`). Found on the way: grep matched line by line, so an allow pattern
  anchored `^…$` (`git fetch origin main`, the push of the run's branch) passed a command whose first line alone
  matched; `finds` matches the whole command.
- **B1.** `shell_words` answers by its exit status alone (0 and the words, 3 and the reason, other = it failed),
  printing the words only at the end; `shell_words_refusal` is gone. Not moved into it: the refusal of a newline
  inside a quoted word, which its callers make only once the command is `git grep` or `gh pr create|edit` — inside
  `shell_words` it would refuse a multi-line commit message that names git grep (a test of #0-130 that must pass).
- **C.** One list of the programs a command can run behind (`WRAPPER_PROGRAMS`, `is_wrapper`).
- **D1.** An interpreter by its path or another name, and a git alias, stay the allow-list's to stop (`dontAsk`
  in autopilot sessions, `readonly-bash.sh`'s first two words for the reviewers); written at `WRAPPER_PROGRAMS`, and
  a guard that reads a command as bash does is #0-167.
- **E1.** The glob-and-grep refusal is kept, and written at the check.

---

### 0-141. One 502 from Maven Central fails the image builds

**Type:** bug · **Priority:** Medium · **Status:** Done, PR #498 (found 2026-10-16 in the smoke tests of 2026-10-15; with
#0-100 and #0-144). Kept in full as the record of the decision and the design it replaced, which ADR-0030 and the code
refer to.

**Problem.** On 2026-10-15 around 19:16 UTC the Docker Compose smoke test failed on three Renovate PRs (#402
oncall-service, #165 auth-service, #194 ingestion-service) and on `main` after #496, each in a Dockerfile's
`dependency:go-offline` on a different artifact, with a 5xx from `repo.maven.apache.org` (502 Bad Gateway); none of
the PRs changed what failed, and a rerun is the only remedy. Two causes. The Maven resolver does not retry a 502:
Maven 3.9.16 ships resolver 1.9.27, whose `aether.connector.http.retryHandler.serviceUnavailable` defaults to
`429,503`. And each of the seven Dockerfiles resolves on its own, with its own cache (`id=<service>-m2`): the smoke
test builds on a fresh runner, so one run fetches nearly the same tree, and the Maven distribution the wrapper
downloads, seven times, seven chances to meet a 5xx.

**Decided (owner, 2026-10-16, third round; ADR-0030).** Maven builds the services once, and the images only
package the jar (R1).
- The Dockerfiles are a JRE `layers` stage: `COPY <service>/target/<service>-*.jar`, exactly one, then
  `jarmode=tools extract --layers --launcher`. The runtime stage takes 4 layered `COPY`s and starts with
  `JarLauncher`; files are root-owned and not writable by `appuser`.
- No Maven, sources or JDK in Docker. `.dockerignore` is an allowlist of those jars.
- build-and-test uploads the jars `verify` tested (`service-jars`, uncompressed, 1 day). The smoke test
  (`needs: build-and-test`) puts them back into `<service>/target/` and is the only job that builds images.
- The per-service `docker-build` matrix is removed: same images, same jars, nothing more proven.
- The Maven repository cache moves from setup-java's `cache: maven` to `actions/cache`.
  - setup-java restores only an exact match of the POMs' hash, so every Renovate PR downloaded the whole tree.
  - The new cache restores by prefix within the month and is saved on a push to `main` only.
- `.mvn/maven.config` retries 429, 500, 502, 503 and 504 (the resolver default is 3 attempts, 5 s apart).
- `make dev-up` runs `make build` first, then `compose up -d --build`.
- #0-100 is fixed with it: a local jar would otherwise carry `application-local.yml` into a local image.
  - The root POM excludes `application-local.*` and `application-secrets.*` from every jar, `shared`'s too.
  - CI plants both in every module, and `check-no-local-config-in-jars.sh` (with `test-…sh`, 14 cases, mutation
    tested) checks each service jar and the `shared` jar nested in it.
- The smoke test runs `break-glass-mfa-reset` without options and expects its refusal (exit 1), which proves
  that `JarLauncher` passes the arguments to `main`.
- `snyk.yml` and `owasp-dependency-check.yml` restore the same Maven cache and never save.

**History of the decision.**
- **First:** retry plus one identical go-offline step in every Dockerfile, into a shared locked cache (A+B1').
  Measured on an empty builder: 245 → 237 s for the 7 images, one resolve instead of seven, builder cache
  9.7 → 6.5 GB.
- **Review r1 found** that its `/m2` copy is a 670 MB layer per image, which docker-build's
  `cache-to: type=gha,mode=max` would export into the 10 GB Actions cache.
- **Second (X):** keep Maven in the Dockerfile, but let CI replace a `FROM scratch AS jar` stage with
  build-and-test's jar.
  - Parts: `build-contexts`, a compose override, a contract checker, and a job building from source on
    `infra` PRs and `main`.
  - It was implemented and reviewed, then replaced before merge. That job downloaded from Central again on every
    push to `main` and on most Renovate PRs. The per-service matrix duplicated the smoke test, and each matrix
    runner downloaded all 800 MB of jars.
  - X's reason, a fresh clone without a JDK, does not hold: Java 21 is a prerequisite.
- **Rejected throughout:**
  - Jib: no Dockerfiles, which the checks and the hardening are written against; reconsider with the registry,
    #0-71.
  - Buildpacks: builder images of several GB.
  - A separate `package -DskipTests` job: two compilations.
  - A repository proxy.

**Measured** (locally, R1):
- `./mvnw clean package -DskipTests` takes 13 s, and the 7 images build in 13 s.
- Each image's build context is only its jar (about 120 MB).
- Layers (incident-service): dependencies 121 MB, loader 0.7 MB, snapshot dependencies 4 kB, application 0.7 MB.
  A code change replaced only the application layer.
- All 7 services are healthy. No `application-local` is in any jar or image, and CI's check catches a planted
  one. `docker compose run --rm auth-service break-glass-mfa-reset` reaches the command (its refusal, exit 1).
- No jar fails the build, and so do two.
- CI, measured on PR #498 (run 38891947846, all seven services) against `main`'s run 38862847045:
  - wall clock: 10 min 16 s instead of 9 min 46 s;
  - runner time: 11 min 41 s instead of 32 min 40 s;
  - the smoke test: 3 min 15 s instead of 6 min 08 s;
  - build-and-test: +44 s, from a first run that restored no cache (compile 37 s instead of 15 s, one download
    from Central).
- A change to one service or to `k8s/` alone now takes about 9.5 min instead of about 6 min 12 s (PR #497),
  because the smoke test follows build-and-test (ADR-0030).

---

### 0-160. What a reviewer could not verify is never checked

**Type:** design · **Priority:** High · **Status:** Done, PRs #513 (D) and #514 (C) — found in the `/review` of #0-157
(2026-10-22); owner's decision: C + D below; in two PRs (2026-10-23): D first, then C. Kept in full for the decisions
(E2, the allow-list, the read scope) and the spikes
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/workflows/backlog-autopilot.js, .claude/agents/ (a new verifier agent),
.claude/skills/review, review-procedure, ship-record, .claude/settings.autopilot.json, .claude/settings.json,
.claude/hooks/, scripts/factory/run-tests.sh), ci (.github/workflows/factory-guards.yml, .github/scripts/ tests and a
structural check), .devcontainer/init-firewall.sh, rules (.ai/rules/review/_common.md), root (README.md "Infrastructure Hardening", docs/ai-factory.md, an ADR in
.ai/decisions/)

**Problem.** The review agents are read-only on purpose (`readonly-bash.sh`: git only, no Maven, no network), so
every claim that depends on the build or on the outside goes to the verdict's `unverified` list
(`_common.md`). Nothing reads it: in the autopilot `unverified` exists only in the verdict schema
(`backlog-autopilot.js`), and neither the acceptance reviewer, the shipper nor the PR record sees it; in a manual
`/review` only the session closes it, if it does. In the review of #0-157 all six reviewers marked the core of the
change unverified (that Tomcat 10.1.61 exists, fixes the six CVEs and is resolved in every service): checked by the
session, by `dependency:tree`, `verify` and Apache's security page, not by the pipeline. Reviewers also see only
"the test gate passed", not what it produced.

**Decided (owner, 2026-10-22).** Reviewers stay without Maven and network (running `mvn` runs the plugins a
reviewed POM declares; a reviewer reads untrusted text, so a fetch could leak). Instead:
- **D. The test gate's artifacts for the reviewers:** the gate writes what it ran and produced (modules, test
  counts and failures, JaCoCo per module, `dependency:tree` of the affected modules) to a file under the run's work
  directory; the review prompt names it and reviewers read it with Read.
- **C. A verification stage after the panel:** a new agent receives only the panel's `unverified` items (never the
  diff, so the change cannot steer it), closes the local ones from D's artifacts and the external ones with
  WebFetch restricted to an allow-list of domains (to decide: tomcat.apache.org, security.snyk.io,
  repo1.maven.org, nvd.nist.gov, github.com/advisories, docs.spring.io ...), and answers per item: verified (with
  the source), refuted (becomes a blocking finding for the next round) or not verifiable (the item stops as
  `NEEDS_HUMAN`, or the owner accepts it in the PR). The result goes into the PR's review record (`ship-record`);
  the manual `/review` runs the same stage.

**Approach (to analyse).** How the allow-list is enforced (permission rules `WebFetch(domain:...)` in the
verifier's frontmatter/settings, or a PreToolUse hook; `settings.autopilot.json` denies WebFetch for everyone
today), that the verifier has no Bash and no write outside its result, what an item it cannot classify does, and
the cost (one agent per round, skipped when no item is unverified). An ADR records it.

**Decided (owner, 2026-10-23, after the analysis).** The Approach above assumed rules could be set per agent;
Claude Code's documentation says otherwise, and the decisions follow from it:
- **Enforcement — a session-level hook keyed on the agent (E2).** A bare `deny: WebFetch` removes the tool for the
  whole session, subagents included, and no allow rule or hook overrides it; a subagent has no permission rules
  of its own (only `tools`, `disallowedTools`, `permissionMode`, `hooks`); frontmatter hooks do not run in
  `claude -p`; session-level hooks do run in subagents and their input carries `agent_type`. So the bare deny
  goes from `settings.autopilot.json`, and a PreToolUse hook on `WebFetch` lets only the verifier through, only
  to `https` URLs under an allow-listed host and path prefix, without a query string (a `domain:` rule matches
  the host only, so `github.com/search?q=<data>` would pass it; and in `dontAsk` WebFetch's built-in preapproved
  documentation domains need no approval). Rejected: rules only (E1: host-only, every agent, preapproved
  domains); a separate `claude -p` process for the verifier with its own settings (E3: keeps the bare deny, but
  the verdicts live in the workflow's memory and would need a new path to a file, a nested authenticated
  `claude`, and a cost cap outside the agent budget) — the fallback if the first step below fails. The weaker
  layer (a hook instead of an absent tool) is named in the ADR and in README "Infrastructure Hardening".
- **First step of C:** confirm that `agent_type` reaches the hook for an agent the `Workflow` runtime spawns (the
  documentation says so for subagents; Workflow is another path). If it does not, E3. **Done 2026-10-23, positive**:
  a session-level PreToolUse hook logged `agent_type` `"review-docs"` for a Workflow agent with
  `agentType: 'review-docs'`, `"workflow-subagent"` for one without, `"Explore"` for an Agent-tool agent, and none for
  the session's own call. E2 stands (ADR-0037). **Second spike, 2026-10-24** (review round 2): the `verifier` run
  from a Workflow logged `agent_type` `"verifier"`, and its frontmatter `read-scope.sh` refused `README.md` and let
  `.ai/runs/…` through; the documentation promises frontmatter hooks only to agents spawned through the Agent tool,
  an @-mention or `--agent`, so the read scope is also session-level (`read-scope.sh --agent verifier`). Review
  round 3 narrowed it to the files the gate writes (`--name 'gate-r*.json' --name 'dependency-tree-r*.txt'`, no
  file with a second hard link): the rest of `.ai/runs/` holds the branch's test output; the other agents' guards
  are still frontmatter-only (#0-164).
- **The manual `/review` runs the gate too:** `run-tests.sh --working-tree` tests the uncommitted changes (the
  modules of the committed and the uncommitted files), records `dirty: true`, and is refused while an autopilot
  run holds the lock.
- **Allow-list, minimal:** `api.osv.dev/v1/`, `osv.dev/vulnerability/` (OSV aggregates GHSA, NVD and vendor
  advisories with fixed-version ranges), `github.com/advisories/`, `repo1.maven.org/maven2/`, and vendor pages
  by path prefix (`tomcat.apache.org/security-`, `spring.io/security/`). Every host beyond Maven Central and
  GitHub is also opened in the devcontainer firewall, for the whole container: that is why the list is short.
- **D's artifact** (`.ai/runs/<item>/gate-r<round>-<attempt>.json`; `.ai/runs/manual/gate-r1.json` for `/review`): the HEAD, per module the counts of surefire's
  `TEST-*.xml` and the line coverage of `jacoco.csv`, only from reports this run wrote (verify does not clean),
  and a `dependency:tree` file; a report the gate cannot read stops it, since missing numbers would read as
  "0 tests". The acceptance reviewer gets the path too.

**Acceptance criteria.**
AC1. Every reviewer of a round gets the test gate's artifacts for that exact HEAD.
AC2. No `unverified` item of the final round reaches a PR without a verdict (verified with a source, refuted, or
not verifiable), and the PR's review record lists them.
AC3. A refuted item blocks like a blocking finding; a not verifiable one stops the item as `NEEDS_HUMAN` unless the
owner accepts it.
AC4. The verifier fetches only from the allow-list (a fetch outside it is refused, shown by a test of the hook or
rule) and never receives the diff.
AC5. README "Infrastructure Hardening" (AI factory) and `docs/ai-factory.md` describe the stage and its network
access.

---

### 0-161. No review rule covers the AI factory itself

**Type:** design · **Priority:** Medium · **Status:** Done, PR #515 — `ruleGap` of review-security, review-architecture
and review-general in both rounds of the `/review` of #0-160 (2026-10-23/24); owner's decision: B′ below (2026-10-24).
Kept in full for the decisions (the trigger, the architect's exception, the `git show` pre-approval)
**Autopilot:** human-only · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** rules (.ai/rules/review/factory.md (new), security.md, architecture.md, _common.md,
.ai/rules/audit.md, .ai/rules/implementation.md, .ai/rules/protected-paths.md "Who uses it"), factory
(.claude/workflows/backlog-autopilot.js `RULE_FILE_OF`, .claude/agents/architect.md, review-security.md,
review-architecture.md, .claude/skills/review-procedure/SKILL.md, .claude/skills/review/SKILL.md), .ai/decisions/
(ADR-0038), .ai/context/security.md, docs (README.md "Infrastructure Hardening", docs/ai-factory.md, .ai/README.md)

**Problem.** `.ai/rules/review/security.md`, `architecture.md` and `general.md` are about the services' code
(tenant isolation, the security chain, decided patterns); nothing in them covers the factory: which agent has the
network, which hosts the firewall opens, that a hook refuses with exit 2 (any other exit code does not block),
that every agent declares its tools and scopes, that a control's list lives once and Factory guards checks its
copies. A finding needs a rule of its dimension by id to block (`_common.md`), so a real defect in a change to
`.claude/`, `.github/`, `scripts/factory/` or `.devcontainer/` (a hook that fails open) can only be
non-blocking, and reviewers report the gap as `ruleGap` every round.

**Decided (owner, 2026-10-24).** Not in `security.md`/`architecture.md`/`general.md` themselves (the implementer reads
them in full for every item, and no autopilot item can change the factory: protected paths), not in
`.ai/context/security.md` with ids (agents may edit `.ai/context/` — a rule that blocks must not live in a file the
judged change can rewrite, #0-153 — and the ids would map to no rule file), and not a new dimension `factory`
(an agent, a gate and an audit dimension for changes that reach only the owner's manual `/review`, too few for the
audit's ≥3 cases). **B′**: a rule file `.ai/rules/review/factory.md` with ids of the existing dimensions —
`FAC-S…` read by review-security, `FAC-A…` by review-architecture — read only when the diff touches the factory's
paths (one sentence in `security.md` and `architecture.md`; `_common.md` says the two prefixes belong to those
dimensions); `RULE_FILE_OF` in `backlog-autopilot.js` maps `FAC` to `factory`, so audits address the file. Plus a
section "AI factory" in `.ai/context/security.md`, without ids, as knowledge for the reader (why the verifier has
the network, where the allow-list is), like "CI workflows".

**Decided (owner, 2026-10-24, after the research).** The factory's paths are the **Owner-only list** of
`protected-paths.md`, not a list of `factory.md`'s own (a second copy would drift, #0-122; every reviewer reads
that file already). The architect reads every rule file but `factory.md` (`architect.md` said "all": without the
exception AC2 fails for it), and `_common.md`'s "nothing else from `.ai/rules/review/`" names the exception, as do
the two reviewers' definitions and `review-procedure`. `FAC-S01` is the rule of two (an agent reading untrusted
text never both reaches a secret and sends data out), the general case the other rules spell out; a section
"Enforced by checks" names what Factory guards and Lint Workflows already check, like `architecture.md` §4. CI
workflows stay out (`.github/workflows/` rules are #0-136's). The review of this change found that no audit reads
`RULE_FILE_OF` (only `ruleFilesOf`, for the architect's plan): its `FAC` entry is kept so that an `FAC-` id never
goes uncounted, not for the audits; `/review` decides whether `factory.md` applies (Step 2, from the list on
`main`) and tells the two reviewers, and ADR-0038 records the layout. Review round 2 (security, `FAC-S03`, blocking):
the first version pre-approved `Bash(git show *)`, which takes `--output=<file>` in a session with no Bash hook;
`/review` now pre-approves only `git show origin/main:.ai/rules/protected-paths.md`, an unreadable list means the
rules apply, and the report says whether they did; the older `git diff *` and the rules read from the branch are
#0-165.

**Acceptance criteria.**
AC1. A finding on a change to the factory's paths can cite a `FAC-S`/`FAC-A` rule by id and block.
AC2. A change that touches no factory path costs the reviewers, the implementer and the architect nothing new to
read.
AC3. The rules cover at least: network tools per agent and the allow-list's one source, firewall hosts (by IP),
tools and read/write scopes per agent, hooks that refuse with exit 2 on any failure, no secret readable by an agent
that can send, one list per control with its copies checked in CI, fail-closed agent answers, every new stage in
the PR record.
AC4. `review-security` and `review-architecture` are told to read `factory.md` exactly when the diff touches a path
of the Owner-only list (`_common.md`, their definitions, `review-procedure`), and no other agent is.

---

### 0-162. A hook that cannot load its helper lets the call through

**Type:** ci · **Priority:** Medium · **Status:** Done, PRs #516, #517 — found by review-security in round 2 of the
`/review` of #0-160 (2026-10-24); the two hooks #0-160 added are already fixed; owner's decision: C below, in two PRs
(2026-10-24). Kept in full for the decisions (both layers, the spikes, the version floor)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/hooks/*.sh, .claude/hooks/test-hooks.sh, .claude/settings.json,
.claude/settings.autopilot.json, .claude/agents/*.md (hook entries), scripts/factory/preflight.sh,
.github/scripts/test-preflight.sh, .github/scripts/ (a check of the hook entries), .github/workflows/factory-guards.yml),
.ai/decisions/ (an ADR), docs (README.md "Infrastructure Hardening", docs/ai-factory.md, .ai/rules/review/factory.md
`FAC-S04` if its wording changes, owner)

**Problem.** Every hook in `.claude/hooks/` starts with `. "$(dirname "$0")/_lib.sh"`. When that fails (the file
missing or unreadable), `block` is undefined and the hook ends with an exit code other than 2 — which Claude Code
treats as a non-blocking error: "The action goes ahead" (code.claude.com/docs/en/hooks.md, read 2026-10-24). The
guard then lets through what it exists to stop (a skipped test run, a protected-path write, a push). The same
for any other crash before `block` (an unset variable under `set -u`).
Shown by the research (2026-10-24), each hook copied without `_lib.sh`: `guard-tests.sh` passes `-DskipTests`,
`guard-git-push.sh` a force push to `main`, `guard-write-in-repo.sh` a Write of `.claude/settings.json`, and
`readonly-bash.sh` (13 agents' frontmatter) and `write-scope.sh` let everything through (exit 0);
`factory-ops-bash.sh` exits 1. Two more ways to the same end, found then:
- **`jq` fails** (installed, but exits non-zero — moved here from #0-132 by the owner): `json_get` returns 3 only
  when neither `jq` nor `python3` exists, so a parser that fails gives an empty value, which the Bash hooks answer
  with `[ -n "$cmd" ] || exit 0` (`guard-tests`, `guard-protected-bash`, `readonly-bash`: exit 0, with a `jq` stub
  that exits 5) and on which `factory-ops-bash.sh` crashes under `set -u` (exit 1). The write hooks refuse (an empty
  path is outside the repository). Already against `FAC-S04` ("the input does not parse").
- **The hook does not start** (the script missing, not executable, no `bash`) or times out: no change inside a
  script can catch that. Claude Code has a field for it, `"onFailure": "block"` on a `command` hook: a hook that
  cannot start, exits other than 0 or 2, times out or prints invalid JSON then blocks the call ("Requires Claude
  Code v2.1.295 or later", same page). The devcontainer installs whatever version is current when the image is
  built (`DISABLE_AUTOUPDATER`), and no check requires one; what an older version does with the field is not
  documented, nor whether a subagent's frontmatter hooks honour it.

**Decided (owner, 2026-10-24).** Option C of the research, both layers (a hook that fails exits 2 itself, and
Claude Code blocks a hook that fails), in two PRs:
- **PR 1, the scripts** (no dependency on the Claude Code version): each hook loads `_lib.sh` with
  `|| { echo "BLOCKED: …" >&2; exit 2; }` and sets, before it, a `trap … EXIT` that turns any exit status other
  than 0 or 2 into 2 (verified on bash 3.2 and 5: an unset variable, a missing command at the end, `exit 1`);
  `json_get` tells "no such field" (empty, 0) from "the parser failed" (non-zero), and the hooks refuse on the
  latter; a test per hook without `_lib.sh`, with an unset variable and with `jq` failing; Factory guards fails a
  hook in `.claude/hooks/` without a row in `test-hooks.sh`'s fail-closed table, whose cases (no `_lib.sh`, an
  abort while loading, `jq` failing) fail a hook without the guarded load or the trap — a behavioural check, not
  one of the text. From the review (round 1): `guard-migrations.sh` refuses when git fails on a migration's path,
  and lets the edit through with a warning only without `jq`/`python3` or without its base ref (`FAC-S04` names
  both); `json_get` refuses empty input (jq reads it as "no field"); the python3 fallback is tested too. Round 2:
  `guard-migrations.sh` asks `git ls-tree` (literal pathspec, exact name) instead of `cat-file -e`, which read
  any git failure as "not on the base".
- **PR 2, Claude Code's layer**: `"onFailure": "block"` on every hook entry of both settings and of every agent's
  frontmatter, checked by Factory guards (like `check-web-access.sh` reads the wiring); `preflight.sh` refuses a
  Claude Code older than 2.1.295; Factory guards also fails a hook command wired in either settings file or an
  agent's frontmatter that is not a `.claude/hooks/*.sh` with a row in the fail-closed table (security review of
  PR 1: today only the directory's files are enumerated); a spike first — does a frontmatter hook honour the field, and what does an older
  version do with it — recorded in an ADR, and a negative answer named as a weaker layer (README "Infrastructure
  Hardening", `FAC-A05`).

**PR 1 merged** (PR #516, 2026-10-24). **PR 2 (2026-10-25).** Spikes, each with an entry pointing at a missing
script: on 2.1.310 the field blocks in `claude -p --settings` (B) and in an Agent-tool agent's frontmatter (A); on
2.1.294 (C) it is ignored without a word while the rest of the file still applies. Owner's choices: the check in
Ruby, parsing the YAML and JSON (`.github/scripts/check-hook-entries.rb`, also refusing shell syntax in a hook's
arguments and `disableAllHooks`); the version is the running binary's (`$CLAUDE_CODE_EXECPATH`, else `claude` on
PATH, an unreadable one refuses); Workflow agents' frontmatter left untested, named in ADR-0039 with #0-164.

**Acceptance criteria.**
AC1. Every hook in `.claude/hooks/` exits 2 when it cannot load `_lib.sh`, shown by a test per hook.
AC2. A new hook without that pattern fails Factory guards.
AC3. Every hook exits 2 when it aborts after loading (an unset variable under `set -u`) and when `jq` fails on its
input, shown by a test per hook; `json_get`'s callers never read a parser failure as an empty value.
AC4. Every hook entry in `.claude/settings.json`, `.claude/settings.autopilot.json` and the agents' frontmatter has
`"onFailure": "block"`, and Factory guards fails one without it, or one whose command is not a hook of the
fail-closed table.
AC5. The autopilot does not start on a Claude Code older than 2.1.295 (`preflight.sh`, with a test).
AC6. The spike's result (frontmatter hooks, older versions) is in an ADR; a layer it shows not to hold is named in
README "Infrastructure Hardening".

---

### 0-163. The autopilot workflow's logic has no tests

**Type:** ci · **Priority:** Medium · **Status:** Done, PRs #522, #523 — from review-general, `/review` of #0-160
(2026-10-23/24); owner's decision below. Kept in full for the decisions (Node pinned like Ruby, how the test reads the script)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/workflows/backlog-autopilot.js, .claude/settings.autopilot.json, .claude/hooks/), ci
(.github/scripts/ (a new test, check-runtime-setup.rb, ci-local.sh), .github/workflows/, .github/actions/setup-node/,
.node-version), .ai/rules/protected-paths.md (owner), .ai/decisions/, docs (CLAUDE.md "Commands", README.md
"Infrastructure Hardening", .ai/context/infrastructure.md)

**Problem.** `backlog-autopilot.js` decides every branch of a run in code — `scopeOf`, `valid`, `openClaims`,
`claimId`, `verifyClaims` (the fail-closed downgrade of an unsourced answer), `refutedFindings`, `unsettledReason`,
the checks of `args` — and none of it is tested: the reviews of #0-160 checked it by reading, and the session by an
ad-hoc script outside the repository. A regression there passes Factory guards.

**Approach (to analyse).** The workflow is a script the runtime evaluates with `agent`, `parallel`, `phase`, `log`
and `args` in scope, not a module: either move the pure functions to a file the workflow and a `node` test both
load (if the runtime allows an import), or evaluate the script's helper section with stubs (what the ad-hoc check
of #0-160 did) — then the test breaks when the section's markers move, which is acceptable if it fails loudly.
Node is on the runner; mutation-check the cases.

**Decided (owner, 2026-10-25, after `/research`).** B + R1, in two PRs. Tests of the helper functions and scenario
tests of the whole run (the checks of `args`, the fail-closed stops), with a fake `agent()`: the workflow runtime
has no import, so a test evaluates the script's text with stubs. Node pinned like Ruby (ADR-0043, PR 1):
`.node-version`, `.github/actions/setup-node`, Node's built-in modules only (no npm); `check-ruby-setup.rb` becomes
`check-runtime-setup.rb` with Ruby and Node as rows of one table; `ci-local.sh` copies the same Node from the
official `node` image (not a tarball through `install-pinned-tool.sh`); `.node-version` on the build-config list.
PR 2: the tests, a Factory guards step, a one-off mutation run recorded in the PR.

**Acceptance criteria.**
AC1. Factory guards runs tests of the workflow's pure functions, among them the verification functions' fail-closed
paths and `acceptUnverifiable`'s id matching.
AC2. Inverting a decision in any of them turns a test red.

### 0-164. The agents' guards rely on frontmatter hooks that Workflow agents are not promised

**Type:** security · **Priority:** Medium · **Status:** Done, PR #520 — `nonBlocking` ARC-02 of review-architecture in
round 3 of the `/review` of #0-160 (2026-10-24); the verifier's read scope is already session-level; owner's decision
below (2026-10-25). Kept in full for the decisions (both layers, the spikes, the required guards)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/hooks/readonly-bash.sh, .claude/hooks/write-scope.sh, .claude/hooks/test-hooks.sh,
.claude/settings.json, .claude/settings.autopilot.json), ci (.github/scripts/ (a structural check),
.github/workflows/factory-guards.yml), docs (README.md "Infrastructure Hardening", docs/ai-factory.md)

**Problem.** Every read-only or write-scoped agent is guarded by a hook in its own frontmatter: `readonly-bash.sh`
for the seven reviewers, acceptance-reviewer, ready-checker, planner, the architect and the audit analysts;
`write-scope.sh` for the architect (`.ai/decisions/ .ai/work/`), the planner (`.ai/plan/ BACKLOG.md`) and
audit-synthesis (`.ai/audit/`). Claude Code documents frontmatter hooks only for an agent spawned through the
Agent tool, an @-mention or `--agent`, in a trusted workspace, never in `claude -p` (`sub-agents.md`, read
2026-10-24); the autopilot spawns them through the `Workflow` runtime. They ran there in the spike of 2026-10-24
(ADR-0037), but nothing promises it, and a release that stops running them would leave a reviewer with the
session's Bash and every agent's writes scoped only by the session-wide guards. README "Known gaps" names only
the `-p` case.

**Approach.** What #0-160 did for the verifier (ADR-0037): the same hooks once more at session level, keyed on
`agent_type` (`--agent <name>`, passing every other agent), in both settings files, next to the frontmatter ones;
a structural check that every agent with a frontmatter guard has its session-level twin with the same arguments.
`readonly-bash.sh` is called per agent with different options (`--architect`, `--k8s`, `--gh-read`), so one
session hook per option, or `--agent` taking a list.

**Also (security review, round 2 of #0-162 PR 2, 2026-10-25).** `check-hook-entries.rb` (ADR-0039) checks every
hook entry that exists, not that one exists: a change that deletes `guard-tests.sh`, `guard-protected-bash.sh`,
`guard-git-push.sh`, `guard-factory-scripts.sh`, `guard-write-in-repo.sh` or `guard-migrations.sh` from
`settings.autopilot.json`, or `guard-migrations.sh` from `settings.json`, passes Factory guards (only the
verifier's hooks are checked to be wired, by `check-web-access.sh`). The structural check of this item is the
place for it: one list of which guard each settings file must run, on which matcher (not a second list per
check, `FAC-A01`).

**Decided (owner, 2026-10-25, after `/research` and spikes; ADR-0041).** A1 + B1 + C1: the twins by hand, one per
guard and arguments, `--agent` taking a comma-separated list (`applies_to_agent` in `_lib.sh`, used by
`readonly-bash.sh`, `write-scope.sh`, `factory-ops-bash.sh` and `read-scope.sh`), in both settings files;
`check-hook-entries.rb` checks them against the frontmatter (the one list) and holds the table of required
session-wide guards (AC4). Spikes on 2.1.310: `claude --settings <file>` adds to the project's `.claude/settings.json`
(both files' hooks ran; the owner kept the twins in both files, and an identical command in both runs once, review
round 1); `agent_type` reaches a
session hook for an Agent-tool agent (`--agents`) and for a Workflow agent (`agentType: 'review-docs'` gave
`review-docs`, none gave `workflow-subagent`). factory-ops' `factory-ops-bash.sh` gets a twin too (frontmatter-only
as well; AC2 names every frontmatter guard).

**Acceptance criteria.**
AC1. For every agent whose frontmatter runs `readonly-bash.sh` or `write-scope.sh`, both settings files run the same
hook with the same arguments for that `agent_type`, shown by test cases (the agent refused, another agent passed).
AC2. Factory guards fails when an agent's frontmatter guard has no session-level twin, or a different one.
AC3. README "Infrastructure Hardening" names the session-level guards and no longer lists this gap.
AC4. Factory guards fails when a session-level guard of `settings.autopilot.json` or `settings.json` is removed or
moved to another matcher, shown by a test case per guard.

### 0-165. The owner's `/review` session trusts the branch it reviews

**Type:** security · **Priority:** Medium · **Status:** Done, PR #521 — from review-security, `/review` of #0-161
(2026-10-24); owner's decision below. Kept in full for the decisions (hook moved to #0-167, the session rule)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/skills/review/SKILL.md, .claude/settings.json, .claude/hooks/ (a session-level Bash
guard), .claude/hooks/test-hooks.sh, .claude/agents/review-*.md, .claude/skills/review-procedure/SKILL.md), docs
(README.md "Infrastructure Hardening", docs/ai-factory.md)

**Problem.** `/review` is meant for a branch the owner did not write too (its Step 3 names "a bot's branch
checked out"), but the session trusts it in two ways:
1. `allowed-tools: Bash(git diff *)` pre-approves every `git diff`, including `--output=<file>` (writes the diff
   anywhere: verified for `git show` with git 2.54, 2026-10-24), `--ext-diff` and `--textconv` (run a program the
   repository's config names). The session has no Bash hook (`readonly-bash.sh` guards the reviewers,
   `guard-protected-bash.sh` autopilot sessions), so text from the change under review that steers it into
   `git diff --output=~/.zshenv …` writes a file the owner's shell runs, without a prompt.
2. The reviewers read the rules they judge by — `_common.md`, their dimension's file, `factory.md` — from the
   working tree, so the branch under review can rewrite them. Only `factory.md`'s trigger list is read from
   `origin/main` (#0-161).

**Approach (to analyse).** For 1: a session-level PreToolUse hook on Bash for the owner's sessions that refuses
`--output`, `--ext-diff`, `--textconv` and `-c` on `git diff`/`git show`/`git log` (the parser of
`readonly-bash.sh` already splits the words; reuse it), or exact `allowed-tools` entries only. For 2: the
reviewers read `.ai/rules/review/` from `origin/main` (`git show`, which their `readonly-bash.sh` allows) when the
diff touches `.ai/rules/`, or `/review` refuses to run on a branch that changes `.ai/rules/` unless the owner says
it is theirs. Check whether Claude Code documents `allowed-tools` matching for options.

**Decided (owner, 2026-10-25, after `/research`; ADR-0042).** 1C + 2A + a written session rule: `/review` and
`/accept` pre-approve exact commands, `/review` fetches `origin/main` first; reviewers read `.ai/rules/review/` with
`git show refs/remotes/origin/main:…` (round 2: the short name loses to a local branch called `origin/main`). Two changes after round 1 of the review: the hook of 1C (a session-level Bash guard
refusing git's `--output`, `--ext-diff`, `--textconv`) moved to #0-167, since its first version could be passed and
a parser that reads a command as bash does is an item of its own; and the session rule is "read a foreign branch's
`.claude/`, `CLAUDE.md` and `.ai/context/` changes before `/review`", not "start the session on `main`": Claude Code's docs say it picks up changed
skills and agents during a session. AC1 is met by the exact commands (none carries an option); its test cases go
with the hook to #0-167. Not done: a Read hook enforcing the rules from main (README names it).

**Acceptance criteria.**
AC1. In the owner's `/review` and `/accept`, no pre-approved command can write a file outside the scratchpad or run
a program the branch names: every `allowed-tools` entry is an exact command without an option (reworded in round 2
of the review, 2026-10-25: the test cases for `--output`, `--ext-diff`, `--textconv`, `-c` went with the hook to
#0-167).
AC2. A branch under `/review` that changes a rule file is judged by the rules on `origin/main`.

---

### 0-166. Checking CI's Linux steps locally takes seven minutes

**Type:** ci · **Priority:** Low · **Status:** Done, PRs #518, #519 — measured during #0-162 PR 2 (2026-10-25); owner's decision below. Kept in full for the decisions (Ruby pinned in CI, the local runner's design)
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** ci (.github/scripts/ (a script that runs CI's lint and factory steps in Docker), .github/workflows/,
.github/actions/setup-ruby/, .ruby-version), factory (.claude/settings.autopilot.json, .claude/hooks/guard-protected-bash.sh,
.claude/hooks/test-hooks.sh), .ai/rules/protected-paths.md (owner), .ai/decisions/, docs (CLAUDE.md "Commands",
README.md "Infrastructure Hardening", .ai/context/infrastructure.md)

**Problem.** CI's Lint Workflows and Factory guards steps are Linux-only in practice (the pinned actionlint,
shellcheck and zizmor are x86_64 Linux binaries; macOS has no gpg, an older Ruby and BSD tools), so before a push
they are run by hand in a throwaway `ubuntu:24.04` container (memory note "Linux CI checks in Docker"; the script
lives only in a session's scratchpad and is rewritten every session). On the owner's Apple Silicon Mac one full run
took 428 s, measured per step on 2026-10-25:
- the whole container runs as `--platform linux/amd64`, emulated, because the linters exist only for x86_64;
- `test-hooks.sh` (128 s) and `test-web-access.sh` (122 s) start thousands of small processes (hook, jq, grep,
  sed per case), which is what emulation makes slow; `test-preflight.sh` 32 s, `test-factory-guards.sh` 33 s,
  shellcheck with its tests 32 s;
- every run starts from a clean image: `apt-get` 48 s and the tools' download 6 s, each time.

On GitHub's runners (native x86) the same steps take well under a minute, so this costs only the local loop, but
it costs it on every review round of a factory change.

**Approach.** One script in the repository (not a scratchpad copy) that:
1. builds once, and reuses, a local image with the apt packages and the pinned tools, installed with
   `install-pinned-tool.sh` at the versions and SHA-256 of `ci.yml`'s `env` (the image is rebuilt when those pins
   change, e.g. tagged with a hash of them);
2. runs the linters (actionlint, shellcheck through `check-shell.rb`, `check-downloads.rb`, zizmor) in the amd64
   image, and every `test-*.sh`/`check-*` of Factory guards in a native arm64 container (bash, jq, ruby and git
   exist for both);
3. takes a list of steps, so a review round runs only the affected ones, and runs all of them by default;
4. mounts the working tree read-only and copies it, as today (uncommitted files included).

**Also (PR #517, 2026-10-25).** The container must reproduce the runner's gems, not only its Ruby version: Ruby
3.2.3 in `ubuntu:24.04` has the json gem 2.6.3, the runner a newer one, and a check that relied on how `JSON.parse`
fills an `object_class` passed locally and failed on the runner (it fails from json 2.12, reproduced). The runner's
Ruby is not pinned at all: the nine `.github/scripts/*.rb` run on whatever Ruby and gems `ubuntu-latest` brings,
while every other CI tool is pinned (ADR-0033). **To decide:** pin Ruby in CI (e.g. `ruby/setup-ruby` with a
version, itself pinned by SHA) for every job that runs a `.rb`, and build the local image from the same version;
or keep the runner's Ruby and only have the local image read the runner's versions (`ruby --version`, `gem list`
in a CI step).

**Decided (owner, 2026-10-25, after `/research`).** S1 + S4 + R2, in two PRs:
- **PR 1, Ruby pinned in CI (R2, ADR-0040):** `.ruby-version` 4.0.9 (the owner chose the 4.0 branch over 3.4), set
  up by one local action, `.github/actions/setup-ruby` (`ruby/setup-ruby` pinned by SHA, then the versions of Ruby,
  json and psych), in the five jobs that run Ruby. From the review (round 1, owner: all proposals): lint-workflows'
  `check-ruby-setup.rb` refuses a step that runs Ruby before that action in its job, and any other `ruby/setup-ruby`;
  `.ruby-version` joins the build-config list (owner); ADR and README say the binary's integrity rests on the action.
  Whether the checks stay portable to Ruby 2.6 (CI no longer tests it) is decided in PR 2. Round 2: #0-135 and #0-153
  got an "Also"; the required "Changes that need the owner" step of Factory guards stays last (moving it first would
  skip the job's tests whenever it fails, and protects nothing the PR's own scripts could not reach before it).
  Left for later: a per-job step iterator in `run-blocks.rb`, so that `check-ruby-setup.rb` stops walking the
  workflows itself beside `RunBlocks.of` (architecture, round 2, ARC-02); PR 2 does not need it (it reads the jobs
  with `safe_load`).
- **PR 2, the script (S1 + S4):** two images built once and reused (`FROM ruby:<.ruby-version>-slim`), the linters in
  amd64 (exactly CI's binaries, through `install-pinned-tool.sh` and `ci.yml`'s pins), the tests native (arm64 on the
  owner's Mac), both at once; a list of steps, all by default. Measured before deciding (2026-10-25): natively on
  arm64 `test-hooks.sh` takes 8 s (128 s emulated), `test-web-access.sh` 4 s (122 s), `apt-get` 10 s (48 s).
- **PR 2, decided after its analysis (owner, 2026-10-25): A2 + B1 + C2 + D2.** A2: no list of steps of its own:
  `ci-local-steps.rb` runs the `run:` steps of the lint-workflows and factory-guards jobs from the workflows, skipping
  (and naming) `uses:`, `if:` and `${{ }}` steps; B1: the image is `ruby:<.ruby-version>-slim` with packages only,
  the linters come from the job's own install step (AC3 reworded); C2: every step runs after a failure, one line per
  step; D2: no more promise for Ruby 2.6 (ADR-0040 amended). No `--with-gh`: the two token steps need `gh`, which the
  image does not have; they stay on the host.
  Review round 1 (owner: proposals 1-8): the tree reaches the container as a tar on stdin, not a mount (security: a
  mounted tree let every step, with network, read the ignored `docker/.env` and `application-local.yml`), a file
  that cannot be read fails the run, a git worktree is refused; the runner prints Ruby's, json's and psych's
  versions (AC5) and removes its RUNNER_TEMP; `test-repository-settings.sh` is a step of its own in `ci.yml`, so it
  runs locally; the base image stays a tag (ADR-0040 says why). Measured then: run as linux/amd64 whole,
  lint-workflows took minutes (the newly local `test-repository-settings.sh`, bash and Ruby emulated); both jobs now
  run native and only the three x86_64 linters are emulated (Docker Desktop's Rosetta runs them in an arm64
  container; zizmor's glibc build needs `libc6:amd64` in the image): a full run 52 s with the image cached (AC2:
  428 s before, at most 143 s).
  Review round 2 (owner: proposals 1-6): the run is refused while `.git` could carry more than the tree (a stash, or
  credentials in the repository's git config) and inside a container (the devcontainer's Docker is the host's, its
  network outside the firewall); factory-guards runs with `--network none`; each image is built once before the
  jobs start; YAML anchors are read (`aliases: true`).

**Acceptance criteria.**
AC1. One command runs every step of Lint Workflows and Factory guards that needs no secret, with the tools pinned in
`ci.yml`, and prints one line per step with its exit code and time.
AC2. A second full run on the owner's Mac takes at most a third of the 428 s measured on 2026-10-25 (the
measurement is in the PR).
AC3. The image is rebuilt only when `.ruby-version` or its own definition changes; the tools always come from
`ci.yml`'s pins, through the job's own install step (reworded by the owner, 2026-10-25: the pins never enter the image).
AC4. CLAUDE.md "Commands" names the command.
AC5. Whether CI pins Ruby is decided (an ADR if it does), and the local image runs the same Ruby and json/psych gems
as the CI job that runs the `.rb` checks, shown by both printing their versions.

---

### 0-168. A copy of the protected paths can run ahead of the one list

**Type:** ci · **Priority:** Medium · **Status:** Done, PR #524 — from review-security and review-architecture, `/review` of
#0-163 PR 1 (2026-10-25); owner's decision below. Kept in full for the decisions (the runtime list, the flat hook line)
**Autopilot:** human-only · **Risk:** medium · **Complexity:** medium · **Depends on:** —
**Touches:** ci (.github/scripts/check-protected-paths.sh, .github/scripts/test-protected-paths.sh), factory
(.claude/settings.autopilot.json, .claude/hooks/guard-protected-bash.sh), .ai/rules/protected-paths.md (owner),
.ai/rules/review/factory.md (owner, if a rule is added)

**Problem.** `.ai/rules/protected-paths.md` is the one list of protected and build-config paths (#0-122); its copies
that cannot read it, the autopilot's Edit/Write denies and `guard-protected-bash.sh`'s regex, are checked by
`check-protected-paths.sh` in one direction only: every entry of the list must be in every copy. A copy that holds an
entry the list lacks passes. In #0-163 PR 1 `.node-version` was added to both copies, and five documents said it was
on the build-config list, before the list had it: `check-factory-guards.sh` rule 6 (which reads the list from the merge
base) would have let a PR changing it through without the owner, and `changed-paths.sh`, `next-item.sh` and
`check-queue.sh` would not have treated it as protected. Three reviewers found it by reading; no check would have.

**Approach (to analyse).** The other direction for the denies: each `Edit(./…)`/`Write(./…)` deny is an entry of the
list or of a named set of other denies (`.git/**`, `.ai/runs/LOCK`, `.ai/runs/state.json`, `.ai/STOP`, which are not
paths of the list on purpose). For the hook: its regex is tested by running it, not parsed (#0-122), so the other
direction there needs either the regex built from the list at a known place or a list of the hook's alternatives
kept next to it and compared. Decide whether a `FAC-S`/`FAC-A` rule should say so for review.

**Decided (owner, 2026-10-25, after `/research`).** R1 + B + the other way for the denies, no new `FAC-` rule (one
sentence at FAC-A01). The four paths outside the lists (`.git/`, `.ai/runs/LOCK`, `.ai/runs/state.json`,
`.ai/STOP`) become a third list of `protected-paths.md`, "Runtime state" (`runtime:start/end`), which only the copy
check reads; before it they were in both copies and checked by nothing. `check-protected-paths.sh` also checks
copy → list: every `Edit(./…)`/`Write(./…)` deny is an entry as written (a directory with its slash), and every
alternative of the hook's `protected=` line, now one flat alternation (the `.ai/runs/(LOCK|state\.json)` group
split), is an entry with or without its slash. Not taken: the hook building its regex from the list (#0-122 keeps
the last line from parsing Markdown), and generating the hook's line (it would change the hook's patterns).

**Acceptance criteria.**
AC1. Factory guards fails when `settings.autopilot.json` denies writing a path that is neither on the list nor in the
named set of other denies, shown by a test case.
AC2. Factory guards fails when `guard-protected-bash.sh` protects a path the list does not hold, or the decision why it
cannot is recorded, with the case shown either way.

---

### 0-169. A factory-ops call is not bound to the command the workflow named

**Type:** security · **Priority:** Medium · **Status:** Done, PR #617 (2026-11-13). Kept in full for the decision, the
spike and the live check (ADR-0053). From the `nonBlocking` of review-security in round 2 of the `/review` of #0-131
(2026-10-25)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** #0-131
**Touches:** factory (.claude/agents/factory-ops.md, .claude/hooks/factory-ops-bash.sh, .claude/hooks/test-hooks.sh),
docs (README.md "Infrastructure Hardening", .ai/decisions/0053)

**Problem.** Since #0-131 only the `factory-ops` agent runs `scripts/factory/` in an autopilot session, and the
lock (the run's base commit and its branch, the one the autopilot may push) moves only through those scripts. The
workflow tells `factory-ops` "Run exactly: <command>", but nothing binds what it runs to that line:
`factory-ops-bash.sh` lets it run any factory script with plain arguments, and its `maxTurns: 4` leaves room for
several. Part of what it relays is text the branch controls (`changed-paths.sh` lists file names), so a steered
`factory-ops` could run `state.sh unlock`, `preflight.sh` and `state.sh branch <another>` in one task.

**Approach (to analyse).** Bind each call to its task: a per-call value the workflow puts in the command and the
hook checks (it cannot see the prompt), or one command per task (`maxTurns` after a spike of what one turn allows),
or `state.sh` refusing a second `preflight`/`branch` in one run by a record the hook keeps.

**Decided (owner, 2026-11-12, after `/research 0-169`; spike 2026-11-13; ADR-0053).** The hook allows one call per
factory-ops run, keyed on `agent_id`: the first call that passes its other rules; every later one is refused, whatever
its command. That first call comes before the agent has read any script's output, from the prompt the workflow's code
builds, so it is the task's; nothing the branch printed can add a second. A refused call does not use it up; the mark
is `ln -s <tool_use_id> .ai/runs/ops-calls/<agent_id>`, so the hook's two copies of one call (frontmatter and session
twin, possibly at once) both pass; no `agent_id` or `tool_use_id` refuses. Rejected: comparing with the prompt read
from the transcript (`transcript_path` is the main session's, spike fact 3), a one-time token (no store the agent
cannot read), a lower `maxTurns` (it counts messages, not calls), hardening `state.sh` (one script at a time).
**Spike, 2026-11-13** (run `wf_913b1a7d-375` + one Agent-tool factory-ops, a session-level hook logging the input):
`agent_id` new for every `agent()` call and Agent-tool spawn, the same for every call of one run (two in a row, two in
one message, a retry after a refusal); `agent_type` as #0-160's spike found; factory-ops sent an absolute path first
(refused by the twin), then the relative one, and the Agent-tool one retried twice after its command had run. **Live
check** (the change in the working tree, an Agent-tool factory-ops): its first command passed both copies of the hook
and left the mark; a second command sent to the same agent was refused.

**Acceptance criteria.** AC1 reworded with the decision (it said "a call other than the one its task named"; no hook
input carries the task, and the first call is the task's).
AC1. Every `factory-ops` call after the first allowed one of its run (`agent_id`) is refused, a refused call does not
use the run's one call, and two copies of one call (`tool_use_id`) pass, shown by test cases (`test-hooks.sh`,
"factory-ops: one call per run", parallel copies included).
AC2. README "Infrastructure Hardening" names the control.

---

### 0-170. `/seed-bugs` measured nothing: the seeder's commands were refused and reported as a skip

**Type:** ci · **Priority:** Medium · **Status:** Done, PR #528 (AC3 is shown by the rerun of #0-115's "after" measure) —
found by the first `/seed-bugs` run on record (P-10 on `253e5b2a3a06`, run `perf-after-p10`, 2026-10-25)
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/agents/defect-seeder.md, .claude/workflows/seed-bugs.js), ci
(.github/scripts/test-autopilot-workflow.mjs)

**Problem.** The run came back SKIPPED with no reason. The seeder had tried `grep … && git show …` (refused by the
shell guard: a separator), then `git -C /workspace show --stat <commit>` and the `git switch -c seed/…` it needs
(refused in `dontAsk`: `git -C …` matches none of the session's allow rules), and answered `{"skipped": true}`: its
definition offers only "skipped" for "this pattern does not fit", and the workflow's schema had no `reason`, so a
blocked tool read as a result. `.ai/audit/benchmark/results.md` does not exist: no run had ever been recorded.

**Fix.** `defect-seeder.md` says how commands run in an autopilot session (from the root, one per call, no `git -C`,
no separators; Read and `git grep` to look) and answers `{"blocked": true, "reason"}` when a command is refused.
`seed-bugs.js` asks for `reason` and `blocked`: blocked is FAILED with the reason, a skip without a reason is FAILED,
and so is a ground truth the Record phase cannot use (no `seed/` branch, no file, a dimension outside the panel).
`test-autopilot-workflow.mjs` runs `seed-bugs.js` against a fake agent for each of them, and a measured run.
Review round 1 added: the answer must name this run's branch (`seed/<pattern>-<runId>`), the line and the rule (a
missing line made every catch read as a miss) and start from the commit given; the reason is cut to 300 characters.
Not here: a record of the runs that measured nothing (#0-171) and a write scope for the seeder (#0-172).

**Acceptance criteria.**
AC1. A refused command of the seeder ends the run FAILED with the refusal, never SKIPPED, shown by a test.
AC2. A skip without a reason, and an unusable ground truth, end it FAILED, shown by tests.
AC3. `/seed-bugs` P-10 on `253e5b2a3a06` in an autopilot session plants the pattern and records a row (the run of
#0-115's pilot, once this is merged).

---

### 0-172. The defect-seeder writes and commits with no write scope

**Type:** security · **Priority:** Low · **Status:** Done, PR #552 (kept for the decision history: the Also sections and
the owner's choice of option C, 2026-10-30) — `nonBlocking` FAC-S03 of review-security in the `/review` of #0-170
(2026-10-25)
**Autopilot:** human-only · **Risk:** medium · **Complexity:** medium (was low: the seeder no longer commits, so the seed
scripts and the workflow change too) · **Depends on:** —
**Touches:** factory (.claude/agents/defect-seeder.md, .claude/settings.json, .claude/settings.autopilot.json,
.claude/hooks/_lib.sh, write-scope.sh, test-hooks.sh, .claude/workflows/seed-bugs.js, scripts/factory/seed-branch.sh,
seed-check.sh, seed-fold.sh, return-to-main.sh), ci (.github/scripts/test-seed-branch.sh, test-autopilot-workflow.mjs,
test-hook-entries.sh),
docs (ADR-0047, ADR-0044 status, docs/ai-factory.md, README "Infrastructure Hardening")

**Problem.** `defect-seeder` has Bash and Edit and commits onto a `seed/` branch, but neither its frontmatter nor a
session-level twin keyed on its `agent_type` runs `write-scope.sh` (ADR-0041): what it may write is bounded only by the
autopilot's denies of the protected paths. It plants a defect in code the merged change touched, so its scope is that
change's files.

**Approach (to analyse).** A `write-scope.sh` for it, in its frontmatter and as a twin in both settings files
(`check-hook-entries.rb` keeps them equal), with a scope the workflow can name per run (the merged change's paths) or a
fixed one (the services' `src/main/`).

**Also (review round 2 of #0-173, security FAC-S03).** The seeder's ban on `git switch`, `git checkout` and a new
branch is only a prompt. Since #0-173, `scripts/factory/seed-check.sh` detects it, but only after the fact: between a
switch and the check, the seeder's calls run on another tree's hooks. A guard keyed on its `agent_type` would refuse
those commands before they run. It belongs with this item's guard (the same places, the same entry check).

**Also (review round 1 of #0-177, security FAC-S05).** Since #0-177 a run's row goes to the gitignored
`.ai/runs/benchmark/results.md`, which `seed-check.sh` (`git status`) cannot see: the seeder could write rows there, or
the run's own id, which makes `seed-record.sh` refuse the real row. The scope must leave `.ai/runs/` out; until then
the owner reads a series' rows before landing them (`docs/ai-factory.md`, ADR-0044 decision 6).

**Also (#0-115's `migration.md` series, 2026-10-26).** `guard-migrations.sh` and the seeder do not fit. The hook
refuses an edit to any migration that is on `origin/main`, but a seed branch is built from a merged change, so every
migration the seeder may touch is on `main`. For the seed branch, a migration the change added is new, because its
base is `main` with the change reverted. P-19 (`mig-after-p19` on `aace4118`) failed: the seeder's Edit of V31 was
refused. P-13 (`mig-after-p13` on `40bf2ef6`) measured only because the seeder appended to V8 with Bash
(`printf … >>`), which the hook does not watch (it matches Edit, Write, MultiEdit). Two problems:
- the measure of the migration patterns (P-13, P-19) depends on which tool the seeder picks. The hook could take the
  seed branch's base, which it already reads from `$FACTORY_BASE_REF` or `.ai/runs/LOCK`, for the seeder's session,
  instead of `origin/main`;
- a Bash redirect writes to an applied migration unseen by the hook. For the seeder that is this item's missing write
  scope. Whether `guard-write-in-repo.sh` covers the autopilot's agents for it was not checked.
Until this is fixed, the migration patterns are not run (owner, 2026-10-26).

**Acceptance criteria.**
AC1. The defect-seeder cannot write outside its scope, shown by a test case.
AC2. Factory guards fails when its guard is missing from one of its places.
AC3. The defect-seeder cannot switch or create a branch, shown by a test case.
AC4. A migration pattern can be planted with the seeder's normal Edit, and the seeder cannot write to a migration with
Bash. Shown by test cases of `guard-migrations.sh` (and of the seeder's write guard).

**Decided (owner, 2026-10-30: option C of the `/research`).** The seeder commits nothing, and its hooks read the run
(ADR-0047). It is the change's real scope, not a fixed one (option A), because the migration guard needs the run's base
anyway, and a fixed scope would still have left P-19 refused. The commit moves to a factory script instead of a
`--seeder` Bash mode that allows `git add`/`git commit` (option B): `seed-fold.sh` threw away the seeder's commit
message anyway. Running seeds only in an autopilot session (D) was rejected: that session allows `git switch`.
- `seed-branch.sh` writes `.ai/runs/SEED` (`<branch> <base> <head>`), and `return-to-main.sh` removes it on `main`.
  `seed_record` (`_lib.sh`) reads it only on the branch it names.
- The seeder's Bash runs the plain `readonly-bash.sh` (frontmatter plus a twin on the reviewers' `--agent` list), so
  `git switch`, `checkout`, `branch`, `commit`, `add` and redirects are refused (AC3, the Bash half of AC4).
- Its Edit runs `write-scope.sh --seed` (frontmatter plus a `--agent defect-seeder --seed` twin in both settings files).
  The hook allows exactly the change's files, `git diff --name-only --no-renames --diff-filter=d <base> <head>`, the
  list `seed-check.sh` checks afterwards. `.ai/runs/` and the hooks are never in it (AC1).
- `migration_base_ref` answers the record's base when no LOCK exists, so `guard-migrations.sh` lets the seeder edit a
  migration the change added (the Edit half of AC4). Since LOCK comes first, `.ai/runs/SEED` needs no protected-paths
  entry. The shared `base_ref` is unchanged, so the factory scripts' integrity check still compares with main.
- Review round 1 (owner: "tak" on 1-4): the seed base was confined to the migration guard (architecture: through
  `base_ref` it had also reached `factory_scripts_intact`); `seed_record` refuses a record naming commits the repository
  does not hold (security: such a base sent `guard-migrations.sh` to its "base not found" exception); `seed-branch.sh`
  notes that the fold expects its two commits (general); a long line of `docs/ai-factory.md` rewrapped (docs).
- Review round 2: no blocking finding (general, security and docs APPROVE; architecture NEEDS_HUMAN, protected paths
  only). Owner: "wprowadź". README "Infrastructure Hardening" names the guard's exception on a seed branch (architecture,
  FAC-A05). Not done: a `--seed` row in the fail-closed table of `test-hooks.sh` (security). Its shared failure paths
  come before the mode split and are covered by the existing row, and its own paths have their cases.
- `seed-check.sh` refuses a seeder commit and an untracked file, and checks the uncommitted edit. `seed-fold.sh`
  commits the working tree through an index of its own, and refuses a HEAD reflog with any entry above the switch
  besides seed-branch.sh's two commits.
- AC2: `check-hook-entries.rb` rule 4 fails when one layer of either guard is missing. It cannot see an agent with no
  guard in either layer, this item's own case: that gap is #0-186.

---

### 0-173. `/seed-bugs` switches the shared working tree to an old commit

**Type:** security · **Priority:** High · **Status:** Done, PR #529 (AC3 is shown by the owner's rerun of #0-115's "after" measure on `76379e806fb4`) — found by the rerun of
#0-115's pilot measure, after #0-170
(P-10 on `253e5b2a3a06`, run `perf-after-p10`, 2026-10-25)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** #0-170
**Touches:** factory (.claude/agents/defect-seeder.md, .claude/workflows/seed-bugs.js, scripts/factory/seed-branch.sh,
scripts/factory/seed-check.sh), ci (.github/scripts/test-autopilot-workflow.mjs, .github/scripts/test-seed-branch.sh,
.github/workflows/factory-guards.yml), docs (docs/ai-factory.md, ADR-0044), .ai/audit/benchmark/patterns.md (owner, if
the choice of commit changes)

**Problem.** The seeder builds its branch on the merged change itself (`git switch -c seed/<pattern>-<run id>
<commit>`), in the working tree the session runs in. That tree is the one the devcontainer mounts and the owner's own
sessions use. Claude Code reads hook scripts from disk on every call and reloads agents, skills and `CLAUDE.md` when they
change (ADR-0042), so from the switch on the session ran on the definitions of that old commit: the run of 2026-10-25
switched to `253e5b2a` (about two weeks old) and got that commit's `guard-protected-bash.sh`, which refused the seeder's
reads, settings that named a `read-scope.sh` the old tree did not have (so every file read failed), and an older
`CLAUDE.md`; the owner's session on the host lost its `verifier` agent until the tree was switched back. A run that had
gone through would have had the panel review under the old agents and, worse, older and weaker guards. Nothing was
committed or pushed; the tree was clean and was switched back to `main` by hand.

**Approach (to analyse).**
- **F1.** Branch from the current base (`main`) and plant the defect in a file the merged change touched, as that file is
  now; the panel reviews the defect alone against `main`. Simple; the tree stays current; the measure is easier than
  intended (a small diff, not a defect hidden in a real change).
- **F2.** Branch from `main`, commit the merged change reverted (the base), then commit it back with the defect (the
  change under review, `mergeBase` = the revert commit): the panel sees the real change with the defect inside it, as
  the benchmark meant, while the tree keeps `main`'s hooks, agents and rules. A change that touched `.claude/` or the
  rules themselves is not a valid target.
- Either way: the run refuses to start unless the tree is on a clean `main`, and returns to `main` at its end, also when
  it fails.

**Decided (owner, 2026-10-25, after `/research`).** F2, through a factory script: `scripts/factory/seed-branch.sh` (run
by `factory-ops`) checks a clean `main` at `origin/main` and no `.ai/runs/LOCK` (no lock of its own: `preflight.sh`
also wants Docker and a green CI, which a measure does not need), refuses a change that touches a protected path or
`CLAUDE.md`, and builds `seed/<pattern>-<run id>` from `main`: the change's code reverted (the base the panel diffs
against), then back under the change's subject; Markdown is not replayed. The seeder only plants and commits on it,
in one of the change's files; the workflow ends on `main` in every outcome (`return-to-main.sh`). Tried on a copy of
the repository: `253e5b2a` no longer applies (refused, back on a clean `main`); `76379e80` (PR #472) does.

**Review round 1 (owner accepted every proposal, 2026-10-25).** Architecture found two blocking gaps (FAC-A02):
- the panel ran on the seeder's word for its branch. Now `scripts/factory/seed-check.sh` confirms the tree before the
  panel runs: on the seed branch, clean, one commit on top of the change, touching only the change's files;
- `finish()` ignored `return-to-main.sh`'s answer, and the Record phase wrote `results.md` while the seed branch was
  still checked out, so every measured run stayed on `seed/…` and the next run was refused. Now the run goes back to
  `main` before Record and an outcome that could not says where it left the tree (`leftOn`). The owner commits
  `results.md` between runs, and `seed-branch.sh` names that file when it refuses.

Also done in that round:
- `$files` became an array, read with `--literal-pathspecs`;
- `--no-renames` in both diffs, and the plantable files leave out the deleted ones;
- tests for a merge commit, a Markdown-only change and a rename or deletion;
- the workflow checks `seed.branch` against `seed/<pattern>-<run id>` and the two shas;
- ADR-0044 records the decision.

**Review round 2 (owner accepted the proposals, 2026-10-25).** Every reviewer approved. The non-blocking notes the
owner took:
- `seed-branch.sh` reads the two protected lists one at a time, each with its own refusal;
- `seed-check.sh` leaves the change's deleted files out of what the seeder may touch;
- a failed run that made the branch carries `cleanup`;
- ADR-0044 no longer says `patterns.md` names the commits.

A guard that refuses the seeder's `git switch` before the call went to #0-172.

**Acceptance criteria.**
AC1. During a `/seed-bugs` run the working tree's `.claude/`, `CLAUDE.md` and `.ai/rules/` are those of `main`, shown by
a test of the workflow's commands (no switch to the merged commit).
AC2. The run refuses to start on a tree that is not a clean `main`, and ends on `main`, shown by tests.
AC3. `/seed-bugs` P-10 on a commit whose code still applies to `main` (`76379e806fb4`) plants the pattern and records a
row (with #0-170's AC3).

---

### 0-174. `/seed-bugs` cannot start from its own command, and reads strings from factory-ops

**Type:** ci · **Priority:** High · **Status:** Done, PR #530 (AC3 is shown by the owner's rerun of #0-115's "after" measure on `76379e806fb4`) — found by the owner's rerun of #0-115's "after" measure,
the first run after #0-173 (P-10 on `76379e806fb4`, run `perf-after-p10`, 2026-10-25)
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-173
**Touches:** factory (.claude/workflows/seed-bugs.js), ci (.github/scripts/test-autopilot-workflow.mjs), docs
(docs/ai-factory.md), .ai/rules/review/factory.md (owner: FAC-A06)

**Problem.** Two defects, one after the other, and no run measured anything:
1. `/seed-bugs P-10 76379e806fb4 perf-after-p10` hands the workflow its words as one string (Claude Code's command
   form, `args: "P-10 …"`), and the script, which reads `args.pattern`, `args.commit` and `args.runId`, stopped
   `NOT_STARTED`. Only a hand-made `Workflow` call with an object started it.
2. `ops()` gave `factory-ops` the bare schema `{ type: 'object' }`. The agent (Haiku) answered `seed-branch.sh`'s JSON
   with every value a string (`"ok": "true"`, `"files": "[…]"`) and wrapped `return-to-main.sh`'s in a `parameter`
   key, so the run failed on a seed branch it had made (`ok !== true`), reported `leftOn: "unknown"` from a tree that
   was on `main`, and named no cleanup (the branch was deleted by hand). #0-173's tests could not see it: the fake
   agent of `test-autopilot-workflow.mjs` ignores `schema`. `backlog-autopilot.js` types most answers it reads
   (`PREFLIGHT` and the rest), but reads `pinned.branch` from `state.sh branch` under `ANY_OBJECT` (a wrong answer
   stops the item, it lets nothing through) and puts `local-review.sh`'s untyped answer in the PR record: #0-175.

**Decided (owner, 2026-10-25).** The script takes both forms: the object, or three words in the order
`<pattern> <commit> <run id>`, checked by the same `SAFE` pattern (a wrong count or an unsafe word: `NOT_STARTED`, no
agent runs). Each script's answer has a typed schema with `additionalProperties: false`: the fields the script prints,
plus `factory-ops`' own `{error, exitCode}`; no `required`, so an error answer still reaches the run's reason. The same
string-args gap in `/audit` and `/docs-audit`, and `backlog-autopilot.js`'s untyped answers, are #0-175. The review
rule is FAC-A06 in `.ai/rules/review/factory.md` (the owner's; review round 1, architecture `ruleGap`).

**Acceptance criteria.**
AC1. `/seed-bugs <pattern> <commit> <run id>` makes the same calls as the object form, and a wrong count or an unsafe
word starts nothing, shown by tests.
AC2. The schemas accept what `seed-branch.sh`, `seed-check.sh` and `return-to-main.sh` print and refuse the answers of
the 2026-10-25 run, shown by a test.
AC3. `/seed-bugs` P-10 on `76379e806fb4` plants the pattern and records a row (with #0-173's AC3).

---

### 0-175. The other workflows cannot start from their commands, and read untyped factory-ops answers

**Type:** ci · **Priority:** Medium (Low until review round 2 of #0-174: once FAC-A06 is on main, `:481` breaks it) ·
**Status:** Done, PRs #571, #610, #611 (kept for the three PRs' decisions) — PR 1 (AC2 for `backlog-autopilot.js`,
2026-11-01), PR 2 (AC2 for every workflow, 2026-11-12), PR 3 (AC1, 2026-11-12); found with #0-174 (2026-10-25)
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-174
**Touches:** factory (.claude/workflows/audit.js, .claude/workflows/docs-audit.js,
.claude/workflows/backlog-autopilot.js, .claude/workflows/seed-bugs.js), .ai/rules/review/factory.md (owner: FAC-A06 to "Enforced by checks"), ci
(.github/scripts/test-autopilot-workflow.mjs), docs (docs/ai-factory.md)

**Problem.** Like `/seed-bugs` before #0-174: Claude Code passes the words typed after the command as one string, and
both scripts read object keys (`args.since`, `args.date`, `args.target`; `args.date`), so `/audit 2026-10-01 2026-10-25`
stops `NOT_STARTED`. `backlog-autopilot.js` is unaffected in its usual form (no args); `/backlog-autopilot #0-25` would
run the queue's next item instead of #0-25.

**Also (review round 1 of #0-174, architecture FAC-A02 and `ruleGap`).** `backlog-autopilot.js` reads
`pinned.branch` from `ops('state.sh', ['branch', …], ANY_OBJECT)` (`:481`): an answer in strings or wrapped in another
key stops the item ("could not record the run's branch"), the same class of defect as #0-174's, failing closed. Its
`local-review.sh` answer (`:559`) only reaches the PR record. FAC-A06 makes it a review finding; nothing checks it.

**Approach.** The same as #0-174: words in a fixed order, checked like the object's values, and a test per script;
typed schemas (FAC-A06) for every `ops()` answer a workflow reads; and a test in `test-autopilot-workflow.mjs` that
every such call's schema types what it reads (a structural check, so FAC-A06 moves to "Enforced by checks").

**Also (review round 3 of #0-177, architecture FAC-A06).** `scripts/factory/_common.sh` answers its own failures (no
`jq`, not inside the repository) with `{"ok":false,"reasons":[…]}`, a shape the typed schemas of `seed-bugs.js`
(`seed-branch.sh`, `seed-check.sh`, `seed-fold.sh`, `seed-record.sh`) do not allow: such a run fails closed on a schema
violation, without its reason. One failure shape for `_common.sh` and every script, or `reasons` in each schema.

**Acceptance criteria.**
AC1. Each of `/audit`, `/docs-audit` and `/backlog-autopilot` starts from its command's words, and refuses a wrong
     count, shown by tests (`/backlog-autopilot`: `#0-N`, or `#0-N <branch>` to resume; `acceptUnverifiable` stays an
     object field). Widened by the owner (2026-11-12): `/backlog-autopilot #0-25` ran the queue's next item instead.
AC2. Every factory-ops answer a workflow reads has a typed schema, and a test fails when one does not.

**It happened (2026-11-01).** The first autopilot run in the devcontainer since #0-174, `wf_8c632098-97c` on #0-191,
stopped at "could not record the run's branch": `state.sh branch` printed `{"branch": …}`, and `factory-ops` handed
it back as a string under a key of its own, which `ANY_OBJECT` let through, so `pinned.branch` was missing. Its
`unlock` came back the same way (`{"output": "{\"unlocked\":true}"}`), unread. The run left the local branch
`feat/0-191-deny-by-default-tests` (its start commit), for the owner to delete.

**PR 1 (owner, 2026-11-01): AC2 for `backlog-autopilot.js`.** Every one of its 13 untyped `ops()` calls, read or not,
gets `answerOf` (`seed-bugs.js`' form: the script's fields and nothing else); `ERROR_FIELDS` also takes `_common.sh`'s
`{ok:false, reasons}`, whose reasons reach the branch stop (this item's "Also" of review round 3 of #0-177, for this
workflow). `test-autopilot-workflow.mjs` reads every `ops()` call from the script's text and fails on one whose schema
names no fields or lets a key of the agent's own through, and checks each schema against what its script prints and
what the agent answered. FAC-A06 stays "Backed by", not "Enforced by" as Touches first said: `factory.md` has no
"Enforced by" rule, since the owner merges these paths through the bypass (its intro). Left for PR 2: AC1;
`audit.js`' `notify.sh` answer (`:107`, untyped and unread; `audit-data.sh`'s is typed); `seed-bugs.js`'
`ERROR_FIELDS` without `ok` and `reasons`, so its schemas still refuse `_common.sh`'s failure and the two `answerOf`
copies differ; and `backlog-autopilot.js`' `PREFLIGHT`, `TESTS`, `PATHS` and `NEXT`, typed by `required` keys but
not closed (`additionalProperties: false`, as FAC-A06 says, needs each script's full output checked first), whose
`TESTS` and `PATHS` also refuse `_common.sh`'s failure, so that stop has no reason (review round 1 of PR 1).

**PR 2 (owner, 2026-11-12, `/research`): AC2 for every workflow.** Decided: two PRs (this, then AC1), the schemas
closed with a structural check (not examples alone), and AC1 widened to `/backlog-autopilot`.
- `backlog-autopilot.js`' `PREFLIGHT`, `TESTS`, `PATHS` and `NEXT` are `answerOf`, with every field their script prints
  (`PREFLIGHT` lacked `state`; `PATHS` lacked `base`, `delta`, `pomSupplyChainLines`, `allModules`, `readyFlagAdded`,
  `buildConfigChanged` and `claudeMdOutsideBlocks`, three of which the path gate reads). With no `required` keys left,
  each call checks what it decides on, and a failure stops with its reason (`failureOf`): the path gate refuses an
  answer without a boolean `needsHuman`, which would otherwise read as "nothing needs a human".
- `audit.js` calls factory-ops through one `ops()`, with `AUDIT_DATA` (was typed by `required` keys) and `NOTIFIED`
  (was `{ type: 'object' }`); a failure of `audit-data.sh` is `FAILED` with its reason. `seed-bugs.js`' `ERROR_FIELDS`
  takes `ok` and `reasons`. The three copies of `ERROR_FIELDS`/`answerOf` (and two of `failureOf`) are compared by a test.
- A test reads the keys of each script's jq output (`preflight.sh`, `run-tests.sh`, `changed-paths.sh`,
  `next-item.sh`, `start-item.sh`, `resume-item.sh`, `return-to-main.sh`, `audit-data.sh`) and fails on one its schema
  does not name: a closed schema would otherwise stop every run on a field added to a script. FAC-A06 says so
  (`factory.md`); it stays "Backed by".
- Known and kept (review round 1): with no `required` keys, an answer the agent sends with a key *left out* passes the
  schema and stops the item, with its reason, where the runtime used to ask again. The asks again that the runs needed
  stay: a wrapped answer and a value sent as a string are still refused by `additionalProperties: false` and the types;
  no run has left a key out. An `anyOf` (the script's shape with its keys required, or a failure) would keep that ask
  too, but Claude Code's structured output is not checked to honour it. No ADR: FAC-A06 and this entry hold the
  decision, as for PR 1. `audit.js` checks every field its decisions rest on (`ownerIsAutopilot`, the label and escape
  counts, `cases`), so a missing one is no "nothing to warn of"; the preflight's refusal keeps one reason per check.

**PR 3 (owner, 2026-11-12): AC1.** Each workflow reads its command's words as `seed-bugs.js` does (#0-174): split on
whitespace, read in the order of the object's keys, then the same checks as the object's values; a run from the words
makes exactly the calls a run from the object does (`test-autopilot-workflow.mjs`, which also fails on the scripts as
they were).
- `backlog-autopilot.js` (A2): no word is the next item, `#0-N` the item, `#0-N <branch>` the resume; three or more is
  `NOT_STARTED` with the usage, before the preflight (nothing locked, moved or notified). `shadow`, `maxRounds`,
  `localReview` and `acceptUnverifiable` stay object fields. Its refusal of a malformed item says "the item", not
  "args.item", as it now comes from a word too.
- `audit.js`: `<since> <date> [target] [dimension…]`. A dimension is now checked against `ALL` in both forms: unchecked,
  a mistyped one started an analyst for a dimension the panel does not have.
- `docs-audit.js`: `<date>`, now checked as a date in both forms (it names the report's file; it was only required
  to be present).
- The usage in `docs/ai-factory.md` ("Running it", the cadence table), `preflight.sh`'s "audit due" note and
  `local-implement.sh`'s header is the word form.

---

### 0-176. `/seed-bugs` reads the panel's verdicts untyped, and an error strands the tree on the seed branch

**Type:** ci · **Priority:** High · **Status:** Done, PR #531 (AC4 is shown by the owner's P-10 or P-11 rerun) — found by `/seed-bugs` P-12 on `47b95294` (run
`perf-after-p12`, 2026-10-25), the first run after #0-174 that reached the panel
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-174
**Touches:** factory (.claude/workflows/seed-bugs.js), ci (.github/scripts/test-autopilot-workflow.mjs), docs
(docs/ai-factory.md), .ai/audit/benchmark/results.md, .ai/rules/review/factory.md (owner: FAC-A06 widened),
.ai/audit/benchmark/patterns.md (owner: P-10 and P-11 reworded to the rewritten PERF-01 and PERF-23, #0-115)

**Problem.** #0-174's class of defect, one stage later. The panel's schema in `seed-bugs.js` named only its required
keys (`{ type: 'object', required: ['dimension', 'verdict', 'blocking'] }`), so all six verdicts came back with every
value a string (`"blocking": "[{…}]"`, `"round": "1"`), and the Record phase threw (`(v.blocking ?? []).some is not a
function`). The script stopped there: the tree stayed on `seed/P-12-perf-after-p12`, no row was written, no cleanup
was named (the owner's session switched back and deleted the branch). The panel had caught the defect: five
dimensions blocked it, performance under PERF-30. `backlog-autopilot.js` is not affected: its `VERDICT` and `FINDING`
are typed.

**Decided (owner, 2026-10-25).** The panel gets a typed `VERDICT`/`FINDING`, copied from `backlog-autopilot.js` (a
workflow cannot import), with `file` and `line` typed on non-blocking findings too (the Record phase matches them)
and only `issue` required of a finding (a measure must not lose a catch over a missing id). A verdict that still is
not one (no `blocking` or `nonBlocking` array) counts as no answer. Every step after the branch is made runs in
`measure()`, and an error there ends the run as `FAILED`, back on main, with the branch named for deletion. FAC-A06
covers any agent's answer a workflow reads, not only `factory-ops`'. The P-12 row is recorded by hand from the run's
journal. Review round 1 (owner, 2026-10-25): `backToMain()` never throws (a failure reads as "not on main"), so an error
in the catch of `measure()` cannot escape; a measure whose row cannot be written ends `MEASURED`, `recorded: false`, with
its data; and a test keeps the panel's schema typed as `backlog-autopilot.js`'s `VERDICT`, but for the relaxations named
in its comment. Review round 2: that test compares both ways (a key only `seed-bugs.js` types fails it too), and a
MEASURED run not back on main names the branch to delete; the unchecked `audit-synthesis` answer went to #0-171.

**Acceptance criteria.**
AC1. The panel's schema accepts a verdict as reviewers write it and refuses the answers of the 2026-10-25 run, shown by
a test.
AC2. A verdict that is not one counts as no answer and the run still records, shown by a test.
AC3. An error after the branch exists ends the run on main and names the branch, shown by a test.
AC4. A `/seed-bugs` run that reaches the panel records its row (the owner's P-10 or P-11 rerun).

---

### 0-177. `/seed-bugs` asks for a commit on `main` between runs, and its panel can tell it is measured

**Type:** ci · **Priority:** Medium · **Status:** Done, PR #533 (the first series on it is #0-115's `security.md`) — found by the owner's measure of #0-115's `performance.md`
(P-10 and P-11 run back to back, 2026-10-25); widened 2026-10-26 by the owner with the blind panel (below)
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** #0-176
**Touches:** factory (.claude/workflows/seed-bugs.js, scripts/factory/seed-branch.sh, scripts/factory/seed-check.sh,
scripts/factory/seed-fold.sh and seed-record.sh (new), scripts/factory/_common.sh, .claude/agents/defect-seeder.md), ci
(.github/scripts/test-autopilot-workflow.mjs, .github/scripts/test-seed-branch.sh, .github/workflows/factory-guards.yml
comment), docs (docs/ai-factory.md, ADR-0044 and the ADR index); scripts/factory/audit-data.sh unchanged (it reads the
tracked `results.md`)

**Problem.** The Record phase appends its row to `.ai/audit/benchmark/results.md` on `main`, and both the run's
`cleanup` and `seed-branch.sh`'s refusal tell the owner to commit that file before the next run (#0-173). But `main`
takes changes only through a pull request (its ruleset), and `seed-branch.sh` starts only on a clean `main` equal to
`origin/main`: a local commit on `main` makes it refuse ("main is not at origin/main"), and a pull request per run
means a merge between every two runs. On 2026-10-25 the session parked the P-10 row in its scratchpad, restored the
file, ran P-11, and merged both rows on a branch by hand.

**Problem (2): the panel can tell a seeded run from a review** (found 2026-10-26, on the owner's question whether the
reviewers know about `/seed-bugs`). The measure rests on the reviewers judging the seed branch as any change, but three
things tell them it is a test, and the first two name the defect:
- the panel's prompt names the branch (`seed-bugs.js`, `Branch seed/P-10-perf-after-p10`): "seed", and the pattern id;
- the base commit, the `mergeBase` the panel is given, says `seed base: the code of <sha> reverted (/seed-bugs, not
  for review)` (`seed-branch.sh`), seen by any `git log` on the branch;
- the catalogue is readable: reviewers have Read, Grep and Glob over the repository and `readonly-bash.sh` allows
  `git show`, `git grep` and `git log`, so `.ai/audit/benchmark/patterns.md` (P-10: N+1, PERF-01) and the "Seeded
  defects" section of `.ai/rules/audit.md` are in reach.
Whether a reviewer of P-10..P-12 read the catalogue was not checked; the results stand, but `/audit` counts a seeded
result as a hard fact, and a measure that is not blind by construction should not. Before the `security.md` series
(P-01..P-05, #0-115).

**Approach (to analyse).** Keep the rows out of the tree while a series runs and land them in one pull request after
it: e.g. the Record phase appends to `.ai/runs/benchmark/results.md` (gitignored, like the other run artifacts), and the
owner copies the new rows into `.ai/audit/benchmark/results.md` with the series' PR; `seed-branch.sh` then no longer
needs to name `results.md`, and `audit-data.sh` keeps reading the tracked file. Or let `seed-branch.sh` accept a tree
whose only change is that file and carry it aside itself (more moving parts).
For the blind panel: (A) a branch name and a base commit message that say nothing (e.g. `review/<8 hex>` and git's
own `Revert "<subject>"`), the pattern kept only in the workflow and the results row; with either (B1) refusing
`.ai/audit/` to the `review-*` agents (a read hook plus `readonly-bash.sh`; leaky: `git grep` without a pathspec and
`git show <rev>:<path>` reach it unless that hook grows pathspec rules) or (B2) leaving the catalogue readable and
recording the residual in ADR-0044: once the prompt and the history are those of a real review, nothing points a
reviewer at it.

**Decided (owner, 2026-10-26, after /research).** 1a with a script, A, A+ and B2:
- the rows: `scripts/factory/seed-record.sh` (through `factory-ops`, typed `{appended}`; no agent writes the row any
  more) appends to the gitignored `.ai/runs/benchmark/results.md`; a run id already there or in the tracked file is
  refused; a series' rows reach `.ai/audit/benchmark/results.md` in one PR; `seed-branch.sh` no longer names
  `results.md`. This reverses ADR-0044's rejection of "results under `.ai/runs/`" (amended there, with why).
- A: the workflow derives the branch (`review/<8 hex>`, FNV-1a of the pattern and the run id, the same on a relaunch)
  and passes it to the scripts; the base says `Revert "<subject>"` (no sha: it would point at `main`).
- A+ (found in the research, a fourth tell): the defect was its own commit on top of the change, so `git show HEAD`
  showed the planted lines alone; `scripts/factory/seed-fold.sh` folds it into the change's commit after
  `seed-check.sh`, before the panel (same tree, so the ground truth's line holds).
- B2: the catalogue stays readable; ADR-0044 decision 6 records the residual and the evidence: the transcripts of the
  18 reviewers of P-10..P-12 hold no read of `.ai/audit/`, `patterns.md` or `audit.md` and no text about seeding, so
  those results stand. B1 (refuse `.ai/audit/` to reviewers) rejected: the same transcripts show `git grep … -- .ai`
  and `-- .` as normal review searches.
- Landing a series' rows stays a step by hand (docs/ai-factory.md), not a `--land` mode: once per series.

Review round 1 (`/review` 12367, owner "1-6"): shellcheck findings fixed (Lint Workflows, found by `ci-local.sh`);
`seed-fold.sh` also drops the run's reflog entries (the branch's, and HEAD's above the switch onto it), since
`git log -g`/`HEAD@{1}` still showed the seeder's commit alone (architecture; confirmed in a scratch repository); a run
id is matched in the first column only (a run id equal to a dimension was refused); a test keeps `seed-record.sh`'s
dimensions equal to the workflow's `PANEL`; ADR-0044 decision 6 names the other residuals (the prompt's shape, the rows
file readable during a series, the seeder's missing write scope, now an "Also" of #0-172).
Review round 2 (`/review` 12367, owner "1-3"): no blocking finding; ADR-0044 decision 6 also names what `main`'s
history and the owner's HEAD reflog (the runs before #0-177, `seed/P-1x-…`) say of the benchmark; `seed-fold.sh`'s
header names the one refusal that comes after the fold; a test keeps the workflow's branch names inside
`SEED_BRANCH_RE`.
Review round 3 (`/review` 12367, owner "tak"): no blocking finding; `seed-record.sh` reads the id column whole before
searching it (`cut | grep -q` under pipefail let a SIGPIPE pass a duplicate run id; a test with a long file fails on
the old pipe); `ops()` says that its arguments must be pattern-checked; ADR-0044 names a HEAD move by another session
during a run among the residuals; `_common.sh`'s failure shape went to #0-175 as an "Also".

**Acceptance criteria.**
AC1. Two `/seed-bugs` runs in a row need no commit and no pull request between them, shown by tests of the scripts.
AC2. The rows of a series reach `.ai/audit/benchmark/results.md` through one pull request, and `docs/ai-factory.md`
says so.
AC3. The panel's prompt and the history from its `mergeBase` to the branch's head name neither the pattern nor that a
defect was planted, and the defect is not in a commit of its own, shown by tests of the workflow and of the scripts.
AC4. What a reviewer can still read of the catalogue (`patterns.md`, `audit.md`) is decided and recorded in ADR-0044
with its residual, and `docs/ai-factory.md` says so.

### 0-179. The Workflow tool shows the panel the `/seed-bugs` command that started the run

**Type:** ci · **Priority:** Medium · **Status:** Done, PRs #553 and #554 (kept for the decision history: C + D, the
script as an aid to the hand reading, the blind re-runs). Found 2026-10-26 in the transcripts of #0-115's
`security.md` series, read before landing its rows (ADR-0044 decision 6).
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium (was low: the scan script and its test) · **Depends on:** —
**Touches:** factory (scripts/factory-admin/seed-scan.sh), ci (.github/scripts/test-seed-scan.sh,
.github/workflows/factory-guards.yml), docs (docs/ai-factory.md, ADR-0044, .ai/audit/benchmark/results.md for AC2)

**Problem.** #0-177 made the panel's prompt, branch and history say nothing about the run. But the Workflow tool
starts the first message of every agent with a block of its own, `[Workflow harness — user request]`. That block
holds, word for word, the user's message that started the workflow. When the owner types
`/seed-bugs P-01 47b95294 sec-after-p01`, each reviewer reads "seed-bugs", the pattern id and the run id before its
task. This happened in four of the five `security.md` runs (P-01, P-03, P-04, P-05). In P-02 the session started the
run in its own turn, after the previous run's notification, so the block was absent. The P-10..P-12 runs of
2026-10-25 relayed the owner's "tak" and "rób", which say nothing. The script cannot remove the block: the tool adds
it, not `seed-bugs.js`. The transcripts show no reviewer acting on it: no tool call or text names a seed, a pattern
or the catalogue. But their thinking is not recorded, so a result from such a run is not blind by construction.

**Approach (to analyse).**
- A neutral start: the owner starts each run with a message that names no pattern, e.g. a plain "next run" once the
  session holds the series' list. The session then calls `Workflow` with the args. This needs no code. It does rest on
  the owner's habit and on the tool keeping that behaviour.
- The series in one call: `seed-bugs.js` takes a list of `pattern commit runId` triples and runs them one after
  another. Only one start message is relayed, and it can stay neutral. This changes the workflow and its tests.
- A check before a series' rows land: search the reviewers' first message for the run's pattern or run id and mark the
  row as not blind. `audit-data.sh` would then count only blind rows as a hard fact. This means a column in
  `results.md` and changes to the script and its test.
- Recorded in ADR-0044 decision 6, as one more thing that told the panel it was measured.

**Acceptance criteria.**
AC1. A `/seed-bugs` run's reviewers receive no message that names the pattern, the run id or `seed-bugs`, shown by
their first message in a run's transcripts, or by a test where the mechanism is a script's.
AC2. P-01, P-03, P-04 and P-05 run again that way (new run ids), and their rows land beside the 2026-10-26 ones.
AC3. ADR-0044 and `docs/ai-factory.md` name the relayed message and how a run avoids it.
AC4. Where a pattern has a row that was not blind and a re-run's row (AC2), the audit counts only the blind one. How it
tells them apart is decided with the mechanism (until then the 2026-10-26 rows say `yes (told the pattern, #0-179)` in
"Caught by expected", review round 1).

**Decided (owner, 2026-10-30: C + D of the `/research`, the scan covering #0-185's and ADR-0044 decision 6's
reads too; the script as an aid).**
- D, the start: the session calls `Workflow` in a turn no user message started. On the owner's message it starts a
  background command that does nothing, and starts the run in that command's notification turn. That turn's first
  message is the `[Workflow harness — computed task]` block alone. A scan of the 20 seed runs on disk shows why the
  owner's habit was not enough: one run's panel got `1-3 tak, dalej`, the owner's answer to another question.
- C, the check: `scripts/factory-admin/seed-scan.sh <transcriptDir> <pattern> <run id>` reports, per reviewer:
  - a relayed message that names the run (`seed`, `benchmark`, `plant`, a pattern id, the run id);
  - a git read that reaches the merged change, as content or names only (#0-185's list);
  - a read of the answer key (ADR-0044 decision 6).
  Tested on fixtures by `test-seed-scan.sh` in Factory guards; 11 mutations caught.
- ADR-0044 decision 6 said "no script: the transcripts' format is not a contract". The owner chose a script that
  helps the hand reading and does not replace it. It refuses (`ok: false`) a shape it does not know: no reviewer, a
  reviewer without its transcript, a first message with neither harness header, a prompt without its mergeBase, a
  seeder prompt naming another run. ADR-0044 is amended.
- Checked against the hand readings on the 20 runs on disk. It found the same 4 relayed commands and the same patch
  read (general, `arch-after-p07`), plus one names-only read the hand scan had not listed: security's
  `git log --oneline -5 refs/remotes/origin/main` in `arch-after-p07`. That read shows subjects only, by a reviewer
  that is not the expected one, so the row stands.
- AC4 needs no code. `.ai/rules/audit.md` (#0-185) reads a marked row as an upper bound, not a hard fact, so a re-run's
  blind row (AC2) is the one that counts.
- The first "Also" is done: #0-184's `check-rule-claims.rb` refuses the measure's words in the rule files (ADR-0046).
  The second (a rule gap of the owner's `architecture.md`) stays for the owner. A row's qualification is in the data
  (the cell), as the scan's result goes.
- Left for after the merge: AC2, re-running P-01, P-03, P-04 and P-05 with new run ids, started the D way and scanned.

- Review round 1 (owner: "tak" on 1-9):
  - the scan knows more forms: git's global options, `grep`, `diff-tree`, `ls-tree`, `archive`, `FETCH_HEAD`,
    `ORIG_HEAD`, `@{…}`, `origin/HEAD`, and says its list is not a proof (security);
  - it no longer flags `Main.java`, a hex-looking word or a searched pattern (general);
  - only `main:.ai/rules/` is excluded (security);
  - it says its output is data (security);
  - a test pins the prompt words it parses from `seed-bugs.js` (architecture);
  - `docs/ai-factory.md` points at the scan instead of copying its list (architecture);
  - ADR-0044's Backlog line and index row name #0-179 (docs, architecture).
  The wider scan found, on the 20 runs on disk, a read by content that no hand scan had listed: security's
  `git grep … refs/remotes/origin/main` of the P-07 host file in `arch-after-p07`. It also found two `ls-tree`
  reads of names. None caught the defect, so the rows stand (ADR-0044).
  Not done: procedure D in `CLAUDE.md` (architecture). `CLAUDE.md` reaches every agent, the reviewers too, and the
  text they read must not mention the measure (ADR-0044 decision 6). D stays in ADR-0044 and `docs/ai-factory.md`.
  ADR-0044 is amended, not replaced (owner): the script helps the decision's hand reading and does not reverse it.

- Review round 2: no blocking finding (security and architecture NEEDS_HUMAN, protected paths only). Owner:
  "popraw". The scan now also knows:
  - `@~`/`@^`;
  - a history walk from HEAD with no revision, or a limit above the branch's two commits (`git log -p`,
    `git log -- <path>`);
  - `--all`/`--branches`/`--remotes`, `reflog` and `show-branch`.
  A patch flag wins over a names flag (security). The header lists its subcommands, and ADR-0044 points back to
  decision 6 (architecture). The relayed message's lines are all indented (18 multi-line relays on disk, checked in
  the session). On the 20 runs on disk the content reads are still the two known ones; two walks of main's history by
  names were added (ADR-0044).

- AC2 done (2026-10-30): P-01, P-03, P-04 and P-05 were re-run as `sec-p0n-blind`, each started from a notification
  turn and scanned. None of the 28 reviewers was relayed a message. Three held (caught and blocked). `sec-p04-blind`
  was caught but not blocked (SEC-31 weighed by today's values), which is #0-187. Rows and note:
  `.ai/audit/benchmark/results.md`.
  The scan learned the reviewed branch's head from the run's journal: `git log -1` of it was a false hit in
  `sec-p05-blind`. The landing's review found that the first version also hid `git log -p <head>` (security,
  architecture). Now that head counts as HEAD does, a head equal to the base or the merged change is refused, an
  unusable journal gives no exception, and `seed-bugs.js` names the scan as the reader of its `'seed fold'` label.

**Workaround, until AC2 (superseded by D above; 2026-10-26, #0-115's `architecture.md` series).** In P-06…P-09, each run was started by the
owner's "dalej" and the workflow was called by the session. Every reviewer's first message relayed only that word.
Until a mechanism lands, this is how a series is run.

**Also (#0-115's `general.md` results, review round 1).** The relayed message is not the only text a reviewer reads
on every run. Its rule files are too, and `architecture.md`'s header said "a seeded result" from PR #536 on (ADR-0044
records it). Only prose holds "a rule file does not mention the benchmark", so the next rewrite can bring it back.
A Factory guards check could refuse `seed`, `seeded`, `benchmark` and `patterns.md` in `_common.md`, the dimension
rule files other than `factory.md` (read only for an Owner-only diff, which a seed branch never is), the `review-*`
agent definitions and the `review-procedure` skill.

**Also (review round 1).** `.ai/rules/review/architecture.md` has no rule that a qualification on the factory's
measurement data (a benchmark row) must be in the data the audit's script reads, not only in prose beside it
(`audit-data.sh` keeps only the table's lines). This is a rule gap for the owner's rules.

### 0-180. `/seed-bugs` measures catches, never false alarms

**Type:** design · **Priority:** Low · **Status:** Done, PRs #559, #560, #561 (kept for the decision history). The owner's question on P-07 of #0-115's `architecture.md`
series (2026-10-26): the code has deliberate exceptions to a rule, so does the measure check that the panel leaves
them alone?
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/workflows/seed-bugs.js, .claude/agents/defect-seeder.md, scripts/factory/seed-record.sh,
scripts/factory/audit-data.sh, their tests), .ai/audit/benchmark/patterns.md and .ai/rules/audit.md (owner), docs
(docs/ai-factory.md, ADR-0044)

**Problem.** A seeded run plants a defect and counts whether its dimension blocks it: it measures catches only. A
panel that blocks too much passes that measure too. Some rules have deliberate exceptions in the code:
- ARC-23: `TenantWebSocketSessions` and `OperatorTenantBootstrap.refreshPendingGauge` run per replica on purpose;
- ARC-29: a state-guarded UPDATE replaces `@Version`;
- SEC-08: `tenant-status.read-only.allowed-writes`.

A reviewer that blocks every missing `@SchedulerLock` would score 100% on P-07 and still block a correct change.
The audit counts false alarms only from the owner's labels on real PRs (`human:fp-<dimension>`,
`.ai/rules/audit.md`). With few autopilot PRs, that count is close to empty, and it never covers a rule's exception
on purpose.

**Approach (to analyse).**
- "Clean" patterns in `patterns.md` (e.g. `C-01`), each a correct change that a careless reading of a rule would
  block: a new per-replica job with its reason in the Javadoc (ARC-23), a conditional UPDATE on a one-writer row
  (ARC-29), a new route in `allowed-writes` with its reason (SEC-08).
- The run plants it like a pattern, but the expected answer is reversed. The expected dimension approving, or
  raising only non-blocking findings, is a pass. A blocking finding there, or in any other dimension, is a false
  alarm. There is no ground-truth line, so `seed-check.sh` checks only the tree.
- The row records it apart from catches, e.g. a "Kind" column or a separate table, so `audit-data.sh` and the
  synthesis do not count a clean run as a missed catch.
- Rotate clean and defect runs in a series, so a reviewer cannot learn that every seeded branch holds a defect.

**Also (#0-115's `general.md` series, 2026-10-26).** A run counts as blocked only when the expected dimension lists
the finding in `blocking` (`seed-bugs.js`, the Record phase). A rule whose answer is `NEEDS_HUMAN` (GEN-08, ARC-01,
ARC-05, ARC-06) is stopped by that verdict too. A reviewer that answers `NEEDS_HUMAN` and leaves the finding in
`nonBlocking` would be recorded as not blocked. It did not happen in that series (gen-after-p16 listed it as
blocking), but the row should take the verdict into account where the rule asks for `NEEDS_HUMAN`.

**Acceptance criteria.**
AC1. `patterns.md` holds at least one clean pattern per rule with a deliberate exception named in the code, starting
with ARC-23.
AC2. A clean run records a false alarm when a dimension blocks it, and a pass when none does. This is shown by tests
of the workflow and of `seed-record.sh`.
AC3. `audit-data.sh` reports clean results apart from catches, shown by its test. `docs/ai-factory.md` describes the
clean runs.

**Decided (owner, 2026-10-31: option A of the `/research`, with the Also).** ADR-0044 decision 7.
- The kind comes from the pattern id (`C-` is clean), never from the seeder. A seeder whose `kind` is not its
  pattern's fails the run.
- A false alarm is a dimension that stops the change *at the planted line*: a blocking finding there, or `NEEDS_HUMAN`
  with a finding there. Unlike this item's first sketch, a blocking finding anywhere else is not one: of the 71
  blocking findings of the 25 defect runs before, 19 were not at the plant. They were the host's code, the plant's
  other half (#0-181) and an old host's artifact. Those are recorded ("Blocking elsewhere") and not counted.
- The rows have their own table, written by `seed-record.sh --clean` to `.ai/runs/benchmark/clean.md` and landed in
  `.ai/audit/benchmark/clean.md`, and are passed by `audit-data.sh` as `seededClean`. A separate table rather than a
  "Kind" column, so neither the audit nor the synthesis can read a pass as a missed catch, and the 27 existing rows
  keep their schema. A run id is unique across both tables.
- `check-rule-claims.rb` checks that a `C-` pattern cites a live rule, as a `P-` pattern does. The audit of a reviewer
  counts `seededFalseAlarms`.
- Also: `NEEDS_HUMAN` with a finding at the planted line counts as blocking in a defect run.
- The owner's files are drafted: `patterns.md` gets C-01 (ARC-23), C-02 (ARC-29) and C-03 (SEC-08); `audit.md` gets
  how to read the clean table.
- Tested: workflow (4 cases), `seed-record.sh --clean` (8 calls, 11 assertions), `audit-data.sh`,
  `check-rule-claims.rb`; 8 mutations caught.
- Review round 1 (owner: "tak" on 1-5):
  - `seed-scan.sh` takes `C-` runs, so their transcripts are scanned before a row lands, and a relayed `C-` id is a
    tell. 3 mutations caught. This was architecture's blocking finding.
  - `docs/ai-factory.md` says the audit reads the tracked tables and a run id is unique across all four.
  - ADR-0044 decision 6 names `clean.md` as in reach of the reviewers during a series.
  - `audit.md` (drafted for the owner) says the "Blocking" column counts `NEEDS_HUMAN` at the plant from #0-180 on,
    and that "No answer" on a clean run is no measure, not a pass.
- Review round 2: architecture's blocking finding resolved (architecture APPROVE). Owner: "popraw". A clean run now
  needs the seeder to say `kind: "clean"`. A `C-` answer without it fails, since it may have planted a defect that a
  dimension rightly blocked. A defect run may still leave it out. Test and mutation added.
- First clean run, `clean-c01` (2026-10-31, C-01 on `aace4118`, blind, scanned clean):
  - architecture, the expected dimension, approved the per-replica gauge (no false alarm on ARC-23's exception);
  - performance noted it (PERF-22, non-blocking);
  - general stopped it under GEN-01: the planted method had no test, which is a right finding.
  Under decision 7's first wording that read as general's false alarm. The owner chose A: a false alarm is a stop under
  the pattern's rule only (its id, or the expected dimension's finding with no id), and a stop under another rule is
  raised. The row was dropped and C-01 runs again under the fixed measure. 4 mutations caught.
- Review round 1 of the fix (`/review 17`): general and architecture APPROVE, nothing blocking. Owner: "1-4". The rule
  id is matched trimmed, in any case and as a prefix, never a longer id or one cited second (test, 5 mutations
  caught); ADR-0044 says why catches and false alarms are scored differently, and its status names the amendment.
- Review round 2 (`/review 17`): general and architecture APPROVE, nothing blocking. Owner: "A and the sentence of
  nb 2". `seed-check.sh` now holds the seeder's rule and dimension to its pattern's row of `patterns.md` on
  `origin/main`, before the panel (architecture's nb 1, FAC-A02: the false-alarm measure rested on the seeder's word);
  first proposed in `seed-record.sh`, moved to `seed-check.sh` by the owner since a refusal after the panel would
  have left a measure under the wrong rule. 12 cases, 9 mutations caught. ADR-0044 decision 7 says why a finding
  with no rule id from another dimension is raised (nb 2).
- First series (2026-10-31, after PR #560, both blind, started from a notification turn, scanned clean), on
  `aace4118`'s `OperatorTenantBootstrap`:
  - `clean-c01-r2` (C-01): no false alarm. architecture approved the per-replica gauge job and said it meets ARC-23,
    and general raised GEN-01 (no test). Landed in `.ai/audit/benchmark/clean.md`.
  - `arch-p07-ctl` (P-07, the defect control on the same file and rule): caught and blocked by architecture under
    ARC-23 at the plant, also by general, security and docs. Landed in `.ai/audit/benchmark/results.md`.
  C-02 (ARC-29) and C-03 (SEC-08) are in `patterns.md` for the next series; AC1 asks for the patterns, not for a run of
  each.

### 0-181. `/seed-bugs` scores a catch by one line, and never compiles the plant

**Type:** ci · **Priority:** Medium · **Status:** Done, PRs #562, #563, #564 (kept for the decision history: A3 and B1, ADR-0044
decisions 8 and 9). Found in #0-115's `docs.md` series (2026-10-27, `docs-after-p17`).
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/workflows/seed-bugs.js, .claude/agents/defect-seeder.md, scripts/factory/seed-check.sh,
.github/scripts/test-autopilot-workflow.mjs, .github/scripts/test-seed-branch.sh; for the compile step also a new
scripts/factory/seed-compile.sh, scripts/factory/_common.sh, scripts/factory/run-tests.sh, .github/scripts/test-run-tests.sh
and a comment in .github/workflows/factory-guards.yml), .ai/audit/benchmark/patterns.md
and .ai/rules/audit.md (owner), docs (docs/ai-factory.md, ADR-0044)

**Problem.**
1. The ground truth is one file and one line, and the Record phase counts a finding as a catch only within 5 lines of
   it (`seed-bugs.js`, `near`). Some defects have two places: P-17 is a method's code and its stale Javadoc. In
   `docs-after-p17` the seeder named the code's line (266), docs blocked the Javadoc (257) under DOC-11, and the row
   says "not caught". The same holds for any pattern where a rule's finding points at the other half (a doc against
   code, a test against the code it pins, a migration against its entity). A plant longer than the window has the
   same gap: in `clean-c01-r2` (#0-180, 2026-10-31) the seeder named the new method's line (152), performance noted
   the job at its Javadoc (145) and the row does not name it as raised.
2. Nothing compiles the plant. In `docs-after-p17` the `private static` method read the instance field `id`, so
   incident-service would not compile; security and architecture said so. The panel then measures a defect easier to
   see than the one in the pattern, and a reviewer may block for the build, not for the rule.

**Approach (to analyse).**
- The ground truth takes a list of places (`[{file, line}]`, at most a few), the seeder names every half the pattern
  has, and `near` matches any of them; `seed-check.sh` checks every file is one of the seeder's.
- Before the panel, compile the affected module on the seed branch (`./mvnw -q -pl <module> compile`, or the test
  gate's compile step) and refuse the run as `SKIPPED` with the compiler's first error when it fails, so the seeder's
  mistake is recorded, not measured.
- Patterns that span two places say so in `patterns.md` (owner), e.g. P-17 "the code and its Javadoc".

**Acceptance criteria.**
AC1. A finding at any place of the ground truth counts as a catch; shown by a workflow test with a two-place truth.
AC2. A plant that does not compile ends the run before the panel, with a recorded reason; shown by a test.
AC3. P-17 run again on `fc368943` after the change records docs as caught without a hand reading.

**Decided (owner, 2026-10-31: A3 and B1 of the `/research`, two pull requests).**
- **The truth is the edit** (first PR, ADR-0044 decision 8). `seed-check.sh` returns the seeder's hunks
  (`git diff -U0 HEAD`), and a finding within 5 lines of any hunk is at the plant. The seeder's own line must lie in
  one of them, or the run fails. The half it leaves unedited on purpose is named in `also`: at most two places, each a
  regular file at HEAD and a line it has (review round 1). The outcome's `onlyAtAlso` names the dimensions that
  reached only such a place; the row's columns are unchanged.
  - Why not the first sketch (a list of places from the seeder): the whole truth would rest on an agent's word again,
    after #0-180 took the kind and the rule from the pattern.
  - Evidence (the 40 run journals on disk): one main-column miss (P-17, docs at the Javadoc), and two secondary ones
    (`arch-after-p07`: docs at the class Javadoc; `clean-c01-r2`: performance at the job's Javadoc). For clean runs it
    matters more: a plant there is a method with its reason, longer than the window.
  - AC1 reads, from this decision: a finding anywhere in the seeder's edit, within 5 lines, or at a place it names in
    `also`, counts as at the plant; shown by workflow tests with a long hunk, two hunks and an `also` place.
- **The plant is compiled** (second PR). A new `seed-compile.sh`, run through factory-ops after `seed-fold.sh`:
  - `test-compile` offline (`-o`) of the planted module (`-am`), with `run-tests.sh`'s hardened Maven call moved to
    `_common.sh` so both use one list of what is stripped;
  - only when the edit holds a `.java` file and no `pom.xml`;
  - a compiler error ends the run FAILED with its first error (a seeder's mistake, #0-170: not SKIPPED), an
    environment error FAILED with its cause.
  - Not taken: the full test gate (minutes and Docker per run, and a defect the tests catch would never reach the
    panel in the autopilot) and a retry by the seeder.
- AC3 after the first PR.
- Review round 1 of the first PR (`/review 17`): general APPROVE; architecture blocked (arc-5c1e, FAC-A03): ADR-0044
  decision 8 pointed to `audit.md`, which said nothing of the new scoring, so the next audit would read rows from
  before and after it as one measure. Owner: "1-5".
  - `audit.md` (drafted for the owner) says how rows before and after #0-181 differ, and that a catch only at an
    `also` place rests on the seeder's word (as `told the pattern`, it never raises a recommendation's confidence).
  - Confirmed in session (architecture's out-of-scope): an added line whose text starts `++ ` showed as `+++ b/…` and
    was read as a file header. The diff now marks the text's lines `>`/`<`. A place must be a regular file at HEAD:
    a tracked symlink had awk read its target outside the tree, and a directory passed with a misleading reason.
  - A place inside the edit fails the run. An unrelated one outside it cannot be checked; the cap of two bounds it.
  - Rule gap (architecture): no rule says a change of how `/seed-bugs` scores a row updates `audit.md`'s reading of
    the rows in the same pull request; FAC-A03 caught it here through the ADR's pointer. Recorded here, no item.
- Review round 2: general and architecture APPROVE, arc-5c1e resolved. Owner: "wprowadź": a path with a space (git
  leaves it unquoted and ends the `+++` header with a tab, confirmed in session) is refused with its reason instead of
  "line is not in its edit". Checked by hand on a scratch repo: the fixture's change has no such path, and adding one
  would change every seed-branch case.
- **Second PR: the compile step (2026-10-31).** `scripts/factory/seed-compile.sh` runs through factory-ops after
  `seed-fold.sh` (ADR-0044 decision 9): `factory_mvn -o test-compile -pl <modules of the edit's .java> -am`, `-amd` too
  when the edit reaches `shared` (owner, 2026-10-31: a broken signature there breaks the services). `run-tests.sh`'s
  hardened Maven call and its environment-error list moved to `_common.sh` (`factory_mvn`, `MAVEN_ENV_ERRORS`, the
  offline forms added); the gate behaves as before but for those two forms, which it now reads as a stop too (it runs
  online, so they would only appear on a real resolution failure: more stop, never more pass; review round 1). Measured: every module from cold in about 10 s offline; a real
  P-17-like plant gives `[ERROR] incident-service/…/Incident.java:[295,50] non-static variable id cannot be referenced
  from a static context`, and an empty local repository `… in offline mode`.
  - AC2 shown by tests: `test-autopilot-workflow.mjs` (compiled after the fold and before every reviewer, with the
    change's and the folded head; a failure, a malformed or an error answer is FAILED with no panel and no row; a
    skipped compile runs the panel), `test-seed-branch.sh` (24 seed-compile cases: offline call, settings, stripped
    environment, `-amd`, POM and no-Java skips, compiler, environment and other errors, the log, every refusal) and
    `test-run-tests.sh` (the environment stripped, no Docker is a stop). 15 mutations caught.
  - Review round 1 (`/review 17`): general APPROVE, architecture NEEDS_HUMAN (Owner-only paths only), no blocking;
    ci-local caught SC2015 in `seed-compile.sh` (fixed). Owner: "1-3 + maven-settings": a skipped compile reaches the
    outcome (`compiled`, `notCompiled`; FAC-A03); a first compiler error outside the seeder's edit is named so, not as
    the plant's; this note's "behaves as before" qualified; `maven-settings.xml`'s header names both callers. 5 more
    mutations caught.
  - Review round 2 (`/review 17`): general APPROVE, architecture NEEDS_HUMAN (Owner-only paths only), every round 1
    finding resolved, no blocking. Owner: "popraw": a first error in another module than the plant's is tested too.
  - Rule gap (architecture): `audit.md` does not say that rows before this step may have been measured on a plant that
    did not build (`docs-after-p17`). Recorded here, no item.
  - #0-181 stays In progress until AC3 (P-17 on `fc368943`, a new run id).
- **AC3 (2026-10-31, `docs-p17-r2`, blind, scanned clean):** the plant compiled; docs caught and blocked it under DOC-11
  at line 266, inside the seeder's edit, with no hand reading (`onlyAtAlso` empty); general and architecture also
  caught it. Row and note in `.ai/audit/benchmark/results.md`.

### 0-182. The k8s reviewer's guard lets `kubectl kustomize` and `kubeconform` take any option

**Type:** security · **Priority:** High · **Status:** Done, PR #547 (kept for the decision history: B after two
review rounds bypassed the guard, ADR-0045). Found by
security in review round 2 of #0-115's `k8s.md` (2026-10-27), as a non-blocking finding on code that change did not
touch.
**Autopilot:** human-only · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/hooks/readonly-bash.sh, .claude/hooks/test-hooks.sh, .claude/agents/review-k8s.md,
.claude/settings.json, .claude/settings.autopilot.json, .github/scripts/test-hook-entries.sh),
.ai/rules/review/factory.md (owner), security (README "Infrastructure Hardening")

**Problem.** `readonly-bash.sh --k8s` (lines 79-81) lets `review-k8s` run `kubectl kustomize` and `kubeconform` as
soon as the first words match, with any further argument. The hook already refuses pipes, chaining, redirects,
substitutions and `--output` for every mode, but not these tools' own options:
- `kubectl kustomize -o <file>` writes a file;
- `kubectl kustomize --enable-alpha-plugins --enable-exec` runs the program a kustomization of the reviewed branch
  names (an exec plugin or a KRM function), and `--load-restrictor LoadRestrictionsNone` reads outside the directory;
- a remote resource in a kustomization, or `kubeconform -schema-location <url>`, fetches from the network.

The reviewer reads a change it did not write, so text in that change can steer it into such a call. Since #0-115's
`k8s.md` the reviewer also runs on every `/seed-bugs` branch, not only when a change touches its paths.
`.ai/rules/review/factory.md` FAC-S03 covers a wildcard allow rule over a command with such an option, but not a
hook mode that passes a whole command (the reviewer's `ruleGap`).

**Approach (to analyse).**
- Allow only the forms CI runs: `kubectl kustomize <dir under k8s/>` with no option, and `kubeconform` with only
  `-strict`, `-summary`, `-kubernetes-version <ci.yml's KUBERNETES_VERSION>`, `-schema-location <ci.yml's pin>` and
  `-` (stdin cannot reach it: one command per call, no pipe), or a file under `k8s/`; or drop `kubeconform`, since
  K8S-03 is now "Enforced by" validate-k8s-manifests and the reviewer need not run it.
- Remote resources: refuse `kubectl kustomize` on a tree whose kustomization names a URL, or accept that the render
  fetches and record it.
- FAC-S03 names hook modes too (the owner's `factory.md`).

**Decided (owner, 2026-10-27).** B: no reviewer runs `kubectl` or `kubeconform`. The `--k8s` mode of
`readonly-bash.sh` is gone, `review-k8s` joins the plain read-only twin in both settings files, its frontmatter runs
the plain hook, and the hook now refuses a mode it does not know (FAC-S04), so a stale `--k8s` fails closed. The
reviewer reads the manifests as files; CI renders every overlay and validates it (K8S-03), and its checks read the
renders (K8S-04, K8S-20…K8S-24). Neither `Bash(kubectl kustomize *)` nor `Bash(kubeconform *)` is on the autopilot's
allow-list any more (the devcontainer has no kubectl either). A render of a tracked-only snapshot with no network is
#0-183, should the owner's manual review want the render back. Recorded in ADR-0045 (review round 3).

How it came to B, for the record:
- `/research` chose A + E2: an allow-list of `kubectl kustomize`'s forms (`kustomize_unsafe`, on `git_grep_unsafe`'s
  model) and a refusal of `://`. Tested first on kubectl 1.36.1 (kustomize 5.8.1): `-o` wrote a file,
  `--enable-helm --helm-command <program>` ran it, `--load-restrictor LoadRestrictionsNone` read outside the root,
  and with no option at all a root above `k8s/` (`.`, a symlink in `k8s/` to `..`) or a base outside it
  (`../../docker` with a kustomization of the branch there) printed a gitignored `docker/.env`.
- Review round 1 found, each confirmed by a test: the shell expands a leading `~+` (a root symlink `~+` -> `k8s`
  made `~+/docker` pass), YAML decodes `"\u002e\u002e/…"` (the escaped path printed the secret), kustomize clones
  `github.com/o/r//dir?ref=v1` (no `://`), and the autopilot's `Bash(kubectl kustomize *)` let every other agent
  run it with no hook.
- Review round 2 found, again confirmed: bash expands `a=~` inside a word, `!!binary Li4vLi4vZG9ja2Vy` (base64 of
  `../../docker`) printed the secret, an upper-case `KUSTOMIZATION.YML` is opened on a case-insensitive APFS and was
  never scanned (it printed the secret), gitignored files under `k8s/` stay readable, and `github.com:o/r` matched
  no refused shape. The guard predicted what kustomize would read; each round found a form it missed. B removes the
  capability instead.

**Acceptance criteria.**
AC1. `test-hooks.sh` refuses `kubectl kustomize` and `kubeconform` for every reviewer, the old `--k8s` mode and any
unknown mode, and `review-k8s`'s twin refuses kubectl; Factory guards' twin check passes with `review-k8s` in the
plain twin (B, see Decided).
AC2. `factory.md` FAC-S03 covers a guard mode that passes a whole command.
AC3. README "Infrastructure Hardening" names the narrowed guard, and the gap leaves its known gaps.

### 0-186. Factory guards cannot see an agent with Bash or Edit and no guard

**Type:** security · **Priority:** Low · **Status:** Done, PR #558 (kept for the decision history and its two rule gaps). From the `/research` of #0-172 (2026-10-30): the defect-seeder
had Bash and Edit and no guard in either layer of ADR-0041, and nothing failed.
**Autopilot:** human-only · **Risk:** medium · **Complexity:** low · **Depends on:** —
**Touches:** ci (.github/scripts/check-hook-entries.rb, test-hook-entries.sh), security (README "Infrastructure
Hardening", its known gap "an agent that should have a guard but has none in its frontmatter is left to review")

**Problem.** `check-hook-entries.rb` rule 4 keeps an agent's guard and its session-level twin equal, so it fails when
one of the two layers is missing. When an agent has neither, it sees nothing (its header says so: "What it does not
see"). A new agent with `Bash` or `Edit`/`Write` in its `tools:` and no guard passes Factory guards. Only a reviewer
can catch it, and for the seeder no one did from #0-170 to #0-172.

**Approach (to analyse).** Factory guards fails an agent whose `tools:` holds `Bash` without a Bash guard in its
frontmatter (`readonly-bash.sh` or `factory-ops-bash.sh`), or `Edit`/`Write` without `write-scope.sh`. The agents the
autopilot's denies and session-wide hooks guard instead (implementer, implementer-light, picker, shipper) are named in
the check, each with its reason.

**Acceptance criteria.**
AC1. Factory guards fails an agent with Bash, or with Edit or Write, and no guard of that kind in its frontmatter,
unless the check names it with a reason. Shown by test cases.
AC2. README's known gap sentence goes.

**Decided (owner, 2026-10-30: option A of the `/research`).** Rule 6 of `check-hook-entries.rb`, on the model of
`check-web-access.sh`'s rule 1 (only the verifier may hold WebFetch), and in the parser that already reads every
agent's frontmatter rather than a second script (ARC-02):
- Bash in `tools:` needs `readonly-bash.sh` or `factory-ops-bash.sh` on a matcher with Bash.
- Edit, Write, MultiEdit or NotebookEdit need `write-scope.sh` on a matcher with each of them, so a guard on `Write`
  alone leaves an `Edit` agent failing.
- No `tools:` means every tool.
- The exceptions are named in `UNGUARDED`, each with its reason: implementer, implementer-light, picker and shipper,
  bounded by the autopilot session's denies and session-wide guards. An exception for no agent, or for one that has
  its guards after all, fails.
- Tested in `test-hook-entries.sh`, 5 mutations caught. ADR-0041 amended. README's known gap now names the residual:
  in an interactive session those four have no guard of their own.
- Rejected:
  - B, a separate script: a second frontmatter parser.
  - C, a frontmatter guard for the four: a second list of the protected paths in a hook. It changes how they run in
    the owner's session, and is a decision of its own.
- Review round 1, no reviewer blocking but docs (owner: "tak" on 1-7):
  - ADR-0041's "Not covered" no longer says an unguarded agent is the reviewer's to catch (docs, blocking);
  - the amendment names the script's rule numbers, and the index row the new rule (architecture);
  - the message reads "has no …";
  - a tool with a specifier (`Bash(git:*)`) counts as that tool, and a `tools:` naming none as every tool (security,
    architecture);
  - two definitions with one `name:` fail, since the twins and the exceptions are keyed on it (security);
  - a test for a Bash guard on a matcher without Bash (architecture);
  - README's residual says the session's own denies and hooks still apply (docs);
  - `factory.md` FAC-A04's "Check:" drafted for the owner.

- Review round 2: docs' blocking finding resolved (docs APPROVE, architecture NEEDS_HUMAN, protected paths only).
  Owner: "popraw". ADR-0041's "rule 3" names the script's rule 4; the header is rewrapped; a string `tools:` is split
  on commas outside a specifier. The old split already read `Bash(a, b)` as Bash, and its extra name changed no
  outcome, so no test can tell the two apart (its mutation survives).

**Also (review round 1, rule gaps, not in this item).**
- An agent whose `tools:` hold `Agent`/`Task` (or an MCP tool) could start a subagent with Bash or file tools outside
  its own guards. None has one today, and no rule asks for a reason (security).
- A skill or command whose `allowed-tools` pre-approves Bash or a file tool in a forked context is not read by
  rule 6, which reads `.claude/agents/` only (architecture).

### 0-187. SEC-31 is weighed by what a log line holds today, not by what it is built from

**Type:** security · **Priority:** Medium · **Status:** Done, PRs #555 and #556 (kept for the decision history: the
rule's three wordings across two review rounds, and the throwable split out to #0-188). From #0-179's blind re-run of
P-04 (`sec-p04-blind` on `aace4118`, 2026-10-30).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** .ai/rules/review/security.md (owner), .ai/audit/benchmark/results.md (the re-run's row)

**Problem.** In `sec-p04-blind` the seeder made `UnrecordedTenantHandler`'s 403 refusal log append `e.getMessage()`,
which holds the SQL and its values. security found it under SEC-31, called it non-blocking and approved. Its reason:
auth-service binds `?` placeholders, so the message holds only the slug-checked tenant id today, and bound secrets
would reach the log only once JDBC batching is turned on. SEC-31 says a raw payload reaches no log line, and its
"Check:" names "a new log statement … built from … a payload". The reviewer weighed today's values instead of applying
the rule. That is the failure GEN-08's "Check:" was sharpened for after P-15 ("a removed assertion is weakened even
when other tests still pin the behaviour", #0-115). Told the pattern, `sec-after-p04` had blocked it.

**Approach.** SEC-31's "Check:" says that the line is the finding, whatever its values are today. A log line or
message built from an exception's message, a request or a payload breaks the rule even when nothing secret is in it
now: the next change that binds a value makes it a leak, and no review of that change looks at this line. Then run
P-04 again on `aace4118`, blind (a new run id, started the #0-179 way, scanned).

**Acceptance criteria.**
AC1. SEC-31's "Check:" says a line built from an exception message, a request or a payload is the finding whatever it
carries today (owner's file).
AC2. P-04 runs again blind, and its row lands beside `sec-p04-blind`'s, blocked or not.

**Progress.** AC1 (owner, 2026-10-30): SEC-31's "Check:" now says such a line is the finding whatever it carries
today. AC2 follows the merge: the reviewers read the rules from `origin/main`, and `seed-branch.sh` starts from a
clean `main`. Then P-04 runs again on `aace4118`, blind, as `sec-p04-blind-r2`, and its row lands in its own pull
request, as P-15's re-run did after GEN-08 (#0-115).

Review round 1 (security, architecture): the first wording kept "a credential, a request or a payload" as its
sources, so a reviewer still had to read `e.getMessage()` as a payload, the step `sec-p04-blind` missed. Read
broadly, it also made the platform's usual `log.warn(…, e.getMessage(), e)` a finding (33 main files hold
`getMessage()`). The owner's second wording names the message of an exception the platform did not write as a
source, and keeps the platform's own content-free exceptions out of it. Its fix is the one `KafkaFailures.reason`
and `describe` already apply (#0-96). The throwable passed to a logger is left to #0-188, a decision for the whole
platform rather than for a review rule.
Review round 2: "a message the platform did not write", so a platform exception that wraps a foreign message counts
(architecture). The carve-out for the logged throwable stops where the change itself puts a credential into what the
exception quotes (security). For example, a key in a URL's query: `RestTemplate`'s I/O error names the URL in its
message (`spring-web` 6.2.19, read in the session).
AC2 done (2026-10-30): `sec-p04-blind-r2`, blind and scanned clean, is caught and blocked by security under SEC-31,
on the same plant at the same line that `sec-p04-blind` approved. Its row is in `.ai/audit/benchmark/results.md`.

### 0-194. The autopilot's preflight does not refuse a session outside the devcontainer or without its settings

**Type:** security · **Priority:** High · **Status:** Done, PR #605 (ADR-0052). Found 2026-11-01: `/backlog-autopilot`
was started in the owner's host session (macOS, plain `claude`, auto mode), not as `docs/ai-factory.md` "Running it"
says. Kept in full as the record of the cases, the spike and the decision, which ADR-0052 and the preflight refer to.
**Autopilot:** human-only · **Risk:** medium · **Complexity:** low · **Depends on:** —

**Second case (2026-11-01, #0-192, run `wf_a2e7e1c8-3d2`).** Started in the devcontainer, but in a session not
started with `settings.autopilot.json`: the preflight passed, the run went through plan, implementation, the gate, the
panel and the verifier (24 minutes, 20 agents), and only the shipper found it had no Bash: no draft PR, the item's
BLOCKED state left uncommitted in the tree. Such a session cannot resume the run either: in `dontAsk` only
`Workflow(backlog-autopilot)` by name is allowed, not a `scriptPath` call. The owner re-ran it as a `branch` run
(`wf_980f0ed3-0b4`, after `git switch main` for the preflight), which shipped PR #576. AC2 would have refused it
before the first agent.

**Third case (2026-11-06, #0-197, run 20261106-214213, `wf_0a53ed01-13c`).** Started in the devcontainer, with
`settings.autopilot.json`, but in a session started at 20:27Z, before PR #589 (merged 21:40Z) changed that file's
`cp` allow rule. Claude Code reads the agent definitions as they change on disk, the settings only when a session
starts: the picker followed the new `picker.md` (`cp` of named files) under the old rule (`cp -r` only) and was
refused, and answered `none`; the empty branch and an empty `.ai/work/0-197` were left for the owner. In the same
session the picker's Grep tool was missing ("No such tool available: Grep"), though `picker.md` lists it. That was
not the stale session (corrected 2026-11-12, from the transcripts): the next run's picker, in a fresh session
(20261106-214534, `wf_fa3d791c-5a0`), lost it too, as has every agent with Bash that called Grep in an autopilot run
(#0-223), so only the `cp` refusal is this item's. The preflight cannot see the stale settings: what it would need
is the session's
settings as loaded, compared with the base commit's (e.g. a hash of `settings.autopilot.json` set in its `env` and
checked against the file, a third signal for AC2).

**Problem.** The run was stopped only by chance: `preflight.sh` refused it for `.claude/settings.local.json`, an open
`autopilot-stop` issue and Docker being off. None of its refusals checks where it runs or how the session was started.
On the host, with a clean `main`, Docker up and no personal settings file, the autopilot would start:
- outside the devcontainer's firewall, with the owner's files, credentials and network (`docs/ai-factory.md`, the
  "Devcontainer + firewall" row of the controls table);
- under the owner's identity: the owner's git config and `gh` token, not the bot's (`devcontainer.json` sets the bot's
  `GIT_*` only in the container, #0-113), so its PR would be the owner's and the `human:*` labels meaningless;
- without `settings.autopilot.json`: no `dontAsk`, none of its deny rules or `--agent` hook entries, and the limits it
  sets (`FACTORY_MAX_BLOCKED`, `FACTORY_AUDIT_EVERY`, `FACTORY_MAX_MERGES_PER_DAY`) fall back to `preflight.sh`'s
  defaults without a word.

**Approach (to decide).** Two refusals, each from a signal only the intended setup gives:
1. Not in the devcontainer: e.g. a variable set only by `devcontainer.json` `containerEnv` (a new one, such as
   `FACTORY_DEVCONTAINER=1`), the working directory being `/workspace`, or the firewall's own test (a host off its
   allow-list is unreachable, as `init-firewall.sh`'s self-test checks with `example.com`). The firewall test is the
   strongest (it is what the container is for) but costs a network timeout on a correct run.
2. Not started with `settings.autopilot.json`: a variable its `env` sets (the three limits today, or a new
   `FACTORY_AUTOPILOT_SETTINGS=1`), and no default in `preflight.sh` for the limits once it is required.
A signal can be set by hand, so this guards against a mistake, not an adversary; that is the gap it closes.

**Acceptance criteria (draft).**
AC1. `preflight.sh` refuses to start outside the devcontainer, naming the signal it missed; `test-preflight.sh` shows
     it.
AC2. It refuses a session not started with `settings.autopilot.json`, or started with settings that differ from the base commit's `settings.autopilot.json` (#0-194's third case; the mechanism is decided in #0-194's analysis: a file cannot carry its own hash), and the limits have no silent default; `test-preflight.sh` shows each refusal. (R-2026-11-11-pipeline-01)
AC3. A correct run in the devcontainer starts as today.
AC4. `docs/ai-factory.md` "Running it" and README "Infrastructure Hardening" name the new refusals.

**Decided (owner, 2026-11-12, after `/research 0-194` and a spike; ADR-0052).**
- AC1 checks the properties the devcontainer gives, not only a marker:
  - `FACTORY_DEVCONTAINER=1` (`containerEnv`);
  - the bot's identity: `FACTORY_BOT_LOGIN` against `GIT_AUTHOR_NAME`, `GIT_COMMITTER_NAME` and `gh api user`, and
    the two `GIT_*_EMAIL` against its noreply address;
  - the firewall: `example.com` must be refused. Only curl's 6, 7 and 28 pass. Its REJECT costs 6 ms.
- AC2's mechanism: `settings.autopilot.json` carries `env.FACTORY_SETTINGS_SHA256`, the sha256 of that file's
  `jq -cS` without that field and of `settings.json`'s (`scripts/factory/settings-hash.sh`). The preflight compares
  the session's value with main's files after its fast-forward. Factory guards' `check-settings-hash.sh` keeps the
  field equal to the files.
- `/review 1267` round 1, all non-blocking, all taken: `settings.json` added to the hash, which
  `settings.autopilot.json` alone left out; the email check; curl's exit codes narrowed; tests for the order against
  the fast-forward, a missing curl and settings that cannot be hashed; the stale defaults in `preflight.sh`'s header;
  jq's printing noted.
- Round 2, non-blocking: the noreply address now needs digits only before the `+` (a glob let `1x+…` through);
  ADR-0052 names the container user's `~/.claude/settings.json` and managed settings as not hashed (an older gap)
  and why curl's exit 6 still passes.
- Rejected: a SessionStart hook writing to `CLAUDE_ENV_FILE`. The docs do not say subagents see it, or that hooks of
  a `--settings` file run, and it would refuse a session after any fast-forward if settings ever reload.
- The spike (devcontainer, Claude Code 2.1.295, `claude -p`) showed that a rule and an `env` value changed in the
  `--settings` file mid-session did not apply, and that the file's `env` reaches a subagent's Bash.
- AC3 is shown in a clone in the devcontainer where the change is `main`. A `--settings` session ran the preflight
  through factory-ops and got `ok: true` with no reasons. The same clone without the settings refused with the four
  missing values. A host clone refused for the devcontainer, the bot login and the firewall.

**Touches:** `scripts/factory/preflight.sh`, `scripts/factory/settings-hash.sh` (new),
`.github/scripts/test-preflight.sh`, `.github/scripts/check-settings-hash.sh` (new),
`.github/workflows/factory-guards.yml`, `.claude/settings.autopilot.json` (`env`), `.devcontainer/devcontainer.json`
(`containerEnv`), `docs/ai-factory.md`, README "Infrastructure Hardening", `.ai/decisions/0052-…`,
`.ai/decisions/README.md`.

### 0-195. The workflow does not check the branch prefix the picker gives an item

**Type:** ci · **Priority:** Medium · **Status:** Done, PR #609 (kept for the four cases and the decision). Found
2026-11-01 in run `wf_8c632098-97c` (#0-175); Medium since 2026-11-04 (owner): four cases, the fourth cost a run.
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —

**Problem.** `picker.md` ("Prepare the branch") names the prefix by the item's type (`bug`/`security` → `fix/`,
`tech-debt` → `refactor/`, `ci` → `ci/`, `docs` → `docs/`, otherwise `feat/`). For #0-191, a `security` item, the
picker made `feat/0-191-deny-by-default-tests`. `backlog-autopilot.js` checks the branch only against
`^[a-z]+/<item>-[A-Za-z0-9._-]+$`, so any prefix passes. The prefix is what Conventional Commits, the PR's title and a
reader of the branch list go by; a wrong one misleads, it breaks nothing.

**Second case (2026-11-01, #0-192, a `security` item).** The picker made `feat/0-192-deny-by-default-three-services`,
committed `chore(factory): start backlog #0-192` on it, then switched to `fix/0-192-…` at the same commit and worked
there (reflog); the `feat/` branch was left behind locally. A `branch` run also records no scope: PR #576 says
"Scope: not-measured — Touches none · plan none" though #0-192 has a Touches line: it skips the plan, and
`backlog-autopilot.js:682` takes the Touches from `next-item.sh`'s answer (`next?.modules`), which a `branch` run does
not ask for.

**Third and fourth cases (2026-11-04, both `security`).** Run 20261104-123011 (`wf_8eec043b-6b8`) made
`feat/0-198-ingestion-route-walk-shape` and shipped PR #587 from it (merged; #0-196, the same kind of item, had got
`fix/` the day before). Run 20261104-135720 (`wf_da30d2f5-240`) made `feat/0-197-auth-walks-literal-exempt-set`,
noticed the prefix and tried `git branch -m fix/…` twice: `dontAsk` refused it (only `git switch *`,
`git checkout -b *` and `git branch --list *` are allowed), the picker answered `none`, and the empty `feat/` branch
was left for the owner to delete (it would have locked #0-197 for the next run, `picker.md` step 3). So a wrong
prefix is no longer only misleading: corrected by the agent, it ends the run. `picker.md` now says the `security` →
`fix/` row in words and that a created name is final (#0-207); that is a prompt, the check below stays the fix.

**Approach.** The workflow knows the type (the picker answers it, `PICK.type`; `next-item.sh` could read it from the
base commit as it reads risk and complexity): it derives the prefix with `picker.md`'s table and stops the item when
the picker's branch has another, before `state.sh branch` records it. The table then lives in the workflow, and
`picker.md` points to it, so the two cannot drift.

**Decided (owner, 2026-11-12, `/research`).** Not the check above but the prefix in code: a check would stop the
item on every wrong prefix, and four runs got it wrong. One table, `BRANCH_PREFIX_OF` in `_backlog.sh`, maps the
`**Type:**` read from the base commit to the prefix (`performance` → `perf/`, new; `design` and a type not listed have
none, so a misspelt type stops the item before it starts instead of getting `feat/`). `next-item.sh` hands it to the
workflow, which names the branch `<prefix>/<item>-<slug>` with the picker's `slug`; a `branch` the picker answers
outside resume is not used; `start-item.sh` refuses another prefix. On resume the branch is the owner's, as given. The
missing scope of a `branch` run (second case) is #0-226.

**Acceptance criteria.**
AC1. Outside resume the branch is `<prefix>/<item>-<slug>` with the prefix next-item.sh reads from the item's
     `**Type:**` on the base commit, whatever branch the picker answers; a missing prefix or an unusable slug stops
     before anything is created (tests in `test-autopilot-workflow.mjs`).
AC2. One table of prefixes (`_backlog.sh`); `picker.md` holds none; `next-item.sh` does not choose an item whose type
     has none, and `start-item.sh` refuses a branch with another prefix (tests in `test-queue.sh`,
     `test-start-item.sh`).

**Touches:** factory (.claude/workflows/backlog-autopilot.js, .claude/agents/picker.md, scripts/factory/_backlog.sh,
scripts/factory/next-item.sh, scripts/factory/start-item.sh, .github/scripts/test-autopilot-workflow.mjs,
.github/scripts/test-queue.sh, .github/scripts/test-start-item.sh), docs (ai-factory.md), root (BACKLOG.md,
.ai/decisions/0051).

### 0-207. The picker spends its turns on commands its session refuses

**Type:** ci · **Priority:** Medium · **Status:** Done — AC1 (PRs #588, #589), AC3 and AC4 (PR #593), AC2 the
pickers of runs 20261106-214534 (PR #590) and `wf_f965afb4-b5e` (PR #601, 2026-11-11; "Closing run" below). Kept in
full as the record of the command forms and why each is what it is, which the agent definitions and ADR-0050 refer to.
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/agents/picker.md, .claude/agents/implementer.md, .claude/agents/implementer-light.md,
.claude/agents/shipper.md, .claude/agents/defect-seeder.md, .claude/settings.autopilot.json, .claude/hooks/_lib.sh,
.claude/hooks/test-hooks.sh, .claude/workflows/backlog-autopilot.js), ci (.github/scripts/check-agent-commands.rb,
.github/scripts/test-agent-commands.sh, .github/workflows/factory-guards.yml), docs (docs/ai-factory.md), security
(README "Infrastructure Hardening", .ai/context/security.md), root (BACKLOG.md, .ai/decisions/0050-…, .ai/decisions/README.md)

**Seen.** The picker composes commands that its autopilot session refuses, then rewrites them one at a time:
- run 20261104-123011 (#0-198, `wf_8eec043b-6b8`): four calls refused by `guard-protected-bash.sh` (`git show … |
  grep …`, `grep … ; git branch …`, `grep … && cat …`), then `git switch -c … && mkdir -p … && cp … && sed -i …` and
  `mkdir -p /workspace/.ai/work/0-198` refused in `dontAsk` (a chain, and an absolute path the rule
  `mkdir -p .ai/work/*` does not match). It went on only because it wrote the three work files with the Write tool;
- run 20261104-135720 (#0-197, `wf_da30d2f5-240`): the same four guard refusals, then `git branch -m` twice and
  `mkdir -p /workspace/.ai/work/0-197 && cp /workspace/.ai/work/_template/* …` refused in `dontAsk`, and it answered
  `none` (#0-195's fourth case).
The session in the container that started the second run read the refusals as a wrong permission mode and told the
owner to switch it back; `dontAsk` was right (the same misreading as on 2026-11-03, when a picker's chained and
`git -C` commands left two runs with no item). The guard's message also misleads: a `git show … | grep …` is refused
as "git grep: a command separator or redirect" (`_lib.sh:162`, reached through `git_grep_unsafe`).

**Problem.** `picker.md` named what to do ("copy the three files", "read the backlog on the base commit") but not the
command forms the session allows, so the model picks its own (a pipe to cut a 400 KB `git show`, absolute
`/workspace/…` paths, one chained command for a whole step). `defect-seeder.md` was fixed the same way for the same
cause (#0-170: "one command per call, no `git -C`, no separators; Read and `git grep` to look"); the picker, the
implementers and the shipper have no such paragraph.

**Done in this PR (owner's copy of the draft).** `picker.md` gets a "How commands run here" section (one plain
command per call, relative paths, Grep/Read/`git grep` to look, Write to create, a refused command answered `none`
with the refusal verbatim) and names each command it needs in its allowed form: `git grep -n -A12 '^### <n>\.'
<base sha> -- BACKLOG.md`, `git grep -c '^| <n> |' <base sha> -- BACKLOG-DONE.md` (the Done row, not the bare
number: `'0-19'` counts 7 lines today, the rows of `0-190`…`0-199` among them, the row form 1), `ls .ai/work/<n>`
(a work directory left by an aborted run stops the item, as a stale branch does; skipped in resume mode, where both are
the run's own), `cp -r .ai/work/_template .ai/work/<n>`, `git add` and `git commit -m … -m …` as two calls, and in
resume mode the `git switch <branch>` of its task; and that a created branch name is final. Every one of those commands
was run through `guard-protected-bash.sh` with `agent_type` picker and passed (exit 0); a piped `git show` was refused
(exit 2). Review round 1 (`/review`, 2026-11-04) added the row form, the work-directory check and the resume line.
Review round 2 (2026-11-05) added that resume mode skips "Prepare the branch" as a whole (step 2 there rested on a
check resume skips, so a literal reading copied the template into the existing directory), and named the
work-directory check a second safeguard: `.ai/work/` is tracked, so the preflight refuses a tree with a leftover
directory first. Every command form was run through the guard again after round 1 (exit 0; the piped control exit 2).
That a refused command ends as `none`, which leaves no state record, is #0-206's second case.

**Third case, after that PR (2026-11-06).** Run 20261106-203806 (#0-197, `wf_d0dcbd83-5d4`), the first after PR
#588: every command of the new section passed up to `git switch -c fix/0-197-auth-walks-literal-exempt-set`, then
`cp -r .ai/work/_template .ai/work/0-197`, the form `picker.md` prescribed, was refused in `dontAsk`, and the picker
answered `none` (the empty branch was left for the owner, who deleted it). The rule `Bash(cp -r .ai/work/_template *)`
matches that command as text; Claude Code (2.1.295) does not let an allow rule run a recursive `cp`. Shown in a
throwaway repository in the devcontainer, `dontAsk`: `cp -r` refused under `Bash(cp -r .ai/work/_template *)`,
`Bash(cp -r .ai/work/_template .ai/work/*)`, `Bash(cp -r *)` and `Bash(cp:*)` (with `Edit` and `Write` allowed too);
a `cp` of files, no `-r`, runs under `Bash(cp:*)` and under `Bash(cp .ai/work/_template/* .ai/work/*)`; a glob source
(`.ai/work/_template/*.md`) and a destination through `..` are refused. No run had ever passed that rule (#0-198's
picker wrote the files with Write). So AC1 below was shown against the hooks and the rules' text, never against the
permission check itself: the hole AC4 names, and AC4 needs more than a text match to close it.

**Done in this PR (2026-11-06, owner's copy of the draft).** `picker.md` "Prepare the branch" step 2 is three
commands: `ls .ai/work/_template`, `mkdir -p .ai/work/<n>`, one `cp` naming each listed file and ending in
`.ai/work/<n>/`, with "not `cp -r`, not a glob" and why. `settings.autopilot.json`: `Bash(cp .ai/work/_template/*
.ai/work/*)` replaces the rule that never ran. All three commands, and `cp -r` as the control, were run in the
devcontainer by `claude -p --settings .claude/settings.autopilot.json` on a clone with both drafts, `dontAsk`, with the
repository's hooks: the three ran, `cp -r` and a `..` destination were refused. Review round 1 (`/review 27`) asked
whether the rule's first `*` lets a source outside the repository through (a secret copied into the tracked, pushed
`.ai/work/`, e.g. `~/.m2/settings.xml`, which the hook's `secrets` list does not name): the same session refused
`cp .ai/work/_template/handoff.md <source> .ai/work/0-999/` for `/home/dev/<file>`, `~/<file>` and `/etc/hostname`,
so Claude Code's own path check holds there, not the hooks (#0-211). Round 1 also fixed `picker.md`'s reason for the
leftover-directory check (a copy onto it overwrites its files; "nest `_template`" was true of `cp -r` only) and named
the template copy as the one exception to "create a file with Write". Copying the template in a factory script
instead, so that no agent needs a `cp` rule, is #0-209.

**After PR #589 (2026-11-06).** Run 20261106-214213 was refused the new `cp` because its session predated the
settings change (#0-194's third case). Run 20261106-214534 (`wf_fa3d791c-5a0`, a fresh session) shipped #0-197 as
PR #590: its picker made no refused call (AC2, first of two). The other agents of that run did: the implementer 10
(a `cat … ; grep …` chain, `git ls-files | grep …`, `git -C /workspace ls-files …`, `git grep … ; git grep …`, a
`git ls-files -- '…*…'` with globs, a `f=… && sed -i …`, an `ls … && grep …` and three `./mvnw test …` with a pipe,
a redirect or `mkdir -p … &&`), the
shipper 4 (a `git status && git branch && gh pr list` chain, a `python3` heredoc to edit the backlog, a
`git rm … && git add -A …` chain and a `sed -i`), the architect and an architecture reviewer one or two each through
`readonly-bash.sh`, and `factory-ops` one: AC3's evidence for the implementers and the shipper.

**Done (2026-11-08, AC3 and AC4).** `implementer.md` and `shipper.md` get a "How commands run here" section from
the refusals of run 20261106-214534 (implementer 10, shipper 4): one plain command per call, relative paths, no
`cat`/`grep`/`sed`/`python3` (Read, Grep, Edit, Write instead), a test run as it is with the surefire report read
after, the PR body written with Write; `implementer-light.md` follows `implementer.md`. `git_grep_unsafe` names a
refused command by its first two words (`git show: a command separator…`), "git grep" only when it is one
(`test-hooks.sh`, four cases); the workflow's resume prompt names "Check the item". AC4: each of `picker.md`,
`implementer.md`, `shipper.md` and `defect-seeder.md` names its command forms in a marked list
(`<!-- commands:start/end -->`, example values), and Factory guards' `check-agent-commands.rb` (tested by
`test-agent-commands.sh`) runs every form, for each agent the list is for (implementer-light with implementer's),
through the session-level Bash hooks of `settings.autopilot.json` and the agent's frontmatter hooks in a throwaway
repository with a lock, against the allow and deny rules, and fails the families Claude Code refuses whatever the
rules say (a recursive `cp`, an absolute or `~` path, a separator, pipe or redirect outside quotes, an unquoted glob,
`..`, `git -C`, `cd`): the second branch of AC4. It found the shipper's `git branch --show-current`, which no rule
allows, before any run did. Review round 1 (`/review`, 2026-11-08): the decision is ADR-0050; the agents to check are
every one with Bash, derived from `tools:` with a named `EXEMPT` list (not a fixed list); the rules of both settings
files are read, as the session merges them; an agent of `ALSO_FOR` is checked with its own frontmatter hooks. Running
the lists through Claude Code's own check in `dontAsk` is #0-214.

**Closing run (2026-11-11, `wf_f965afb4-b5e`, #0-189, PR #601).** The first run after #0-209 and #0-215 (the picker
only reads, under `readonly-bash.sh --picker`), in a session started at 15:45Z, after the last change to
`settings.autopilot.json` (2026-11-10), Claude Code 2.1.295. The picker ran 5 commands and gave its answer, and
none was refused: AC2's second run. Its one failed call, `ls .ai/work/0-189` (exit 2, "No such file or
directory"), is the check `picker.md` prescribes answering "no leftover directory"; the hook-path risk #0-215's
review round 3 accepted did not happen. The branch it named, `refactor/0-189-…` for a `tech-debt` item, is the
table's prefix (not a #0-195 case). The other agents' failed calls, each in the transcript:
- architect, 1: `git grep -n -E "^#+ |^\*\*[A-Z]+-[0-9]+" -- .ai/rules/review/…` refused by `readonly-bash.sh
  --architect` ("a | inside quotes counts too"), the refusal #0-123 decided to keep; `architect.md` ("Tools") already
  names `-e <pattern> -e <other>`. Its next call used that form for another search and it did not list the rule ids
  again. Nothing to change.
- implementer-light, 2: the Grep tool missing ("No such tool available: Grep. Grep is not available in this session"),
  #0-223; and `./mvnw -q test -pl oncall-service -Dtest=…`, the form `implementer.md` prescribes, failing on
  "Could not find artifact com.incidentplatform:shared:jar:1.0.0-SNAPSHOT" (not refused: it ran), #0-222. It went on
  with `git grep` and with `-am -Dsurefire.failIfNoSpecifiedTests=false`.
- implementer-light (self-check performance), 1: a Read of `com/example/oncall/…` (the package is
  `com.incidentplatform`; probably taken from the example paths of `implementer.md`'s command list), followed by the
  right one. A one-off.
- acceptance-reviewer, 2: `git grep --no-index … -- /workspace/.ai/runs/0-189/tests-r1-0.log` refused ("git option
  not allowed here"), as it should be; then a Read of that log at `offset` 1400, `limit` 600 over Read's 25 000-token
  cap. Its task names `gate-r*.json` for the counts (#0-160); recorded here, a rule only if it repeats.

**Acceptance criteria (draft).**
AC1. `picker.md` names the allowed form of every command it needs; each passes `guard-protected-bash.sh` and runs in
     an autopilot session (`dontAsk`, `settings.autopilot.json`): done, this item's two PRs (the second after the
     third case above).
AC2. The next two autopilot runs' pickers have no refused call (their transcripts), or the item records which.
AC3. `implementer.md`, `implementer-light.md` and `shipper.md` get the same paragraph where their transcripts show
     refused calls (to check: the runs of #0-196, #0-198); the guard's message for a separator outside `git grep`
     names the command as it is, not "git grep" (`test-hooks.sh` shows it); the workflow's resume prompt
     (`backlog-autopilot.js:478`) names the picker's section "Check the item", not "Choose the item".
AC4. A check (a Factory guard, or a case of `test-hooks.sh`) takes every command form an agent definition prescribes
     (`picker.md`, `defect-seeder.md`; a marked list in each) and shows it passes that agent's hooks and matches an
     allow rule of `settings.autopilot.json`, so the prose cannot drift from the allow-list unnoticed (review round 1:
     today AC1 is shown by hand only). A match of the command against the rule's text is not enough (the third case:
     `cp -r` matched and was refused): the check runs each form through Claude Code's own permission check in
     `dontAsk` (e.g. `claude -p --settings .claude/settings.autopilot.json` on a throwaway clone), or names the
     command families that check overrides whatever the rules say (a recursive `cp`, a glob, `..`) and refuses them
     in the prose.

### 0-209. The picker copies the work template itself, through an allow rule

**Type:** ci · **Priority:** Low · **Status:** Done, PR #595 (kept for the decision history: options (a)/(b)/(c) and
review round 1's one parser of the backlog). From #0-207's third case (2026-11-06).
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** factory (scripts/factory/start-item.sh, scripts/factory/next-item.sh, .claude/workflows/backlog-autopilot.js, .claude/agents/picker.md,
.claude/settings.autopilot.json, .github/scripts/test-autopilot-workflow.mjs, .github/scripts/test-start-item.sh,
.github/scripts/test-queue.sh, .github/scripts/check-hook-entries.rb, .github/workflows/factory-guards.yml), docs (docs/ai-factory.md, .ai/README.md, .ai/rules/audit.md), root (README.md,
BACKLOG.md)

**Problem.** Creating `.ai/work/<n>` is a fixed step with one right result, yet the picker does it with commands it
composes, under an allow rule: `Bash(cp .ai/work/_template/* .ai/work/*)` (#0-207) and `Bash(mkdir -p .ai/work/*)`.
The first form it was given, `cp -r`, was refused by Claude Code whatever the rule said and stopped a run; the current
form names the template's files in `picker.md`, so a file added to `_template` is copied only because the picker lists
the directory first; and the `*` of both rules accepts any argument, held back only by Claude Code's own path check (a
`..` destination is refused today) and the hooks' heuristics. A script would take the item id, check it
(`^0-[0-9]+$`), refuse an existing directory, copy the whole template and answer JSON, and the `cp` rule would go.

**Why it is not a picker command.** `guard-factory-scripts.sh` lets only `factory-ops` run `scripts/factory/`
(backlog #0-131), so the workflow has to call it: (a) `ops('start-work-dir.sh', [item])` after the picker has created
the branch and before its commit, which splits the picker into two calls; or (b) before the picker, on `main`, which
leaves an untracked directory behind when the picker answers `none` (`return-to-main.sh` and the preflight would then
have to clean or refuse it). To decide; each needs cases in `test-autopilot-workflow.mjs`.

**Decided (owner, 2026-11-09): neither, (c).** (a) splits the picker into two sessions with state between them and
leaves `git switch -c`, the edits and the commit as commands the session can refuse; (b) creates the directory before
the item is checked and needs a cleanup path in `return-to-main.sh`. (c): the picker only checks the item and names
its branch, and the workflow runs `scripts/factory/start-item.sh <base sha> <item> <branch> <run id>` through
factory-ops after the picker's answer and before `state.sh branch`. The script does the whole start, in the model of
`seed-branch.sh` (ADR-0044): it refuses anything but a clean main at the base commit, a branch or work directory that
exists, an item not ready or not Open on that commit (its fields read by `backlog_json`, the parser `next-item.sh`
uses, which now skips an item that is not Open too: review round 1, where a parser of the script's own counted the
fields quoted in an item's text and would have refused this item); then the branch, the whole template
(`cp -R`, a new template file included), progress.md's title and a `[start]` line, the status field, one commit
(`chore(factory): start backlog #<item>`, no `Co-Authored-By`: code wrote it, #0-212); a refusal after the branch
exists removes the branch and the directory. A failed start stops the item at `pick`, recorded and notified, like a
failed picker. The picker loses Edit and Write, its `git switch -c`/`mkdir`/`cp`/`git add`/`git commit` forms, and the
two allow rules go. Resume mode is unchanged (the picker switches to the owner's branch; no start).

**Acceptance criteria.**
AC1. `start-item.sh` starts an item as above and answers `{ok, branch, workDir, head}`; each refusal answers
     `{ok:false, reasons}` and leaves a clean main with no branch and no work directory
     (`.github/scripts/test-start-item.sh`, in Factory guards).
AC2. The workflow calls it once, after the picker and before `state.sh branch`, never on resume, `none` or `failed`;
     a refusal, an untyped answer or no answer stops the item at `pick` with no branch in the lock
     (`test-autopilot-workflow.mjs`).
AC3. `picker.md` creates nothing (tools Read, Grep, Glob, Bash; its command list passes `check-agent-commands.rb`),
     and `settings.autopilot.json` has no `mkdir -p .ai/work/*` or `cp .ai/work/_template/*` rule.
AC4. The start and the choice read an item the same way: `start-item.sh` takes its fields from `backlog_json`, so
     text that quotes them counts for nothing, and `next-item.sh` skips a ready item that is not Open
     (`test-start-item.sh`, `test-queue.sh`).

### 0-215. The picker writes nothing, yet its Bash may still write

**Type:** ci · **Priority:** Low · **Status:** Done, PR #596 (kept for the decision history: option A rejected for
B, the resume's switch in code). From the review panel of #0-209 (security and architecture, round 1, 2026-11-09).
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** factory (.claude/agents/picker.md, .claude/hooks/readonly-bash.sh and its tests, .claude/settings.json,
.claude/settings.autopilot.json, .github/scripts/check-hook-entries.rb and test-hook-entries.sh,
scripts/factory/resume-item.sh, .github/scripts/test-resume-item.sh, .github/workflows/factory-guards.yml,
.claude/workflows/backlog-autopilot.js and test-autopilot-workflow.mjs, docs/ai-factory.md, .ai/decisions/), root
(README.md)

**Problem.** Since #0-209 the picker only reads: it checks the item and names its branch, and `start-item.sh` starts
the item. On resume it runs one `git switch <branch>`. It has no file tool, but its Bash has no guard of its own: it is
one of `check-hook-entries.rb`'s `UNGUARDED` agents, bounded only like the implementer, so the autopilot's allow rules
(`git switch *`, `git checkout -b *`, `git add *`, `git commit *`, `git push -u origin *`, `gh pr create *`,
`./mvnw *`) hold for it too. It reads text an outsider can write (PR titles, through `gh pr list`). A picker that
still runs `git switch -c` would also leave a branch that locks the item, which `start-item.sh` then refuses with
"not on main", without naming that branch.

**Proposed (first draft).** `readonly-bash.sh` in the picker's frontmatter and as its session-level twin in both
settings files, with a mode that also allows `git switch <branch>` of the resume's branch only, and the picker out of
`UNGUARDED`.

**Decided (owner, 2026-11-10): the switch is code too (option B, ADR-0051).** A hook cannot know the resume's branch
(`args.branch`), so a `git switch` it allows could only be checked for its shape: another item's branch would pass, and
the workflow checks the branch the picker answers, not where HEAD is. So the workflow switches before the picker
(`scripts/factory/resume-item.sh <base> <branch>`, through factory-ops, as `start-item.sh` starts an item since #0-209)
and the picker's mode allows no git write at all. Rejected: option A, the first draft above.

**Acceptance criteria.**
AC1. The picker's Bash runs under `readonly-bash.sh --picker` (frontmatter and the `--agent picker --picker` twin),
     which allows read-only git, `gh pr list` in the one form `picker.md` names (matched whole) and
     `ls .ai/work/0-<n>` that resolves to itself (no symlink in any part), only; `test-hooks.sh` shows `git switch` (with and without `-c`),
     `git commit`, `git push`, `gh pr create`/`view`, other `gh pr list` forms (`-w=true`, `-R`, `--search`) and other
     `ls` forms refused for the picker.
AC2. `UNGUARDED` no longer names the picker, and `check-hook-entries.rb` and `check-agent-commands.rb` pass (the
     picker's list goes through its new guard; its dependency check matches the row as `'^[[:punct:]] 0-<n> [[:punct:]] '`,
     as the guard refuses a `|` even inside quotes).
AC3. On resume the workflow runs `resume-item.sh` once, before the picker, and never on a fresh run: a branch that is
     not an item's, or an `item` that is not the branch's, is `NOT_STARTED` before anything moves; a refusal or a wrong
     answer stops the item at `pick`, recorded against the branch's item and notified, with the picker not called;
     `test-resume-item.sh` shows every refusal leaving the tree as it was.

### 0-220. The pipeline audit's data attaches the wrong `/ready` PR to a case

**Type:** ci · **Priority:** Medium · **Status:** Done, PR #612 (kept for the owner's decisions on AC2 and AC3). From the pipeline audit 2026-11-11 (R-2026-11-11-pipeline-02:
PR #581 got #582).
**Touches:** ci (scripts/factory/audit-data.sh, scripts/factory/_backlog.sh, .github/scripts/test-audit-data.sh),
root (.ai/rules/audit.md, .ai/rules/acceptance.md), factory (.claude/agents/audit-pipeline.md, .claude/skills/ready/SKILL.md)

**Problem.** `ready_of` (`scripts/factory/audit-data.sh`) attaches the newest merged `docs/backlog-ready-<item>` PR,
whatever the run's date: PR #581 (BLOCKED 2026-11-02T11:47Z) got #582 (merged 12:16Z, with the corrected criteria)
instead of #578, the `/ready` on its base. An item readied on another item's branch gets no `/ready` PR at all
(#0-200 on `docs/backlog-ready-0-199`; #0-197 and #0-198 on `docs/backlog-ready-0-196-0-197`). And
`.ai/rules/acceptance.md` makes every `Risk: high` item `NEEDS_HUMAN`, so the case rule "acceptance other than
ACCEPT" makes each risk-high PR a case by construction (PR #583).

**Acceptance criteria.**
AC1. A case's `readyPr` is the item's newest `/ready` PR merged before the run started (its run id), not the newest
overall; `test-audit-data.sh` shows it with two `/ready` PRs, one merged after the run.
AC2. A `/ready` PR that readies an item on another item's branch is found for that item too, by the item sections its
merge changed in `BACKLOG.md` (not its title); a test shows it. Reworded by the owner (2026-11-12, `/research`): the
titles of the real PRs name items they only add as not-ready (#568 "add #0-193").
AC3. A risk-high PR is not a case by construction: `.ai/rules/acceptance.md` no longer makes `Risk: high` a
`NEEDS_HUMAN` (the workflow decides risk itself, `riskHigh`), so a `NEEDS_HUMAN` on one names a real reason; a test
shows both sides. Reworded by the owner (2026-11-12, `/research`, option 3C): a filter on the reason's free text would
have kept #583 a case (it named a scope creep too) and the rule a duplicate of the code's decision.

**Done as (2026-11-12).** `audit-data.sh` reads, per merged `/ready` PR, the items its merge made or changed and left
`ready` or `human-only` (`readied_items`, `_backlog.sh`; the merge commit from `gh`, the blobs from the local
history, the branch name only when the merge is not there), and bounds a case's `readyPr` by the run's start from its
PR (`Autopilot run <runId>`), the stop for a BLOCKED run without a PR, or the shipping run for an escape; each case
says which (`readyBound`: run, stop, none). On the real data #581 gets #578 (was #582), #583, the resume the next day,
#582. `acceptance.md` drops the Risk reason; `audit.md` says how to read a risk-high `NEEDS_HUMAN` from before.

### 0-223. The implementers are told to use a Grep tool their session may not have

**Type:** ci · **Priority:** Medium · **Status:** Done, PR #608 (kept for the evidence of the 31 runs, which #0-225
rests on). Found 2026-11-11 in run `wf_f965afb4-b5e` (#0-189, PR #601; #0-207 "Closing run"); the first case is
#0-194's third.
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/agents/implementer.md, .claude/agents/picker.md), root (BACKLOG.md)

**Problem.** Every agent lists Grep in its `tools:`, yet in an autopilot run an agent that also has Bash never got
it. The devcontainer keeps the transcripts of 31 workflow runs (2026-10-09 to 2026-11-11, all Claude Code
2.1.295); read on 2026-11-12, every Grep or Glob call in them:

| Agent | Bash in `tools:` | Calls | Result |
|---|---|---|---|
| picker | yes | 7 Grep, in `wf_8abc9297-e9e`, `wf_cd369594-aef`, `wf_a2e7e1c8-3d2` (2), `wf_c1597fde-23e`, `wf_0a53ed01-13c`, `wf_fa3d791c-5a0` | all "No such tool available" |
| implementer-light | yes | 1 Grep, in `wf_f965afb4-b5e` | "No such tool available" |
| audit-synthesis | no (`Read, Grep, Glob, Write`) | 2 Grep and 4 Glob, in `wf_fd96a770-4d1` and `wf_bd883dfd-e1f` | all ran |

The message in full (`wf_f965afb4-b5e`): "No such tool available: Grep. Grep is not available in this session —
search file contents with `grep` via the Bash tool instead." It is not a stale session: #0-194's third case was put
down to one, but the next run's picker (`wf_fa3d791c-5a0`) and implementer-light (a session started at 15:45Z, a day
after the last change to `settings.autopilot.json`) were in fresh ones. So it looks as if Claude Code 2.1.295 does not
give Grep to an agent that has Bash, and the message points to Bash instead. That is a reading of 14 calls, not a
documented rule; no agent with Bash called Glob, so whether it loses Glob too is not shown. Each agent went on with
Read or `git grep`. The advice in the message is wrong here: no allow rule of `settings.autopilot.json` lets `grep` run
in Bash. #0-123 settled this for the reading agents: "the Grep and Glob tools do not exist in every Claude Code
version", so `git grep` and `git ls-files` are the search, and six definitions say it (`architect.md:28`,
`acceptance-reviewer.md:20`, `planner.md`, `ready-checker.md` and the two audit analysts). Two do not:
`implementer.md:72` (and so implementer-light) names "the Grep tool (or `git grep …`)" and Glob first, and
`picker.md:37` "the Grep and Read tools". A lost Grep call costs a turn; a model that takes the message's advice
spends another on a refused `grep`.

**Approach.** Align the two with the rest, as #0-123 decided: `git grep -n -e <pattern> -e <other> -- <paths>` to
search and `git ls-files <path>` to list, with the same parenthesis. Confirming why the tool is missing (Claude
Code's documentation or a `claude -p` check of an agent with and without Bash, as #0-214 would run) is not needed for
the fix: `git grep` works either way.

**Decided (owner, 2026-11-12, `/research`).** Align the two with #0-123, and in the same sentence tell them that a
"No such tool" message suggesting `grep` via Bash does not apply (the command is refused): removing the tool's name
alone leaves the second lost turn. The picker gets no new `git grep` form for the working tree: it reads the item on
the base commit. Removing Grep and Glob from the agents' `tools:` was not taken: it reverses #0-123's choice, and
whether those tools may reach a secret is a question of its own (#0-225).

**Acceptance criteria.**
AC1. `implementer.md` and `picker.md` name `git grep` and `git ls-files` (the picker: `git grep` on the base commit)
     as the search and listing, not the Grep and Glob tools, with #0-123's reason and the sentence on the message
     that suggests `grep`; their marked command lists are unchanged, and Factory guards' `check-agent-commands.rb`
     keeps passing.
AC2. No agent definition under `.claude/agents/` prescribes the Grep or Glob tool as the one way to search or list
     (a `git grep` over the definitions, in the PR).

### 0-235. The shell guard does not see a protected runtime path removed through its parent

**Type:** security · **Priority:** Low · **Status:** Done, PR #619 (kept for the decision history: the options of
`/research`, four review rounds, the git route left to #0-236). From the security review (FAC-S03, and its rule gap) of
#0-233 (2026-11-13); approach decided by the owner after `/research 0-235` (2026-11-13), ADR-0054.
**Autopilot:** human-only · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** ci (.github/scripts/check-agent-commands.rb, .github/scripts/test-agent-commands.sh,
.github/workflows/factory-guards.yml), factory (.claude/hooks/_lib.sh, .claude/hooks/guard-protected-bash.sh,
.claude/hooks/test-hooks.sh), root (.ai/rules/review/factory.md (owner), .ai/decisions/ (ADR-0054, ADR-0050,
ADR-0053), .ai/context/security.md, BACKLOG.md), docs (README.md "Infrastructure Hardening")

**Problem.** `guard-protected-bash.sh` refuses a shell write that names a protected path. `.ai/runs/LOCK`,
`.ai/runs/state.json` and `.ai/runs/ops-calls/` (#0-233) sit under `.ai/runs/`, which is not protected (an item's own
`.ai/runs/<item>/` is the implementer's), and `.ai/STOP` under `.ai`, so a command that removes them without naming
them passes it: `rm -rf .ai/runs`, a glob, `find .ai/runs -type l -delete`, `cd .ai/runs && rm -rf ops-calls`. They are
gitignored, so no diff shows it. Without the lock `base_ref()` falls back to a ref; the marks and the breaker's count
reset. Today the allow list of `settings.autopilot.json` (`dontAsk`) holds none of these programs, so only code run
through `./mvnw` (#0-116) reaches them; but nothing checked that the allow list stays so.

**Decided (owner, after `/research`).** The allow list is the control, the guard a heuristic. Rule 4 of
`check-agent-commands.rb` (ADR-0054): every `Bash(...)` allow rule of both settings files, and of the `allowed-tools` of
a skill an autopilot agent preloads, starts with a prefix of `SAFE_PREFIXES` (a program that cannot remove or move a
path it does not name, with why), or is in `EXEMPT_RULES` with its reason (`./mvnw *`, #0-116; `scripts/factory/*`,
factory-ops only). A closed list, so a program nobody judged fails. Rejected: (a) the guard recognising parents, globs,
`find -delete` and `cd` (text matching with no end of forms, and `./mvnw` stays); (b) the state in one protected
directory (its parent can still go, and it moves the lock under every hook, script and ADR that names it); a list of
dangerous commands (an unjudged program passes); detecting the removal (`./mvnw` can rewrite lock and marks
consistently). Claude Code's sandbox, which binds child processes, is #0-116's ("Also").

**Review round 1 (2026-11-13).** Security (sec-4a1d, blocking) found two allowed git forms that reach the state
without naming it, both passing every hook of the shipper and the implementer (checked in a scratch repository):
`git add -f .ai/runs` then `git rm -r -f .ai/runs` deletes it, `git mv .ai x` moves it; and `git switch` overwrites an
ignored file from a commit that tracks it. The first version's `SAFE_PREFIXES` said `git add`/`rm`/`mv` touch "tracked
files only", which was untrue. Owner: close the route, not only name it. `git_runtime_unsafe` (`_lib.sh`) refuses
`git add -f`/`--force` in any spelling and a `git mv` of `.ai`, `.ai/runs` or `.`; the prefixes' reasons name it; the
`switch` case, which needs a commit made with `add -f` or reviewed on `main`, is a named gap. With it: each prefix as
narrow as the rules judged (architecture and security), no shell operator in a rule's text (security).

**Review round 2 (2026-11-13).** Security upheld sec-4a1d with three more forms, checked in a scratch repository:
`.gitignore` is not protected, so an implementer that removes `.ai/runs/` from it makes a plain `git add .ai/runs`
stage the state (no `-f`); `git mv .//.ai x` moves it and `git mv -f f .ai/runs//LOCK` overwrites the lock (paths were
not resolved); a quoted subcommand in a compound command slipped past the text fallback. Each round found another
form of the same thing: the state lives in the working tree every allowed git command acts on. Owner: option 3 of
the round-2 report. git's `add`, `rm`, `mv`, `switch` and `checkout -b` leave `SAFE_PREFIXES` for `EXEMPT_RULES`, with
that reason; `git_runtime_unsafe` stays as a heuristic and resolves paths (`//`, `.`, `..`), checks `add`/`rm`/`mv`
paths into the state and `mv` paths above it, and matches the unquoted text of a part it cannot split; a newline in a
rule's text fails rule 4; the docs name the git route open until #0-236 moves the state out of the working tree.
Rejected: patching the guard further (a heuristic with no end, as `/research` said), and moving the state now (the
fix, but a refactor of its own: #0-236).

**Review round 3 (2026-11-13).** No blocking finding; sec-4a1d resolved under the owner's decision. Fixed with it
(owner: all in this PR): the shell guard matched protected paths as literal text, so the allowed
`git log --output=.ai/runs//LOCK` overwrote the lock with a branch and a base of the agent's (checked in a scratch
repository; older than this item) and `mkdir -p .ai/runs//ops-calls/<id>` blocked a factory-ops run: it now resolves
`//` and `/./` first. `runtime_path` splits without globbing; `git switch`/`checkout -b` have their own reason (no form
refused); the paths are resolved from the root (`git -C`, `--work-tree` match no rule).

**Acceptance criteria.**
AC1. Factory guards fails when an allow rule of either settings file, or of a preloaded skill's `allowed-tools`, runs a
program outside `SAFE_PREFIXES` that is not in `EXEMPT_RULES` (`rm`, `find`, an interpreter, `git clean`, any git
subcommand, a wrapper, `Bash(*)`, a bare `Bash`), and when an exemption is stale; the repository's rules pass; shown by
`test-agent-commands.sh`; a prefix wider than the rules judged (`gh pr checkout`, `git fetch *`) and a rule holding a
shell operator fail too.
AC1b. `guard-protected-bash.sh` refuses `git add -f` in every spelling, a `git add`/`rm`/`mv` path that resolves into
the state and a `git mv` path that resolves above it (`.//.ai`, `.ai/runs//LOCK`, `x/../.ai`), and passes `git add`,
`rm` and `mv` of tracked paths, shown by `test-hooks.sh`; git's commands on the working tree are `EXEMPT_RULES`
entries naming #0-236.
AC2. README "Infrastructure Hardening", ADR-0053 and `.ai/context/security.md` name the allow list as what keeps the
runtime state out of reach of every program but the exemptions, the git route as open until #0-236, and the guard as
a heuristic; `factory.md` FAC-S03 names the rule (owner).

---

### 0-237. Migration stage 1: the organisation `profitbuild` and the transfer of incident-platform

**Type:** ci · **Priority:** High · **Status:** Done, PRs #623 and #624 (2026-11-13). Kept in full for the transfer's
findings and its rollback. Stage 1 of ADR-0055 (owner, 2026-11-13).
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** — (stage 0, ADR-0055 merged in PR #620)
**Touches:** factory (scripts/factory/audit-data.sh, scripts/factory/owner-login.sh, .github/scripts/test-owner-login.sh,
.github/scripts/test-audit-data.sh, .github/workflows/factory-guards.yml), root (.ai/decisions/ (ADR-0055, ADR-0034),
.ai/rules/audit.md (owner), BACKLOG.md), docs
(README.md "Infrastructure Hardening": Factory guards, owner labels, escape markers; docs/ai-factory.md; README's links
and badge in PR 1b)

**Problem.** ADR-0055 moves the repository from the owner's account to an organisation, `profitbuild`, which will
hold the factory's own repository (stage 4) and the next product (stage N). Two checks took the owner to be the
repository's owner login, which after the transfer is the organisation's name, an account that never adds a label or
opens a pull request: `audit-data.sh` (`gh repo view`) would mark every `human:*` label and every escape marker
unverified, so the audits would count no owner decision at all, silently; factory-guards' "Changes that need the
owner" (`github.repository_owner`) would no longer recognise the owner's own pull requests, which would then need an
approval nobody else can give. The frontend (`incident-platform-frontend`) is not transferred: it stays outside the
factory (ADR-0055).

**Approach.** PR 1a: one script, `scripts/factory/owner-login.sh` (with the factory's helpers, so it moves with them in
stage 4), prints the one admin of
`.github/repository-settings/repository.json` read where the caller cannot be steered: `--github <owner/repo>` reads
it on `refs/heads/main` from GitHub's API (not a bare `main`, which a tag could shadow, round 2) (`audit-data.sh`: code run in a session can move a local ref or add a replace ref, review
round 1, arc-3c71), `<commit>` reads the blob with replace refs and grafts off (factory-guards: the pull request's base,
in CI's fresh checkout); it fails with no owner on no file, zero or several admins, or a value that is no GitHub login.
Factory guards counts only that owner's approval, not any organisation member's (ARC-02). The file is a `.github/`
path only the owner's reviewed pull requests change; GitHub's admins are compared with it only by the owner's own
`repository-settings.rb check` (CI's read-only token cannot see them, round 1, arc-9a04), so step 5 below is where it
is proved true after the transfer. ADR-0034 records that its `admins` list is now also the owner's identity. Known and
not changed here: `audit-data.sh` takes `<owner/repo>` from `gh repo view`, the clone's remote, which code run in a
session can repoint (as before this item); stage 4's dispatcher names the repository from its environment. ADR-0055 is amended with the
factory's purpose (a product of its own, stages T and N) before the owner accepts it.

Then the owner, in this order (the transfer keeps issues, pull requests, stars and redirects the old URLs):
1. Create the free organisation `profitbuild`, the owner its only owner; two-factor authentication required for members.
2. Settings → Transfer of `lukaszplawiak/incident-platform` to `profitbuild`; then `git remote set-url origin
   https://github.com/profitbuild/incident-platform.git` in every clone (the Mac, the devcontainer; HTTPS, which `gh`
   authenticates, not SSH: the SSH form of an earlier draft of this step was refused with "Permission denied (publickey)").
3. Reinstall what is bound to the account rather than the repository: Renovate (the GitHub App, for the organisation,
   this repository only), and check that Snyk's and the NVD key's secrets and the environments survived.
4. Organisation settings: base permission "No permission"; members cannot create repositories or change visibility;
   Actions' "Require actions to be pinned to a full-length commit SHA" at the organisation too, and the repository's own
   `sha_pinning_required` (ADR-0020) checked still on after the move (ADR-0034 keeps it outside the files); the machine
   account `lukaszplawiakbot` keeps Write on this repository only, as an outside collaborator, until builder-app replaces
   it (stage 4).
5. `ruby .github/scripts/repository-settings.rb check` with the owner's token: the ruleset, its bypass (the admin role:
   now the organisation's owners too, which is the owner alone), environments, admins and secrets as in the files.
PR 1b: README's links and badge to the new URL, whatever step 5 found, and one item merged the usual way (stage 1's exit).

**What the transfer found (2026-11-13, PR 1b, PR #624).** The transfer kept the issues, pull requests, environments, the
machine account (outside collaborator, Write), secret scanning and push protection, the workflow token's read-only
default and `sha_pinning_required`; the owner is still the repository's only admin (`plan` refuses otherwise).
`check` found two differences:
- **The ruleset's bypass list was empty** on GitHub (`bypass_actors: []`, confirmed in the UI), which made every PR of
  the owner unmergeable (CODEOWNERS covers every path, and nobody else approves); `apply` restored the admin role from
  `rulesets/main.json`. Recorded in ADR-0034's consequences.
- **`dismissal_restriction`**, a `pull_request` parameter GitHub returns only for an organisation's repository, was
  not in the file; PR 1b writes today's value (`enabled: false`, unchanged). Restricting who may dismiss a review to
  the owner is a possible hardening (the machine account, with Write, can dismiss the owner's "changes requested",
  though that gives it no approval), recorded as point 4 of #0-153 (stage 6a).
After PR #624 the owner turned on Dependabot alerts and set the organisation's Actions settings. The devcontainer was
rebuilt (`devcontainer up --remove-existing-container`). There the machine account's token showed as classic
(`repo`, `read:org`, no `workflow`), its permissions on the repository as `push` without `admin` or `maintain`, and a
test branch it pushed (`3985c1c6`, author and committer `lukaszplawiakbot`) reached GitHub and was deleted. `main`'s CI
and Factory guards on `91990164`, the merge of PR #624, were green: stage 1's exit.

**Closed with one owner step left:** two-factor authentication required in the organisation (Settings → Access →
Authentication security). It changes no file, and while the owner is the organisation's only member it changes nobody's
access.

**Rollback.** Transfer back to the owner's account (the redirects follow); `owner-login.sh` reads the same file there.
Then the owner runs `repository-settings.rb check` before the next merge: a transfer may empty the bypass list again
(ADR-0034), and if GitHub no longer returns `dismissal_restriction` on a personal account's repository, that key comes
out of `rulesets/main.json` first, so that `apply` sends only parameters GitHub accepts and can restore the bypass.

AC1. `audit-data.sh` and factory-guards read the owner from `repository.json` through `owner-login.sh`, on GitHub's main
and at the pull request's base; neither reads `gh repo view`'s owner or `github.repository_owner` for it, and factory
guards counts only the owner's approval.
AC2. With the repository an organisation's, the owner's labels and markers are verified (test-audit-data.sh: the stub's
repository is `org/r`, the owner `o`); the bot's login in the clone (working tree, origin/main, a replace ref) changes
nothing, and GitHub's file unreadable or naming two admins leaves the owner unknown and nothing vouched (fail closed).
AC3. `owner-login.sh` refuses zero or several admins, a non-list, a non-string, a value that is no login, a commit
without the file, and honours no replace ref or textconv driver (test-owner-login.sh, in Factory guards).
AC4. After the transfer `repository-settings.rb check` passes with the owner's token, and one item is merged the usual
way (PR 1b).

### 0-240. The build VM reaches the Mac's loopback services

**Type:** security · **Priority:** Medium · **Status:** Done, PR #632 (2026-11-14)
(ADR-0057: neither option alone; rootless Docker, so code a test runs is no longer root in the VM, and with it a rule
of root's in the VM, option 1, which that makes binding). From review round 3
of #0-238 (security, finding 1), checked by hand the same day (owner, 2026-11-14).
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** #0-238
**Touches:** factory (scripts/factory-admin/build-vm/, an owner-only path), root (.ai/decisions/ ADR-0056 amended or a
new ADR), docs (docs/ai-factory.md "Build VM" and "What isolates what", README.md "Infrastructure Hardening")

**Problem.** Lima's user-mode network forwards `host.lima.internal` (192.168.5.2) to the Mac's loopback. On
2026-11-14 a server bound only to the Mac's `127.0.0.1` answered from the build VM and from a container started on
the VM's Docker. Code an agent runs gets root over that Docker (#0-116), so it reaches every service the owner keeps
on loopback to keep it private: Grafana with every tenant's logs (behind its password), Ollama, a service started by
`spring-boot:run`, anything else. The devcontainer's firewall denies the path from inside the container, but not from
a container the code starts beside it. Not a regression (Docker Desktop's `host.docker.internal` reaches the Mac's
loopback the same way), but stage 2 is meant to take the Mac out of the reach of that code, and this path keeps it in.

**Approach.** Decide between, by testing each on `factory-build` (`create.sh`, then the isolation checks and the S3
gate still pass):
1. A rule in the VM, from `provision.sh`, that drops traffic addressed to 192.168.5.2 except DNS (port 53): that
   address is also the VM's gateway and resolver (checked 2026-11-14), so the rule matches the destination address,
   not the route. Root in the VM can remove it, so it binds only code without root, and is a layer, not a boundary.
2. A network for the VM in which the Mac's loopback is not forwarded (`vzNAT`, if Lima can then do without its
   user-mode network for its own SSH and guest agent).
3. Keep it open until stage C, where the VM runs off the Mac and a cloud firewall sits outside it, and say so where
   the gap is listed.
Whatever is chosen, `create.sh` checks it on the started VM, as it does the mounts.

AC1. The decision and the test of each option tried are in ADR-0056 (amended) or a new ADR.
AC2. If the path is closed: from the VM and from a container on its Docker, a server on the Mac's `127.0.0.1` does not
answer, and `create.sh` refuses a VM where it does; the S3 gate still passes.
AC3. README "Infrastructure Hardening", `docs/ai-factory.md` and #0-116 say what is closed and what is left.
