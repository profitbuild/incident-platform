# Backlog

Known work that is not done yet: defects, design decisions still to be made, and tech debt.
Code, Javadoc, config comments and commits reference items as `backlog #N`.

## Conventions

- **Numbering:** new items are numbered `0-1`, `0-2`, `0-3`, ... in order of creation and are
  referenced as `backlog #0-N` (always with the word `backlog`). Never reuse a number. The `0-`
  prefix keeps them apart from the legacy references `backlog #1`–`#82` that already exist in code
  and commit history (those items were never recorded in a file and are not backfilled here) and
  from GitHub issue/PR numbers, which use the same `#N` form.
- **Every `TODO`/`FIXME` in code must reference an item** (`TODO (backlog #N)`), per CLAUDE.md.
  Add the item here first, then reference it.
- **Status:** `Open` · `In progress` · `Blocked` · `Done`. A finished item leaves this file: its row moves to
  [`BACKLOG-DONE.md`](BACKLOG-DONE.md) with the PR, so references in code stay resolvable, and its whole section moves
  with it, unchanged apart from its status (`Done, PR #N (<date>)`), to the end of that file's "Details": the history of
  a decision is kept there, not here, because every agent that picks work reads this file. `Blocked` names its reason
  in one line (`**Status:** Blocked — <reason> (autopilot run <id>)`); an item the owner freezes because a later
  change replaces it reads `**Status:** Blocked — superseded by <what> (ADR-NNNN, <date>); was <old status>`, and its
  index row `Blocked (superseded, ADR-NNNN)`.
- **Type:** `bug` · `security` · `design` (a decision is needed before implementation) · `tech-debt` ·
  `performance` · `ci` · `docs`. The type gives an autopilot item's branch prefix; the table is `BRANCH_PREFIX_OF` in
  `scripts/factory/_backlog.sh`, and an item of a type it does not list is never chosen (backlog #0-195).
- **Autopilot fields** (optional; an item without them is never picked by the autopilot). A second
  line under the Type/Priority/Status line, and a third with the predicted reach:
  `**Autopilot:** ready | proposed | not-ready | human-only · **Risk:** low | high · **Complexity:** low | medium | high · **Depends on:** #0-N, …`
  `**Touches:** <module> (<packages>), …` — the modules the change is expected to reach (vocabulary and
  rules: `.ai/rules/planning.md`, "Touches").
  - `ready` is set **only by the owner**, after `.ai/rules/ready.md` holds (the `/ready` skill drafts it);
    the autopilot takes only `ready` items whose dependencies are `Done`, in the order of the approved
    queue `.ai/plan/queue.md` (`/plan-backlog` proposes it; without a queue, by priority).
  - `proposed` marks a follow-up the autopilot created from an implementer's "Follow-up needed"; it also
    carries `**Follow-up of:** #0-N` on the same line. It waits for `/ready` like any draft. Once `ready`
    and its parent is done, the autopilot takes it before the next queue row.
  - `Risk: high` means the owner merges it, whatever the reviewers say. `Complexity: low` allows the
    optional local-model implementer (`docs/ai-factory.md`).
  - An item that a reviewer or the audit later traces back to an escaped defect gets
    `**Fixes:** #0-N · **Escaped from:** <stage>` on the same line, where `<stage>` is `review-<dimension>` when
    the panel missed it, or the pipeline stage that let it in (`ready`, `queue`, `pick`, `plan`, `implement`,
    `acceptance`, `ship`); the audits count these (the pipeline audit, backlog #0-121, by the date the marker
    was added), but only a marker that reached `main` in a PR the owner opened (backlog #0-129). Factory guards
    fails a line with `**Escaped from:** <stage>` and no `**Fixes:** #0-<digits>` before it (backlog #0-128).
- **Acceptance criteria** for an autopilot item are numbered (`AC1.`, `AC2.`, …), each one checkable by a
  test or a CI check script (not a command run by hand), so that `acceptance-reviewer` can map each to evidence. Prose `**Acceptance.**`
  paragraphs stay valid for items done by hand.
- **Priority:** `High` (breaks a core promise or lets a known failure recur) · `Medium` ·
  `Low`.
- Changing what an item says about the code is a docs change: keep README, `CLAUDE.md` and
  `.ai/` in sync (see `.ai/README.md`).

## Open items

| # | Title | Type | Priority | Status |
|---|---|---|---|---|
| [0-2](#0-2-make-the-docker-compose-smoke-test-a-required-check-and-add-context-boot-tests) | Make the compose smoke test a required check; add context-boot tests | ci | High | Open |
| [0-3](#0-3-decide-token-revocation-coverage-across-services) | Decide token-revocation coverage across services | design | Medium | Open |
| [0-4](#0-4-escalation-event-is-published-at-most-once) | Escalation event is published at-most-once | tech-debt | Medium | Open |
| [0-5](#0-5-testcontainers-and-kafka-test-jars-ship-in-every-service-jar) | Testcontainers and Kafka test jars ship in every service jar | tech-debt | Medium | Open |
| [0-6](#0-6-untracked-todos-need-a-backlog-reference) | Untracked `TODO`s need a backlog reference | tech-debt | Low | Open |
| [0-13](#0-13-asymmetric-service-tokens-or-mtls-for-service-identity) | Asymmetric service tokens or mTLS for service identity | design | Medium | Open |
| [0-14](#0-14-by-slack-is-open-to-any-authenticated-role) | `GET /by-slack/{id}` is open to any authenticated role | tech-debt | Low | Open |
| [0-15](#0-15-incidentackclient-is-not-authorized-on-the-status-endpoint) | `IncidentAckClient` is not authorized on the status endpoint | bug | Medium | Open |
| [0-17](#0-17-alert-on-service_client_fallback_totalreasonauth) | Alert on `service_client_fallback_total{reason="auth"}` | tech-debt | Medium | Open |
| [0-20](#0-20-tenant-owned-fallback-contact) | Tenant-owned fallback contact | design | Medium | Open |
| [0-22](#0-22-the-operator-alert-is-email-only) | The operator alert is email only | tech-debt | Low | Open |
| [0-23](#0-23-the-oncall-and-slack-workspace-retry-never-fires) | The `oncall` and `slack-workspace` `@Retry` never fires | tech-debt | Low | Open |
| [0-24](#0-24-on-call-contacts-are-not-verified-against-tenant-membership) | On-call contacts are not verified against tenant membership | design | Medium | Open |
| [0-25](#0-25-a-stale-notification_queue-write-can-overwrite-a-terminal-status) | A stale `notification_queue` write can overwrite a terminal status | tech-debt | Medium | Open |
| [0-28](#0-28-notification_queue-rows-are-never-purged) | `notification_queue` rows are never purged | tech-debt | Low | Open |
| [0-31](#0-31-auth-service-identityconfig-split-evaluated-and-deferred) | auth-service identity/config split — evaluated and deferred | design | Low | Open |
| [0-32](#0-32-no-notification-channel-is-retried-after-a-failed-send) | No notification channel is retried after a failed send | design | Medium | Open |
| [0-33](#0-33-unify-caching-on-caffeine-once-a-third-cache-appears) | Unify caching on Caffeine once a third cache appears | tech-debt | Low | Open |
| [0-34](#0-34-servicetokenprovider-cache-has-no-metrics) | `ServiceTokenProvider` cache has no metrics | tech-debt | Low | Open |
| [0-35](#0-35-slack-install-via-oauth-add-to-slack-brings-back-ack-via-slack) | Slack install via OAuth ("Add to Slack") brings back ACK via Slack | design | Medium | Open |
| [0-36](#0-36-nothing-checks-entity-index-annotations-against-the-real-schema) | Nothing checks entity `@Index` annotations against the real schema | tech-debt | Low | Open |
| [0-37](#0-37-ingest-rate-limiter-answers-429-which-alertmanager-drops-without-retry) | Ingest rate limiter answers 429, which Alertmanager drops without retry | design | Medium | Open |
| [0-38](#0-38-integration-key-format-has-no-checksum-and-a-separator-inside-its-alphabet) | Integration key format has no checksum and a separator inside its alphabet | tech-debt | Low | Open |
| [0-40](#0-40-dead-letter-topics-have-no-consumer-or-replay-tooling) | Dead-letter topics have no consumer or replay tooling | design | Medium | Open |
| [0-41](#0-41-teamid-from-event-payloads-is-not-validated-against-the-tenants-teams) | `teamId` from event payloads is not validated against the tenant's teams | design | Low | Open |
| [0-43](#0-43-api-key-introspection-can-be-amplified-from-many-ips) | API key introspection can be amplified from many IPs | design | Low | Open |
| [0-44](#0-44-concurrent-cache-misses-for-one-api-key-each-call-auth-service) | Concurrent cache misses for one API key each call auth-service | tech-debt | Low | Open |
| [0-45](#0-45-api-key-usage-write-holds-a-second-auth-service-db-connection) | API key usage write holds a second auth-service DB connection | tech-debt | Low | Open |
| [0-46](#0-46-personal-api-keys-can-be-granted-scopes-their-owners-role-does-not-allow) | Personal API keys can be granted scopes their owner's role does not allow | bug | Low | Open |
| [0-48](#0-48-user-pii-lives-on-the-users-row-erasure-is-in-place-anonymization) | User PII lives on the `users` row; erasure is in-place anonymization | design | Low | Open |
| [0-55](#0-55-auth-email-failures-do-not-tell-an-smtp-outage-from-a-rejected-address) | Auth email failures do not tell an SMTP outage from a rejected address | design | Low | Open |
| [0-56](#0-56-forgot-password-leaks-whether-an-account-exists-through-response-time) | forgot-password leaks whether an account exists through response time | design | Medium | Open |
| [0-58](#0-58-globalexceptionhandler-and-unauthorizedentrypoint-have-no-tests-of-their-own-in-shared) | `GlobalExceptionHandler` and `UnauthorizedEntryPoint` have no tests of their own in `shared` | tech-debt | Medium | Open |
| [0-62](#0-62-any-github-action-from-the-marketplace-is-allowed-to-run) | Any GitHub Action from the Marketplace is allowed to run | ci | Low | Open |
| [0-64](#0-64-kubernetes-pods-run-without-a-securitycontext) | Kubernetes pods run without a `securityContext` | design | Medium | Open |
| [0-65](#0-65-no-networkpolicy-every-pod-can-reach-every-other-pod) | No NetworkPolicy: every pod can reach every other pod | design | Medium | Open |
| [0-66](#0-66-redis-and-kafka-in-kubernetes-have-no-authentication-and-no-data-store-uses-tls) | Redis and Kafka in Kubernetes have no authentication, and no data store uses TLS | design | Medium | Open |
| [0-67](#0-67-all-seven-services-share-one-database-role) | All seven services share one database role | design | Medium | Open |
| [0-68](#0-68-sast-has-never-run-snyk-code-is-not-enabled-and-codeql-is-not-set-up) | SAST has never run: Snyk Code is not enabled, and CodeQL is not set up | ci | Medium | Open |
| [0-69](#0-69-the-snyk-dependency-scan-fails-on-every-run-so-a-new-finding-changes-nothing) | The Snyk dependency scan fails on every run, so a new finding changes nothing | ci | High | Open |
| [0-70](#0-70-built-images-are-not-scanned-and-no-sbom-is-produced) | Built images are not scanned, and no SBOM is produced | ci | Low | Open |
| [0-71](#0-71-kubernetes-and-compose-images-use-mutable-tags-and-some-are-not-tracked-by-renovate) | Kubernetes and compose images use mutable tags, and some are not tracked by Renovate | tech-debt | Low | Open |
| [0-72](#0-72-docker-compose-publishes-every-port-on-all-interfaces-with-default-credentials) | docker-compose publishes every port on all interfaces, with default credentials | tech-debt | Low | Open |
| [0-73](#0-73-swagger-ui-and-the-openapi-document-are-public-in-every-profile) | Swagger UI and the OpenAPI document are public in every profile | tech-debt | Low | Open |
| [0-74](#0-74-no-way-to-report-a-vulnerability-privately) | No way to report a vulnerability privately | docs | Low | Open |
| [0-75](#0-75-the-ingress-has-no-tls) | The Ingress has no TLS | design | Low | Open |
| [0-77](#0-77-should-devtoken-require-an-explicit-switch-as-well-as-the-dev-profile) | Should `/dev/token` require an explicit switch as well as the dev profile? | design | Low | Open |
| [0-79](#0-79-at-hpa-maxima-during-a-rolling-update-the-connection-pools-exceed-what-postgres-allows) | At HPA maxima during a rolling update, the connection pools exceed what Postgres allows | design | Medium | Open |
| [0-85](#0-85-a-tenant-id-with-data-in-other-services-but-no-user-can-be-provisioned) | A tenant id with data in other services but no user can be provisioned | design | Low | Open |
| [0-86](#0-86-integration-tests-load-the-web-slice-test-configuration) | Integration tests load the web-slice test configuration | tech-debt | Low | Open |
| [0-87](#0-87-operator-mfa-enrolment-is-not-bound-to-the-invite) | Operator MFA enrolment is not bound to the invite | design | Low | Open |
| [0-94](#0-94-logs-are-plain-text-with-no-structure-escaping-or-collection) | Logs are plain text, with no structure, escaping or collection | design | Medium | Open (steps 1, 2 done: JSON, collection) |
| [0-95](#0-95-kafka-messages-have-no-envelope-correlation-id-schema-version-producer) | Kafka messages have no envelope (correlation id, schema version, producer) | design | Low | Open |
| [0-97](#0-97-kafka-consumers-on-defaulterrorhandler-and-a-dead-letter-replay) | Kafka consumers on `DefaultErrorHandler`, and a dead-letter replay | design | Low | Open |
| [0-98](#0-98-mfa-recovery-verifies-the-person-by-procedure-only) | MFA recovery verifies the person by procedure only | design | Low | Open |
| [0-99](#0-99-public-token-endpoints-have-no-request-limit) | Public token endpoints have no request limit | security | Low | Open |
| [0-101](#0-101-offboard-a-tenant) | Offboard a tenant | design | Medium | Open |
| [0-102](#0-102-the-pause-of-suspended-tenants-background-work-at-scale) | The pause of suspended tenants' background work at scale | performance | Low | Open |
| [0-105](#0-105-the-email-channels-worst-case-send-is-not-checked-against-the-scheduler-lock) | The email channel's worst-case send is not checked against the scheduler lock | performance | Low | Open |
| [0-106](#0-106-kubernetes-has-no-observability-stack) | Kubernetes has no observability stack | design | Medium | Open |
| [0-107](#0-107-no-alert-reads-log-content) | No alert reads log content | design | Low | Open |
| [0-108](#0-108-architecture-tests-archunit-for-the-decided-patterns) | Architecture tests (ArchUnit) for the decided patterns | ci | Medium | Open |
| [0-110](#0-110-maven-enforcer-allowed-repositories-and-pinned-plugin-versions) | Maven Enforcer: allowed repositories and pinned plugin versions | ci | Low | Open |
| [0-111](#0-111-openapi-contract-diff-on-pull-requests) | OpenAPI contract diff on pull requests | ci | Low | Open |
| [0-112](#0-112-mutation-testing-on-the-classes-a-pr-changes) | Mutation testing on the classes a PR changes | ci | Low | Open |
| [0-116](#0-116-the-devcontainer-firewall-does-not-bind-code-an-agent-runs) | The devcontainer firewall does not bind code an agent runs | design | High | Open |
| [0-117](#0-117-the-escalation-level-bound-is-hard-coded-in-three-services) | The escalation level bound is hard-coded in three services | tech-debt | Low | Open |
| [0-171](#0-171-a-seed-bugs-run-that-measured-nothing-leaves-no-record) | A `/seed-bugs` run that measured nothing leaves no record | ci | Low | Open |
| [0-178](#0-178-a-real-defect-the-panel-missed-never-becomes-a-seeded-pattern) | A real defect the panel missed never becomes a seeded pattern | design | Medium | Open |
| [0-183](#0-183-the-k8s-reviewer-could-render-a-tracked-only-snapshot-with-no-network) | The k8s reviewer could render a tracked-only snapshot with no network | security | Low | Blocked (superseded, ADR-0055) |
| [0-188](#0-188-a-logged-exceptions-message-reaches-the-log-as-the-library-wrote-it) | A logged exception's message reaches the log as the library wrote it | security | Medium | Open |
| [0-190](#0-190-a-failed-seed-bugs-run-leaves-the-tree-on-its-branch-once-the-seeder-has-edited) | A failed `/seed-bugs` run leaves the tree on its branch once the seeder has edited | ci | Low | Open |
| [0-193](#0-193-four-forked-security-chains-do-not-add-apikeyauthfilter-as-sec-12-says-they-do) | Four forked security chains do not add `ApiKeyAuthFilter`, as SEC-12 says they do | security | Medium | Open |
| [0-201](#0-201-a-ready-items-touches-line-is-validated-only-once-it-is-queued) | A `ready` item's Touches line is validated only once it is queued | ci | Low | Blocked (superseded, ADR-0055) |
| [0-202](#0-202-the-owner-and-the-bot-share-one-working-tree) | The owner and the bot share one working tree | design | Low | Open |
| [0-204](#0-204-a-runs-record-keeps-no-run-id-no-agent-calls-and-no-stage-of-each-commit) | A run's record keeps no run id, no agent calls and no stage of each commit | ci | Low | Open |
| [0-205](#0-205-a-runs-transcripts-expire-after-90-days-and-nothing-reads-them-per-agent) | A run's transcripts expire after 90 days and nothing reads them per agent | ci | Low | Open |
| [0-208](#0-208-five-route-walks-hold-five-copies-of-isexempt) | Five route walks hold five copies of `isExempt` | tech-debt | Low | Open |
| [0-210](#0-210-twenty-one-deny-rules-of-the-autopilot-settings-never-match) | Twenty-one deny rules of the autopilot settings never match | ci | Low | Blocked (superseded, ADR-0055) |
| [0-211](#0-211-two-lists-of-secret-paths-and-nothing-keeps-them-equal) | Two lists of secret paths, and nothing keeps them equal | ci | Low | Blocked (superseded, ADR-0055) |
| [0-212](#0-212-a-factory-commit-does-not-say-which-run-and-which-agent-wrote-it) | A factory commit does not say which run and which agent wrote it | ci | Low | Open |
| [0-213](#0-213-an-exception-ends-the-autopilot-and-the-audit-workflows-with-no-outcome) | An exception ends the autopilot and the audit workflows with no outcome | ci | Low | Blocked (superseded, ADR-0055) |
| [0-214](#0-214-the-agents-command-lists-are-not-run-through-claude-codes-own-permission-check) | The agents' command lists are not run through Claude Code's own permission check | ci | Low | Blocked (superseded, ADR-0055) |
| [0-217](#0-217-start-itemsh-copies-the-work-template-without-checking-it-for-symlinks) | start-item.sh copies the work template without checking it for symlinks | ci | Low | Blocked (superseded, ADR-0055) |
| [0-218](#0-218-no-seeded-pattern-measures-security-on-a-weakened-forked-chain-or-an-idor) | No seeded pattern measures security on a weakened forked chain or an IDOR | ci | Low | Open |
| [0-219](#0-219-performances-seeded-results-predate-the-blind-panel-and-no-clean-run-measures-its-false-alarms) | performance's seeded results predate the blind panel, and no clean run measures its false alarms | ci | Low | Open |
| [0-221](#0-221-two-audit-reports-of-one-day-can-give-the-same-recommendation-id) | Two audit reports of one day can give the same recommendation id | ci | Low | Open |
| [0-224](#0-224-no-reviewer-is-told-to-read-the-log-pipelines-rules-when-a-change-touches-docker) | No reviewer is told to read the log pipeline's rules when a change touches `docker/` | ci | Low | Open |
| [0-225](#0-225-the-autopilot-allows-the-grep-and-glob-tools-and-no-secret-rule-or-hook-names-them) | The autopilot allows the Grep and Glob tools, and no secret rule or hook names them | security | Low | Blocked (superseded, ADR-0055) |
| [0-226](#0-226-a-resumed-run-records-no-scope) | A resumed run records no scope | ci | Low | Blocked (superseded, ADR-0055) |
| [0-227](#0-227-a-risk-high-items-real-needs_human-ships-as-a-pr-instead-of-stopping) | A risk-high item's real `NEEDS_HUMAN` ships as a PR instead of stopping | ci | Low | Blocked (superseded, ADR-0055) |
| [0-228](#0-228-a-blocked-draft-writes-scope-not-measured-and-the-audit-reads-scopenot) | A BLOCKED draft writes "Scope: not measured." and the audit reads `scope:not` | ci | Low | Blocked (superseded, ADR-0055) |
| [0-229](#0-229-ingestions-redis-dedup-and-rate-limits-are-tested-only-against-mocks) | ingestion's Redis dedup and rate limits are tested only against mocks | tech-debt | Low | Open |
| [0-230](#0-230-renovate-rebases-every-open-pr-on-every-merge-58-of-the-actions-minutes) | Renovate rebases every open PR on every merge: 58% of the Actions minutes | ci | Medium | Open |
| [0-231](#0-231-a-new-push-to-a-pull-request-does-not-cancel-its-running-ci) | A new push to a pull request does not cancel its running CI | ci | Low | Open |
| [0-232](#0-232-no-check-keeps-the-concurrency-block-of-the-pull-request-workflows) | No check keeps the concurrency block of the pull request workflows | ci | Low | Open |
| [0-234](#0-234-a-refused-second-factory-ops-call-leaves-no-record-the-audit-reads) | A refused second factory-ops call leaves no record the audit reads | ci | Low | Blocked (superseded, ADR-0055) |
| [0-236](#0-236-the-factorys-runtime-state-lives-in-the-working-tree-the-agents-git-commands-act-on) | The factory's runtime state lives in the working tree the agents' git commands act on | security | Medium | Blocked (superseded, ADR-0055) |
| [0-238](#0-238-migration-stage-2-a-build-vm-provisioned-as-code-runs-todays-devcontainer) | Migration stage 2: a build VM, provisioned as code, runs today's devcontainer | ci | High | In progress |
| [0-239](#0-239-the-build-vms-scripts-have-no-repeatable-test) | The build VM's scripts have no repeatable test | ci | Low | Open |
| [0-242](#0-242-the-build-vms-listener-check-runs-only-when-the-vm-is-created) | The build VM's listener check runs only when the VM is created | security | Low | Open |
| [0-243](#0-243-two-parsers-read-the-devcontainers-allow-list) | Two parsers read the devcontainer's allow-list | ci | Low | Open |
| [0-244](#0-244-no-review-rule-covers-the-build-vms-own-allow-list) | No review rule covers the build VM's own allow-list | security | Low | Open |
| [0-245](#0-245-validation-errors-do-not-redact-apikey-and-privatekey-fields) | Validation errors do not redact `apiKey` and `privateKey` fields | bug | Medium | Open |
| [0-246](#0-246-service-classes-below-60-coverage-found-with-0-57) | Service classes below 60% coverage, found with #0-57 | tech-debt | Low | Open |
| [0-133](#0-133-incidentresolvedevent-carries-no-openedat) | `IncidentResolvedEvent` carries no `openedAt` | tech-debt | Low | Open |
| [0-134](#0-134-diff-cover-is-installed-by-version-without-hashes) | `diff-cover` is installed by version, without hashes | ci | Low | Open |
| [0-135](#0-135-kubectl-in-ci-is-downloaded-unverified) | kubectl in CI is downloaded unverified | ci | Low | Open |
| [0-136](#0-136-the-security-review-rules-have-no-rule-for-the-ci-supply-chain) | The security review rules have no rule for the CI supply chain | docs | Low | Open |
| [0-139](#0-139-the-hpas-scale-the-jvm-services-on-memory) | The HPAs scale the JVM services on memory | design | Low | Open |
| [0-140](#0-140-the-services-pods-are-not-spread-over-zones-nor-rebalanced-after-scale-down) | The services' pods are not spread over zones, nor rebalanced after scale-down | design | Low | Open |
| [0-143](#0-143-the-images-do-not-use-a-cds-or-aot-cache) | The images do not use a CDS or AOT cache | design | Low | Open |
| [0-151](#0-151-local-actions-are-called-by-path-not-by-githubs-self-repository-syntax) | Local actions are called by path, not by GitHub's self-repository syntax | ci | Low | Open |
| [0-152](#0-152-refresh-the-snyk-cli-signing-key-before-2027-01-06) | Refresh the Snyk CLI signing key before 2027-01-06 | ci | Medium | Open |
| [0-153](#0-153-decide-which-paths-need-the-owners-review-before-auto-merge) | Decide which paths need the owner's review, before auto-merge | design | Medium | Open |
| [0-155](#0-155-a-scan-that-cannot-run-on-main-alerts-no-one) | A scan that cannot run on `main` alerts no one | ci | Medium | Open |
| [0-156](#0-156-secrets-are-scanned-only-after-the-push) | Secrets are scanned only after the push | security | Medium | Open |
| [0-158](#0-158-spring-boot-35-is-out-of-open-source-support-decide-the-move-to-4x) | Spring Boot 3.5 is out of open-source support; decide the move to 4.x | design | High | Open |
| [0-159](#0-159-security-version-overrides-in-the-root-pom-are-bumped-and-checked-by-hand) | Security version overrides in the root POM are bumped and checked by hand | ci | Medium | Open |
| [0-167](#0-167-no-hook-of-the-owners-session-refuses-gits-writing-options) | No hook of the owner's session refuses git's writing options | security | Medium | Blocked (superseded, ADR-0055) |

---

### 0-2. Make the docker-compose smoke test a required check, and add context-boot tests

**Type:** ci · **Priority:** High · **Status:** Open

**Problem.** The "Docker Compose Smoke Test" was red on `main` for at least six consecutive runs
(2026-09-19) and PRs kept merging. The cause, a missing `TokenRevocationChecker` bean that stopped
incident-service from starting, was fixed in PR #410. It slipped through because
`StompAuthChannelInterceptorTest` mocks the checker, so no unit test boots the real context.

**Work.**
1. GitHub branch protection on `main`: require "Docker Compose Smoke Test" (a repository setting;
   skipped path-filtered jobs count as passing, so this does not block unrelated PRs).
2. Add a fast context-boot test per service (a slim `@SpringBootTest` or context runner) so wiring
   errors fail in "Build, Test & Coverage" (~2 min) and not only in the ~5 min compose run.
3. Optional: notify on failing `main` CI.

**Acceptance.** A PR that breaks service startup cannot merge, and the failure shows in the fast
job first.

---

### 0-3. Decide token-revocation coverage across services

**Type:** design · **Priority:** Medium · **Status:** Open

**Context.** Revocation (Redis `auth:revoked:{jti}`) is enforced only in auth-service. Every other
service, including STOMP `CONNECT` on incident-service, uses the no-op `TokenRevocationChecker`
from `SharedSecurityAutoConfiguration` (PR #410). A logged-out user's access token stays usable on
those services until it expires (default access-token TTL is 15 minutes; service tokens 1 hour).

**Questions to settle first.**
- Is a 15-minute window acceptable for this system (multi-tenant SOC / ops data)?
- If not: check per service, or once at a gateway?

**Options.**
1. Accept and document (current state); shorten the TTL if wanted.
2. Redis-backed checker in `shared`, registered where Redis is configured. Today only ingestion and
   auth have Redis; this adds a per-request lookup and a Redis dependency to the rest, plus a
   fail-open policy to agree on.
3. Enforce at a gateway or ingress once, in front of all services.

**Also decide.** A WebSocket authenticates only at `CONNECT`, so an open connection outlives a
logout under any option: periodic re-validation, a session-revoked event that closes connections,
or accept it.

**Deliverable.** A recorded decision (`.ai/README.md` asks for an ADR for technology decisions).
Implementation, if chosen, becomes its own item.

---

### 0-4. Escalation event is published at-most-once

**Type:** tech-debt · **Priority:** Medium · **Status:** Open

**Problem.** `EscalationScheduler.escalate()` marks the task `ESCALATED` in its own short
transaction and only then publishes `IncidentEscalatedEvent` to Kafka. If the process crashes in
between, the task is `ESCALATED` but the event is never sent: nobody is notified for that level.
The code documents this trade-off in a `TODO` (see backlog #0-6).

**Approach.** Transactional outbox for the escalation event, as already done for
`incidents.lifecycle` in incident-service (backlog #36: `IncidentEventOutbox` and its scheduler are
the reference implementation). Justified because a lost escalation is the failure the platform
exists to prevent.

**Acceptance.** State change and event staging commit atomically; a crash between them no longer
loses the notification; the `TODO` in `EscalationScheduler` is replaced by a `backlog #0-4`
reference or removed.

---

### 0-5. Testcontainers and Kafka test jars ship in every service jar

**Type:** tech-debt · **Priority:** Medium · **Status:** Open

**Problem.** `shared/pom.xml` declares `org.testcontainers:testcontainers`, `postgresql` and `kafka`
with `compile` scope, so `testcontainers-1.21.4.jar` and `kafka-1.21.4.jar` end up in
`BOOT-INF/lib` of every service's fat jar and Docker image.

**Approach.** Move them to `test` scope, or into a separate test-jar/module that services depend on
in `test` scope. Changing `shared` rebuilds all 7 services, so do it as its own PR.

**Acceptance.** The jars are absent from a built service jar (`jar tf`), all services still build,
and existing Testcontainers-based tests still pass.

---

### 0-6. Untracked `TODO`s need a backlog reference

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Problem.** CLAUDE.md forbids `TODO`/`FIXME` without a backlog reference. These have none; some
sit near comments that cite other items, so triage each one:

- `auth-service`: `AuthServiceApplication` (future service split — now linked, backlog #0-31); `User` and
  `UserManagementService` (Data Vault — now linked, backlog #0-48)
- `escalation-service`: `EscalationScheduler` (outbox for the escalation event, see backlog #0-4)
- `incident-service`: `IncidentKafkaConsumer` (per-severity topics); `IncidentCommandService`
- `ingestion-service`: `AlertKafkaProducer` (envelope pattern)
- `shared`: `TenantKafkaRecordInterceptor` (OpenTelemetry)

**Work.** For each: create or link an item and write `TODO (backlog #N)`, or delete it.
Optionally add a CI grep that fails on a new `TODO` without `backlog #`.

---

### 0-13. Asymmetric service tokens or mTLS for service identity

**Type:** design · **Priority:** Medium · **Status:** Open

**Context.** Every service holds the same HMAC secret (`jwt.secret`), so any service can mint a token
with any tenant and any role. Per-tenant service tokens (backlog #0-11) stop a forged header from
outside the platform but not a compromised service. The README "Design Decisions" section records why
RS256/Keycloak was rejected; this item asks whether that still holds.

**Options.** (1) Accept and keep documenting the limitation. (2) Asymmetric signing (RS256/EdDSA +
JWKS), private key only in auth-service, services verify only. (3) mTLS or a service mesh for service
identity, with authorization policy at the mesh. (4) OAuth2 client-credentials tokens issued by
auth-service, with `aud` and scopes.

**Deliverable.** A recorded decision (an ADR, per `.ai/README.md`). Implementation becomes its own item.

---

### 0-14. `GET /by-slack/{id}` is open to any authenticated role

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Problem.** oncall-service's `SecurityConfig` has exact-path rules only for `/current` and
`/current/all`, so `/api/v1/oncall/by-slack/{slackUserId}` falls through to
`anyRequest().authenticated()` and any role can read it. It returns less data than `/current`, but it
is an internal service-to-service lookup.

**Wider than oncall.** The same holds platform-wide: an endpoint that is only `authenticated()`
accepts every principal type. Since backlog #0-11 a service token authenticates, but only in the
service named in its `aud` claim, so an oncall-bound token cannot reach auth-service any more. Within
one service it still reaches every `authenticated()`-only route, and a controller that dereferences
`@AuthenticationPrincipal UserPrincipal` fails with a 500 instead of a 403 for a service caller.

**Decide.** The intended roles per route, and whether the shared chain should deny `ServicePrincipal`
by default and let each service opt routes in, rather than each service excepting itself.

---

### 0-15. `IncidentAckClient` is not authorized on the status endpoint

**Type:** bug · **Priority:** Medium · **Status:** Open, deferred to be done together with #0-35 (found by code reading, not run)

**Problem.** notification-service's `IncidentAckClient` calls `PATCH /api/v1/incidents/{id}/status`
with a service token (ACK via Slack). That endpoint has `@PreAuthorize("hasRole('RESPONDER') or
hasRole('ADMIN')")` and dereferences `principal.userId()`. After backlog #0-11 the token
authenticates, but as a `ServicePrincipal` with `ROLE_SERVICE`, so the call is answered with 403; and
`@AuthenticationPrincipal UserPrincipal` would be `null` for a service caller.

**Decision needed.** How a service acts on behalf of a user: a dedicated service endpoint that takes
`acknowledgedBy` from the request, or propagating the user's identity. Then add a test that sends a
real service token to this endpoint.

**Found in the analysis of 2026-10-15** (`/research`, not run):
- The path is unreachable today: no message carries the Acknowledge button since #0-21, and #0-35 brings it back.
  So this is a precondition of #0-35, deferred to be done with it (the owner's decision): the OAuth install may
  change how a Slack user maps to a platform user, which decides the answer for an unmapped one.
- `UpdateStatusCommand` has only `status` and `comment`: the `acknowledgedBy` the client sends is dropped
  silently, and the actor would be the principal; `principal.userId()` would also be a 500 (NPE) for a service
  caller, past the 403.
- `SlackActionService` invents the actor for a Slack user with no on-call mapping
  (`UUID.nameUUIDFromBytes(slackUserId)`), so history and audit would name a user who does not exist.
- Recommended direction: a trusted subsystem, not identity propagation (a click carries no platform token, and a
  token minted for the user would be an impersonation capability). An internal `ROLE_SERVICE` endpoint in
  incident-service for the acknowledgement only, the pattern of auth-service's `/api/v1/internal/...` endpoints
  (tenant from the token's claim, `hidden = true`), with a required `acknowledgedBy`, the source recorded as Slack
  and the relay in the audit; an unmapped Slack user is refused and counted, not given an invented id; tests with a
  real service token (accepted), a user token and another audience (refused). Widening `PATCH /status` to services
  was rejected: it would give a service token every transition and put an on-behalf-of field on a user endpoint.

---

### 0-17. Alert on `service_client_fallback_total{reason="auth"}`

**Type:** tech-debt · **Priority:** Medium · **Status:** Open

**Problem.** Fail-open clients count every fallback in `service.client.fallback{client,target,reason}`
(backlog #0-11), and `reason="auth"` (401/403) is a misconfiguration, not an outage. Nothing alerts on
it. Also: `service.client.fallback` does not say which operation fell back (for example a target lookup or a PRIMARY
lookup); an `operation` tag needs a change in `shared`.
**Unblocked by #0-16 (Done):** a rule in `docker/prometheus.rules.yml` with `scope: platform` now reaches the
operator — by email if `severity: critical` (out of band, `docker/alertmanager.yml`), and as an incident of the
reserved `platform-operator` tenant in any case. Earlier it would have become an incident of the unowned `system` tenant.

---

### 0-20. Tenant-owned fallback contact

**Type:** design · **Priority:** Medium · **Status:** Open

**Context.** The proper counterpart of the "fallback users on each escalation level" in PagerDuty: a
tenant configures its own last-resort contact, used before an entry is parked as UNDELIVERABLE (backlog
#0-18 removed the shared fallback address, so today "nobody on call" means UNDELIVERABLE plus an alert to
the operator). No notification setting exists per tenant (`tenant_settings` in auth-service only has
`mfaRequired`).

**Decide.** Where it lives (auth-service tenant settings, or a notification-service table), whether it is per
tenant or per team (see #0-12), who may edit it, and how notification-service reads it (HTTP with the
service token, or a copy kept in sync).

Related, accepted trade-off of #0-18: `NO_ONCALL` is terminal on the first attempt (unlike an oncall-service outage, which is
retried), so a shift-handover gap parks an `INCIDENT_OPENED` notification as UNDELIVERABLE. A short retry for `NO_ONCALL`
is worth weighing together with the tenant-owned contact.

---

### 0-22. The operator alert is email only

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Problem.** The content-free alert for an UNDELIVERABLE notification (backlog #0-18) is sent by email only.
`SlackNotificationChannel.send` posts into the tenant's own workspace (backlog #0-21) and stores the message
against the incident id, which an operator alert must not do, so Slack and SMS operator alerts need a plain-message path of their own.
Without an operator address only the ERROR log and the `notification.undeliverable` metric remain, and an
alert on that metric is backlog #0-17.
The email is limited to one per tenant and reason per interval, in memory and per replica; a cross-replica limit
(for example Redis, which ingestion already uses) or a digest is possible if that proves noisy.
The alert is sent synchronously on the scheduler thread, and the SMTP timeouts bound each socket operation, not the whole send.

---

### 0-23. The `oncall` and `slack-workspace` `@Retry` never fires

**Type:** tech-debt · **Priority:** Low · **Status:** Open (premise confirmed and approach decided in `/ready`, 2026-11-14:
remove both retries)
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** notification-service (client; src/main/resources/application.yml; src/test), root (README.md "Resilience" row, .ai/decisions/0016)

**Problem.** `OncallClientImpl`'s three lookups (`getCurrentOncall`, `findBySlackUserId`, `findCurrentByUserId`) carry
`@Retry(name = "oncall")` outside a `@CircuitBreaker` whose fallback answers every failure: `getCurrentOncall` and
`findCurrentByUserId` throw `OncallLookupUnavailableException`, which is not in the retry's `retry-exceptions` (a
whitelist), and `findBySlackUserId` returns `Optional.empty()`, a success to the retry. So the retry never runs, and
its `ignore-exceptions` (4xx) has no effect either. `SlackWorkspaceClientImpl`'s `@Retry(name = "slack-workspace")`
has the same shape and the same defect; its `application.yml` comment points here, and
`SlackWorkspaceClientResilienceTest` pins `max-attempts=1`, which hides it. No test runs the oncall client through
its proxies (`OncallClientImplTest` calls it directly). The retry that does run is the scheduler's: an entry whose
lookup failed stays PENDING and is tried again every cycle (30 s) until `lookup-retry-window` (10 min).

**Approach (decided).** Remove both retries, the way escalation-service's `OncallServiceClient` and notification's
`IncidentAckClient` work: a circuit breaker with a fail-open fallback that calls `ClientFallbackMetrics.record`, and no
retry, because the scheduler retries with a deadline (the repository's convention for retries, #0-52). Behaviour does
not change, as the retries never ran. Not chosen: making them fire the Slack Web API's way (`fallbackMethod` on
`@Retry`), which doubles the worst case of each lookup on the scheduler thread (8 s to about 16 s, about 32 s for an
escalated entry) and leaves about 7 s under the 4-minute lock; and listing the fallback's exception in
`retry-exceptions` (ingestion's way), which would retry 4xx and an open breaker too. The ACK path's invented actor when
`findBySlackUserId` fails (`UUID.nameUUIDFromBytes`) is #0-15's, not this item's. Left as it is: ingestion-service's
`application.yml` comment "(unlike notification-service's oncall retry, backlog #0-23)" stays true as history and is
another service.

**Acceptance criteria.**
AC1. `OncallClientImpl` carries no `@Retry`, and `application.yml` has no `resilience4j.retry.instances.oncall`; its
`@CircuitBreaker`s and fallbacks are unchanged.
AC2. `SlackWorkspaceClientImpl` carries no `@Retry`, and `application.yml` has no
`resilience4j.retry.instances.slack-workspace`; its `@CircuitBreaker` and fallback are unchanged.
AC3. A test runs `OncallClientImpl` through its Spring proxies (AOP, `CircuitBreakerAutoConfiguration`,
`RetryAutoConfiguration`, WireMock, as `SlackWorkspaceClientResilienceTest`): a 503 on each of the three lookups makes
exactly one request and ends as today (`OncallLookupUnavailableException` for `getCurrentOncall` and
`findCurrentByUserId`, `Optional.empty()` for `findBySlackUserId`), and `service_client_fallback_total{client="oncall"}`
goes up by one per call.
AC4. `SlackWorkspaceClientResilienceTest` no longer sets `max-attempts`, and shows one request on a 503 with the
service's own configuration.
AC5. The comments of both clients and of `application.yml`, README's "Resilience" row and ADR-0016 (its lines on
`@Retry(name = "oncall")` being "probably inactive" and on "the #0-23 problem") say the lookups have no retry of their
own and the scheduler's PENDING window is their retry; nothing calls them "probably inactive" or "unverified".
AC6. `./mvnw verify -pl notification-service -am` passes, with the 60% JaCoCo and `diff-cover` thresholds.

---

### 0-24. On-call contacts are not verified against tenant membership

**Type:** design · **Priority:** Medium · **Status:** Open

**Problem.** The `email`, `phone` and `slackUserId` of an on-call entry are free text entered by whoever creates the
schedule. Nothing checks that they belong to a member of the tenant, so a tenant admin can point its own incident
content at any address or Slack user. It is the tenant's own content going where the tenant chose, so it is not a
cross-tenant leak, but "tenant content only reaches members of that tenant" is then enforced by trust and not by the
platform. Found by security review of #0-18.

**Approach.** Take the contact from the user record in auth-service (a member of the tenant) instead of from free
text, or verify the address on creation (a confirmation email). Hardening in the same area: `SlackNotificationChannel.isSlackUserId` is only `startsWith("U")`; a stricter shape (for
example `^U[A-Z0-9]{8,}$`) would narrow what a tenant-controlled id can address, and the router shares the predicate.
Related: #0-20 (tenant-owned fallback contact).

---

### 0-25. A stale `notification_queue` write can overwrite a terminal status

**Type:** tech-debt · **Priority:** Medium · **Status:** Open (approach decided in `/ready`, 2026-11-14: state-guarded
conditional UPDATEs, not `@Version`)
**Autopilot:** ready · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** notification-service (domain, repository, service, scheduler; src/test), root (.ai/context/architecture.md)

**Problem.** The notification outbox entity, `NotificationQueueEntry`, has no guard against a stale write. Its
writers (`NotificationPersistenceService.markSent`, `markFailed`, and since #0-18/#0-19 `markUndeliverable` and
`recordLookupFailure`) save a detached entity, which is a merge that writes every mapped column as it was loaded.
That is safe today only because ShedLock serialises the scheduler; a run that outlives the lock, or an old pod during a
rollout, could overwrite another writer's status (for example the scheduler's catch-all `markFailed` over an
UNDELIVERABLE). And there is a second writer: `NotificationQueueRepository.restartLookupRetryWindows`, the bulk
UPDATE run when a tenant is resumed, whose own Javadoc says a stale scheduler entry "can write its old value back".

**Approach (decided).** The way auth-service's `AuthEmailOutbox` does it since #0-52 (ADR-0015), not `@Version`: each
transition is a conditional `UPDATE ... WHERE id = :id AND status = 'PENDING'` (`@Modifying(flushAutomatically = true,
clearAutomatically = true)`, returning the row count), and `recordLookupFailure` also guards its own field
(`first_lookup_failure_at`), so a stale write neither overwrites a terminal status nor undoes a restart. A count of 0
means another writer got there first: logged at info and counted in a Micrometer counter
`notification.queue.stale_write` tagged with the operation (`sent`, `failed`, `undeliverable`, `lookup`), and nothing
else happens (no audit event, no operator alert). No migration. Why not `@Version`, though CLAUDE.md lists it and
escalation-service's `EscalationTask` uses it for the same pause/resume shape: the criterion this item writes into
`.ai/context/architecture.md` (AC6). A write that records the outcome of an irreversible step on a row in a one-way
state machine is a state-guarded conditional UPDATE; a row that several places change over time (a timer, a level,
edited fields) carries `@Version`. `notification_queue` records a send that already happened, so it is the first;
`EscalationTask` moves its timer and level again and again, so it stays the second. Neither prevents a duplicate send
(it is detected after the send): ShedLock stays the guard against that.

**Acceptance criteria.**
AC1. An integration test (Testcontainers, notification-service) shows `markSent`, `markFailed`, `markUndeliverable`
and `recordLookupFailure` change only a row whose `status` is `PENDING`: on a row already SENT, FAILED or
UNDELIVERABLE each changes nothing and its row count is 0.
AC2. A test shows the scheduler's catch-all, after `markUndeliverable` has committed, leaves the row UNDELIVERABLE (its
`error_message` and `processed_at` unchanged).
AC3. A unit test shows that when the conditional update affects 0 rows, `NotificationPersistenceService.markUndeliverable`
writes no `NOTIFICATION_UNDELIVERABLE` audit event, `NotificationService.markUndeliverable` raises no operator alert,
and `notification.queue.stale_write` is incremented with the operation's tag.
AC4. A test shows `recordLookupFailure` does not overwrite a non-null `first_lookup_failure_at`, and a restart by
`restartLookupRetryWindows` is not undone by a stale scheduler write.
AC5. `.ai/context/architecture.md` replaces "An outbox row has one writer after its INSERT … the two such exceptions"
with the criterion above (outcome of an irreversible step on a one-way state machine: state-guarded conditional
UPDATE; a row changed over time from several places: `@Version`), names the notification queue next to the auth email
outbox, `AuthToken.markUsedIfUnused` and `mfa_recovery_requests`, and `EscalationTask` as the `@Version` case with a
bulk UPDATE that bumps `version`.
AC6. `./mvnw verify -pl notification-service -am` passes, with the 60% JaCoCo and `diff-cover` thresholds.

---

### 0-28. `notification_queue` rows are never purged

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Problem.** Nothing deletes queue rows in any status: SENT and FAILED were never purged, and since #0-18 UNDELIVERABLE rows
accumulate as well. The partial index `idx_notification_queue_status_created (status, created_at) WHERE status = 'PENDING'`
keeps the scheduler fast, but the table only grows, and an operator browsing UNDELIVERABLE rows has no index for them.

**Approach.** A ShedLock-protected retention job (delete terminal rows older than a configurable age, keeping UNDELIVERABLE
longer), like `NotificationScheduler`'s existing `slack_message_ts` cleanup. Decide retention with the audit requirements in
mind: the audit events are the compliance record, the queue is a work queue.

---

### 0-31. auth-service identity/config split — evaluated and deferred

**Type:** design · **Priority:** Low · **Status:** Open

**Context.** `AuthServiceApplication`'s own class Javadoc carries a `TODO (Backlog)` sketching a future split
(`auth-service` → authentication only; `identity-service` → users/teams/tenant settings; `apikey-service` →
machine-to-machine credentials, optional), explicitly flagged there as one of backlog #0-6's untracked TODOs. While
scoping backlog #0-21/#0-30, a *different* two-way split (identity/AuthN vs. config/integration, i.e. `ApiKey` +
`Integration` + `TenantSettings` together) was evaluated as an alternative to building #0-21 inside the existing
monolith. **Rejected for now, evidence below.**

**The TODO's own trigger doesn't apply yet.** Its stated criteria: *"Split when: independent scaling is needed,
separate teams own auth vs identity, or compliance (PCI-DSS, SOC2) mandates credential isolation. Do NOT split
prematurely."* None currently hold. Its own listed prerequisites also aren't done: a Redis credential cache for the
login hot path (`AuthService.login()` fetches `User` in the same transaction today), an outbox pattern for the
invite/user-deletion flow, and database separation.

**Why the user-proposed grouping (ApiKey+Integration+TenantSettings) isn't a clean file-move either, found by
reading the code:**
- `ApiKeyLookupServiceImpl.buildPrincipal` eager-fetches `User` (`ApiKeyRepository.findActiveByHash` does
  `LEFT JOIN FETCH k.ownerUser`) and reads `ownerUser.getRoleNames()`/`getEmail()` **in the same transaction, on
  every API-key-authenticated request** — not a one-off reference, a hot-path one.
- `Team` is needed by both proposed halves: `TeamService` (user-team membership, identity side) and
  `Integration.team` + `ApiKeyLookupServiceImpl.resolveTeamId` (config side, same hot path as above).
- `TenantSettings.isMfaRequired()` is read synchronously inside `AuthService.login()` — the TODO's own split
  already anticipated this by keeping `tenant_settings` with `identity-service`, not with `apikey-service`,
  which argues against grouping it with `Integration`/`ApiKey` as "config".
- `UserManagementService.archiveUser()`/`anonymizeUser()` write `User` and revoke the user's personal `ApiKey`s in
  one local `@Transactional` block today — a GDPR-relevant deletion flow that would become a distributed
  transaction post-split, exactly the class of problem the TODO's own "outbox pattern" prerequisite exists to solve
  first.
- Two FK constraints would cross the boundary (`api_keys.owner_user_id → users`, `integrations.team_id → teams`,
  both `ON DELETE SET NULL`) — schema-level, comparatively cheap — but the *ORM object-graph* coupling above is the
  real cost, not the FK syntax.
- The good news: the HTTP layer is already a clean boundary — none of the 6 controllers in auth-service mix both
  concerns.

**Decided.** Build backlog #0-21's new `SlackWorkspace` entity now, inside auth-service, shaped to require near-zero
rework if a split ever happens: no JPA relation to `User`, `teamId` stored as a plain column (not a `@ManyToOne`),
same flat-package convention `Integration`/`ApiKey` already use. Defer the actual split until the TODO's own trigger
conditions are met.

---

### 0-32. No notification channel is retried after a failed send

**Type:** design · **Priority:** Medium · **Status:** Open

**Problem.** Delivery is "at most once" per channel. `NotificationService.processEntry` tries each routed
channel once (plus, for Slack only, the in-call `@Retry` of `SlackApiClient`, which ran on a send only since #0-103;
email and SMS have none), records a failure in `notification_log`,
and marks the queue entry SENT anyway. A Slack API outage, an SMTP timeout or a Twilio error therefore loses
that channel's message for good. Backlog #0-21 adds one more cause: if auth-service cannot answer the
tenant's Slack-workspace lookup, Slack is skipped for that notification while email/SMS go out. That was a
deliberate choice: holding the whole entry (the #0-19 pattern) would make auth-service a hard dependency of
email and SMS, and retrying only the auth-service case would make one config lookup more reliable than the
send itself.

**What already exists.** Idempotency in `notification_log` is keyed per channel (incident + tenant + event type
+ escalation level + channel). If an entry stayed PENDING after a partial send, the next cycle would skip the
channels that already went out, so a per-channel retry needs no migration for that part. Since #0-104 one more cause loses a channel's message without a retry: while the `slack`
circuit breaker is open, Slack messages are recorded FAILED (`SLACK_UNAVAILABLE`, `circuit_open`) without being tried,
accepted until this item; a per-channel retry would send them once it closes. It costs more than a slow Slack did:
an open breaker fails a run's whole batch (up to `batch-size`, 200) in milliseconds, where a hanging Slack used to
reach about three entries per run and leave the rest PENDING (review of #0-104). Leaving such an entry PENDING, as a
failed on-call lookup does, needs this item's per-channel state: the failed Slack row in `notification_log` would
make the next run skip the channel. Since #0-93 every
channel failure carries a `NotificationFailureReason` marked permanent or not (a rejected address, a Slack channel
the bot is not in, versus an unreachable server or a rate limit), so what is worth retrying is already decided;
what is left is the per-channel state and its retry window.

**Open questions.** (1) The router asks oncall-service again on every cycle, and the on-call can change between
cycles: a retried Slack DM could go to someone other than the person who got the email. Pin the resolved
recipient on the entry, or accept it? (2) What does an entry become when the retry window runs out after some
channels were delivered? Not UNDELIVERABLE, since someone was reached. (3) `first_lookup_failure_at` is shared
with the #0-19 lookup window, so a per-channel window probably needs its own column or table. (4) Which failures
are worth retrying (5xx, timeout) and which are permanent (Slack `channel_not_found`, `invalid_auth`)?

**Approach.** Per-channel delivery state (pending / sent / failed-permanent) with backoff and a bounded window,
the same for every channel and cause. Not a Slack-only special case. Precedent since #0-52: auth-service's
`auth_email_outbox` (`next_attempt_at`, `deadline`) with `AuthEmailRetryPolicy` (backoff list, last step repeats,
bounded by a deadline, the last attempt moved to it), one writer with state-guarded conditional UPDATEs, and counters
for sends and give-ups.

---

### 0-33. Unify caching on Caffeine once a third cache appears

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Context.** The codebase has two in-memory caches, both hand-rolled `ConcurrentHashMap`s with a TTL and a
1000-entry cap (at the cap: evict expired, otherwise skip caching): `ServiceTokenProvider` (`shared`, one
token per tenant and audience, valid until token expiry minus a buffer, `synchronized` refresh so one token
is minted per miss) and `CachingSlackWorkspaceClient` (notification-service, backlog #0-21, 60 s TTL, caches
"no workspace" but never a failure, no lock around the HTTP call on purpose). No service configures Spring's
cache abstraction (`@EnableCaching`, `CacheManager`, Caffeine).

**Why not now.** Two caches, both working, each with semantics that would need custom configuration in
Caffeine (a per-entry `Expiry` for the token). Migrating means a new dependency, a change in `shared` (all 7
services rebuild), and ordering the cache aspect against Resilience4j on the same bean — `@Cacheable` is
applied by the same AOP proxy, so a self-call through `this` bypasses it exactly like the #0-21 circuit-breaker
bug. The gain (LRU instead of "skip when full", built-in metrics, less duplicated code) is small for two sites.

**Trigger.** A third cache. The likely one is the API-key lookup (`ApiKeyLookupServiceImpl.findActiveByHash`,
once per API-key-authenticated request) when `ApiKeyAuthFilter` is wired outside auth-service (backlog
#0-16 option 3, #0-30). It needs eviction on revoke (`@CacheEvict`), which is where the Spring abstraction
pays off. At that point introduce one Caffeine `CacheManager` and migrate both existing caches with it.

**Checked and deliberately not cached** (so nobody adds these believing they are missing):
- On-call lookups (`OncallClientImpl`, escalation's `OncallServiceClient`): rotations and overrides change who
  is on call; a stale entry pages the wrong person. Low volume, and #0-19's retry relies on fresh answers.
- `TenantSettings.isMfaRequired` (once per login): a security setting — a cached "false" would let logins skip
  MFA for a TTL after an admin enables it. One primary-key read.
- `IncidentAckClient` (a write), `GeminiClientImpl` (unique input per postmortem).
- Token revocation (`isRevoked`): already in Redis.

---

### 0-34. `ServiceTokenProvider` cache has no metrics

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Problem.** `ServiceTokenProvider` (`shared`) caches one service token per (tenant, audience), bounded at
`MAX_CACHED_TENANTS` = 1000. When the map is full of live entries it returns an *uncached* token, which means
minting a new JWT on every service-to-service call for that tenant. Today the only signal is a WARN log.
There is no hit rate, no size and no count of refused puts, so nobody can tell whether the cap is too small
or the refresh buffer too long. Every service calls another one through this class, so it runs on every
tenant's notification, escalation and ACK path.

**Approach.** Same as `CachingSlackWorkspaceClient` (backlog #0-21): a `CacheMeterBinder` subclass reading
`LongAdder`s, registered under `cache="service-token"`, so the meters use Micrometer's standard names
(`cache.gets{result=hit|miss}`, `cache.puts`, `cache.evictions`, `cache.size`) plus `cache.puts.skipped`.
A miss is a call that reaches `refreshAndGet`. Count it once per minted token, not per thread that waited on
the monitor and then found a fresh token (those are hits). `ServiceTokenProvider` is a `@Component` in `shared`, so
the `MeterRegistry` becomes one more constructor parameter. That touches every test that builds the class with
`new`, and a change in `shared` rebuilds all 7 services, which is why it was not folded into #0-21.

**Relation to #0-33.** If the move to Caffeine happens first, the standard meters come from
`CaffeineCacheMetrics` and this item reduces to tagging the cache. The meter names are the same either way,
so dashboards built on this item survive #0-33.

---

### 0-35. Slack install via OAuth ("Add to Slack") brings back ACK via Slack

**Type:** design · **Priority:** Medium · **Status:** Open

**Problem.** Backlog #0-21 connects a tenant's Slack by a manually pasted bot token. Without OAuth the only way an
admin can get an `xoxb-` token is from a Slack App they created in their own workspace. Slack signs every
interactive callback (a button click) with the signing secret of the App that posted the message, so each tenant's
clicks are signed with a secret the platform does not have. `SlackSignatureVerifier` checks one platform-wide
`SLACK_SIGNING_SECRET` and answers 401. The Acknowledge button was removed from messages rather than left to fail on
every click. `/api/v1/slack/actions`, `SlackActionService` and `updateMessageAfterAck` are kept unchanged. Found by
the #0-21 security review, where the DTO Javadoc (tenant's own App) and #0-21's reasoning for a global signing secret
(one App) contradicted each other.

**Options.**
- **(B, recommended) One platform App, OAuth v2 install.** An admin, logged in with the platform's own JWT, starts
  the install. The backend redirects to `slack.com/oauth/v2/authorize` with a signed, short-lived, single-use
  `state` bound to tenant and admin. The callback exchanges `code` + client secret via `oauth.v2.access` and stores
  the `xoxb-` token and `team.id` in the existing `SlackWorkspace`. The global signing secret is then correct and the
  button comes back as it was. This is standard for multi-workspace Slack apps (PagerDuty, Opsgenie). **It is Slack
  OAuth with the platform as the client, not an external identity provider for user login**, so the plan to stay on
  the platform's own JWTs (README "Design Decisions") is unaffected. Needs: `SLACK_CLIENT_ID`/`SLACK_CLIENT_SECRET`,
  public distribution enabled on the App (no Marketplace listing needed), an HTTPS redirect URL (a tunnel for local
  development), and a callback that is public in the filter chain (a browser redirect carries no JWT), so its whole
  security rests on `state`: test CSRF, replay and tenant mismatch.
- **(A) Keep one App per tenant, store its signing secret too.** The webhook reads the unverified `payload.team.id`,
  finds the workspace by `slack_team_id` (new internal auth-service lookup), verifies with that tenant's secret, then
  checks that the button's tenant matches the workspace's. It works without OAuth, but it needs a second encrypted
  secret (V18), manual Interactivity URL setup per tenant, and it becomes throwaway once (B) exists.
- Socket Mode was considered: with one App per tenant it means one WebSocket and app-level token per tenant held
  by notification-service. Rejected.

**Approach.** (B), together with #0-15.

**Requires #0-15.** The button's path ends in `IncidentAckClient`, which incident-service refuses today (403, and
its `acknowledgedBy` is dropped): with the button back and #0-15 open, every click would fail silently. The two
are done together; #0-15 records the analysis and the recommended endpoint.

**When.** Before the first production tenant uses Slack (the owner's decision, 2026-10-15): acknowledging from Slack
is part of the offer from the start, so this and #0-15 are done before anyone connects Slack in production. It used
to read "when Slack is actually used by tenants", a moment nothing in the platform would signal. Until then
incidents are acknowledged in the app.

---

### 0-36. Nothing checks entity `@Index` annotations against the real schema

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Problem.** Eight entities in six services (`Incident`, `IncidentHistory`, `AuditEvent`, `EscalationTask`,
`NotificationLog`, `NotificationQueueEntry`, `OncallSchedule`, `Postmortem`) list their indexes in
`@Table(indexes = ...)`. The Flyway migrations are the real schema. `ddl-auto: validate` does not check indexes,
so the lists are documentation that nothing verifies. `NotificationLog` drifted twice (V2 dropped its three
single-column indexes, V5 replaced one of V2's composites) before backlog #0-9 caught it by reading the code. Some
lists are also simplified on purpose: JPA cannot express a partial index, so `NotificationQueueEntry` shows
`(status, created_at)` for a `WHERE status = 'PENDING'` index.

**Options.** (1) A Testcontainers test per service that reads `pg_indexes` after the migrations and asserts every
`@Index` name on the service's entities exists (names only, since the definitions can't match exactly for
partial/expression indexes). Each service with Postgres integration tests already boots the migrated schema.
(2) Drop `@Index` from every entity and treat the migrations as the only documentation. This removes the drift
risk, but readers lose the at-a-glance list.

**Approach.** (1), added to each service's existing Postgres integration test, or a small shared test helper
in `shared`'s test utilities if one fits.

---

### 0-37. Ingest rate limiter answers 429, which Alertmanager drops without retry

**Type:** design · **Priority:** Medium · **Status:** Open (found while researching #0-16, not run)

**Problem.** `AlertIngestionController` answers 429 when the tenant or IP bucket is empty (around line 199).
Alertmanager's webhook notifier retries only network errors and 5xx and drops every 4xx, 429 included
(`notify/util.go`, `notify/webhook/webhook.go` in prometheus/alertmanager; the PagerDuty/Opsgenie notifiers add 429
to their retry codes, the webhook one does not). A tenant over its limit therefore loses its pages silently until
the next group flush, which is the failure the platform exists to prevent.

**Decide.** (1) 503 + `Retry-After` for webhook sources, so the sender retries within its flush window. (2) A limit
that does not reject per request (queue, or shed low severities first). (3) Keep 429 and document the loss.
Related: the response-code contract from #0-16 (a definite "no" is 4xx, "don't know / try later" is 503).

---

### 0-38. Integration key format has no checksum and a separator inside its alphabet

**Type:** tech-debt · **Priority:** Low · **Status:** Open

**Problem.** `ApiKeyHasher` produces `ipl_` + a base64url body. `_` and `-` are part of that alphabet, so the
separator can also appear inside the body (GitHub chose `_` for its token prefixes because it is not in their
body alphabet). There is no checksum, so a malformed key cannot be rejected without a lookup, and secret
scanning (GitHub's partner program asks for a unique prefix, high entropy and a 32-bit checksum) is weaker.
Entropy (24 random bytes, 192 bits) is fine.

**Work.** A new format, e.g. `ipl_` + base62 body + 6-character CRC32. Accept both formats during a transition.
Stored hashes need no migration, because the hash covers the full raw key.

**Acceptance.** New keys carry a checksum; a key with a bad checksum gets 401 without a lookup.

---

### 0-40. Dead-letter topics have no consumer or replay tooling

**Type:** design · **Priority:** Medium · **Status:** Open

**Problem.** `alerts.dead-letter`, `incidents.dead-letter`, `escalation.dead-letter`, `notification.dead-letter`
and `postmortem.dead-letter` are written by `DeadLetterPublisher` and read by nothing. A dead-lettered alert or
lifecycle event is lost unless someone reads the topic by hand, and nothing says that it happened.

**Decide.** (1) Alert on dead-letter growth (a metric plus a rule routed to the operator route from #0-16).
(2) A replay tool or endpoint, and who may use it: replaying a record re-enters tenant data into the pipeline, so
it needs the same per-record tenant resolution as the original consumers.

---

### 0-41. `teamId` from event payloads is not validated against the tenant's teams

**Type:** design · **Priority:** Low · **Status:** Open (found by code reading, not run)

**Problem.** `teamId` travels in `UnifiedAlertDto` and every `IncidentEvent` and is used for routing
(`IncidentCreationService`, escalation-service's `IncidentEventConsumer`, notification-service's
`NotificationRouter`) without checking that the team belongs to the tenant. The oncall lookups it feeds are
tenant-scoped, so a wrong id finds nobody rather than another tenant's people; the effect is a missed PRIMARY
lookup, not a leak.

**Decide.** Validate once where the id enters the platform (at incident creation, pulling from auth-service per the
#0-30 pattern), or accept and document it next to #0-12.

---

### 0-43. API key introspection can be amplified from many IPs

**Type:** design · **Priority:** Low · **Status:** Open (accepted residual risk of #0-16, found in review, not run)

**Problem.** Every unknown `ipl_…` key sent to ingestion-service is one introspection call to auth-service.
`AuthFailureRateLimiter` bounds that per client IP (10 failures, refilled per 60 s), and the negative cache
(`CachingApiKeyIntrospectionClient`, 5 s, 1,000 entries) only helps when the same wrong key repeats. A sender
with many IPs and a fresh random key per request therefore turns its request rate into auth-service calls,
up to the IP bucket capacity times the number of IPs. It cannot authenticate (192-bit keys), and under
sustained load the `api-key-introspection` breaker opens, so ingest answers 503: the failure mode is
unavailability of key authentication, not a bypass. It also hurts valid keys that are not in the positive
cache while the breaker is open.

**Decide.** (1) Accept and document (today's state). (2) A global cap on introspection calls per second in
ingestion-service (bulkhead or rate limiter on the client), so an attack degrades only uncached keys.
(3) Reject malformed keys offline first, which needs the checksum from #0-38. (4) Edge rate limiting (the
Cloudflare/Ingress layers in `application.yml`'s rate-limiting comment). (2) and (3) are cheap together.

---

### 0-44. Concurrent cache misses for one API key each call auth-service

**Type:** tech-debt · **Priority:** Low · **Status:** Open (found in review, not run)

**Problem.** `CachingApiKeyIntrospectionClient.introspect` checks its maps and on a miss calls the delegate
directly, with no per-key coalescing. When an active key's entry expires (every 60 s), N concurrent requests
with that key send N introspection calls instead of one. Negligible at today's traffic; it grows with the
concurrency of a single integration and with the number of ingestion-service replicas.

**Work (when a high-throughput integration appears).** Single-flight per key hash (a map of in-flight
futures), or a cache library with an async loader — which is also the trigger for #0-33. Keep the rule that
failures are never cached.

---

### 0-45. API key usage write holds a second auth-service DB connection

**Type:** tech-debt · **Priority:** Low · **Status:** Open (found in review, not run)

**Problem.** `ApiKeyIntrospectionService.resolve` runs in a read-only transaction and calls
`ApiKeyUsageRecorder.recordUsage`, whose `last_used_at` update runs in `REQUIRES_NEW`: the outer transaction
is suspended and a second Hikari connection is taken for the update. auth-service's pool is 5
(`maximum-pool-size`). The write is throttled (once per `api-key.usage.write-interval`, default 5 min, per
key), so this matters only when many distinct keys miss the introspection cache at once — for example after
an ingestion-service restart (cold cache), when every integration's first request lands together.

**Work.** Load-test that cold-cache burst first. If the pool saturates: raise `maximum-pool-size`, or do the
write after the read transaction has ended (not nested), or hand it to a bounded executor with the metric
kept. The synchronous `REQUIRES_NEW` design is documented in `ApiKeyUsageRecorder`; a change reverses it and
should say so there.

---

### 0-46. Personal API keys can be granted scopes their owner's role does not allow

**Type:** bug · **Priority:** Low · **Status:** Open (found in #0-16 review, by reading the code, not run)

**Problem.** `ApiKeyScope.allowedForRole` decides which scopes a PERSONAL key may carry, and its own Javadoc
says a personal key "cannot be granted scopes beyond what the owner's tenant-level role permits". But it
only knows `ROLE_ADMIN` and `ROLE_RESPONDER`: every scope except `teams:write` is allowed to a RESPONDER,
including `alerts:ingest`, while the ingest endpoint lets a JWT in only with `INGESTOR` or `ADMIN`. So a
RESPONDER can create a personal key that does what their own token cannot. The same mapping decides every
other scope, so the check is not a real "no more than the owner" rule, only a hand-kept list. `ROLE_INGESTOR`
owners are not handled at all (they get no scope).

**Still latent.** Two places check a scope. Ingest's `hasScope(alerts:ingest)` is out of reach for personal
keys: #0-16 made auth-service's introspection answer `active:false` for every PERSONAL key. Since #0-89 the
team routes of auth-service need `teams:read` / `teams:write` (`SecurityConfig`, `ApiKeyAccess`; a key
reaches no other route of auth-service), but each also keeps its role check, which a key passes only with
its owner's current roles, so a scope this mapping wrongly allows gains nothing there. It becomes a real
bug as soon as a scope guards a route without a role check.

**Work.** Derive "allowed for role" from the same rule the endpoint enforces (e.g. `alerts:ingest` requires
`INGESTOR` or `ADMIN`), handle every role in `SecurityRoles`, and decide what happens to existing personal
keys whose scopes their owner no longer qualifies for (reject at use, or revoke). Test per role and scope.

---

### 0-48. User PII lives on the `users` row; erasure is in-place anonymization

**Type:** design · **Priority:** Low · **Status:** Open (was an untracked `TODO (Data Vault)`, see #0-6)

**Problem.** `User` stores `email` and `password_hash` on the `users` row. GDPR erasure
(`UserManagementService.anonymizeUser` → `User.anonymize`) overwrites them in place with a placeholder
and keeps the row, so historical references (audit log, incident assignments) stay valid. The residual
risk: any copy of the email outside that row (a cache, a log line, another service, a backup) can still
be linked to the user's UUID, and every new PII column has to be remembered in `anonymize()`.

**Option considered ("Data Vault" split).** Keep `users` PII-free (`id`, `tenant_id`, `active`, ...) and
move PII to a `personal_data` table (`user_id` FK, `email`, `password_hash`, ...); erasure becomes
`DELETE FROM personal_data WHERE user_id = ?`. Costs: a migration of existing rows, a join on the login path
and on every email lookup (`findByEmailAndTenantId`, the unique email-per-tenant constraint moves with it),
and it does not by itself remove copies held elsewhere.

Copies known so far include the audit log: events such as `USER_CREATED` and, since #0-80,
`TENANT_PROVISIONED` / `TENANT_ADMIN_REINVITED` carry the user's email address in their payload, and
anonymizing the user does not touch them.

**Work.** Decide whether the in-place approach is enough (document what "erased" covers, including logs
and backups) or plan the split, when a customer or audit requires stronger erasure guarantees. The
`TODO`s in `User` and `UserManagementService` point here.

---

### 0-55. Auth email failures do not tell an SMTP outage from a rejected address

**Type:** design · **Priority:** Low · **Status:** Open (found with #0-52)

**Problem.** `AuthEmailScheduler` treats every failed send alike: counted as
`auth.email.send{outcome="failed"}` and retried until the request's deadline. An SMTP connection or
authentication failure (the platform's problem) and a recipient the server rejects with a permanent
5xx, e.g. a typo in an invite address (the tenant's problem), look the same. So at low volume one
rejected address fires `AuthEmailDeliveryFailing`, a critical email to the operator about a tenant's
data, and a permanently rejected address is retried for 7 days for nothing.

**Approach.** Classify the exception from `JavaMailSender`: connection / authentication / timeout
(`MailAuthenticationException`, `MailSendException` caused by `ConnectException`,
`SocketTimeoutException`) versus a rejected recipient (`SendFailedException` with invalid addresses,
SMTP 5xx on RCPT). Tag the counter (`cause=transport|recipient|other`) and alert only on `transport`.
notification-service already does this classification (#0-93, `EmailNotificationChannel.classify`, with a
recipient rejection only for an SMTP reply naming the address: an enhanced `5.1.x`, or 550/551/553 without one,
so "550 5.7.1 Relaying denied" stays the platform's); moving it to `shared` would give both services one rule.
Decide whether a permanent recipient rejection gives up at once (`PERMANENTLY_FAILED`, reason
`RECIPIENT_REJECTED`) and how the tenant's admin learns about it (audit event, admin UI), since it
is not the operator's to fix. Check how 4xx (greylisting, mailbox full) is reported, since that must
keep being retried.

**Also: bounces after acceptance.** An entry is SENT once the SMTP server accepts the message; a later bounce
(mailbox does not exist, complaint) never reaches auth-service. With a real provider (SES, Postmark, SendGrid —
none is configured yet, and Kubernetes' `MAIL_HOST` points at a missing host, #0-42) consume its bounce/complaint
webhook or notification, mark the entry, and tell the tenant's admin, the same "tenant's problem, not the
operator's" route as a rejected recipient.

---

### 0-56. forgot-password leaks whether an account exists through response time

**Type:** design · **Priority:** Medium · **Status:** Open (found with #0-52)

**Problem.** `POST /api/v1/auth/forgot-password` always answers 202, but does different work on the request
thread depending on the account: an unknown email sleeps in `WorkSimulator` (8–11 ms, calibrated once to the
"user exists" path), a reset already PENDING returns after one read, and a new reset looks up the user
and inserts the outbox request (since #0-52 the token is created later, by the scheduler). Each branch
has its own latency, so response times measured at scale tell which emails have accounts. The calibration
drifts with every change to the "user exists" path. The endpoint has no rate limit, which makes the
measurement cheap and also lets anyone flood a mailbox with reset emails.

**Approach.** (A) Take the work off the request path, as the OWASP Forgot Password Cheat Sheet suggests:
the endpoint only records "reset requested (email, tenant)" and returns 202, the same single insert whether or
not the account exists; a scheduled job (ShedLock) resolves the user, invalidates old tokens, creates the new
one and writes the email outbox entry. `WorkSimulator` then goes away. Needs a table (and a retention rule for
requests about unknown emails, which hold an email address). (D) Rate limit per IP and per email with bucket4j on
Redis, the pattern ingestion-service already uses (#67), answering 202 either way.

---

### 0-58. `GlobalExceptionHandler` and `UnauthorizedEntryPoint` have no tests of their own in `shared`

**Type:** tech-debt · **Priority:** Medium · **Status:** Open (found with #0-57; narrowed in `/ready`, 2026-11-14)
**Autopilot:** ready · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** shared (src/test: com.incidentplatform.shared.exception, com.incidentplatform.shared.security)

**Problem.** Once the JaCoCo agent attached (#0-57), `shared`'s own tests turned out to cover none or little of its
Kafka tenant classes, `GlobalExceptionHandler` and `UnauthorizedEntryPoint`. #0-91/#0-92 gave the Kafka classes
their own tests (`TenantKafkaRecordResolverTest`, the interceptors' tests, `DeadLetterPublisherTest`; and
`AuditEventKafkaSenderTest` exists). Left: `GlobalExceptionHandler` (`shared/exception`) and `UnauthorizedEntryPoint`
(`shared/security`) have no test class in `shared`: services' security tests exercise them, and the
`SharedSecurityAutoConfiguration*Test`s only construct the entry point, but JaCoCo counts only a module's own tests.
Both are on the error path of every service: the body of every 4xx/5xx answer and of every 401.

**Work.** Unit tests of each class's contract in `shared`: JUnit 5 and Mockito, no Spring context (as
`JwtAuthFilterTest`), `GlobalExceptionHandlerTest` in `shared/src/test/java/com/incidentplatform/shared/exception/`
and `UnauthorizedEntryPointTest` in `.../shared/security/`. The response is a Mockito `HttpServletResponse` over a
`StringWriter` (or `spring-test`'s `MockHttpServletResponse` if it is already on `shared`'s test classpath): no new
dependency in `shared/pom.xml`. Test code only: a test that would need a production change is not written here.
Out of scope: `GlobalExceptionHandler` does not redact `apiKey` and `privateKey` fields (#0-245), and the service
classes below 60% (#0-246).

**Acceptance criteria.**
AC1. `GlobalExceptionHandlerTest`: `handleResourceNotFound` returns 404 with `RESOURCE_NOT_FOUND` and the
exception's message.
AC2. `GlobalExceptionHandlerTest`: `handleBusinessException` returns the exception's own `httpStatus` and `errorCode`.
AC3. `GlobalExceptionHandlerTest`: `handleValidationErrors` returns 400 `VALIDATION_FAILED` with one `ValidationError`
per field error; the rejected value of a field whose lower-cased name contains `password`, `secret`, `token` or
`api_key` is `[REDACTED]` (`userPassword` among them); a normal field keeps its value; a null rejected value stays
null. (`apiKey` and `privateKey` are not redacted today: #0-245, not asserted here.)
AC4. `GlobalExceptionHandlerTest`: `handleConstraintViolation` returns 400 with the property path and message of each
violation, and a null rejected value.
AC5. `GlobalExceptionHandlerTest`: `handleTypeMismatch` returns 400 `INVALID_PARAMETER_TYPE`, its message naming the
parameter only.
AC6. `GlobalExceptionHandlerTest`: `handleAuthenticationException` returns 401 `UNAUTHORIZED` with a fixed body that
holds no text of the exception; `handleAccessDenied` returns 403 `FORBIDDEN` with a fixed body.
AC7. `GlobalExceptionHandlerTest`: `handleOptimisticLocking` returns 409 `OPTIMISTIC_LOCK_CONFLICT`.
AC8. `GlobalExceptionHandlerTest`: `handleUnexpectedException` returns 500 `INTERNAL_SERVER_ERROR` with no internal
message in the body, and rethrows a `NoResourceFoundException` instead of answering 500.
AC9. `GlobalExceptionHandlerTest`: the `requestId` of every body is the MDC's `requestId`, or `"unknown"` when the MDC
has none; the MDC is cleared after each test.
AC10. `UnauthorizedEntryPointTest`: `commence` sets status 401, content type `application/json` and UTF-8, and writes
an `ErrorResponse` with `errorCode` `UNAUTHORIZED` and `status` 401, read back with a real `ObjectMapper`.
AC11. `UnauthorizedEntryPointTest`: `requestId` comes from the response's `X-Request-Id` header when it is set and not
blank, else from the MDC, else `"unknown"`: all three paths and a blank header.
AC12. `UnauthorizedEntryPointTest`: the body holds no text of the `AuthenticationException` passed in.
AC13. Both classes are above 60% LINE in `shared`'s JaCoCo report (`./mvnw verify -pl shared`), and the change passes
the existing `jacoco:check` and `diff-cover`; no new CI check.

---

### 0-62. Any GitHub Action from the Marketplace is allowed to run

**Type:** ci · **Priority:** Low · **Status:** Open (found with #0-59)

**Problem.** The repository's Actions policy is `allowed_actions: all` (Settings → Actions → General;
`GET /repos/{owner}/{repo}/actions/permissions`), so any workflow change can pull in any third-party
action, and only review stands between a typo-squatted or abandoned action and the job's token and
secrets. #0-60 fixes *which version* of an action runs; this is about *which actions* may run at all.

**Approach.** Switch to "Allow {owner}, and select non-{owner}, actions and reusable workflows": allow
actions created by GitHub, and list the others by owner or repository (today `dorny/paths-filter`,
`madrapps/jacoco-report`, `azure/setup-kubectl`, `docker/*`; `github/codeql-action` is GitHub's own).
Adding a new third-party action then needs a deliberate settings change as well as a PR. Prefer an
explicit list over "verified creators", which admits every verified publisher. Record the list in
README "Infrastructure Hardening", since the setting is invisible in diffs. It takes two calls:
`PUT /repos/{owner}/{repo}/actions/permissions` sets `allowed_actions=selected`, and
`PUT .../actions/permissions/selected-actions` sets the list. The first call also carries
`sha_pinning_required` (on since #0-60), and GitHub's docs do not say what omitting it does: send
`sha_pinning_required=true` with it and re-read the settings afterwards, so narrowing the allowed
actions does not switch SHA pinning off.

---

### 0-64. Kubernetes pods run without a `securityContext`

**Type:** design · **Priority:** Medium · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** No Deployment or StatefulSet in `k8s/base` sets a pod or container `securityContext`, and the namespace
(`k8s/base/namespace/namespace.yml`) carries no Pod Security Admission label. The service images already run as a
non-root user (`USER appuser` in every Dockerfile), but nothing in the manifests enforces it, so an image that drops
that line would run as root unnoticed. Containers also keep the default capabilities, may escalate privileges, have a
writable root filesystem and no seccomp profile, and every pod gets the namespace's service account token mounted
although no service calls the Kubernetes API.

**Approach.** Label the namespace `pod-security.kubernetes.io/enforce: restricted` (and `warn`/`audit`), then give every
workload `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`,
`seccompProfile.type: RuntimeDefault`, `readOnlyRootFilesystem: true` with an `emptyDir` for `/tmp` (the JVM and
Tomcat write there), and `automountServiceAccountToken: false`. Postgres, Redis and Kafka need their own check: their
images expect to write to their data directories and some start as root.

---

### 0-65. No NetworkPolicy: every pod can reach every other pod

**Type:** design · **Priority:** Medium · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** `k8s/` has no NetworkPolicy, so the namespace is flat: any pod reaches Postgres, Redis, Kafka, every
service's management port (8091–8097) and incident-service's `/dev/**` wherever the dev profile is on. One compromised
or misbehaving pod can use all of them. This is what made #0-63 exploitable from inside the cluster even though the
Ingress does not route `/dev`.

**Approach.** A default-deny policy for ingress (and later egress) in the namespace, then explicit allows: the Ingress
controller to the API ports, each service to the data stores it uses (auth-service and ingestion-service to Redis,
everything but oncall-service to Kafka, all services to Postgres), service-to-service calls that exist
(notification → incident, oncall, auth; escalation → oncall; ingestion → auth; postmortem-service has an
`incident-service.base-url` setting but no code calls it), and the
monitoring namespace to the management ports. Egress default-deny also needs DNS (kube-dns) for every pod and the
external calls: postmortem-service to the Gemini API, notification-service to Slack, the SMTP server and the SMS
provider, auth-service to the SMTP server. Needs a CNI that enforces NetworkPolicy; Minikube's default does not.

---

### 0-66. Redis and Kafka in Kubernetes have no authentication, and no data store uses TLS

**Type:** design · **Priority:** Medium · **Status:** Open (found in the 2026-09-30 infrastructure security audit;
the Postgres part is done: the Secret with #0-78, the default password in PR #444)

**Problem.**
- **Redis** (`k8s/base/infrastructure/redis.yml`) runs `redis-server --appendonly yes` with no password. It holds
  the token revocation list and the rate-limit buckets, so any pod can un-revoke a token or reset a limit. Since
  Redis 8 (2026-11-12) the image also ships the Query Engine, JSON, time series and probabilistic modules, so more
  commands sit behind the same open port (review of the Redis 8 move, security).
- **Kafka** (`kafka.yml`) listens `PLAINTEXT` with no SASL and no ACLs. Any pod can produce to `alerts.raw` or
  `incidents.lifecycle` for any tenant: since #0-92 consumers refuse a record whose header and payload disagree,
  but a forged record naming one tenant in both is taken as that tenant's.
- **Postgres** (done): since #0-78 the password comes from each overlay's `app-secrets` (`DB_PASSWORD`, passed to the
  six services that use the database and to the init script that creates the role), and the base no longer ships a
  Secret. `application.yml` used to fall back to `${DB_PASSWORD:incident_secret}`, so a run without the variable
  connected with the dev password; it now reads `${DB_PASSWORD}` with no default, and a CI step ("No service has a
  default database password") keeps it that way. No in-app check was added: Kubernetes (`secretKeyRef`) and compose
  (`${VAR:?}`) already stop a missing password with a clear message (an empty Kubernetes value gets
  through and fails like a wrong password), and for `spring-boot:run` the symptom ("password
  authentication failed", since Spring Boot leaves an unresolved placeholder in `spring.datasource.*`) is documented
  in `docs/database-roles.md`.
- No connection to any of the three uses TLS.

**Approach.** Redis `requirepass`
(or ACL users) from a Secret, wired to `REDIS_PASSWORD`, which the services already read. Kafka SASL/SCRAM with a
user per service and ACLs per topic, which also closes the forged-header path. TLS on all three once a certificate
source exists (#0-75). Pairs with #0-67.

---

### 0-67. All seven services share one database role

**Type:** design · **Priority:** Medium · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** Every service connects as `incident_app`, which owns the database, the `public` schema and every table
in it (since #0-78 it is no longer a superuser, but as the one owner it still has every right on every table, and an
owner bypasses Row-Level Security unless a table sets `FORCE ROW LEVEL SECURITY`; and as an owner it can create
triggers and functions that run with the rights of whoever fires them, including the admin). That
each service owns its own tables (CLAUDE.md "Persistence") is a convention; the database does not enforce it. A SQL injection or code execution bug in any service, including the least trusted ones
(postmortem-service handles LLM output), can read and write auth-service's tables: Argon2 password hashes, encrypted
MFA and Slack secrets, API key hashes, auth tokens.

**Approach.** Builds on #0-78 (done: `incident_app` is no longer a superuser, `postgres` is the admin; see
`docs/database-roles.md`). One role per service that owns its tables and its
Flyway history table, with no rights on other services' tables; a separate migration role if Flyway should not run as the runtime role. Existing tables need an
ownership transfer migration per service. Decide whether each service gets its own schema (cleaner grants,
`search_path` per role) or stays in `public` with per-table grants.

---

### 0-68. SAST has never run: Snyk Code is not enabled, and CodeQL is not set up

**Type:** ci · **Priority:** Medium · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** The `snyk-code` job in `snyk.yml` fails on every run with `403 Snyk Code is not enabled (SNYK-CODE-0005)`
(verified on the #0-61 dispatch run), and `continue-on-error: true` shows it as a success. No SARIF is produced, so
the Security tab has never had a code-scanning result, while README describes the job as "static analysis of Java
source code". GitHub's CodeQL, free for public repositories, is not configured (`code-scanning/default-setup`:
`not-configured`, languages `actions`, `java-kotlin`).

**Approach.** Enable CodeQL default setup (Java and Actions; the Actions queries also check workflows for injection
and permission problems), then remove the `snyk-code` job, or enable Snyk Code on the account if a second SAST engine
is wanted. Correct README "Security Scanning" either way.

---

### 0-69. The Snyk dependency scan fails on every run, so a new finding changes nothing

**Type:** ci · **Priority:** High · **Status:** Open — A1 done in PR #622 (owner, after `/research 0-69`, 2026-11-13); A2, B1-B3 open
(found in the 2026-09-30 infrastructure security audit; updated 2026-10-20 and 2026-11-13)
**Autopilot:** human-only · **Risk:** high · **Complexity:** high · **Depends on:** #0-158 (the date B2's ignores expire on)
**Touches:** root (pom.xml, .snyk, BACKLOG.md), ci (.github/workflows/snyk.yml), docs (README.md "Infrastructure Hardening")

**Problem.** `snyk test --severity-threshold=high` is red on every push to `main` and every weekly run, so a new
critical CVE would not change its status. The `.snyk` ignores were no sound baseline either: the Tomcat ones
(removed by #0-157) justified the risk with "All endpoints require JWT authentication", which is false (login,
health, Swagger #0-73 and the Slack webhook are public, ingestion takes API keys) and no mitigation for a Tomcat CVE,
reached before any Spring Security filter.

**State on 2026-11-13 (run 43451054483, `/research 0-69`).** 34-42 issues in each of the eight projects, 295 entries.
`.snyk` holds 9 ignores, expiring 2026-12-31 or 2027-01-01. By how each can be fixed (versions: Maven Central today):

| Group | Newest open-source release of our line | Fix |
|---|---|---|
| Spring Framework 6.2 (`spring-webmvc` Critical Arbitrary Code Injection, `spring-web` XSS / cookie without `Secure` / DoS, `spring-expression`, `spring-beans`, `spring-context-support` Directory Traversal) | 6.2.19, ours: the line's last | 7.x only, Spring Boot 4 (#0-158) |
| Spring Security 6.5 (Timing Attack, Predictable IV with CBC) | 6.5.11, ours: the last | 7.x only |
| spring-kafka 3.3, kafka-clients 3.9 (data amplification, sequential allocation) | 3.3.16, 3.9.2: the last | 4.x (Kafka 4, Renovate #165) |
| Micrometer 1.15 (CRLF Injection, memory not released), reactor-core 3.7 | 1.15.12, 3.7.19: the last | 1.16.x (a minor above what Boot 3.5 manages) / Boot 4 |
| jaxb-core 4.0.9 (XXE) | 4.0.9: the last 4.0 | Boot 4 |
| Jackson 2.21 (databind Critical deserialization, DoS), also through Flyway's `jackson-dataformat-toml` | 2.21.8 | **A1, done**: `jackson-bom.version` (Flyway needs no bump) |
| PostgreSQL JDBC (failing open) | 42.7.14 | **A1, done**: `postgresql.version` |
| Netty 4.1 through Lettuce (Critical, host mismatch, infinite loop) | 4.1.140 | **A1, done**: `netty.version` (GitHub's advisories fix the Critical and the loop by 4.1.137; Snyk names no fixed version, so the next run on main shows what it clears) |
| zstd-jni 1.5.6-4, snappy-java 1.1.10.5, at.yawk lz4-java 1.10.1, from kafka-clients | 1.5.7-26, 1.1.10.12, 1.14.0 | A2: overrides, if kafka-clients 3.9.2 takes them |
| zookeeper 3.8.6 through `spring-kafka-test` (scope `test`, not in any jar) | 3.8.8 | A2: override, or the gate leaves test scope out (check Snyk's Maven options) |

No producer enables Kafka compression (`git grep compression`), so the compression issues need a compressed batch
from someone else; Kafka in k8s has no authentication (#0-66), so that is a limit, not a fix.

**Plan (owner, after `/research`).**
- **A1 (done):** the overrides of the table, each with its Snyk ids in the root `pom.xml` comment (the #0-157 pattern).
- **A2:** zstd-jni, snappy-java and lz4-java overrides with a Kafka test that sends compressed batches; zookeeper 3.8.8
  or test scope out of the gate.
- **B1, first of B:** triage `spring-webmvc`'s Critical (Arbitrary Code Injection): what it needs and whether a service
  reaches it. Reachable: #0-158 becomes urgent and no ignore is written for it.
- **B2:** for each issue only Boot 4 fixes, an ignore in `.snyk` with a reason from reachability (which feature it
  needs, whether a service uses it), expiring on the date #0-158's ADR sets (its AC1: the migration plan, or a deferral
  with a date). An ignore "tracked for the 4.x migration" without that date is what this item exists against.
- **B3:** before 2026-12-31, re-check the 9 ignores that expire then, so the job does not turn red again for that;
  among them the two Netty ones (`SNYK-JAVA-IONETTY-16438322`, `-16438930`), whose reason, "requires Spring Boot 4 /
  Netty 4.2", may be false since 4.1 is patched up to 4.1.140 (security review of A1).
- Find out why OWASP Dependency-Check is green where Snyk reports Critical issues (another database, CPE matching, a
  suppression) before a green OWASP run is read as clean.

**Acceptance criteria.**
AC1. Every issue with a fix in the current line is fixed by an override naming its Snyk ids (A1 done, A2 open).
AC2. `spring-webmvc`'s Critical is triaged in this item, with what it needs and whether a service reaches it.
AC3. Every remaining issue has an ignore with a reachability reason and an expiry no later than #0-158's decision date.
AC4. The dependency job is green on `main`, and a new high issue turns it red.

---

### 0-70. Built images are not scanned, and no SBOM is produced

**Type:** ci · **Priority:** Low · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** OWASP Dependency-Check and Snyk scan the Maven dependency tree only. The operating system packages of the
`eclipse-temurin:*-jre-alpine` runtime images, and the JRE itself, are scanned by nothing. CI builds all seven images
(`push: false`) but does not scan them, and no SBOM records what an image contains.

**Approach.** Scan each built image in the Docker job (Trivy or Grype, pinned by version and checksum like the Snyk CLI,
#0-61), failing on fixable high and critical findings, and emit an SBOM (Syft or `docker buildx` attestations) as a
build artifact.

---

### 0-71. Kubernetes and compose images use mutable tags, and some are not tracked by Renovate

**Type:** tech-debt · **Priority:** Low · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.**
- The service Deployments in `k8s/base` use `image: <service>:latest` with `imagePullPolicy: IfNotPresent`; the
  overlays replace the tag with `dev`, `staging` or `1.0.0`, all mutable, so a node can keep running an old image
  under the same tag.
- Third-party images in `k8s/` are not tracked by Renovate, whose `kubernetes` manager needs file patterns that
  `renovate.json` does not set: `apache/kafka:3.7.0` (compose runs 3.9.2), `redis:8-alpine` (was 7 until 2026-11-12), `postgres:16-alpine`,
  `busybox:1.36`, and since #0-42 `axllent/mailpit` in `k8s/overlays/dev/mailpit.yml`, whose tag
  `check-k8s-mail.rb` requires to equal compose's: a compose-only Renovate PR fails that check until the manifest is
  bumped by hand (ADR-0026).
- `docker/docker-compose.yml` uses `:latest` for `provectuslabs/kafka-ui`, `danielqsj/kafka-exporter` and
  `dpage/pgadmin4` (`grafana/grafana` was pinned to `13.2.3` in #0-94 step 2, as it reads every tenant's logs).

**Also (owner, 2026-11-12): a major of an image moves everywhere at once.** Four Renovate PRs bump a major in compose
only, each green on CI but each leaving the image at another version in the tests and in k8s: #165 `apache/kafka`
3.9.2 → 4.4.0 (`DeadLetterPublisherKafkaIntegrationTest` pins `apache/kafka:3.9.2`, "the compose tag" per CLAUDE.md;
k8s runs 3.7.0), #194 `redis` 7 → 8 (`MfaResetRateLimiterTest` and `PlatformRateLimiterTest` ran `redis:7-alpine`, as
k8s did; done on 2026-11-12 the way this paragraph says: compose, both tests, k8s and the mutation case of
`test-k8s-environments.sh` in one change, #194 superseded), #171 `postgres` 16 → 18 (conflicting; every Testcontainers test and k8s run `postgres:16-alpine`; 18 needs
the volume mounted one level up and an empty volume, `make dev-reset`), and #166 `eclipse-temurin` 21 → 25 in the seven
Dockerfiles (the runtime would differ from the JDK that compiles and tests, 21 in CI and the devcontainer: a decision
of its own, with #0-158). The other three are held, not merged: a major goes to compose, the Testcontainers tags and k8s in one change, or
not at all; Renovate does not see the tags in Java test code, so the grouping has to name them too (a `customManagers`
regex, or one constant per image the tests read).

**Approach.** Pin every third-party image to a version tag (and a digest where Renovate can keep it current), enable
Renovate's `kubernetes` manager for `k8s/**/*.yml`, and deploy service images by immutable tag (the commit SHA) or
digest once a registry exists. Group an image that compose and k8s both run (`axllent/mailpit`, and Kafka once its
versions agree) across the two managers in one `packageRules` entry, so both files move in one PR.
Since #0-29, `.github/scripts/check-k8s-environments.rb` refuses an untagged or `latest` image in the prod render
and a service tagged with an environment's name, but accepts any other tag (`1.0.0` included), so it does not
make prod immutable; once services deploy by digest, tighten its rule 3 to require a digest for them (its
mutation test already has a digest case).

---

### 0-72. docker-compose publishes every port on all interfaces, with default credentials

**Type:** tech-debt · **Priority:** Low · **Status:** Open — Grafana done in #0-94 step 2 (found in the 2026-09-30 infrastructure security audit)

**Problem.** Every `ports:` entry in `docker/docker-compose.yml` has the form `"5432:5432"`, which binds `0.0.0.0`,
so on any shared network (office, café) other machines reach Postgres (the services' role with `incident_secret`, and
since #0-78 the `postgres` superuser with `postgres_admin_dev`, both the `docker/.env.example` values), Redis (no password), Kafka
(plaintext), pgAdmin (`admin`), Prometheus (with `--web.enable-lifecycle`, which lets anyone
reload or shut it down), Alertmanager and every service's management port. Docker's port publishing also bypasses
host firewalls such as `ufw`. Grafana is no longer one of them: since it reads every tenant's logs (#0-94 step 2)
it is on `127.0.0.1:3000` with `GRAFANA_ADMIN_PASSWORD` (no default) instead of `admin`/`admin` on every interface.

**Approach.** Prefix every published port with `127.0.0.1:`. Services talk to each other on the compose network and
need no published ports for that; only the ports a developer opens in a browser or a client need publishing.

---

### 0-73. Swagger UI and the OpenAPI document are public in every profile

**Type:** tech-debt · **Priority:** Low · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** `SharedSecurityAutoConfiguration.PUBLIC_PATHS` permits `/v3/api-docs/**`, `/swagger-ui/**` and
`/swagger-ui.html` in every service and profile, and springdoc runs with its defaults (enabled) in every service that
has it: auth, ingestion, incident, notification, oncall and postmortem. escalation-service has no HTTP API and no springdoc. An unauthenticated caller gets the full API description of each of those services, including internal
endpoints. The Ingress routes only `/api/v1/*` and
`/ws` today, which hides it from outside the cluster, but that is a routing detail, not a control.

**Approach.** Disable springdoc outside `local`/`dev` (`springdoc.api-docs.enabled=false`,
`springdoc.swagger-ui.enabled=false` by default, enabled in those profiles). Those properties go in each of the six
services' `application.yml` (and a dev-profile file where the k8s dev overlay should show the docs). The public paths
are in `shared`'s `PUBLIC_PATHS`, so dropping them, or permitting them only when springdoc is enabled, changes all
seven services at once.

---

### 0-74. No way to report a vulnerability privately

**Type:** docs · **Priority:** Low · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** The repository is public but has no `SECURITY.md`, private vulnerability reporting is off
(`private-vulnerability-reporting`: `enabled: false`), and Dependabot alerts are off (`vulnerability-alerts`: 404).
Someone who finds a vulnerability has only public issues to report it in, and GitHub's own advisory matching does not
alert on the dependency graph. Renovate updates dependencies but is not an alerting channel.

**Approach.** Add `SECURITY.md` (supported versions, how to report, expected response), turn on private vulnerability
reporting and Dependabot alerts (alerts only; Renovate keeps doing the updates).

---

### 0-75. The Ingress has no TLS

**Type:** design · **Priority:** Low · **Status:** Open (found in the 2026-09-30 infrastructure security audit)

**Problem.** `k8s/base/infrastructure/ingress.yml` has no `tls:` section, so login requests, JWTs and Integration API
keys cross the network in plain text, and the HSTS header every service sends is ignored by browsers over HTTP.

**Approach.** A `tls:` block per overlay with a certificate from cert-manager (or the cloud provider's), and
`nginx.ingress.kubernetes.io/ssl-redirect: "true"`. The dev overlay can keep plain HTTP on Minikube.

---

### 0-77. Should `/dev/token` require an explicit switch as well as the dev profile?

**Type:** design · **Priority:** Low · **Status:** Open (from the review of #0-63)

Not a committed fix: decide first whether it is worth doing.

**Problem.** `DevTokenController` exists whenever the `local` or `dev` profile is active, and its startup guard only
rejects a missing profile. #0-63 showed that one wrong line in a shared ConfigMap is enough to give a production
deployment the dev profile. Since #0-63 the CI check on the rendered overlays catches that, but it is a tripwire for
accidents in `k8s/`, not a property of the application.

**Approach, if taken.** Require an explicit property on top of the profile (for example
`dev.token-endpoint.enabled=true`, `@ConditionalOnProperty`), set only by `application-local.yml` and the dev overlay.
Against: a second setting to keep in sync for a dev-only convenience, and the profile check plus the CI check may be
enough. Decide before implementing.

---

### 0-79. At HPA maxima during a rolling update, the connection pools exceed what Postgres allows

**Type:** design · **Priority:** Medium · **Status:** Open (found in the review of #0-78)

**Problem.** In Kubernetes every service that uses the database keeps a Hikari pool of 5 connections
(`DB_POOL_SIZE` in `app-config`; auth-service hard-codes 5). The HPAs own the replica counts and each overlay sets
their ceilings (since #0-137, which kept the ceilings as they were): staging keeps base's 3 for auth-service and
incident-service and 2 for each of the other four, which is 70 connections; prod raises incident-service to 5 (80;
ingestion-service's 5 adds none, it has no database); dev caps every HPA at 1 (30). If every Deployment rolls at the same time, each adds one
surge pod (`maxSurge: 1`): 100 in staging, 110 in prod. (Written while #0-29 had swapped the two overlays, as
"staging 110"; corrected when #0-29 was fixed: prod is the one with the most.) Postgres runs with the default `max_connections` of 100. Since #0-78 the services' role is not a
superuser, so it cannot use the 3 connections reserved for superusers (`superuser_reserved_connections`), and gets 97.
A deploy at peak load can then fail new pods with "too many connections". Before #0-78 the margin was zero. The
Postgres pod's 512Mi memory limit also caps how far `max_connections` can simply be raised. The admin can still log in
when the services have taken every other connection, which is the reserve's purpose.

**Approach.** Decide with a measurement, not by guessing a number. The options are:
- size `max_connections` together with the pod's memory (`-c max_connections=...` on the StatefulSet);
- lower `DB_POOL_SIZE` per pod, which needs a throughput check;
- put a pooler (PgBouncer) in front once the replica counts grow.

`docs/database-roles.md` explains the arithmetic.

---

### 0-85. A tenant id with data in other services but no user can be provisioned

**Type:** design · **Priority:** Low · **Status:** Open (found in the review of #0-80; needs verification)

**Problem.** `POST /api/v1/platform/tenants` (#0-80) refuses an id only if auth-service's `tenants` table
has it, and V21 filled that table from auth-service's `users`. The other six services keep `tenant_id` as a
plain string on their own rows. If any of them holds rows under an id that never had data in auth-service,
an operator can provision that id, and its new admin sees those rows. Possible sources, to be verified:
- incident-service's `/dev/token` (dev profile only) mints a token for any tenant id, so a dev or test
  database may have incidents, on-call schedules or postmortems under such ids. Its default is
  `test-tenant`, which the README's end-to-end test uses;
- a hard-deleted tenant's users (only archive/anonymize exist today, so possibly none);
- alerts ingested under an Integration API key always belong to a tenant with a user, so probably not.

Only an operator can do this, so it is an accident or a rogue-operator risk, not an outside attack. Today
`docs/tenant-provisioning.md` tells the operator to check the id first. An id with any data in auth-service,
archived users included, is already refused: since #0-82 every auth-service table holding a tenant's data has a
foreign key to `tenants` (V31), so such an id has its row, and provisioning's insert refuses it (that replaced a
check of the users, `UserRepository.existsAnyByTenantId`).

**Approach.** First verify: list the tenant ids each service's tables hold and which of them auth-service
has no record of, on every deployed database. Then either:
- **Document and close.** If no production database can hold such ids, keep the guide's check.
- **Refuse at provisioning.** auth-service asks every service whether the id is in use, through an internal
  service-token endpoint per service; many calls, and a new cross-service dependency for a rare action.
- **Record unknown ids.** A one-off backfill of `tenants` from every service's distinct `tenant_id`,
  which blocks those ids for good.

---

### 0-86. Integration tests load the web-slice test configuration

**Type:** tech-debt · **Priority:** Low · **Status:** Open (found while implementing #0-83)

**Problem.** `AuthServiceApplication` declares its own `@ComponentScan("com.incidentplatform.auth",
"com.incidentplatform.shared")`. That replaces the scan `@SpringBootApplication` would do, including
its `TypeExcludeFilter`, so a `@SpringBootTest` (e.g. `AuthRepositoryIntegrationTest`) scans the test
sources too: `AuthApiTestApplication` (itself a `@SpringBootApplication`) and, through it,
`AuthWebMvcTestConfig`. The integration context therefore gets the web slice's no-op
`TokenRevocationChecker` (`@Primary`), and a test bean named like a production bean silently replaces
it. #0-83 hit this: a mock `MfaSessionStatusService` replaced the real one in the integration tests.
Worked around by giving the slice's beans their own names and `@Fallback`.

**Approach.** Drop the explicit `@ComponentScan` (`shared` is already scanned through
`scanBasePackages` or its auto-configuration, to be checked), or add Boot's exclude filters
(`TypeExcludeFilter`, `AutoConfigurationExcludeFilter`) and move `AuthApiTestApplication` out of the
scanned package. Then check that no integration test relied on the leaked beans. Other services
with an explicit `@ComponentScan` may have the same issue.

---

### 0-87. Operator MFA enrolment is not bound to the invite

**Type:** design · **Priority:** Low · **Status:** Open (option deferred in #0-83)

**Problem.** Enabling MFA needs only a password-authenticated session. #0-83 answered the risk that a
password thief enrols their own factor with an email on every MFA change and a 24 h grace period
before the platform API accepts a new factor. That leaves a window: an owner who does not read the
email within the grace period, or whose mailbox is also compromised, does not stop it.

**Option.** For the `platform-operator` tenant, make enrolling the TOTP part of accepting the invite
(the invite link is itself proof from outside the password channel), and refuse `/mfa/setup` from a
password-only session of an operator. Existing operator accounts without MFA would then be
re-invited. Stronger, with no window, but it changes the invite flow and the operator bootstrap.

**Also possible, smaller.** A content-free alert to the platform channel whenever a
platform-operator account enables MFA (the pattern of the operator's undeliverable-notification
alert), so a second person sees it even if the owner's mailbox does not (suggested in the review of
#0-83).

**Or, with several operators.** A new operator factor counts only once a second operator admin
approves it (four eyes), so a thief who holds both the password and the mailbox still cannot pass
the platform API alone. Needs at least two operator admins, and a recovery path for a deployment
with one (suggested in the review of #0-83).

**When.** If the platform API gains more powerful actions (suspension, #0-82, has landed and is
alerted on every change; offboarding, #0-101, would be the next), or a deployment has several
operators.

---

### 0-94. Logs are plain text, with no structure, escaping or collection

**Type:** design · **Priority:** Medium · **Status:** Open — step 1 done (PR #463), step 2 done (PR #464), step 3 open (raised in the analysis of #0-91/#0-92)

**Problem (before step 1).** Every service logged plain text: six shared the pattern
`%d [%X{tenantId}] [%X{requestId}] [%X{userId}] %-5level %logger - %msg%n`, auth-service uses Spring Boot's
default. No `logback*.xml`, no encoder escapes anything. So:
- **Log injection.** Any value from outside that reaches a log line (a Kafka header such as `X-Event-Type`, a
  payload field, an HTTP header, an exception message quoting a library's input) can carry CR/LF and forge or
  split lines. #0-92 closes it for the tenant id only (a strict format checked at every entry); other fields
  rely on each call site remembering not to log them raw (`notification` `IncidentEventConsumer` does,
  others do not).
- **No machine-readable fields.** The MDC keys (tenant, request, user, Kafka message id) are only positions in a
  string, so filtering one tenant's or one request's lines, or correlating them across services, needs regexes.
- **No collection.** Neither docker-compose nor `k8s/` runs a log collector or store (no Loki, Promtail, Fluent
  Bit, Alloy, ELK): logs live in each container's stdout until it is replaced. An incident on the platform
  itself is investigated container by container, and nothing alerts on log content.

**How production systems handle it.** Structured (JSON) logs to stdout, one object per line, the encoder
escaping every value; a common field schema (ECS or similar: timestamp, level, logger, message, trace and span
ids, service, plus the platform's own tenant and request ids); a collector shipping them to a store queried by
field, with retention and access control (logs carry tenant data); trace ids from OpenTelemetry linking logs,
metrics and traces. Spring Boot 3.4+ (this project: 3.5) has built-in structured logging
(`logging.structured.format.console=ecs|logstash|gelf`), so no extra encoder dependency is needed.

**To analyse as a whole, before any change:**
- format and field schema (ECS vs Logstash vs GELF), MDC keys mapped to fields, the same in all seven services;
- local readability: JSON for containers, plain text for `spring-boot:run` (profile-dependent) or one format;
- collection and storage: which stack (Loki + Alloy is the usual fit next to the existing Prometheus/Grafana/
  Alertmanager), in compose and k8s, retention, who may read logs (they hold tenant content and PII: #0-48);
- tracing: OpenTelemetry/Micrometer Tracing for trace ids in logs (none today);
- what must never be logged (secrets, tokens, raw payloads) and how that is checked;
- CI: the smoke test and anything that greps log output.

**Decided (2026-10-08, analysis of the whole item).** Three steps, one PR each:
1. **JSON in ECS for every service — done.**
   - *Format.* Spring Boot's own structured logging, ECS on the console and in a log file if one is configured,
     set for all seven services by `shared`'s `StructuredLoggingDefaults` (an `EnvironmentPostProcessor`, added
     after the config data). ECS rather than Logstash or GELF: a standard schema with room for
     `trace.id`/`span.id` (step 3), read as is by Loki, Elastic and Grafana. ECS nests its own fields (`log.level`,
     `service.name`, `error.stack_trace`) and puts every MDC key at the top level; the set reaching the log is
     pinned (`tenantId`, `requestId`, `userId`, `kafkaMessageId`), the interceptor's `_kafkaStartNanos` excluded.
     The encoder escapes every value, so the log injection above is closed for every field, not only the
     tenant's. The six services' copies of the text pattern are gone; auth-service, on Boot's default before, is
     like the others (its break-glass command too).
   - *Enforcement.* A default can be overridden from anywhere, so `StructuredLoggingGuard` refuses to start a
     service whose effective console or file format is not `ecs`, that names a Logback file (`logging.config`,
     `logback.configurationFile`) or has one on the classpath (`logback*.xml`/`.groovy`, test ones included, in
     any jar), or whose JSON object is reshaped (`logging.structured.json.*` beyond the platform's own `exclude`:
     a renamed or excluded `tenantId` would vanish from every line), whatever set it. The one exception is `platform.logging.plain-text: true`, which a developer puts
     in the gitignored `application-local.yml` with an empty console format to get plain text in the old MDC
     pattern (the default's `logging.pattern.console`); set anywhere else it still works, and is logged as a
     warning at every start. CI's sixth structural rule (`check-structured-logging.sh`, with its own cases) fails
     on that switch in the usual spellings, and on a Logback file, in tracked files; any other way of switching
     JSON off already stops the service in the smoke test. This replaced, in review, a first CI check of format
     keys in committed configuration, which a `config/` copy, YAML flow style, quoted keys,
     `SPRING_APPLICATION_JSON` or a ConfigMap outside the repository got around.
   - *What a line must never carry* (tokens, secrets, keys, raw payloads) is a rule in CLAUDE.md, not a check: the
     encoder makes any value safe to print, not safe to disclose. The manual guards (`AuditText`, `printable()`
     in `SlackApiClient`) stay where a value goes to a tenant-readable record (audit, `notification_log`).
   - *Tests.* `StructuredLoggingDefaultsTest` runs a real `SpringApplication`: ECS fields and the MDC key set, a
     CR/LF in the message, an argument, an MDC value and an exception kept inside one line, a log file in ECS,
     a start refused for a format set in `application.yml`, by an argument, through `SPRING_APPLICATION_JSON` and
     by `logging.config`, plain text with the switch. `StructuredLoggingGuardTest` takes each refusal on its own
     (either output, case and padding, `logback.configurationFile`, every Logback file, the classpath lookup, a
     reshaped JSON object, the switch honoured only when true and logged, both environment-variable spellings). A
     packaged service jar logs JSON from its first line (checked on oncall-service).
   - *Not covered:* a deployment outside this repository setting the switch on purpose (whoever can, can also
     change the image; it is logged), and the content of an exception's message (escaped, not filtered).
2. **Collection — done (decided 2026-10-09).** docker-compose only: `docker-socket-proxy` → Alloy → Loki, read in
   Grafana (Explore → Loki), every new image (and Grafana) pinned by tag. k8s has no monitoring at all (no Prometheus, Grafana or
   Alertmanager), so logs there come with the rest of it, in #0-106, not alone.
   - *Collection.* Alloy (`docker/alloy/config.alloy`) discovers the containers named `incident-*` (the filter does
     not depend on the compose project name) and reads their stdout from the Docker API. Labels stay few and
     bounded: `service` (the compose service), `container`, `level` (from ECS's `log.level`). `tenantId`,
     `requestId`, `userId` and `kafkaMessageId` are **structured metadata** of each line, queryable
     (`| tenantId="acme"`) without a stream per value: the cardinality reason the `tenant` tag left
     `kafka.records.received` in #0-92. Only the services (compose names ending in `-service`) are parsed
     (`stage.match`): another container's JSON (kafka-ui, a library image) sets no level and no identifiers, as its
     values are not the platform's and as labels could add streams without bound. Lines that are not JSON
     (Postgres, Kafka, Redis) are kept unparsed. A service's level outside TRACE..ERROR (JSON of its own on its
     raw stdout) becomes `OTHER`, so `level` has at most six values. The other containers' raw lines are kept too,
     on purpose, under the same 15 days: an incident on the platform is often in Postgres, Kafka or the proxy, not
     only in the services. They may carry tenant content (a Postgres error quoting a row, a Kafka UI request), so
     they get the same access rules as the services' lines, nothing looser. A
     service run with `spring-boot:run` is no container and is not collected, nor is auth-service's break-glass
     command (`docker compose run --rm`, docs/tenant-provisioning.md: its container is not named `incident-*` and is
     removed when it ends); its audit events are recorded as usual, its log lines go only to the operator's
     terminal. Positions are kept on a volume, so a
     restarted Alloy does not resend everything.
   - *Docker API.* Through `tecnativa/docker-socket-proxy`, never the socket: the socket is root on the host,
     and `:ro` protects the file, not the API. The proxy answers GET on `/containers` and `/networks` (Alloy's
     discovery lists both) and refuses the rest, every POST (exec, stop, create) included, and is on an
     `internal` network with Alloy alone. Rejected: the socket mounted in Alloy (the usual tutorial; a compromised
     collector would own the host) and Docker's Loki logging driver (a plugin on every developer's host, and a
     `logging:` block in every service). *Not covered:* the proxy cannot narrow `/containers` further, so whoever
     controls Alloy can still read every container's environment (secrets included, Grafana's password too, through
     inspect) and files (archive, export); and `attach/ws`, a GET that upgrades to a websocket able to feed a
     container's stdin (checked: 101), harmless here as no container keeps stdin open. Much less than root on the
     host, but not nothing. The proxy is pinned by
     digest (the one container with the socket) and hardened (read-only root with a tmpfs for its rendered config,
     every capability dropped, `no-new-privileges`, 128 MiB), and the smoke test fails if a write gets through it or its
     network is not internal. The way
     past it, should it matter, is a collector with no Docker API at all: `loki.source.file` over Docker's
     `/var/lib/docker/containers` mounted read-only (works on a Linux host, not inside Docker Desktop's VM, so not
     for the developers' machines) or a logging driver; kept for k8s, where Alloy reads the kubelet's files (#0-106).
   - *Retention and access.* 15 days (`retention_period: 360h`, compactor `retention_enabled`; without it Loki
     deletes nothing), the same as Prometheus: one window for investigating an incident on the platform from both,
     and no tenant content kept longer. Lines older than 7 days are refused, and so is a line about an hour behind its stream's newest (Loki's
     out-of-order window): an Alloy that lost its positions re-reads old Docker logs, those lines are dropped and
     `LogsDropped` fires once (seen in testing). Loki has `auth_enabled: false` (one
     org): whoever reaches it can read, push and query every line. So it publishes no port, its delete API is off
     (`deletion_mode: disabled`; retention does not need it), and it is on the internal `logs` network alone with
     Alloy, Grafana and Prometheus; Alloy, whose HTTP API shows its config, is on `logs` and `docker-api` only. The
     services, kafka-ui, pgAdmin and the rest are on `default` and cannot reach either (a first version had both on
     `default`, where any compromised container could read every tenant's logs and erase lines). Grafana is its
     only reader, so who may read the logs is who may log in to Grafana; it is on `logs` (Loki and Prometheus are
     there) and on `grafana-ui`, a network of its own only to publish its port, not on `default`: from there a
     compromised container could log in (an old volume still has `admin`) and query Loki through Grafana's
     datasource proxy, around the `logs` network (found in the third review). The smoke test checks that none of
     the proxy, Loki, Alloy and Grafana is on `default` in the compose file, that Loki and Alloy (and Grafana when
     it runs) do not answer from the services' network (only a curl DNS, connect or timeout error counts, never a
     docker failure) and the proxy is on internal networks only, and that Loki and Alloy answer on `logs`; it also pins exactly who is on
     `logs`, `docker-api` and `grafana-ui`, and that the first two are internal, so adding a service or a UI
     image to one of them fails CI.
     Grafana was `admin`/`admin` on every interface (#0-72); since it reads tenant content it is published
     on `127.0.0.1` only, its admin password is `GRAFANA_ADMIN_PASSWORD` with no default (empty in
     `.env.example`, so compose refuses to run until a developer sets one; CI sets a dummy) and its image is
     pinned (`13.2.3`, was `latest`). The password applies to a new `grafana_data` volume only; an older one keeps
     `admin` until reset (README Step 5), and `make dev-up` warns while Grafana still accepts `admin`/`admin`, or when the password is under 16 characters (`docker/grafana-password-check.sh`, reading it as compose does: BOM, `export`, quotes, inline comments, and a `$` outside single quotes said to be interpolated rather than measured; its 28 cases, with a stub curl, run in CI's build job, `.github/scripts/test-grafana-password-check.sh`).
     Grafana sends nothing it does not need (usage reporting, update and plugin checks, news feed off) and installs
     no plugin from its UI, as `grafana-ui` gives it a route out. Memory is capped (Loki 1 GiB, Alloy 512 MiB, about
     150 and 80 MiB in use when measured), so a heavy query cannot starve the services on a laptop or CI runner;
     Loki also runs with `GOMEMLIMIT` and bounds each query (no longer than the retention, 8 parallel parts and 16 for the TSDB index (128 by
     default), 500 series, 2000 lines, 2 GB read, 1 minute (the HTTP server's timeouts, 30 s by default, raised to 70 s so they do not cut it first), 4 at once; the index-stats and volume caches off), and its ingestion rate is written out (4 MB/s, bursts of 8), which caps the rate, not the
     disk. Its WAL replay is capped at 400 MB (the default, 4 GB, is above the container's limit: after one OOM
     kill the replay would pass it again and Loki would restart for ever). Alloy has `GOMEMLIMIT` too and sends no
     usage report. Loki and Alloy are hardened like the proxy (read-only root, no capabilities, no privilege
     gain), Alloy running as its image's `alloy` user (473) rather than root; a line over 64 KB is cut (4 queries x 2000 lines x 256 KB, Loki's own size, would not fit 1 GiB), not
     refused (a refusal would count as a drop). `LogPipelineRestarting` (two restarts in 30 minutes) covers the
     restart loop `LogPipelineDown` cannot see, as every `up=1` between restarts resets its 5 minutes. Alloy's
     and Loki's own lines are collected too, on purpose (they are where a pipeline problem shows); while Loki is
     down, Alloy's errors about it wait in its queue like any other line. Grafana 13 downloads app plugins from grafana.com at start (seen: advisor, the Drilldown apps,
     Pyroscope); `GF_PLUGINS_PREINSTALL_DISABLED` stops it, as none is needed where every tenant's logs can be
     read. No access per tenant: the logs are the platform's, read by its
     operators. One tenant's lines cannot be deleted before the retention is up: #0-101. Usage reporting to
     Grafana Labs is off. Docker keeps at most 3 x 10 MB of each container's json-file log (`x-logging` in
     compose; it grew without bound before), Alloy having shipped it.
   - *Alerts on the pipeline* (`logs` group in `prometheus.rules.yml`, all `high`, to the platform webhook): a
     pipeline that stops says nothing by itself. `LogPipelineDown` (Loki or Alloy unreachable for 5 minutes),
     `LogPipelineRestarting` (two restarts in 30 minutes, at once: a loop keeps `up` mostly 1, so
     `LogPipelineDown` stays quiet; a first version, three in 15 minutes, missed a slow loop of one OOM kill
     every 6-10 minutes), `LogsNotFlowing` (Alloy sent no line for 15 minutes while up and discovering: a
     renamed container, lost targets; a live stack is never silent that long, as the proxy alone logs each
     discovery call; 112 lines a minute was the fewest in 3 idle hours, measured),
     `LogPipelineNotScraped` (no `up` series for either for 5 minutes: a scrape job removed or renamed, which
     `LogPipelineDown` cannot see; added in review),
     `LogDiscoveryFailing` (Alloy's Docker discovery kept failing for 5 minutes: a 2-minute window, as a 10-minute
     one let a single failed refresh fire it, e.g. the proxy is
     down: Alloy's own component health stays "healthy" then, found by stopping the proxy) and `LogsDropped` (any
     line Alloy gave up on, per reason; lost for good; late by design, as Alloy retries a batch for about 8.5
     minutes first, its backoff written out in `config.alloy`; the counter exists at 0 for every reason from
     Alloy's start, so the first drop counts). Rotation bounds what an Alloy outage can catch up on: a chatty
     service fills its 3 x 10 MB in minutes, and lines rotated away meanwhile are lost uncounted. promtool tests for each (sustained, blip, idle, other
     job/mechanism), and `routes test` lines in CI. Alerts on what the lines say: #0-107.
   - *CI.* `validate-monitoring-config` runs `loki -verify-config`, `alloy validate` and `alloy fmt` (canonical
     form) on the images it reads from the compose file, so the tags cannot drift apart. The smoke test starts the pipeline with the services and runs
     `.github/scripts/test-log-collection.sh`: every service's lines are in Loki with a `level`; a probe
     container's JSON line has its level as a label and `tenantId`/`requestId` as structured metadata, never
     labels; a line that is not JSON arrives unparsed; the proxy, asked from Alloy's network, answers Alloy's
     reads and refuses writes (aimed at a container that does not exist, so a misconfigured proxy cannot make the
     check stop a real one) and other reads; every network of the proxy, Loki and Alloy is internal, and neither
     Loki nor Alloy answers from the services' network; a non-service container's JSON is not parsed. One
     deadline for the whole run (4 minutes; one per check could add up past the job's timeout), and every request
     to Loki has its own 10 s limit. Breaking the `service` relabel, the level path, the tenant mapping, the
     services-only match, `POST=0`, `internal` or Loki's network makes it fail (checked). `test-postgres-roles.sh`
     checks compose refuses to run without `GRAFANA_ADMIN_PASSWORD`, as it does for the database passwords.
3. **Tracing — open.** Micrometer Tracing with OpenTelemetry: `trace.id`/`span.id` in every line, `traceparent`
   across HTTP and Kafka (the header half of #0-95), so one alert can be followed from ingestion to its notifications.

### 0-95. Kafka messages have no envelope (correlation id, schema version, producer)

**Type:** design · **Priority:** Low · **Status:** Open (a `TODO` in `AlertKafkaProducer` that cited no backlog
item, found in the review of #0-91/#0-92)

**Problem.** A record is its domain payload plus headers (`X-Tenant-Id`, a copy of the payload's tenant since
#0-91; `X-Event-Type` on `incidents.lifecycle`). Nothing carries a correlation id from the alert through the
incident to its notifications, a schema version, or the producing service and time, so tracing one alert
across services, replaying with context or evolving a payload shape has nothing to go on.

**Options.** A typed `KafkaEnvelope<T>` in `shared` (routing metadata next to the payload; every producer and
consumer changes, a deserialization strategy for both shapes during a migration), or standard headers
(W3C `traceparent` via Micrometer Tracing / OpenTelemetry, a schema-version header) with payloads unchanged.
The tenant stays the payload's either way (#0-92). Justified together with tracing (#0-94) or when producers
and consumers multiply; not before.

### 0-97. Kafka consumers on `DefaultErrorHandler`, and a dead-letter replay

**Type:** design · **Priority:** Low · **Status:** Open (option deferred in #0-96)

**Problem.** Since #0-96 every consumer decides each record's fate itself, in `MANUAL_IMMEDIATE` mode, through
`DeadLetterPublisher` (`deadLetterThenAcknowledge`, `redeliverLater`, `redeliverIfTransientElseDeadLetter`) and
`KafkaFailures`. That is correct, but six consumers repeat the same catch blocks, and nothing stops a new one from
acknowledging too early or returning without acknowledging, which skips the record (`DeadLetterPublisherKafkaIntegrationTest`).
A transient failure is retried every 5 s, with no backoff, until its redelivery deadline (30 min, in memory per
instance, `RecordRedeliveries`). And nothing reads the dead-letter topics: a record put there is kept, not processed.

**Options.**
- Spring Kafka's `DefaultErrorHandler` with a recoverer built on `DeadLetterPublisher` (the tenant-less record,
  the `AuditText` reason and the `X-Tenant-Unresolved` marker of #0-92 stay there): listeners throw, the
  container retries with an exponential backoff, a non-retryable exception (or `KafkaFailures` says not
  transient) goes to the recoverer, which waits for the copy before the offset is committed. One place for all
  consumers; `AckMode.RECORD`, no `Acknowledgment` in the listeners; an exponential backoff instead of a fixed
  5 s, and the deadline expressed as the handler's (`ExponentialBackOffWithMaxRetries` or a max elapsed time).
- A replay tool for the dead-letter topics: it must resolve the tenant again from the original payload (README
  "Infrastructure Hardening": the topics' content is untrusted until Kafka ACLs, #0-66), and deduplicate copies
  stored twice by `sourceTopic`, `sourcePartition` and `sourceOffset` (at-least-once since #0-96).

**When.** When consumers multiply, or when the first dead-lettered record has to be processed.

---

### 0-98. MFA recovery verifies the person by procedure only

**Type:** design · **Priority:** Low · **Status:** Open (left out of #0-90 on purpose)

**Problem.** The operator-assisted MFA recovery of a customer tenant's only admin (#0-90) records how the
operator verified the person (`MfaVerificationMethod` and a note), but the platform checks none of it. It holds
no contact of the tenant independent of the admin's own account (`tenants.first_admin_email` is usually the very
mailbox that may be compromised), and a `DNS_TXT_RECORD` verification is the operator's own lookup. The waiting
period and the notice to the account are the platform's safeguards; the verification itself rests on the
operator following docs/tenant-provisioning.md.

**Approach.** Record verified contacts per tenant at onboarding (a phone number, a billing or security contact,
the customer's domain), editable only through the platform API with the same rules; let the recovery request name
which contact was used, and for a domain have auth-service look the TXT record up itself (a value it generated,
on `_incident-platform.<domain>`), refusing the request until it matches.

**When.** When customers are onboarded under contract (a contact exists anyway), or when a recovery request is
disputed.

---

### 0-99. Public token endpoints have no request limit

**Type:** security · **Priority:** Low · **Status:** Open (found in the security review of #0-90)

**Problem.** auth-service's public endpoints that take an emailed token (`POST /api/v1/auth/reset-password`,
`/accept-invite`, and since #0-90 `/mfa-recovery/cancel`) have no request limit. A token is 32 random bytes,
stored as a hash and single-use, so guessing one is out of reach; an unauthenticated flood of invalid tokens still
costs a database lookup and a WARN line each. Login has its own brute-force protection; these do not.

**Approach.** One limiter for the public token endpoints together, not one per endpoint: per client address (the
Ingress's forwarded address, trusted only from the Ingress) and in total, in the Redis bucket4j setup ingestion
uses, fail-open like it (a refused recovery or password reset is worse than a flood that Redis's absence lets
through); 429 with Retry-After; the WARN for an invalid token sampled or counted instead of logged per request.

**When.** Before the platform is exposed to the internet without a WAF or rate limit at the edge.

---

### 0-101. Offboard a tenant

**Type:** design · **Priority:** Medium · **Status:** Open (split out of #0-82)

**Problem.** A tenant can be suspended (#0-82) but not ended: a customer who leaves keeps its data in all
seven services (incidents, audit, notifications, on-call, postmortems, users, teams, keys, Slack
workspace) and in Redis, with no export and no deletion short of editing the databases.

**Approach.** The pattern of Azure's tenant life cycle and AWS SaaS Lens: on request, suspend the tenant
in full and move it to `OFFBOARDING`; export its data (a signed link to the account owner for a limited
time); a grace period in which it can still be resumed; then an orchestrated, resumable, idempotent
deletion in every service (an internal per-service "delete tenant" step, the orchestrator in auth-service
recording each one), Redis included; then `OFFBOARDED`, a tombstone that keeps the id taken (ties into
#0-85). Decide first: the export format, the grace period, the audit trail's retention (often longer than
the customer), backups, and whether the destructive step needs a second operator (#0-87). Run it from an
approval, keep a tested runbook. The platform's own logs too (since #0-94 step 2): Loki keeps every tenant's
lines for 15 days in one org with no tenant label, so one tenant's cannot be deleted sooner; either the
offboarding waits out the retention (state it in the export/erasure answer), or it uses Loki's delete API with
a `tenantId` structured-metadata filter (needs `deletion_mode` set and the compactor's delete requests; to be
tried).

**When.** Before the first customer leaves, or the first erasure request for a whole organisation.

### 0-102. The pause of suspended tenants' background work at scale

**Type:** performance · **Priority:** Low · **Status:** Open (found in the review of #0-82 step 2b)

**Problem.** `PausedTenantsSync` (notification-, escalation-, postmortem-service) asks auth-service about every
tenant with waiting work, one call each, serially, every 10 s, and the sync interval equals the status cache's TTL,
so nearly every call misses the cache: about 3 services x N tenants / 10 s on `/internal/tenant-status`. Its
candidate queries (`SELECT DISTINCT tenant_id ... WHERE status ...`) and the schedulers' `NOT EXISTS` read every
pending row of a paused tenant on each run, as the partial indexes they use do not hold `tenant_id`; a tenant held
with nothing waiting is still asked about every run (it must be, to see its resumption); a tenant held
for weeks with alerts still flowing (notifications are written meanwhile) makes every poll walk its backlog.
`notification_queue` has no `tenant_id` index for the resumption's UPDATE. Fine at today's scale; not at
thousands of tenants with work waiting. A run that runs out of its budget leaves the rest to the next (which goes on
after it), so at that size a suspension takes several runs to reach every service (the timers no longer depend on it:
the pause is measured from `suspended_at`).

**Approach.** Measure first (the provider's cache hit/miss counters, `EXPLAIN ANALYZE` on a seeded database).
Then, as needed: a sync interval at least twice the status cache's TTL (most lookups then hit the cache) or
lookups fanned out a few at a time on virtual threads instead of one after another; a partial index
`(tenant_id) WHERE status = 'PENDING'` per work table (the candidate query becomes an index-only scan); a batch
status endpoint in auth-service (a service token per tenant today: a tenant-less list
would need a second purpose token, CLAUDE.md's deny-by-default rule), or a sync interval above the TTL; `tenant_id`
in the partial pending indexes (`CREATE INDEX CONCURRENTLY`, alone in its migration, with
`spring.flyway.postgresql.transactional-lock: false`).

**When.** Before tenants with work waiting number in the hundreds, or when auth-service's status endpoint shows in
its own latency.

---

### 0-105. The email channel's worst-case send is not checked against the scheduler lock

**Type:** performance · **Priority:** Low · **Status:** Open (found in the second review of #0-103)

**Problem.** `NotificationScheduler` checks its budget between entries, and since #0-103 refuses to start unless
budget + 30 s + each channel's `NotificationChannel.worstCaseSendTime()` fits its 4-minute ShedLock. Only Slack
declares one (about 51 s). Email and SMS return zero, so they share the fixed 30 s margin with the entry's database
writes and the Slack workspace lookup in auth-service. An SMTP server that accepts the connection and then stalls
costs up to `mail.smtp.connectiontimeout` + `timeout` (+ `writetimeout`) per command, 5 s each by default, over
several commands of one session; with Slack, SMTP and auth-service all hanging at once, the entry in flight could
outlive the lock and a second replica send the same notifications. Not new with #0-103 (the margin always assumed
it), but now there is a place to say it.

**Options.** `EmailNotificationChannel.worstCaseSendTime()` derived from the `spring.mail` timeouts and a bound on the
commands of one send, if JavaMail gives one; or a hard deadline on the send (a `TimeLimiter`, or the session
closed after a total timeout), which bounds it whatever the protocol does and is then what it declares. The same
for SMS once it has a real provider.

---

### 0-106. Kubernetes has no observability stack

**Type:** design · **Priority:** Medium · **Status:** Open (found in the analysis of #0-94 step 2)

**Problem.** `k8s/` deploys the seven services, Postgres, Redis and Kafka, and nothing that watches them: no
Prometheus, Alertmanager or Grafana, so none of the alerts in `docker/prometheus.rules.yml` (the operator's email,
the dead man's switch, #0-16) exist in a cluster, and since #0-94 step 2 no log collection either: logs live in
each pod's stdout until it is replaced. Everything in `docker/` (compose) is all the platform has.

**Approach (to analyse).** The usual way is the kube-prometheus-stack / Grafana's Kubernetes monitoring Helm charts,
or the same components as Kustomize manifests: Prometheus (or Alloy as the scraper) with the same rule file, Alertmanager with
the same routes, Loki, and Alloy as a DaemonSet reading `/var/log/pods` (no Docker socket: the kubelet's files, with
RBAC for pod metadata only). Retention and access as decided for compose in #0-94 step 2; a managed backend is the
other option. Touches #0-64 (securityContext) and #0-65 (NetworkPolicy: who may reach Loki).

### 0-107. No alert reads log content

**Type:** design · **Priority:** Low · **Status:** Open (left out of #0-94 step 2 by decision)

**Problem.** Since #0-94 step 2 the platform's logs are in Loki, but nothing reads them for alerts: Loki's ruler is
off (`docker/loki.yml`). Most signals already are metrics with alerts (errors per service, failed deliveries, the
outbox, Kafka redeliveries), so this is for what only a line shows, e.g. `StructuredLoggingGuard`'s WARN that
plain-text logs were switched on in a deployment (#0-94 step 1), or a burst of ERROR lines from a service whose
metrics look healthy. Also a service that stops logging: `LogsNotFlowing` (#0-94 step 2) fires only when Alloy
sends no line at all, and `docker-socket-proxy` logs each of Alloy's discovery calls, so one service, or all seven,
going silent never fires it; a per-service query on the lines (`absent_over_time` per `service`) would.

**Approach (to analyse).** Loki's ruler with LogQL alerting rules sent to the same Alertmanager (rules in the repo,
tested like the Prometheus ones if a tool allows), or recording rules turning a log query into a metric that a
Prometheus rule alerts on. Only for signals no metric gives.

---

### 0-108. Architecture tests (ArchUnit) for the decided patterns

**Type:** ci · **Priority:** Medium · **Status:** Open
**Autopilot:** not-ready (human-only: `architecture-tests/` and `.ai/rules/` are Owner-only) · **Risk:** low ·
**Complexity:** medium · **Depends on:** —

**Problem.** The decided patterns of `.ai/rules/review/architecture.md` §3 and SEC-04 are enforced only by review.
Several have been broken before (#0-47 `= 0L` on `@Version`, #0-83 a bulk `@Modifying` without
`flushAutomatically`), and the seeded-defect benchmark plants exactly these (P-06 ARC-22, P-07 ARC-23, P-08 ARC-25).
With unattended agents writing code, a rule that only a reviewer checks is a rule a reviewer can miss; a test that
fails in the autopilot's test gate (`run-tests.sh`, before the panel) also costs a round less than a finding.

**Approach.** A test module `architecture-tests` (test scope only, depends on `shared` and every service) with one
ArchUnit rule per invariant, each `.because("<rule id>: <why in one sentence>")`, so the failure names the rule a
change broke. Candidates, re-checked against `main` on 2026-11-01 (a grep, not ArchUnit: the module's first run
gives the real count):
1. **ARC-23.** A `@Scheduled` method's class takes its lock: the method has `@SchedulerLock`, or its class holds a
   `LockingTaskExecutor` (`AuditOutboxRelay`, `PausedTenantsSync` lock programmatically), or the method is marked
   per-replica (see Decided below). Today two jobs run on every replica on purpose (`TenantWebSocketSessions`,
   `OperatorTenantBootstrap.refreshPendingGauge`), with the reason only in Javadoc, which ArchUnit cannot read.
   Label: Backed by (whether a job changes shared state, and whether the executor wraps the body, stay reviewed).
2. **ARC-22, SEC-04.** `KafkaTemplate.send` is called only with a `ProducerRecord` (no `send(topic, ...)`
   overload) and only from the sender classes of today: `AlertKafkaProducer`, `AuditEventKafkaSender`,
   `IncidentEventKafkaSender`, `DeadLetterPublisher`. (The first wording, "only `TenantRecords` /
   `DeadLetterPublisher`", was false: three senders call `send(record)` with a record `TenantRecords` built.)
   Catches P-06 (a direct send from a new class). Label: Backed by (that the record comes from
   `TenantRecords.forTenant` is data flow, not visible to ArchUnit).
3. **ARC-25.** A `@Version` field is `Long`, and no constructor of its class writes it (a field initialiser
   `= 0L` compiles to a write in every constructor, so a bytecode rule sees it; no source-level test needed).
   Catches P-08. Label: Backed by (whether a new entity needs `@Version` at all is ARC-25's judgement).
4. **ARC-26.** Every `@Modifying(clearAutomatically = true)` also sets `flushAutomatically = true`. The rule is
   the whole invariant. Label: Enforced by (`build-and-test`, a required check of `main`).
5. **ARC-24.** No `@KafkaListener` method, and no class holding one, is `@Transactional`
   (`IncidentEscalationEventConsumer` was, and was fixed). Label: Backed by (acknowledgement paths stay reviewed).

Dropped from the first list: "no class of one service depends on a package of another; `shared` on none". Every
service is its own Maven module, so such a dependency needs a POM entry (`review-k8s`, Factory guards' POM step),
and `shared` → service is a cycle Maven does not build: the rule would guard what the build already guards.

Violations of `main` are fixed or marked per-replica in the same PR, not frozen: `FreezingArchRule` and its store
only if the first run finds a violation that cannot be fixed there, each one listed in this item with its reason
(a store is a file a change could edit to pass).

**Decided (owner, 2026-11-01).**
- All five candidates go in.
- A per-replica job is marked by an annotation in `shared` (e.g. `@PerReplica("<reason>")`), which the ArchUnit rule
  accepts and the reviewer judges: ARC-23's "says why" moves from Javadoc to the annotation. Not an allow-list in the
  test: `architecture-tests/` is Owner-only, so every item adding a legitimate per-replica job (clean pattern C-01)
  would stop at the test gate and wait for the owner.

**Acceptance criteria.**
AC1. `./mvnw verify` runs the architecture tests in "Build, Test & Coverage" and they pass on `main`.
AC2. Each rule fails a fixture that violates it (one negative test per rule), and its message starts with the rule id.
AC3. `.ai/rules/review/architecture.md` (and `security.md` for SEC-04) carries each rule's label, "Enforced by" or
     "Backed by", naming the test; `check-rule-claims.rb` passes. CODEOWNERS covers the module
     (`check-protected-paths.sh`).
AC4. The benchmark stays true: `seed-bugs` runs no test gate before the panel (only `seed-compile.sh`, #0-181), and a
     reviewer spends no finding on an "Enforced by" rule (`_common.md`). Every pattern of `patterns.md` whose rule
     becomes "Enforced by" is retired with that reason; a "Backed by" pattern stays (the rule is still reviewed).
AC5. README "Infrastructure Hardening" lists the control.

**Touches:** `architecture-tests/` (new), root `pom.xml` (`<modules>`), `.github/CODEOWNERS`,
`.ai/rules/review/architecture.md`, `.ai/rules/review/security.md`, `.ai/audit/benchmark/patterns.md`, README
"Infrastructure Hardening", `shared` (the annotation) and the two per-replica jobs.

---

### 0-110. Maven Enforcer: allowed repositories and pinned plugin versions

**Type:** ci · **Priority:** Low · **Status:** Open
**Autopilot:** not-ready · **Risk:** high · **Complexity:** low · **Depends on:** —

**Problem.** `mvn verify` runs every plugin a POM declares. An unattended change to a POM can add a plugin or
a repository, and the build runs that code with the network and files of wherever it runs. Review and
`factory-guards.yml` (a POM supply-chain change needs the owner's approval) are the only checks.

**Approach.** `maven-enforcer-plugin` in the root POM: `requirePluginVersions`, `banRepositories` /
`requireNoRepositories` (Maven Central only), `banDuplicatePomDependencyVersions`, and `bannedDependencies`
for known-bad coordinates. Root POM is a CODEOWNERS path.

**Acceptance criteria.**
AC1. A module declaring a plugin without a version, or a `<repository>`, fails `./mvnw verify`.
AC2. The current build passes unchanged.

---

### 0-111. OpenAPI contract diff on pull requests

**Type:** ci · **Priority:** Low · **Status:** Open
**Autopilot:** not-ready · **Risk:** low · **Complexity:** medium · **Depends on:** —

**Problem.** A change to a controller can change the public API (a removed field, a new required
parameter) without any check noticing; the Angular frontend (and any API client) finds out at runtime.

**Approach.** Generate each service's OpenAPI document in CI (springdoc at build time) and diff it against
`main` (openapi-diff); a breaking change fails unless the PR carries the owner's approval, the same rule
`factory-guards.yml` applies to test tampering. Interacts with #0-73 (OpenAPI public in every profile).

**Acceptance criteria.**
AC1. A PR removing a response field fails the check; adding an optional field passes.
AC2. The check's result names the endpoint and the breaking change.

---

### 0-112. Mutation testing on the classes a PR changes

**Type:** ci · **Priority:** Low · **Status:** Open
**Autopilot:** not-ready · **Risk:** low · **Complexity:** medium · **Depends on:** —

**Problem.** Coverage (#0-57) proves lines ran, not that tests would notice them change. The reviewers'
behaviour → test map is a judgement by a model. Nothing measures it.

**Approach.** PIT (`pitest-maven`) on the classes changed by a PR only (`scmMutationCoverage` or an explicit
target list), threshold start at 60% and raised later; informational for two weeks, then required.

**Acceptance criteria.**
AC1. A PR reports the mutation score of its changed classes in the job summary.
AC2. Once required, a score under the threshold fails the check.

---

### 0-116. The devcontainer firewall does not bind code an agent runs

**Type:** design · **Priority:** High · **Status:** Open (carried out by migration stage 2, then C, ADR-0055); accepted for shadow mode (decision 2026-10-09); must be done before phase 3 (auto-merge)
**Autopilot:** human-only · **Risk:** high · **Complexity:** high · **Depends on:** —
**Stage 2 (#0-238, ADR-0056):** narrowed, not closed. In the build VM the Docker that code an agent runs gets root
over is the VM's, which mounts nothing of the Mac; that code still holds the VM (the bot's token and Claude Code's
login in the devcontainer's volumes) and reaches the Mac's loopback services (Grafana with every tenant's logs, Ollama, anything bound to `127.0.0.1`) through Lima's user-mode network (#0-240).
**ADR-0057 (2026-11-14, spike approved by the owner):** in the build VM, AC1 and AC2 hold. The VM's Docker is rootless,
so root in any container a test starts is the unprivileged `factory`; root's `FACTORY-EGRESS` lets `factory` reach DNS
and an allow-list only. Checked as `dev` through `docker`: a `--network host` or bridged container reaching
`example.com`, and one reaching the Mac's `127.0.0.1`, are rejected; `iptables` flushes and writes to the VM's `/etc` do
not reach the VM; the gate passes (639 tests). `create.sh` checks the boundary on every VM. Left open: code still reads
what `factory` holds (the devcontainer's volumes with the bot's token and Claude Code's login, stage 4 of ADR-0055),
and on the Mac nothing changed. This item closes with #0-238's AC5, once the autopilot runs only in the build VM.

**Problem.** The devcontainer's firewall (`.devcontainer/init-firewall.sh`) is `iptables` in the same network
namespace the agents run in, and it holds only while nothing there is root. Testcontainers needs Docker, so
the container reaches the host's Docker (docker-outside-of-docker), and Docker access is root over the
devcontainer itself: `docker exec -u 0 <this container> …` works from `dev` (checked 2026-10-09), and so
would a container on the host network or in this container's network namespace. Code an agent writes and
runs (a test) can therefore drop the firewall or send data out around it, read files the agents' tools may
not (`docker/.env`, `application-local.yml`), and start containers outside it. The agents' own commands
are still bound: `Bash(docker *)`, `curl` and `sudo` are denied in `.claude/settings.autopilot.json`, and
the hooks refuse what they can recognise.

**Decided for now (2026-10-09).** Accepted while the autopilot runs in shadow mode: the machine account's
token reaches this repository only, CI runs on every PR, the owner reads each PR before merging, and the
autopilot cannot merge. Recorded in `docs/ai-factory.md` ("What isolates what") and README "Infrastructure
Hardening". Not accepted for unattended merging: this item is a precondition of phase 3.

**Options (to analyse before implementation).**
- **A. No Docker in the devcontainer.** The firewall becomes a real boundary (no root for `dev`); the
  test gate runs unit tests only and Testcontainers tests run in CI alone, so items touching repositories,
  migrations or Kafka show their failures only on the PR.
- **B. A filtering Docker API proxy (recommended).** The container gets a proxy instead of the socket,
  deny by default on the request body: no `exec` into the devcontainer, no `Privileged`, no `CapAdd`, no
  host or `container:` network mode, no host PID, no bind mounts outside an allow-list, and only listed
  images (`postgres:16-alpine`, `apache/kafka`, Ryuk): an image name is itself a channel, as pulling
  `<host>/<data>:tag` contacts that host. The path-only proxy used for Alloy (#0-94 step 2, tecnativa)
  cannot inspect bodies, so this is a component of our own, with its own tests, kept in step with the
  calls Testcontainers makes.
- **C. The boundary outside the container**: a separate VM (Lima, Colima) or cloud runner whose egress is
  filtered at the host or hypervisor. A second Docker daemon for the tests (dind) on Docker Desktop needs
  `--privileged`, from which escaping into Docker Desktop's VM, which has the internet, is easy.

**Also: Claude Code's Bash sandbox** (found in `/research 0-235`, 2026-11-13; not measured). `sandbox.filesystem.denyWrite`
binds the commands an agent runs and the processes they start, Maven's included, and `sandbox.network` proxies their
egress; hooks run outside it, so `factory-ops-bash.sh` keeps its marks; `failIfUnavailable` and
`allowUnsandboxedCommands: false` in `--settings` keep a session from running without it (code.claude.com/docs/en/sandboxing).
Neither settings file has a `sandbox` key today. Three things to measure before it counts as a boundary here: the
Testcontainers tests need the Docker socket (`allowUnixSockets`), which the documentation names as access to the host,
the hole this item is about; bubblewrap in an unprivileged container needs `enableWeakerNestedSandbox`; and the factory
scripts write the lock and the state, so they would be `excludedCommands`, outside it. A spike in the devcontainer
decides whether it is an option D next to A-C or a layer under one of them.

**Acceptance criteria** (for the option chosen).
AC1. From inside the devcontainer, code run as `dev` cannot change the firewall's rules or reach a host
outside the allow-list, directly or through any container it can start.
AC2. The Testcontainers tests still run in the autopilot's test gate (B, C), or the gate's reduced scope
is documented and CI covers the rest (A).
AC3. `docs/ai-factory.md` and README "Infrastructure Hardening" describe the boundary as it is.

---

### 0-117. The escalation level bound is hard-coded in three services

**Type:** tech-debt · **Priority:** Low · **Status:** Open (found by `/ready #0-7`, 2026-10-09)

**Problem.** The highest escalation level, `2`, is written separately in escalation-service
(`EscalationTask.isMaxLevel()`, `>= 2`), notification-service (`IncidentEventConsumer.MAX_ESCALATION_LEVEL`)
and, after #0-7, incident-service. A third level added in one place would be dead-lettered by the others.

**Approach (to analyse).** One constant in `shared` next to `IncidentEscalatedEvent`, used by all three; a
change to `shared` changes all seven services (CLAUDE.md), so it is its own item, not part of #0-7.

---

### 0-133. `IncidentResolvedEvent` carries no `openedAt`

**Type:** tech-debt · **Priority:** Low · **Status:** Open (found while fixing #0-119, 2026-10-15)

**Problem.** postmortem-service needs when the incident opened (the `postmortems` row, the Gemini prompt),
but the event has only `durationMinutes` (whole minutes, `Duration.toMinutes()` of `createdAt` to
`resolvedAt` in incident-service) and `occurredAt`. Since #0-119 the consumer derives
`openedAt = occurredAt - durationMinutes`, so the opening is off by up to 59 s, and `occurredAt` is the
time `IncidentEventPublisher` built the event, not the incident's `resolvedAt`. The consumer's
`openedAt` branch exists, but no producer fills it.

**Approach.** Add `openedAt` (the incident's `createdAt`) to `IncidentResolvedEvent` in `shared` and set
it in `publishResolved`; postmortem-service keeps the derived value as the fallback for events already
in the topic or the outbox. A change to `shared` changes all seven services (CLAUDE.md); check every
consumer of the record (none of them should need more than recompiling).

---

### 0-134. `diff-cover` is installed by version, without hashes

**Type:** ci · **Priority:** Low · **Status:** Open (found while fixing #0-76, 2026-10-15)

**Problem.** "Build, Test & Coverage" in `ci.yml` runs `pip install 'diff-cover==10.6.0'`: the version is
pinned, but neither the wheel nor its dependencies are checked, and the dependencies (`Jinja2`, `pluggy`,
`chardet`, `Pygments`) are resolved from PyPI at install time, so a new release of any of them changes
what runs with no change in this repository. README cites it as pinned beside the Snyk CLI (#0-61), which
is checked against a SHA-256, and kubeconform now is too (#0-76); `diff-cover` is the one tool CI installs
at a weaker level. The job runs a PR's own code with a read-only token and no secrets, so the reach is a
coverage gate that could be made to pass, not a credential.

**Approach.** A lock file with every package's hashes (`pip-compile --generate-hashes`, or `uv pip
compile`) committed under `.github/`, installed with `pip install --require-hashes --no-deps -r`; Renovate
can update a pip-compile file and its hashes together (`pip-compile` manager), so the bump need not be by
hand (as for the release-asset tools since #0-147, ADR-0033). Decide whether that manager is turned on for `.github/`.

---

### 0-135. kubectl in CI is downloaded unverified

**Type:** ci · **Priority:** Low · **Status:** Open (found in the review of #0-76, 2026-10-15)

**Problem.** The k8s job (`validate-k8s-manifests` in `ci.yml`) installs kubectl with
`azure/setup-kubectl` (v4.0.1, pinned by SHA), which downloads `dl.k8s.io/release/v<version>/bin/linux/amd64/kubectl`
with `toolCache.downloadTool` and caches it without checking a checksum or a signature (`src/run.ts` at that
SHA). Since #0-76 its version is pinned, but nothing checks that the binary is the one Kubernetes released.
kubectl renders the manifests into `/tmp/*-rendered.yml`, and the checks after it read those files: #0-63's
"staging and prod set no Spring profile", #0-42's mail check and kubeconform itself, so a replaced kubectl could
make them all pass, the vector #0-76 closed for kubeconform. Same reach as #0-76: a read-only token and no
secrets in that job.

**Approach.** Kubernetes signs its release binaries with Sigstore: `kubectl.sig` and `kubectl.cert` sit next
to the binary on `dl.k8s.io` (checked for v1.36.5: the certificate is issued by `sigstore.dev` to
`krel-staging@k8s-releng-prod.iam.gserviceaccount.com`, OIDC issuer `https://accounts.google.com`). Download
kubectl directly instead of through the action, and verify it with `cosign verify-blob --certificate
--signature --certificate-identity --certificate-oidc-issuer` before it runs. cosign itself then has to be
installed pinned and checked (`sigstore/cosign-installer` by SHA, or the binary with its published checksum),
and the expected identity checked against the Kubernetes release documentation rather than taken from one
certificate. The `.sha256` next to the binary is from the same host, so on its own it is the weaker check
ADR-0021 refused for Snyk.

**Also (review round 2 of #0-166 PR 1, 2026-10-25).** The runtimes' setup actions have the same gap: `setup-java`,
`setup-python` and, since #0-166 (ADR-0040), `ruby/setup-ruby` (all pinned by SHA) download a prebuilt runtime and
verify nothing (`setup-ruby` v1.335.0's `downloadAndExtract`: download, then `tar -xz`), and every check of their
jobs runs on it. Ruby's builds (`ruby/ruby-builder`) publish no signature; decide per runtime what can be checked
(a published digest, an attestation) and what stays the action's word, in the same pass as kubectl.

---

### 0-136. The security review rules have no rule for the CI supply chain

**Type:** docs · **Priority:** Low · **Status:** Open (found in the review of #0-76, 2026-10-15)
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** `.ai/rules/review/security.md`

**Problem.** ADR-0021 (Snyk CLI) and ADR-0027 (the k8s job's inputs) decide that a tool CI downloads is
pinned and checked before it runs, and ADR-0027 says how a reviewer recognises a violation (a tool fetched
from `latest` or without a checked checksum or signature, an unpinned validation input). No rule in
`.ai/rules/review/security.md` says so: SEC-50 is about the project's dependencies and their CVE suppressions
(`owasp-suppressions.xml`, `.snyk`), not about tools a workflow downloads. The security reviewer of
#0-76 reported it as a rule gap, so a change that reintroduced `releases/latest` could be found but not
cited as blocking.

**Approach.** The owner adds one rule (`.ai/rules/` is human-owned), written as #0-115 asks, e.g. "A tool or
data file a workflow downloads is pinned (version, commit or digest) and checked (checksum from two
channels, or a signature) before it runs; ADR-0021, ADR-0027. Check: every new `curl`/`wget`/install in
`.github/` names a version and verifies it." Open gaps it would flag today: #0-134, #0-135.

**Also (found in the review of #0-147, 2026-10-17).** ADR-0033 replaced ADR-0021's two channels with a check
against the publisher (attestation, signature, checksums file or digest), so the rule cites ADR-0033 and reads
"checked against its publisher by `check-pinned-tools.sh`, installed only by `install-pinned-tool.sh`". The
security reviewer of #0-147 named two more checks the rule should carry: a privileged trigger (`workflow_run`,
`pull_request_target`) decides by event and repository, never by branch name (the fork's `main` of #0-148,
today only in `.ai/context/security.md` "CI workflows"); and no code from the checkout that a step holding a
secret relies on (an installer script, a tool it runs) runs after an untrusted build step in the same job (the
Snyk CLI's installer ran after `./mvnw compile` until that review).

**Also (found in the security review of #0-109, 2026-10-18).** No rule covers a scanner the scanned change can
reconfigure: a tool that reads its config or ignore file from the checked-out tree (betterleaks' `.gitleaks.toml`
and `.gitleaksignore` at the root, read even when a flag names another directory) lets the pull request it checks
switch its rules off; `secret-scan.sh` refuses both (ADR-0036). Nor one for a workflow command built from a
repository-controlled string (a file name with a newline in an `::error file=...` annotation). Candidate rule: "a
CI check reads its rules from the base branch or from flags, never from the tree it checks".

**Also (found in the review of #0-29, 2026-10-15).** No rule covers the separation of deployment environments
either: which namespace an overlay deploys into and what prod runs. `check-k8s-environments.rb` enforces both in
CI, but a reviewer cannot cite a rule for a change that weakens it. The check also skips resources without
`metadata.namespace`, the cluster-scoped ones: no overlay renders one other than its Namespace today, but a
ClusterRole or ClusterRoleBinding added to one environment would act across the whole cluster unchecked. When the
rule is written, decide whether the check should also refuse every cluster-scoped kind other than Namespace in an
overlay's render; that part touches `.github/scripts/check-k8s-environments.rb` and its test as well.

**Also (the research of #0-161, 2026-10-24).** `.ai/context/security.md` "CI workflows" (privileged triggers,
secrets only in an environment `main` may use, a step holding a secret relying on nothing that ran after the
build, `permissions:` per job) is knowledge without ids, so none of it can be cited as blocking either. #0-161
left CI out of `factory.md` on purpose (a different domain: GitHub's tokens and the supply chain, not agents),
but its form is the precedent: a file read only when the diff touches `.github/workflows/` or `.github/actions/`
(or rules in `security.md`, read by the implementer for every item — which no autopilot item needs, as
`.github/` is Owner-only); decide here which.

**Also (the research of #0-115's `security.md`, 2026-10-26).** Kept apart from that rewrite; why: #0-115, "Decided for
`security.md`". The rules written here take its form (an invariant with a "Check:" line, "Backed by:" where a check
exists).

---

### 0-139. The HPAs scale the JVM services on memory

**Type:** design · **Priority:** Low · **Status:** Open (found in the analysis of #0-137, 2026-10-15)

**Problem.** Every HPA in `k8s/base/*/service-hpa.yml` scales on CPU (70%) and on memory (80%), and an HPA scales up when
either metric is above its target. The services are JVMs: the heap grows to what the JVM is allowed and is rarely given
back to the operating system, so memory utilisation stays high after the load is gone. The memory metric can then hold a
service at its ceiling, or scale it up on heap growth that is not load; and the ceilings are what #0-79's connection
arithmetic counts. Not measured: no cluster runs these manifests yet.

**Approach.** Measure first, on a cluster under load: whether memory utilisation follows the load at all. If it does
not, scale on CPU only, or on a metric that follows the work (requests per pod, or the Kafka consumer lag through KEDA
for the consumers), and keep memory as a limit (OOM protection), not a scaling signal.

---

### 0-140. The services' pods are not spread over zones, nor rebalanced after scale-down

**Type:** design · **Priority:** Low · **Status:** Open (left open by #0-138, ADR-0029, 2026-10-16)

**Problem.** Since #0-138 each service's pods spread over nodes (`topologySpreadConstraints` on
`kubernetes.io/hostname`, `ScheduleAnyway`), but not over zones: on a cluster with several zones, every pod of a
service may run in one zone, whose outage takes the service down. And the spread is applied only when a pod is
scheduled: an HPA scale-down removes pods without regard to it, and a drain's evicted pods land wherever there is
room, so the placement can drift until the pods are rescheduled. Not observable yet: no cluster runs these manifests.

**Approach.** Once the target cluster and its zones are known: a second constraint on `topology.kubernetes.io/zone`
(`ScheduleAnyway` unless every zone is sure to have capacity), extended in `check-k8s-environments.rb` rule 6; and
decide whether the cluster runs a descheduler (`RemovePodsViolatingTopologySpreadConstraint`) or accepts the drift.

---

### 0-143. The images do not use a CDS or AOT cache

**Type:** design · **Priority:** Low · **Status:** Open (left open by #0-141, ADR-0030, 2026-10-16)

**Problem.** Since #0-141 every image runs the jar extracted into Spring Boot's layers, the layout Spring Boot's
CDS support (and Java 24+'s AOT cache) is built on, but no image creates or uses an archive: each start loads and
links every class again. Start-up time matters for the HPAs' scale-up and for a rollout; not measured.

**Approach.** Measure the start-up of one service first. If worth it: a training run in the `layers` stage
(`-XX:ArchiveClassesAtExit=application.jsa -Dspring.context.exit=onRefresh`) and `-XX:SharedArchiveFile` in the
`ENTRYPOINT`; the training run starts the Spring context, so it must not need the database, Kafka or secrets
(check what each service's refresh touches), and the JVM flags of the training run and of the runtime must match.

---

### 0-151. Local actions are called by path, not by GitHub's self-repository syntax

**Type:** ci · **Priority:** Low · **Status:** Open (found in the review of #0-147, 2026-10-17; waits on actionlint)

**Problem.** The workflows call `.github/actions/restore-maven-caches` and `save-maven-caches` as
`uses: ./.github/actions/...`. GitHub's `$/` self-repository syntax (July 2026) names the repository the workflow
runs from rather than a path in the checkout, and zizmor's `self-repository` audit asks for it. The pinned
actionlint (v1.7.12) predates the syntax and would refuse it, so `.github/zizmor.yml` turns the audit off for the
whole repository (#0-147): a new local action called by path is not flagged either.

**Approach.** When Renovate bumps actionlint (#0-147, ADR-0033) to a release that accepts `$/`: switch the five
`uses: ./.github/actions/...` lines (zizmor's auto-fix), check that `check-maven-caches.rb` (the tenth structural
rule) still recognises the two actions under the new form, and delete the `self-repository` entry from
`.github/zizmor.yml`. Touches `.github/`, so human-only.

---
### 0-152. Refresh the Snyk CLI signing key before 2027-01-06

**Type:** ci · **Priority:** Medium · **Status:** Open — C and D done in PR #621 (owner, after `/research 0-152`, 2026-11-13); B
waits for Snyk's next key (found in the review of #0-147, 2026-10-17; due before 2027-01-06)
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** ci (.github/scripts/check-pinned-tools.sh, .github/scripts/test-check-pinned-tools.sh,
.github/scripts/watch-signing-keys.sh, .github/scripts/test-watch-signing-keys.sh, .github/workflows/ci.yml,
.github/workflows/snyk.yml, .github/workflows/signing-keys.yml, .github/keys/), docs (ADR-0033, README.md
"Infrastructure Hardening", .ai/context/infrastructure.md)

**Problem.** `check-pinned-tools.sh` checks the Snyk CLI pin against `sha256sums.txt.asc`, signed by the key
committed as `.github/keys/467717A30B2B4658415975629691DA64D0025194.asc` (ADR-0033). That key and its subkey expire
on 2027-01-06, and the checker refused `EXPKEYSIG`: from that day Lint Workflows would be red on every pull request
and on `main` (`main-guard.yml` then opens `autopilot-stop`), and both `snyk.yml` jobs would stop before the scan.
What `/research` found (2026-11-13, `gh api` on snyk/cli, gpg in a container):
- **Snyk rotates, it does not extend**: the key file's history holds three keys, `68BF…9569` (2022, no expiry),
  `A226…296E` (2023-01-05 to **2025-01-04**) and ours, `4677…5194` (**2025-01-06** to 2027-01-06): the new key came two
  days after the old one expired. In December there would be no new key to take, as the first Approach assumed.
- **gpg judges the key at verification time**: v1.1294.2 (2024-11-26), signed by the 2023 key before it expired, now
  reads `EXPKEYSIG` (exit 0, `VALIDSIG` with the signature's date in field 5). Every old release fails with the key,
  so no older pin is a way round.
- Snyk publishes no GitHub attestation (404) and its releases are not immutable: `gpg:` stays the only method.

**Decided (owner, after `/research`).**
- **C (done):** an expired key passes only for a pin that was already on main before the key expired (same file,
  word for word, at the last first-parent merge commit dated before the expiry; `fetch-depth: 0` in lint-workflows and both
  `snyk.yml` jobs) and whose signature is dated before that expiry. A pin that reached main later, a shallow history,
  no git or a file the commit lacks needs an unexpired key; a revoked key refuses every pin. Why it holds: a stolen
  expired key could backdate a signature, but only for a pin that reaches main after the expiry (ADR-0033 amended).
  Review round 1 (security sec-5b1e, architecture arc-5c1e) replaced the first anchor, `HEAD^`: in `snyk.yml`, which
  runs on main only, a bypass-merged pin would have been "unchanged" from the next commit on and got `SNYK_TOKEN`.
  Review round 2 (security): a key both expired and revoked read `EXPKEYSIG` plus `KEYREVOKED`, not `REVKEYSIG`, and
  passed (checked with gpg 2.4.7), so the checker also refuses `KEYREVOKED` and a key whose validity is `r`; and the
  anchor takes merge commits only, since the ruleset allows rebase and squash, whose commits carry their author's dates.
- **D (done):** `signing-keys.yml` runs `watch-signing-keys.sh` every Monday: each key file's `<fingerprint>.source`
  names the publisher's file (`snyk/cli help/_about-this-project/snyk-code-signing-public.pgp`); a new primary
  fingerprint, a revocation or a later expiry there opens one issue, and a key it cannot fetch or read opens another
  and fails the job (both labelled `security`, found by label and author `app/github-actions`, so an outsider's issue
  with the same title cannot silence it). lint-workflows checks offline that every key has its `.source`.
- **B (open):** when the watch's issue opens (or Renovate's bump fails on the old key), one owner PR: the new key
  file and its `.source`, after the three-way fingerprint check (snyk/cli, docs.snyk.io, keys.openpgp.org), the new
  `verify=gpg:` in `snyk.yml`, and the pin bumped to a release the new key signed.
- Rejected: refreshing in December (no key yet), accepting `EXPKEYSIG` without the base condition (a backdated
  signature for a new pin would pass), a new install method (no Snyk attestation; npm provenance unverified).

**Acceptance criteria.**
AC1. An expired key passes for a pin on main before its expiry, signed before it, also after later changes to the
file; it refuses a pin that reached main after the expiry, a backdated side-branch commit merged after it, a
backdated commit straight on main (a rebase), a shallow history, no history, and a signature dated after the expiry;
a revoked key refuses a pin long on main, and so does a key both expired and revoked; shown by
`test-check-pinned-tools.sh`. (done)
AC2. `watch-signing-keys.sh` reports a rotated, a revoked and an extended key (exit 3), passes the committed one
(exit 0), fails closed on a missing source, a failed fetch or an unreadable key (exit 1), and `--sources-only` fails a
key without its source; shown by `test-watch-signing-keys.sh`. (done)
AC3. Snyk's next key is committed after the three-way check and the Snyk CLI pin names it and a release it signed,
with `check-pinned-tools.sh` green on that pull request. (open)

---

### 0-153. Decide which paths need the owner's review, before auto-merge

**Type:** design · **Priority:** Medium · **Status:** Open (carried out by migration stage 6a, ADR-0055); noted 2026-10-16 (PR #499) in #0-113, moved here from it and widened by its security review (2026-10-18); a precondition of phase 3 (auto-merge, `docs/ai-factory.md`)
**Autopilot:** human-only · **Risk:** high · **Complexity:** low · **Depends on:** —

**Problem.** Since #0-113 (ADR-0034) the code owner review of `.github/CODEOWNERS` is enforced, so what it does not
name is what a PR can change on green checks alone, and with auto-merge without anyone reading it. Three points are
known.

**1. `.dockerignore` (noted 2026-10-16, PR #499).** Since #0-141 the root
`.dockerignore` is the allowlist that keeps sources, `.env` files and `application-local.yml` out of every
image's build context (SEC-33). An agent may change it: a narrowing breaks the image build (the smoke test is
red), and a widening reaches an image only together with a Dockerfile `COPY`. Both changes go to the k8s
reviewer (PR #499) and to the security reviewer, who answers `NEEDS_HUMAN` for a widening; no script checks
it (`check-no-local-config-in-jars.sh` checks the jars, not the images). That is enough while the owner
reads every PR before merging. Once a PR can merge without that read, decide whether `.dockerignore` and
`*/Dockerfile.dockerignore` go on the build-config list of `.ai/rules/protected-paths.md` (the autopilot then
stops on any change to them, and Factory guards rule 6 asks for the owner's approval). Not done in #499: the
list is for what decides how the build is verified, and today a reviewer and the owner catch a widening.

**2. `.ai/context/` and `.ai/decisions/` (security review of #0-113, 2026-10-18).** Every agent and reviewer reads
them as authority (the architecture, security and CI rules, the decided patterns), but neither is in CODEOWNERS nor
on the protected list. A PR that changes only Markdown skips the build (`detect-changes`), so a bot PR rewriting
`.ai/context/security.md`, or adding an ADR that "decides" a pattern the reviewers then accept, merges on green.
Harmless while the owner reads every PR (shadow mode); decide before phase 3 whether they become code-owned (the
autopilot's own knowledge updates, `.ai/rules/implementation.md`, then wait for the owner) or stay open with
another check.

**Also (review round 2 of #0-166 PR 1, 2026-10-25).** The build-config list (`mvnw`, `mvnw.cmd`, `.mvn/`, and
`.ruby-version` since #0-166) is code-owned today only through the shadow-mode catch-all (point 3): `check-protected-paths.sh` asks
CODEOWNERS lines of the owner-only list alone, and Factory guards rule 6 is what holds the build-config list. When
phase 3 removes `*`, decide whether those paths get lines of their own.

**3. The shadow-mode catch-all (#0-113, 2026-10-18).** Until phase 3 `.github/CODEOWNERS` opens with `* @lukaszplawiak`,
so every PR needs the owner's approval (the machine account's own approval would otherwise count). Phase 3
removes that line; what this item decides is what stays owned once it is gone.

**4. Who may dismiss a review (#0-237, 2026-11-13).** In an organisation the ruleset's `pull_request` rule has
`dismissal_restriction`; `rulesets/main.json` keeps GitHub's default, `enabled: false`, so any account with Write, the
machine account included, can dismiss the owner's "changes requested". It gives that account no approval, so while
the owner approves every PR it only removes a block the owner can set again. Once a PR can merge on another approval
(review-app, stage 5; auto-merge, phase 3), decide whether dismissals are restricted to the owner (`enabled: true`,
`allowed_actors` naming the owner) and how that actor's id is written in the file.

**Acceptance criteria.**
AC1. Each path above is either code-owned (CODEOWNERS, and `.ai/rules/protected-paths.md` when an agent must not
write it) or the reason it is not is recorded here and in `docs/ai-factory.md`.
AC2. `docs/ai-factory.md` phase 3 names the decision.

---

### 0-155. A scan that cannot run on `main` alerts no one

**Type:** ci · **Priority:** Medium · **Status:** Open — found in the analysis of #0-154 (2026-10-18)
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —

**Problem.** From 2026-10-18 06:16 every run of `snyk.yml`'s dependency scan on `main` ended in `Authentication
error (SNYK-0005)`: `SNYK_TOKEN` (last set 2026-07-19) no longer authenticates, most likely a Snyk token expired
after 90 days. Until then the same job failed on its findings (46–47 issues, #0-69), so a red Snyk run on `main` was
normal and the switch from "found issues" to "could not scan at all" changed nothing anyone sees. Nothing watches
it: `main-guard.yml` reacts to the CI workflow only, the code scan hides its errors behind `continue-on-error: true`
(its 403, #0-68), and so does the OWASP scan, whose NVD outage or bad key would look the same as a clean run. The
platform then has no dependency scan while every signal says what it always said.

**Approach (to analyse).** Tell a tool that could not run from one that found something: `snyk test` exits 1 on
findings and 2 on an error (authentication, configuration), 3 when it finds no project; dependency-check reports
an NVD failure in its log. A scan step could fail hard only on the error case, and something must then reach the
owner: `main-guard.yml` widened to the scan workflows for that case only (it would stop the autopilot, which may be
too much for a scan), or an issue of its own, opened by the scan's run on `main` or `schedule` and closed by its
next good run. Also, as #0-152 does for Snyk's signing key: record the token's expiry and warn ahead of it. Whatever
is chosen, the #0-69 and #0-68 failures must not raise it every week, or it says nothing either.

**Acceptance criteria.**
AC1. A scan on `main` (push or schedule) that cannot authenticate or reach its database reaches the owner in a way
that does not depend on opening the Actions tab.
AC2. A scan that only finds issues (#0-69) does not.

---

### 0-156. Secrets are scanned only after the push

**Type:** security · **Priority:** Medium · **Status:** Open — found in the analysis of #0-109 (2026-10-18)
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** #0-109

**Problem.** The Secret Scan job (#0-109, ADR-0036) and GitHub's push protection both run after the push. This
repository is public, so a secret on a pushed branch is published before either says anything: the finding
means rotating it, not deleting it. Nothing scans before the push: no git hook in the repository
(`.githooks`, `core.hooksPath`: none), and the autopilot's push path (`.claude/hooks/guard-git-push.sh`, the
shipper) checks branches, not content. Also open: an allow comment (`gitleaks:allow`) passes whatever its line
holds, its reason unchecked.

**Seen (2026-11-06, #0-197, PR #590).** The autopilot shipped a PR whose Secret Scan failed at once: the implementer
repeated auth-service's two dev-only test keys (`mfa.encryption-key`, `slack.encryption-key`, base64 of
`test-key-32-bytes-for-dev-only!!` and `slack-key-32-bytes-for-dev-only!`, the values of every auth-service security
test) in a nested class with `@NestedTestConfiguration(OVERRIDE)`, which inherits none of the outer properties, and
`generic-api-key` matched the two new lines. No secret, but the gate, the panel (all five APPROVE) and acceptance
passed it: none of them runs `secret-scan.sh`. A fix commit on top does not clear it, since the scan reads every
commit of the range (`git log -p -m`, ADR-0036): the owner folded the `gitleaks:allow` comments into the implementer's
commit (`fixup!` + `git rebase --autosquash`) and force-pushed the bot's branch (head `30e1bf3e` → `f3f40556`). So for
an agent the check belongs before its commit is final, not only before the push: run on the branch's commits by the
test gate (`run-tests.sh`, which already knows the run's base), a finding is a fixable failure for the
implementer, who can still amend its own commit (to decide with the Approach below).

**Approach.** The same pinned betterleaks before the push: in the factory's push path (the session hook or the
shipper's script, `.claude/`, owner-only) on the commits the push sends, and as an opt-in pre-push hook for
developers (`core.hooksPath` to a committed directory), in the devcontainer by default. Decide whether an allow
comment must carry a reason the script checks (like `# not-a-download: <why>`, #0-149).

**Acceptance criteria.**
AC1. An agent's push of a commit holding a secret-shaped string is refused before it reaches GitHub.
AC2. A developer who enables the hook gets the same refusal, with the same rules and binary as CI.
AC3. README "Infrastructure Hardening" lists the control and drops the gap.

---

### 0-158. Spring Boot 3.5 is out of open-source support; decide the move to 4.x

**Type:** design · **Priority:** High · **Status:** Open — found with #0-157 (2026-10-20)
**Autopilot:** human-only · **Risk:** high · **Complexity:** high · **Depends on:** —

**Problem.** The platform runs Spring Boot 3.5.16 (root `pom.xml`), whose open-source support ended 2026-06-30
according to `.snyk` (to verify on spring.io). Snyk names the 4.x line (Spring Boot 4, Framework 7, Security 7,
spring-kafka 4) as the only fix for a growing share of the findings: `spring-webmvc` `SNYK-JAVA-ORGSPRINGFRAMEWORK-19267098`
(Critical, Arbitrary Code Injection), `spring-web` (XSS, cookie without `Secure`, two resource exhaustions),
`spring-expression`, `spring-beans`, `spring-security-core` (Timing Attack) and `spring-security-crypto`
(Predictable IV with CBC), `spring-kafka` `-19267472`, Netty via Lettuce, lz4 and zookeeper via
`spring-kafka-test`. Since June every such `.snyk` ignore says "tracked for the Spring Boot 4.x migration", but no
item tracks it.

**Approach (to analyse).** Commercial support for 3.5 against migrating. The migration's reach: Spring Security 7,
Jackson 3, spring-kafka 4 with kafka-clients 4, Hibernate 7, springdoc 3, Testcontainers 2, the starters split in
Boot 4. One parent POM means the services cannot move one at a time: decide one PR or steps (`shared` first,
behind a branch), and what CI proves at each. Record the decision in an ADR.

The migration also removes the root POM's `tomcat.version` override (#0-157), which keeps Tomcat 10.1 patched until
then.

**Acceptance criteria.**
AC1. An ADR decides: the migration with its plan, or a deferral with its reason and a date to revisit.
AC2. If migrating, the steps are items in this backlog, and the `.snyk` ignores citing "the 4.x migration" name them.

---

### 0-159. Security version overrides in the root POM are bumped and checked by hand

**Type:** ci · **Priority:** Medium · **Status:** Open — found by the `/review` of #0-157 (2026-10-22)
**Autopilot:** not-ready · **Risk:** medium · **Complexity:** low · **Depends on:** —

**Problem.** The root `pom.xml` overrides versions the Spring Boot parent manages (`tomcat.version`,
`postgresql.version`, `jackson-bom.version`, ...) to take CVE fixes. Two things nothing checks: (1) Renovate sees
no dependency that uses `tomcat.version` (it only drives the parent's BOM), so a new Tomcat 10.1 release with a
fix reaches us only when a person reads Apache's security page; `postgresql.version` was bumped by hand too (PR
#305). (2) Nothing fails when an override is lower than what the parent manages, so a parent bump can be held back
silently by a stale override (at the move to Spring Boot 4, #0-158, a leftover `tomcat.version` 10.1.x would force
Tomcat 10.1 onto Boot 4).

**Approach (to analyse).** (1) Whether Renovate's maven manager bumps these properties as they are, or a
`customManagers` regex (a `<!-- renovate: depName=... -->` comment before the property, like the CI tools' pins,
#0-147) is needed; limit Tomcat to the 10.1 line (`allowedVersions`). (2) A check in CI that every overridden
property is at least the parent's managed version: `maven-enforcer-plugin` with a custom rule, or a script over
`help:effective-pom` of the parent; consider it with #0-110 (Enforcer in the root POM).

**Acceptance criteria.**
AC1. A new Tomcat 10.1 or PostgreSQL JDBC release opens a Renovate PR for its property.
AC2. A root POM property lower than the version the Spring Boot parent manages fails CI, with the property named.

---

### 0-167. No hook of the owner's session refuses git's writing options

**Type:** security · **Priority:** Medium · **Status:** Blocked — superseded by migration stage 6a (ADR-0055, 2026-11-13); was Open — moved out of #0-165 (2026-10-25), whose round-1
review found the first version of the hook passable
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** #0-165
**Touches:** factory (.claude/hooks/ (a session-level Bash guard, `_lib.sh`), .claude/hooks/readonly-bash.sh,
.claude/hooks/guard-protected-bash.sh, .claude/hooks/guard-factory-scripts.sh, scripts/factory/local-review.sh,
.claude/hooks/test-hooks.sh, .claude/settings.json, .claude/settings.autopilot.json, .claude/skills/research/SKILL.md,
.claude/skills/ship/SKILL.md, .github/scripts/check-hook-entries.rb, .github/scripts/test-hook-entries.sh),
.ai/rules/review/factory.md (owner, FAC-S03), .ai/decisions/, docs (README.md "Infrastructure Hardening",
.ai/context/security.md, docs/ai-factory.md)

**Problem.** `git diff`, `git show` and `git log` take `--output=<file>` (writes anywhere) and `--ext-diff`/
`--textconv` (run a program git's configuration names). In autopilot sessions too (#0-131, review round 3): `Bash(git log *)` and its
siblings are allowed there, and since #0-131 `guard-protected-bash.sh` refuses those options only in their plain
form, so a spliced form could still write `.ai/runs/LOCK`, the run's branch the push guard trusts. `/research` pre-approves `git log *`, `git diff *` and
`git show *`, `/ship` `git diff *`, and the owner's session has no Bash hook, so text the session reads (a
diff, a backlog item, a web page) that steers it into such a command runs without a prompt. #0-165 removed the
wildcards from `/review` and `/accept` only. `readonly-bash.sh` refuses the options for the reviewers by matching
the raw text, which quoting inside a word or a line continuation can split.

**What round 1 of #0-165 found in the first version** (a word split as bash splits it, then compared): an option
spliced with empty quotes or a backslash, a backslash-newline continuation, a quote spanning lines (a newline
reset the quote state), a word built at run time from variables set in the same command, and a hook that ignored
its check's exit status. Claude Code's own permission check refused brace expansion, `$( )` and `$'…'` but
pre-approved the variable case under `Bash(git log *)` (spike, 2026-10-25).

**Approach (to analyse).** Either a guard that reads a command as bash does (continuations, quotes, heredocs,
expansions; failing closed on what it cannot read) with mutation-tested cases for each shape above, or exact
`allowed-tools` in `/research` and `/ship` too (cheaper; `/research` then prompts for most git reads). Also decide
`readonly-bash.sh`'s raw-text match.

**Also (round 2 of the review of #0-165, 2026-10-25; non-blocking there).** `scripts/factory/local-review.sh` reads
`_common.md` and `general.md` from the working tree (`cat`), not from main; the autopilot's reviewers could read
the rules at the recorded `mergeBase` instead of `refs/remotes/origin/main`; `docs/ai-factory.md` "What isolates
what" does not describe #0-165 yet; and `factory.md` has no rule that a control reading the base names an
unambiguous ref, nor one listing the files of a branch that steer the owner's session (`.claude/`, `CLAUDE.md`,
`.ai/context/`).

**Acceptance criteria.**
AC1. No skill of the owner's session pre-approves a git command that can carry `--output`, `--ext-diff` or
`--textconv`, or a hook of every session refuses them, shown by test cases for each shape of round 1 of #0-165.
AC2. `readonly-bash.sh` refuses those options however the word is quoted or continued, shown by test cases.
AC3. README "Infrastructure Hardening" no longer lists this gap.

---

### 0-171. A `/seed-bugs` run that measured nothing leaves no record

**Type:** ci · **Priority:** Low · **Status:** Open — `nonBlocking` FAC-A03 of review-architecture in the `/review` of
#0-170 (2026-10-25)
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-170
**Touches:** factory (.claude/workflows/seed-bugs.js, scripts/factory/seed-record.sh: the row writer since #0-177), ci
(.github/scripts/test-autopilot-workflow.mjs), .ai/rules/audit.md (owner)

**Problem.** `seed-bugs.js` writes a row to `.ai/audit/benchmark/results.md` only for a MEASURED run; a FAILED or
SKIPPED one is returned to the session that started it and nowhere else. The audit then cannot tell a dimension that
was measured and caught nothing from one that was never measured, which is how #0-170 went unseen: no row had ever
been written.

**Approach (to analyse).** Record every run, its outcome and reason included (a row with `FAILED`/`SKIPPED`), and have
the audit count the attempts per dimension next to the catches.

**Also (review round 2 of #0-176, architecture FAC-A02).** A MEASURED run reports `recorded: true` once `audit-synthesis`
answers without an error, whatever it answered: nothing checks that the row was written. A typed answer
(`{ appended: boolean }`, FAC-A06) and `recorded` only on `appended === true` would close it, with the same row writer.
Done by #0-177: `scripts/factory/seed-record.sh` writes the row (into `.ai/runs/benchmark/results.md`) and the run is
recorded only on its `appended: true`; `audit-synthesis` no longer takes part. A FAILED or SKIPPED row (AC1) would go
through the same script.

**Acceptance criteria.**
AC1. A FAILED or SKIPPED run leaves a row with its outcome and reason, shown by a test.
AC2. The audit's benchmark section reports, per dimension, runs that measured nothing.

---

### 0-178. A real defect the panel missed never becomes a seeded pattern

**Type:** design · **Priority:** Medium · **Status:** Open — the owner's question in the research of #0-115's
`security.md` (2026-10-26): should real defects found by review or audit become seeded patterns?
**Autopilot:** human-only · **Risk:** medium · **Complexity:** medium · **Depends on:** —
**Touches:** .ai/rules/audit.md (owner), .claude/agents/audit-reviewers.md, .claude/agents/audit-synthesis.md,
.claude/skills/apply-audit/SKILL.md, scripts/factory/audit-data.sh (+ its test), .ai/audit/benchmark/patterns.md
(owner), docs (docs/ai-factory.md); optionally scripts/factory/seed-branch.sh and .claude/workflows/seed-bugs.js (replay)

**Problem.** `.ai/audit/benchmark/patterns.md` says "A defect that escaped to `main` becomes a new pattern here (the
audit report proposes it; the owner adds it)", but nothing does it: neither `.ai/rules/audit.md`, nor the audit agents,
nor `/apply-audit` has a step that proposes a pattern, so the catalogue holds only the 18 synthetic patterns written at
the start. The two signals a pattern should come from are recorded and then lost:
- an escape (the "Fixes … Escaped from" marker of an item, vouched by `audit-data.sh`) shows what the panel
  does not see, the most valuable pattern there is; the audit counts it, but no pattern follows, so nothing checks that
  the rule written after it now catches it;
- a `ruleGap` in a verdict (a defect the reviewer saw but could not block, e.g. `releases/latest` in #0-76, which became
  #0-136) reaches the backlog only when the session that ran the review copies it; `audit-data.sh` does not collect
  them.

**Approach (to analyse).** Close the loop: escape or rule gap → the rule (new or sharpened, the owner's
`.ai/rules/review/<dimension>.md`) → a pattern in `patterns.md` with its source → `/seed-bugs` on it once the rule is on
`main`.
- Which defects: an escape always; a `ruleGap` once its rule exists; a defect the panel caught and blocked only by the
  owner's choice, for the critical classes (tenant isolation, auth) as a regression guard when rules are rewritten
  (#0-115). Not every finding: a catalogue fed by what the panel already catches measures less and less (survivorship).
  A pattern is a repeatable mutation ("drop the tenant predicate"), not a one-off, and not a duplicate of one there.
- Who: the audit, which already has the escapes and the verdicts; a recommendation "pattern P-NN from <rule>, source PR
  #…" in its report, applied by the owner with `/apply-audit` like any other. `audit-data.sh` collects the verdicts'
  `ruleGap` entries per dimension.
- `patterns.md` gets a "Source" column: the PR or commit of the real defect, or "synthetic".
- Optional, "replay": for an escape, the fix commit is the exact recipe: `seed-branch.sh` could revert the fix on the
  change that held the defect, with no seeder (deterministic, as realistic as it gets); only while that revert still
  applies to `main`, so for recent escapes; older ones fall back to a described pattern.

**Acceptance criteria.**
AC1. A vouched escape in an audit's period ends in a recommendation for a pattern (or a recorded reason why not), shown
by a test of the audit's data or of the synthesis' rules.
AC2. `audit-data.sh` reports the verdicts' `ruleGap` entries per dimension, shown by its test.
AC3. `patterns.md` names each pattern's source, and `docs/ai-factory.md` describes the loop.

**Also (review round 2 of #0-115's `architecture.md`; moved to #0-184, 2026-10-28).** Nothing checks that the rule a pattern cites is a live id
of its dimension's file. Retiring ARC-20 left P-06…P-08 citing it until the same PR renamed them, and nothing would
have failed if it had not. A Factory guards check could read `patterns.md`'s "Rule" column against the ids of
`.ai/rules/review/<dimension>.md` and refuse one that is missing or `retired`.

### 0-183. The k8s reviewer could render a tracked-only snapshot with no network

**Type:** security · **Priority:** Low · **Status:** Blocked — superseded by migration stage 5 (ADR-0055, 2026-11-13); was Open. From #0-182 (owner, 2026-10-27): B took the render away
from the k8s reviewer; this is how to bring it back safely, if the owner's manual review misses it.
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** #0-182
**Touches:** factory (scripts/factory/ or .claude/hooks/: a render script and its test, readonly-bash.sh,
.claude/agents/review-k8s.md, both settings files), .ai/rules/review/_common.md and factory.md (owner), security
(README "Infrastructure Hardening")

**Problem.** Since #0-182 the k8s reviewer reads manifests as files; an overlay's patches over a base are read by
hand. A guard that predicts what `kubectl kustomize` reads failed twice (#0-182's rounds: `~`, YAML escapes and tags,
remote shorthands, file-name case, gitignored files).

**Approach (to analyse).** Control what kustomize can reach instead of predicting it, as Argo CD and Flux do: a script
(e.g. `render-k8s.sh <overlay>`) copies to a temporary directory only the files under `k8s/` that git tracks or
that are new and not ignored, refuses a symlink (mode 120000), and runs `kubectl kustomize` there with no option and
no network (an unreachable proxy, `GIT_ALLOW_PROTOCOL=file`, or `sandbox-exec` on macOS). The reviewer's hook allows
that script with one overlay name and nothing else. Nothing outside the snapshot exists for kustomize to read, so
YAML tricks no longer matter.

**Acceptance criteria.**
AC1. The script renders the repository's overlays as CI does, and refuses a symlink, an ignored file and a remote
base; shown by its test, with a mutation of each refusal failing a case.
AC2. Every attack of #0-182's rounds, replayed against the script, prints no file from outside the snapshot.
AC3. README "Infrastructure Hardening" and `review-k8s.md` describe the render; `_common.md` names it (owner).

### 0-188. A logged exception's message reaches the log as the library wrote it

**Type:** security · **Priority:** Medium · **Status:** Open. Known gap of README "Infrastructure Hardening" since #0-94
step 1, which had no item. Split out of #0-187's review (2026-10-30, security and architecture round 1).
**Autopilot:** human-only · **Risk:** medium · **Complexity:** medium · **Depends on:** —
**Touches:** shared (logging: `StructuredLoggingDefaults` or a converter, and its tests), all 7 services through
`shared`, security (README "Infrastructure Hardening", its known gap), .ai/rules/review/security.md SEC-31's last
sentence (owner)

**Problem.** A throwable passed to a logger (`log.warn("…", e)`) puts its message into ECS's `error.message` and every
cause's message into `error.stack_trace`, as the library wrote it. The ECS encoder escapes it, but nothing filters it.
A database, driver, parser or client exception quotes what its query, call or input held: SQL text, a Postgres
`Detail` with key values, a JSON fragment, a URL with a query string. Logs are read across tenants (one Loki org,
#0-94 step 2). `KafkaFailures.reason`/`describe` (#0-96) keeps such messages out of dead-letter reasons and the lines
built from them, but every other `log.*(…, e)` keeps them. SEC-31 (#0-187) judges a new line that adds an exception's
message itself, and leaves the throwable to this item. Dropping the throwable everywhere would also drop the stack
traces the operator debugs with.

**Approach (to analyse, `/research`).**
- What reaches the log today, by exception type and service.
- A converter in `shared` that writes `error.stack_trace` with each foreign exception's message replaced by its type
  (the platform's own content-free exceptions kept), against what debugging loses.
- How systems of this kind handle it (log redaction at the encoder, an allow-list of exception types).
- Whether an operator-only log stream changes the answer.

**Acceptance criteria.**
AC1. A decision, as an ADR, on what a logged throwable may carry.
AC2. If it filters, a test per service type of exception shows a foreign message absent from `error.message` and
`error.stack_trace`, and the platform's own message kept.
AC3. README's known gap sentence names the outcome.

### 0-190. A failed `/seed-bugs` run leaves the tree on its branch once the seeder has edited

**Type:** ci · **Priority:** Low · **Status:** Open. Found in `clean-c01-r3` (2026-10-31): the seeder named line 134,
the host's own per-replica job, not its plant at 148-165, and `seed-bugs.js` failed the run ("the seeder's line is not
in its edit", #0-181), rightly.
**Autopilot:** not-ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (scripts/factory/return-to-main.sh, .claude/workflows/seed-bugs.js,
.github/scripts/test-seed-branch.sh, .github/scripts/test-autopilot-workflow.mjs), docs (ADR-0044, docs/ai-factory.md)

**Problem.** Every failure after the seeder's edit (`seed-check.sh` refuses it, the line is not in it, an `also`
place is wrong, the fold or the compile fails) ends with the seeder's edit uncommitted on the seed branch.
`return-to-main.sh` never discards work (`working tree not clean: left as it is for the owner`), so the run ends on
`review/<hex>` and the owner restores the file, runs `return-to-main.sh` and deletes the branch by hand
(`clean-c01-r3`). Until then the session runs on the seed branch, with `.ai/runs/SEED` still holding the seeder's
scope, and the next run is refused. The edit is the run's own: a throwaway plant on a throwaway branch.

**Approach (to analyse).**
- `return-to-main.sh` takes an explicit mode for a seed run that discards only a tracked edit of the change's files on
  the branch named in `.ai/runs/SEED` (never untracked files, never another branch, never on `main`), then returns.
  The autopilot's call keeps "never discards work".
- Or `seed-bugs.js` keeps the plant's diff in the outcome (for the owner to read) and asks a new `seed-discard.sh`.
- Either way, the outcome says what was discarded, so a failed run's plant can still be read.

**Acceptance criteria.**
AC1. A seed run that fails after the seeder's edit ends on a clean `main`, the branch deleted and `.ai/runs/SEED`
gone; shown by tests.
AC2. Nothing but the run's tracked edit on its own branch is ever discarded (untracked files, another branch, `main`
and an autopilot run keep today's refusal); shown by tests.

### 0-193. Four forked security chains do not add `ApiKeyAuthFilter`, as SEC-12 says they do

**Type:** security · **Priority:** Medium · **Status:** Open. Found in `/ready #0-191` (2026-11-01).
**Autopilot:** not-ready · **Risk:** medium · **Complexity:** low · **Depends on:** —

**Problem.** SEC-12 (`.ai/rules/review/security.md`) and CLAUDE.md "Invariants" say a forked `SecurityFilterChain` "adds
`ApiKeyAuthFilter` itself"; `.ai/context/architecture.md` says so only "if it needs API keys". Of the five forks outside
auth-service, only ingestion-service does (`ingestion/config/SecurityConfig`). incident, notification, oncall and
postmortem build their chain with `SharedSecurityAutoConfiguration.buildCommonSecurity`, which adds `JwtAuthFilter` and
`TenantStatusFilter` but not `ApiKeyAuthFilter`; only the shared default chain adds it
(`SharedSecurityAutoConfiguration`, `addFilterBefore(apiKeyAuthFilter, …)`). None of the four accepts keys (the no-op
`ApiKeyLookupService` answers `Invalid`), so a key should still end in 401, but nothing shows it, and a reviewer judging
a new fork by SEC-12 checks a step the existing ones do not have. `ApiKeyAuthFilter` is also a `@Bean`
`OncePerRequestFilter` with no `FilterRegistrationBean`, so Spring Boot may register it as a servlet filter outside the
security chain in every service; to verify.

**Seen in the security review of PR #572 (#0-191, 2026-11-01).** Spring Boot also registers the auth filter beans
(`JwtAuthFilter`, and `ApiKeyAuthFilter` in incident, whose chain does not add it) as plain servlet filters, so they run
outside the security chain as well; no test shows it either way. `JwtAuthFilter`'s Javadoc ("Why no @Component") says
the `@Bean` in `SharedSecurityAutoConfiguration` "ensures exactly one registration", which a `@Bean` of a `Filter` does
not: Boot registers every `Filter` bean unless a `FilterRegistrationBean` disables it. Whichever of A or B is chosen,
the registrations are settled with a test (a `FilterRegistrationBean` with `setEnabled(false)`, or proof that none is
needed) and the Javadoc says what is true.

**Approach (to decide).** (A) `buildCommonSecurity` adds `ApiKeyAuthFilter`, so every chain has it from one place,
and the servlet registration question is settled with it; or (B) SEC-12 and CLAUDE.md say what `architecture.md`
already does (only a service that accepts keys adds it). #0-191's tests show the behaviour either way.

**Touches:** shared (security, with A; then `.ai/context/architecture.md` too), `.ai/rules/review/security.md`
(owner), CLAUDE.md "Invariants" (owner).

### 0-201. A `ready` item's Touches line is validated only once it is queued

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 7 (ADR-0055, 2026-11-13); was Open. Found by `/plan-backlog` on 2026-11-02 (owner: record it in the
queue PR).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** ci (scripts/factory/_backlog.sh, scripts/factory/check-queue.sh, .github/scripts/test-queue.sh, .github/workflows/factory-guards.yml), root (BACKLOG.md)

**Problem.** PR #578 (`/ready #0-199`) gave #0-199 a Touches line with a parenthesis inside a module's parentheses
(`root (…, .ai/decisions/0048-….md (Status line), …)`). Factory guards passed it: its "Execution queue is consistent"
step (`factory-guards.yml:159`) runs `check-queue.sh`, which checks Touches only for the items the queue lists, and
`main` had no `.ai/plan/queue.md`. The next `/plan-backlog` queued #0-199 and `check-queue.sh` failed: `_backlog.sh`
derives the modules with `gsub("\\([^)]*\\)"; "")` (`:70`), which does not nest, so the first `)` ended the group and
`.ai/decisions/README.md` and `BACKLOG.md)` were read as modules. A `ready` item is picked without a queue too
(`next-item.sh`, by priority), with a wrong module list for its scope measurement. Stage that let it in: `ready`
(the ready-checker drafts Touches, nothing checks them before the PR merges).

**Approach (to decide).** Either check the Touches of every item with an `**Autopilot:**` line in Factory guards
(the same unknown-module rule as `check-queue.sh`, queue or no queue), or forbid nested parentheses in Touches and
say so in `.ai/rules/planning.md`, or make the module split nest-aware; the first is needed in any case.

**Acceptance criteria (draft).**
AC1. Factory guards fails a PR whose `BACKLOG.md` has an item with an `**Autopilot:**` line and an unknown module in
     its `**Touches:**`, whether or not `.ai/plan/queue.md` exists or lists it; a case in `test-queue.sh` (or its own
     test) shows it.
AC2. A Touches line with a parenthesis inside a module's parentheses is either read correctly or refused with an
     error naming the item; a test shows which.

### 0-202. The owner and the bot share one working tree

**Type:** design · **Priority:** Low · **Status:** Open (carried out by migration stage 2, ADR-0055); To consider (owner, 2026-11-02, before the first autopilot
run of the #0-199 queue).
**Autopilot:** human-only · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** root (.devcontainer/devcontainer.json, .ai/decisions/ an ADR), docs (docs/ai-factory.md)
**Stage 2 (#0-238, ADR-0056):** settled for the build VM: the devcontainer there mounts the VM's own clone
(`create.sh`), with no gitignored file of the owner's; it closes with #0-238's AC5, once the autopilot runs only there.

**Problem.** The devcontainer bind-mounts the host's checkout (`devcontainer.json:21`, `workspaceMount …
type=bind` → `/workspace`), so the owner's sessions on the host and the bot's in the container share one `.git`, one
HEAD, one index and one set of files. Only the commit identity (`GIT_AUTHOR_*`/`GIT_COMMITTER_*`, `:33-36`), the `gh`
login and the `~/.claude` and `~/.m2` volumes are the bot's own. What follows today:
- the owner cannot work while the autopilot runs: a `git switch` or an edit on the host moves or dirties the bot's
  branch mid-run; the preflight refuses a dirty tree only at start (`docs/ai-factory.md`, the stop conditions), nothing
  guards the run itself;
- a file in the tree reaches both: `.claude/settings.local.json` would merge into the bot's `dontAsk` session, so the
  preflight refuses to start while it exists (`docs/ai-factory.md:78-80`);
- every gitignored file of the checkout is readable in the container, `docker/.env` and the services'
  `application-local.yml` included (the same reason `ci-local.sh` sends the tree as a tar instead of a mount, #0-166);
  the container's firewall (`init-firewall.sh`) limits where it could go.

**Seen.** Autopilot run 20261102-113931 (#0-199) started while the shared tree was on the owner's `plan/2026-11-02`;
during the run the owner, on the host, switched it to `main` and merged PRs #579 and #580. The run's branch happened to
start from `main` (`eea28f7d`) and nothing broke, but nothing guarded it either.
Again on 2026-11-03 (reflog of the shared tree): run 20261103-121611 (#0-200) ended on `main` at 12:33:28Z; at
12:49:08Z the owner's session on the host created `docs/backlog-factory-run-trace` and began editing `BACKLOG.md`;
at 12:49:41Z HEAD moved back to `main`, with no new entry in `state.json`, and the session's uncommitted edits went
with it, which the session noticed only later. What moved it is not known: no autopilot run of the container is in
its transcripts at that time (its runs that day started 13:33Z and 13:36Z), and a run its preflight refuses does not
run `return-to-main.sh` (`backlog-autopilot.js:432-435` returns before it; only `notStarted()`, after a passed
preflight, does), so a refused run does not explain it either. Nothing was lost this time, but the owner's work in
progress was changed under them, and in the other direction a run could have started with the owner's edits.

**Not this.** ADR-0044 rejected a worktree per `/seed-bugs` run: the workflow's agents read hooks from the session's
own directory, so the session would have to start inside it. This item is about the container's tree as a whole, not
one run's.

**Approach (to consider).** A separate clone for the container (a named volume, or a second host directory, cloned
from `origin` and with no gitignored files of the owner's), with the owner's checkout no longer mounted; or a
`git worktree` of the host's repository as the container's workspace (one object store, separate HEAD and index;
gitignored files stay out, but `.git` is still shared); or keep the shared tree and record the rule ("no work on the
host during a run") with a guard that notices a HEAD move by someone else during a run. To weigh: where the bot's
`application-local.yml` and `docker/.env` then come from (the test gate needs a build, Testcontainers, no services),
how the owner reviews the bot's branch (fetch from `origin`), the `--admin` merge from the host, the clean-`main`
preflight, and the cost of a second Maven/Docker cache.

### 0-204. A run's record keeps no run id, no agent calls and no stage of each commit

**Type:** ci · **Priority:** Low · **Status:** Open (carried out by migration stage 3, ADR-0055); Owner, 2026-11-03 (what the factory keeps of a run, for the audits).
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** ci (.claude/workflows/backlog-autopilot.js, scripts/factory/state.sh, .github/scripts/test-autopilot-workflow.mjs,
.github/scripts/test-factory-state.sh, .claude/agents/shipper.md, .claude/skills/ship-record/), docs (docs/ai-factory.md)

**Problem.** The workflow counts the work agents' calls (`calls`, `backlog-autopilot.js:62,77`) and returns them in
the run's result (`agentCalls`, `:262,700,711`), but `state.sh record` keeps only `t`, `item`, `outcome`, `pr` and
`stage` (`state.sh`, the `record` filters): no run id, no call count, no time per stage, and nothing that ties a commit
to the stage and round that wrote it. `progress.md` has one line per stage, but it is a work file the agents write. So
the pipeline audit (#0-121) cannot say from the record which stage introduced a line, and cost per item is not
measured at all.

Separately, `docs/ai-factory.md:48` tells phase 3 to allow `gh pr merge * --squash --auto`. A squash merge leaves
`main` with one commit per PR, so the branch's commits, their trailers (#0-203's extension) and the per-stage ranges
below no longer exist on `main` (the run's branch is deleted on merge). The repository merges with merge commits
today.

**Approach (to decide at `/ready`).** The workflow keeps, per agent call, `{agent, stage, round, startedAt,
durationMs, headBefore, headAfter}`, and passes the list to the shipper with the review record, which puts it into
the PR body (one more `<details>` block of `ship-record`; `audit-data.sh` already reads PR bodies, so the trace
reaches the audit durably, like the review record). `state.sh record` gains the run id and the call count, plain
values that pass the workflow's `SAFE` pattern (`q()`), which a JSON list would not. How the workflow learns the head
around a call is to decide: the work agents' answers name it (checked against the branch afterwards), or an ops
call per committing stage (one more `factory-ops` call each). Whether the workflow can know its own `wf_<id>` (the
transcripts' directory, #0-205) is to check in the runtime. Phase 3's merge becomes `--merge --auto`.

**Acceptance criteria (draft).**
AC1. A shipped or blocked PR's body holds the run's trace: one row per agent call with agent, stage, round, duration
     and the commits it added; a workflow test with a fake `agent()` shows it for a run with a fix-review round.
AC2. `state.json`'s history entry carries the run id and the agent call count; `test-factory-state.sh` shows both and
     an old entry without them still reads.
AC3. `docs/ai-factory.md`'s phase 3 says `--merge --auto`, with the reason (the branch's commits are the audit's
     evidence).

### 0-205. A run's transcripts expire after 90 days and nothing reads them per agent

**Type:** ci · **Priority:** Low · **Status:** Open (carried out by migration stage 3, ADR-0055); Owner, 2026-11-03 (what each agent touched, for the audits).
**Autopilot:** human-only · **Risk:** medium · **Complexity:** medium · **Depends on:** #0-204 (the run id in the record)
**Touches:** ci (scripts/factory/ a new archive-and-summary script and its test, .claude/workflows/backlog-autopilot.js,
scripts/factory/audit-data.sh, .github/scripts/test-audit-data.sh, .gitignore if the archive is in the workspace),
docs (docs/ai-factory.md, .ai/README.md)

**Problem.** The only full record of what an agent read, edited and ran, and of what a hook refused it, is the
session's transcripts (`~/.claude/projects/-workspace/<session>/subagents/workflows/wf_<id>/`, the agents' `.jsonl`
files and the workflow's `journal.jsonl`) in the container's `~/.claude` volume. Claude Code deletes them after
`cleanupPeriodDays` (90, `.claude/settings.json:75`), and a rebuilt volume loses them sooner. Nothing links a run to
its directory: `audit-data.sh` passes the analysts the transcripts' root only ("may be unreadable"). A hook's refusal
reaches only the refused agent (`_lib.sh` `block()`, exit 2), so how often an agent fights a guard is seen only by
reading transcripts by hand: both #0-199 runs that died on `maxTurns` (2026-11-02, #0-206) were diagnosed that way.

**Approach (to decide; proposed: derive from transcripts, no new recorder).** A factory script, run at
the end of each run, copies the run's `wf_<id>` directory into an archive that the cleanup does not reach, and writes
from it one summary per agent call: turns, tokens (the transcripts' `usage`), model, tools used, paths read and
written, commands (shortened, no file contents) and every refusal with the hook that gave it. `audit-data.sh` includes
the summaries. Rejected: a PostToolUse hook writing an action log during the run — it records again what the
transcripts already hold, sits on every call of the run, and with `onFailure: "block"` a logger that fails would stop
the run; its file would be as writable by the agents as the transcripts are. Reconsider only if the summaries show a
gap. Claude Code's own OpenTelemetry export is out of scope: it needs a way out of the devcontainer's firewall (an ADR
of its own).
To weigh: the archive holds what the agents read (never committed; where it lives with #0-202's shared tree; whether a
later run's agents may read it, a prompt-injection path the audit agents already treat as data); how the run finds
its `wf_<id>` (#0-204); whether each `block()` message names its hook.

**Acceptance criteria (draft).**
AC1. After a run, its transcripts are in the archive under the run id, and a summary per agent call holds turns,
     tokens, tools, paths and refusals; a test on a fixture transcript shows each field, including a refused call.
AC2. No summary holds a file's content or a token-shaped string; the test shows a fixture with both left out.
AC3. `audit-data.sh` puts the summaries of the period's runs into its output; `test-audit-data.sh` shows it, and an
     audit with no archive still runs.

### 0-208. Five route walks hold five copies of `isExempt`

**Type:** tech-debt · **Priority:** Low · **Status:** Open. From the security reviewer's non-blocking finding on PR #587
(#0-198, 2026-11-04).
**Autopilot:** not-ready · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** shared (test-jar?), incident-service, ingestion-service, notification-service, oncall-service,
postmortem-service (src/test: `*/api`), root (.ai/decisions/0048-every-route-is-walked-deny-by-default.md, BACKLOG.md)

**Problem.** `isExempt(String pattern)` (rule 3 of ADR-0048: an exact key, or a `/**` key matching its base and what
lies under it) is the same method, byte for byte, in `IncidentDenyByDefaultTest:503`, `IngestionDenyByDefaultTest:438`,
`NotificationDenyByDefaultTest:533`, `OncallDenyByDefaultTest:388` and `PostmortemDenyByDefaultTest:402` (checked
2026-11-04: the five bodies are identical); auth-service's two walks have their own `isExempt(String, RequestMethod)`.
Nothing keeps the copies in step: a fix to one leaves four services matching their exempt sets the old way, and no test
reports it. The reviewer saw two of the five. The same goes for the rest of the walk (`routes()`, the method
expansion, the positive control): ADR-0048 decision 6 chose one copy per service on purpose, "a shared helper would
need a test-jar of `shared` … it can follow once all five exist", which they now do. A second, smaller point from the
same PR (general, GEN-30): two positive controls (`Ingestion`, `Oncall`) assert `isEqualTo(403)` on top of
`isNotEqualTo(401)`, the other three only the latter; the exact 403 also pins the role rule, so a role change breaks
the control for a reason that is not authentication.

**Approach (to decide).** (a) A test-jar (or `test-fixtures`) of `shared` with the walk and `isExempt`, each service's
test keeping its literal exempt set and its context (a new inter-module test dependency: owner); (b) keep five copies
and add a check that they are equal (a test or a Factory guard comparing the method bodies); (c) leave it, and record in
ADR-0048 why. Whether the positive controls should agree on `isNotEqualTo(401)` alone is part of it.

### 0-210. Twenty-one deny rules of the autopilot settings never match

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 6c (ADR-0055, 2026-11-13); was Open. Seen 2026-11-06 (#0-207's third case): every
`claude --settings .claude/settings.autopilot.json` session prints these warnings at start.
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/settings.autopilot.json, possibly .github/scripts/ for a check), root (BACKLOG.md)

**Problem.** Claude Code 2.1.295 warns that two deny rules can never match: `Bash(gh pr edit *human:*)` and
`Bash(gh pr create *human:*)` mix `*` with the trailing `:*` prefix syntax, so they are matched as a literal prefix.
The settings' `$comment` calls them "a plain-text second line" behind `guard-protected-bash.sh` (`gh_label_unsafe`,
backlog #0-126): the hook still refuses every form (`test-hooks.sh` cases), but the second line does not exist. It
also warns that `Write(./.ai/runs/LOCK)`, `Write(./.ai/runs/state.json)`, `Write(./.ai/STOP)` and
`Write(./.ai/audit/decisions.md)` are not read by file permission checks (only `Edit(path)` rules are, and cover every
file tool); their `Edit(…)` twins are there, so these four are dead lines, not a hole.

**Seen again, wider (2026-11-12, #0-194's spike and AC3).** A `claude -p --settings .claude/settings.autopilot.json`
session in the devcontainer (Claude Code 2.1.295) warned about the two label rules and about **19** `Write(…)` deny
rules, not 4. The other fifteen are the protected paths and build files: `.ai/rules/**`, `.claude/**`, `.github/**`,
`architecture-tests/**`, `AGENTS.md`, `scripts/factory/**`, `.ai/plan/**`, `scripts/factory-admin/**`,
`.devcontainer/**`, `mvnw`, `mvnw.cmd`, `.mvn/**`, `.ruby-version`, `.node-version` and `.git/**`. Each of the 19 has
its `Edit(…)` twin in the same `deny` list (checked with jq against the file), so all of them are dead lines, not a
hole; `.claude/settings.json` has no `Write(…)` deny. The title said six until then; it is 21.

**Acceptance criteria (draft).**
AC1. The two label rules have a form Claude Code matches (its warning names `Bash(gh pr edit *human*)`), checked by a
     refused `gh pr edit 1 --add-label human:agree` in a `dontAsk` session with the hook off, or are removed with the
     `$comment` saying the hook is the only line.
AC2. The 19 `Write(path)` deny rules are removed, each with its `Edit(path)` twin left in place (or the `$comment` says
     why they stay); a Factory guard, or a case of an existing one, fails a `Write(…)` deny rule without its
     `Edit(…)` twin, so that removing the dead line can never leave a hole.
AC3. A session started with the settings prints no permission-rule warning; a Factory guard keeps it so if one can
     (whether Claude Code exposes the check outside a session is to find out).

### 0-211. Two lists of secret paths, and nothing keeps them equal

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 6c (ADR-0055, 2026-11-13); was Open. From the security reviewer's rule gap in review round 1 of #0-207
(2026-11-06).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/hooks/guard-protected-bash.sh, .claude/hooks/test-hooks.sh, .claude/settings.json,
.claude/settings.autopilot.json, possibly .github/scripts/ for a check), root (BACKLOG.md)

**Problem.** The secret files an agent must not reach are named twice: as `Read(…)` deny rules (`settings.json`:
`./docker/.env`, `./docker/secrets/**`, `./.env`, `./.env.*`; `settings.autopilot.json` adds `application-local.y*ml`,
`~/.config/gh/**`, `~/.claude/.credentials.json`, `~/.claude.json`, `~/.ssh/**`, `~/.netrc`, `~/.git-credentials`,
`~/.m2/settings*.xml`) and as the `secrets` regex of `guard-protected-bash.sh`, which stops a Bash command naming one
(a deny rule on Read does not cover `cat` or `cp`). The two have drifted: the regex names `settings-security.xml` but
not `~/.m2/settings.xml`, nor the root `.env`/`.env.*`. Today a Bash copy of `~/.m2/settings.xml` is refused only
because Claude Code refuses a source outside the working directory (#0-207's round 1). The root `.env` is inside it,
yet in review round 2 of #0-207 the same `dontAsk` session refused `cp .ai/work/_template/handoff.md .env
.ai/work/0-999/` and the same with `.env.local` (both files present, nothing copied). Which layer refused them is not
shown (no control run): possibly `settings.json`'s `Read(./.env)`/`Read(./.env.*)` deny applied to a `cp` source, so
the hook's gap is not open today, but it rests on Claude Code, not on the hook. The same shape as FAC-A01: one
control, two lists, no check.

**Acceptance criteria (draft).**
AC1. The regex names every path the Read deny rules of both settings files name, or a comment says why one is left
     out; `test-hooks.sh` has a refused case for each added path.
AC2. A check (Factory guard or `test-hooks.sh`) derives the list from the deny rules and fails when the regex misses
     one, so the next added secret cannot drift.

### 0-212. A factory commit does not say which run and which agent wrote it

**Type:** ci · **Priority:** Low · **Status:** Open (carried out by migration stage 4, ADR-0055); Split from #0-203 (owner, 2026-11-03; split 2026-11-07, when
#0-203 shipped the attribution trailer and the architect's commit form).
**Autopilot:** human-only · **Risk:** medium · **Complexity:** medium · **Depends on:** #0-204 (the run id in the record)
**Touches:** ci (the commit guard of each committing agent and its twin in both settings files, `.claude/hooks/test-hooks.sh`, `.github/scripts/check-hook-entries.rb` if the guard is new, a Factory guards check of the trailers on a factory PR's commits), docs (docs/ai-factory.md).

**Problem.** Every commit of a run is authored by
`lukaszplawiakbot`, whichever of picker, architect, implementer (first round, fix-tests, fix-review), self-check or
shipper wrote it, and the only attribution in it is the trailer the agent writes itself, which proves nothing. So
`git blame` cannot tell the pipeline audit (#0-121) which agent introduced a line, and the `human:introduced-*`
labels (`.ai/rules/audit.md`) are its only source. Proposed: every autopilot commit carries `Factory-Run: <runId>` and `Factory-Agent: <agent>`,
and a hook on `git commit` refuses one whose `Factory-Agent` is not the call's `agent_type` or whose `Factory-Run` is
not the run in `.ai/runs/LOCK` — the two facts a hook can check. The stage and round (`fix-review r2`) are not
trailers: a hook does not know them and the agent would only declare them; the workflow records them with the
commit range of each call (#0-204). `git commit --trailer <key>=<value>` puts a trailer on a one-line command; the
architect's one allowed commit form (`readonly-bash.sh --architect`, #0-203) must then admit these two. The start
commit of a run is not an agent's since #0-209: `scripts/factory/start-item.sh` writes it, with no `Co-Authored-By`
and out of reach of a hook on `git commit` (it runs inside a factory script); it takes `Factory-Run` from its run-id
argument, and whether its `Factory-Agent` is `start-item.sh` or absent (AC2 then exempts it) is this item's to decide.
Not done by this item:
phase 3's `--squash` (`docs/ai-factory.md:48`) would drop the branch's commits and their trailers from `main`'s
history; #0-204 corrects that line.

**Acceptance criteria (draft).**
AC1. Every commit an autopilot run writes carries `Factory-Run` and `Factory-Agent`; a commit whose
     `Factory-Agent` differs from the call's `agent_type`, or whose `Factory-Run` differs from the run in the lock, is
     refused; `test-hooks.sh` cases show both refusals and an allowed commit for each committing agent.
AC2. Factory guards fails a PR from the bot's account with a commit that lacks either trailer.

### 0-213. An exception ends the autopilot and the audit workflows with no outcome

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 4 (ADR-0055, 2026-11-13); was Open. From #0-206 (2026-11-07): the same class of defect, outside its
Touches.
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/workflows/backlog-autopilot.js, .claude/workflows/audit.js,
.claude/workflows/docs-audit.js), ci (.github/scripts/test-autopilot-workflow.mjs), docs (docs/ai-factory.md)

**Problem.** #0-206 made an agent call that throws (agent() ends without its structured answer, e.g. its `maxTurns`
spent) a `null` in `backlog-autopilot.js`'s `as()`, so every agent's failure reaches `stopItem`. Two exceptions still
end a workflow with no outcome:
- in `backlog-autopilot.js`, one of the script's own code between two stops (a field read off an answer the schema
  let through, a helper's error): the run ends with `.ai/runs/LOCK` held, no state, no notification;
- in `audit.js` and `docs-audit.js`, whose `as()` (`audit.js:25`, `docs-audit.js:16`) calls `agent()` bare and whose
  runs have no catch: an analyst that ends without an answer ends the audit with no report and no reason.
`seed-bugs.js` already has the general form: `try { return await measure() } catch (e) { return finish({ outcome:
'FAILED', … }) }` around the whole run (#0-176), with `finish()` that never throws.

**Acceptance criteria (draft).**
AC1. `backlog-autopilot.js`'s run is wrapped like `seed-bugs.js`'s: an exception outside an agent call stops the
     item through `stopItem` (lock released, state recorded with the stage, notified); a workflow test throws from a
     helper and shows it.
AC2. `audit.js` and `docs-audit.js` end with an outcome naming the agent and the reason when an agent call throws; a
     test in `test-autopilot-workflow.mjs` shows it for each.

### 0-214. The agents' command lists are not run through Claude Code's own permission check

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 6c (ADR-0055, 2026-11-13); was Open. From #0-207's AC4 (owner, 2026-11-08: the static check in CI
now, this one later).
**Autopilot:** human-only · **Risk:** low · **Complexity:** medium · **Depends on:** —
**Touches:** factory (scripts/factory-admin/ a new script and its test), docs (docs/ai-factory.md)

**Problem.** `check-agent-commands.rb` (#0-207) matches each listed command against the rules' text and a list of
families Claude Code refuses whatever a rule says; what Claude Code itself decides in `dontAsk` it sees only through
that list, which was learnt from refusals (`cp -r`, #0-207's third case). A new Claude Code release can refuse more,
or a form the list does not name, and nothing shows it before a run spends its turns. Only a session shows it: `claude
-p --settings .claude/settings.autopilot.json` in the devcontainer, on a throwaway clone, asked to run each listed
command. That needs the owner's Claude login and costs tokens, so it is the owner's tool, run after a Claude Code
update, not a CI step (CI holds no Claude credentials, and should not).

**Acceptance criteria (draft).**
AC1. A script in `scripts/factory-admin/` runs every command of the agents' marked lists in a `dontAsk` session with
     `settings.autopilot.json` on a throwaway clone and reports each one run or refused, with the refusal.
AC2. `docs/ai-factory.md` names it as a step after updating Claude Code in the devcontainer.

### 0-217. start-item.sh copies the work template without checking it for symlinks

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 4 (ADR-0055, 2026-11-13); was Open. From the review of #0-209 (round 2), named in ADR-0051.
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (scripts/factory/start-item.sh, .github/scripts/test-start-item.sh)

**Problem.** `start-item.sh` copies `.ai/work/_template/` with `cp -R`, which copies a symlink in the template as a
link; the item's commit then holds a link the next agents read through. The template is on `main` (owner-reviewed),
so this needs a change that slipped through review first, but nothing refuses it.

**Proposed.** Refuse to start when the template holds a symlink (`find .ai/work/_template -type l`), with a test.

### 0-218. No seeded pattern measures security on a weakened forked chain or an IDOR

**Type:** ci · **Priority:** Low · **Status:** Open. From the reviewers' audit 2026-11-11 (R-2026-11-11-03).

**Problem.** Seven of the 8 autopilot PRs of 2026-10-10 to 2026-11-11 changed or tested the security chain and the
route walks (SEC-10/12/14), and review-security approved all of them, yet no seeded pattern plants a weakened forked
chain (SEC-12) or an access by id that checks only that the row exists (SEC-13, IDOR). Its seeded catches cover
SEC-03, 04, 06, 10 and 31 only, so on the class of change the autopilot ships the security reviewer is measured only
by owner `human:agree`.

**Work.** The owner adds to `.ai/audit/benchmark/patterns.md`, defect patterns table:

| Id | Dimension | Rule | Defect to plant |
|---|---|---|---|
| P-25 | security | SEC-12 | in a `SecurityFilterChain` the change declares or changes, end it in `authenticated()` instead of `authenticatedExceptPurposeTokens()`, or drop its `.cors(...)`; never in a chain the change does not touch |
| P-26 | security | SEC-13 | in a read or change by id the change adds or modifies, compare only that the row exists (drop the tenant, team or role comparison) |

**Acceptance criteria.**
AC1. One blind `/seed-bugs` row each for P-25 and P-26 in `results.md`, scanned clean.

### 0-219. performance's seeded results predate the blind panel, and no clean run measures its false alarms

**Type:** ci · **Priority:** Low · **Status:** Open. From the reviewers' audit 2026-11-11 (R-2026-11-11-04).

**Problem.** All of review-performance's seeded evidence is three rows of 2026-10-25 (perf-after-p10, -p11, -p12),
run before #0-177, when the panel's prompt named the seed branch and its base. The 8 live PRs of the period reached
no performance-sensitive path, so these rows are its only measure, and a non-blind row can overstate a result
(sec-after-p04 against sec-p04-blind, #0-187). No clean (`C-`) pattern exists for performance, so its false-alarm
rate is unmeasured.

**Work.** Re-run P-10, P-11 and P-12 through `/seed-bugs` as it is now: `review/<8 hex>` branch, `Revert "<subject>"`
base, `seed-fold.sh`, started from a notification turn, scanned with `scripts/factory-admin/seed-scan.sh` before the
rows land. The owner adds one clean pattern for the Weight rule's exception to `.ai/audit/benchmark/patterns.md`
(e.g. an unpaged read over a set the change's own code bounds, or a `@Scheduled` job that is one bounded statement,
PERF-22) and runs it once, alternating with the defect runs.

**Acceptance criteria.**
AC1. Three blind performance rows in `results.md`, each scanned clean.
AC2. One clean performance row in `clean.md`.

### 0-221. Two audit reports of one day can give the same recommendation id

**Type:** ci · **Priority:** Low · **Status:** Open. From `/apply-audit` of the 2026-11-11 audits (owner, 2026-11-11).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** root (.ai/rules/audit.md), ci (.github/workflows/factory-guards.yml, .github/scripts/)

**Problem.** `.ai/rules/audit.md` ("Format of a recommendation") gives one id form, `R-YYYY-MM-DD-NN`, but an audit
writes a report per target (reviewers and pipeline, #0-121). On 2026-11-11 the pipeline synthesis improvised
`R-2026-11-11-pipeline-NN` so that its ids would not repeat the reviewers' `R-2026-11-11-01`..`04`; nothing asked it
to, and nothing checks that the ids in `.ai/audit/decisions.md` are unique. A second report of the same target on the
same day (an audit re-run after a failure) would also start again at `01`. No script parses the ids (the ledger, the
calibration lines' `(R-…)` and the analysts' `previousRecommendations` hold them as text), so a duplicate is not a
crash but a ledger row the next audit cannot tell apart.

**Decided (owner, 2026-11-11).** Write down the form already in use, no renaming: `R-YYYY-MM-DD-NN` for the
reviewers' report, `R-YYYY-MM-DD-pipeline-NN` for the pipeline report; a second report of the same target on the
same day continues its `NN`. Full symmetry (`R-…-reviewers-NN`) was considered and not taken: it would mix two forms
in the ledger for no gain.

**Acceptance criteria.**
AC1. `.ai/rules/audit.md` "Format of a recommendation" gives both forms and the continued `NN` for a same-day re-run.
AC2. A Factory guards step fails when two rows of `.ai/audit/decisions.md` carry the same id, or an id matches neither
form; its test shows both failures and a valid ledger.

### 0-224. No reviewer is told to read the log pipeline's rules when a change touches `docker/`

**Type:** ci · **Priority:** Low · **Status:** Open. Found 2026-11-12 checking PR #604 (which agents read
`.ai/context/infrastructure.md` "Log pipeline").
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** root (.ai/rules/review/security.md (owner)), ci (scripts/factory/changed-paths.sh, .github/scripts/)

**Problem.** The docker-compose log pipeline has security rules: Loki and Alloy have no authentication, and Grafana
reads every tenant's logs. Grafana is not on `default`, the pipeline sits on the internal `logs` and `docker-api`
networks, Alloy reaches Docker only through `docker-socket-proxy`, labels are only `service`/`container`/`level`
with the MDC ids as structured metadata, and Loki's delete API is off. Until PR #604 those rules were in CLAUDE.md,
which every reviewer has in context. Since then they are in `.ai/context/infrastructure.md` "Log pipeline", behind a
pointer, and no reviewer is told to read that section when a change touches `docker/`:
- `review-k8s` is the only one whose criteria name `infrastructure.md` (`k8s.md:12`, for "CI gotchas"). Its gate
  (`changed-paths.sh:68`, `/review` step 2) matches `k8s/`, a `Dockerfile`, `pom.xml` and `.dockerignore`. It does
  not match `docker/docker-compose.yml`, `docker/alloy/config.alloy` or `docker/loki.yml`.
- `review-security`, `review-general` and `review-architecture` read the context file their criteria name
  (`review-procedure` step 3): `security.md`, `architecture.md` and `project.md`.
- `changed-paths.sh` records `docker` as an area (`:81`) but no rule file is added for it (`:90-92` add one only for migrations, entities and `k8s`).

What still guards them:
- Comments in the changed files themselves, which every reviewer reads (`docker-compose.yml:326`,
  `config.alloy:65` and `:89`, `loki.yml:107`).
- `test-log-collection.sh` in the Docker Compose smoke test, which checks the networks, the published port, the
  labels and the structured metadata. That test is not a required check (#0-2), and nothing tests the delete API.

**Approach (to decide).**
- (A) `security.md`'s opening read list adds `.ai/context/infrastructure.md` "Log pipeline" when the diff touches
  `docker/`. These are security controls: unauthenticated services and every tenant's logs. One sentence in an
  owner file.
- (B) `review-k8s`'s gate also matches `docker/`. Its rules are about manifests, images and POMs, not compose
  networks, so it would run on changes it has no rules for.
- (C) Optional with either: a case in `test-log-collection.sh` that asks Loki's delete endpoint and expects a
  refusal, so the one untested rule gets a check.

(A) is the closest fit; (C) is cheap once #0-2 makes the smoke test required.

**Acceptance criteria (draft).**
AC1. A reviewer whose criteria cover the log pipeline's rules is told to read `.ai/context/infrastructure.md`
     "Log pipeline" when a change touches `docker/`, shown by the rule file's text (and, if the gate changes, a case
     in the test of `changed-paths.sh`).
AC2. If (C) is taken, `test-log-collection.sh` fails when Loki accepts a delete request, shown by running it against
     a Loki with the delete API on.

### 0-225. The autopilot allows the Grep and Glob tools, and no secret rule or hook names them

**Type:** security · **Priority:** Low · **Status:** Blocked — superseded by migration stage 2 and 4 (ADR-0055, 2026-11-13); was Open. From the `/research` of #0-223 (owner, 2026-11-12).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/settings.autopilot.json, .claude/settings.json, possibly .claude/agents/*.md `tools:`,
.claude/hooks/test-hooks.sh), root (BACKLOG.md, README.md "Infrastructure Hardening")
**Stage 2 (#0-238, ADR-0056):** the build VM's clone holds no secret file of the owner's (`docker/.env`, the
`application-local.yml` files); what a task itself writes there is stage 4's (no secret file in the task container).

**Problem.** `settings.autopilot.json` allows `Grep` and `Glob`, and every agent but `factory-ops` and the verifier
lists them in `tools:`. The secret files are denied as `Read(…)` rules only (`./docker/.env`, `./docker/secrets/**`,
`**/application-local.y*ml`, the home files of #0-211), and the only hook on a file tool matches `Read`. In Bash, the
agents' search is `git grep`, whose allow-list of options keeps it to tracked files, so a gitignored secret is never
read (#0-123, `_lib.sh` `git_grep_unsafe`). The Grep tool goes through none of that: whether Claude Code applies the
`Read` deny rules to Grep and Glob, and whether its Grep searches ignored files, is not checked here. Today it does
not matter: no autopilot run has given Grep to an agent with Bash (31 runs, #0-223). A Claude Code version that gives
it back would open the path without a change in this repository; `audit-synthesis`, which has no Bash, gets both
tools now, but it holds no tool that sends data out.

**Proposed, to decide with the item.** (a) `Grep(…)` and `Glob(…)` deny rules next to each `Read(…)` secret rule, in
both settings files, with a `test-hooks.sh`-style check that the lists are equal (the shape of #0-211); or (b) drop
`Grep`/`Glob` from the autopilot's allow list and from the `tools:` of the agents with Bash, so `git grep` is the only
search there (reverses #0-123's "use them only if you actually have them", where that reasoning lives); or (c) first
measure what Claude Code does (a `dontAsk` session, Grep for a token of `docker/.env`, as #0-214 would run). A
change to `settings.autopilot.json` changes its hash: the devcontainer is rebuilt and a new `--settings` session
started (#0-194).

### 0-226. A resumed run records no scope

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 4 (ADR-0055, 2026-11-13); was Open. Split from #0-195's second case (owner, 2026-11-12).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** factory (.claude/workflows/backlog-autopilot.js, possibly scripts/factory/next-item.sh,
.github/scripts/test-autopilot-workflow.mjs), root (BACKLOG.md)

**Problem.** A run started with `branch` (resume) skips `next-item.sh` and the plan, so `record.scope =
scopeOf(next?.modules, plannedModules, lastPaths?.areas)` (`backlog-autopilot.js`) gets no Touches and no plan: PR #576
said "Scope: not-measured — Touches none · plan none" though #0-192 has a Touches line. The audits then miss the item's
predicted reach. `next-item.sh <base> <item>` cannot simply be asked on resume: its own draft PR is a lock, so it
answers "in progress or blocked".

**Proposed, to decide with the item.** Read the item's Touches from the base commit on resume (a mode of
`next-item.sh` that skips the lock check, or `backlog_json` through another script), and say in the record that the plan
was skipped, not that it predicted nothing.

---

### 0-227. A risk-high item's real `NEEDS_HUMAN` ships as a PR instead of stopping

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 6a (ADR-0055, 2026-11-13); was Open. From the review of #0-220 (architecture, round 1, 2026-11-12).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-220
**Touches:** factory (.claude/workflows/backlog-autopilot.js, .github/scripts/test-autopilot-workflow.mjs), docs (docs/ai-factory.md)

**Problem.** `backlog-autopilot.js:815` stops an item on an acceptance `NEEDS_HUMAN` only when it is not risk-high
(`if (acc.verdict === 'NEEDS_HUMAN' && !riskHigh) return stopItem(...)`). The exemption existed because
`.ai/rules/acceptance.md` made every `Risk: high` item `NEEDS_HUMAN`; #0-220 removed that reason, so a `NEEDS_HUMAN`
on a risk-high item now names a real one (an ambiguous criterion, a decision the item does not make, scope creep), and
the item still ships as a PR where a low-risk one stops BLOCKED. Nothing is lost (the owner merges every risk-high PR
and its acceptance JSON holds the reason), but the asymmetry's reason is gone and nothing records why it stays. The
acceptance prompt (`:777`) also still passes `Risk: ${item.risk}`, which acceptance.md now says decides no verdict;
`docs/ai-factory.md:31` describes the exemption ("NEEDS_HUMAN → BLOCKED (risk-high: owner merges)").

**Approach (to decide).** Drop `&& !riskHigh` (a risk-high item with a real reason stops as any other, draft PR with
the reason), or keep it with a comment saying why the owner's merge is enough; either way the prompt stops naming the
Risk, and the docs line follows.

**Acceptance criteria.**
AC1. An acceptance `NEEDS_HUMAN` on a risk-high item is handled as decided, and `test-autopilot-workflow.mjs` shows it
on a risk-high and a low-risk item.
AC2. The acceptance prompt does not name the item's Risk; `docs/ai-factory.md` describes what the workflow does.

---

### 0-228. A BLOCKED draft writes "Scope: not measured." and the audit reads `scope:not`

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 4 (ADR-0055, 2026-11-13); was Open. Found while implementing #0-220 (2026-11-12), on PR #581.
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** ci (scripts/factory/audit-data.sh, .github/scripts/test-audit-data.sh), factory (.claude/agents/shipper.md,
.claude/skills/ship-record/SKILL.md)

**Problem.** The draft PR of an item BLOCKED before any scope was measured says `Scope: not measured.` in prose (#581),
where `ship-record` writes the category, `not-measured`. `audit-data.sh` reads `Scope: ([a-z-]+)`, so it takes `not`,
which is no clean category, and the case carries the signal `scope:not`: noise for the analyst, and a case for a run
that may have no other signal.

**Approach (to decide).** `ship-record`/`shipper.md` write `Scope: not-measured` when the record has no scope (the
category the workflow's `scopeOf` already uses), and `audit-data.sh` gives a scope that is no known category its own
signal (`scope:unreadable`) instead of a fragment of a word.

**Acceptance criteria.**
AC1. A BLOCKED draft with no measured scope records `Scope: not-measured`.
AC2. `test-audit-data.sh` shows a PR body with `Scope: not measured.` and one with an unknown category: neither yields
`scope:not` or a category the scope table (`audit.md`) does not name.

---

### 0-229. ingestion's Redis dedup and rate limits are tested only against mocks

**Type:** tech-debt · **Priority:** Low · **Status:** Open. From the review of the Redis 7 → 8 move (architecture,
2026-11-12).
**Touches:** ingestion-service

**Problem.** ingestion-service keeps its alert deduplication (`DeduplicationService`, `setIfAbsent` with a TTL) and its
bucket4j rate limits (`RateLimitingService`, `AuthFailureRateLimiter`) in Redis, but `DeduplicationServiceTest` and
`RateLimitingServiceTest` mock the Redis template: no test runs them against a real Redis. Only auth-service's
`MfaResetRateLimiterTest` and `PlatformRateLimiterTest` start a Redis (Testcontainers). So a Redis major (8 since
2026-11-12, #0-71) or a bucket4j/Lettuce upgrade that changed `SET … NX EX` or the buckets' Lua scripts would pass
CI for ingestion and show only in the compose smoke test, if a request reached the path there.

**Approach.** A Testcontainers test per Redis-backed class, on the image compose runs (`redis:8-alpine`), as
auth-service's two do: a duplicate within the TTL is refused and accepted after it, and a bucket refuses past its
limit and refills.

**Acceptance criteria.**
AC1. `DeduplicationService` and each bucket4j rate limiter of ingestion-service have a test against a real Redis of
compose's image, showing the behaviour above.

---

### 0-230. Renovate rebases every open PR on every merge: 58% of the Actions minutes

**Type:** ci · **Priority:** Medium · **Status:** Open. From the measurement of the billable Actions minutes
(owner, 2026-11-12), before the repository may go private (a private repository's minutes come from the plan's quota:
2000 a month in Free, 3000 in Team).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low
**Touches:** root (renovate.json, README.md "Dependency Updates — Renovate"), docs (.ai/decisions/0036)

**Problem.** Measured from the Actions API over 18 days (2026-10-26 – 11-12, 992 runs; a job's duration rounded up
to a whole minute, as GitHub bills it): ~8 455 billable minutes, ~14 100 a month. Of them:

| Source | Minutes / 18 days | Share |
|---|---|---|
| 5 open Renovate PRs (243 CI runs + 243 Factory guards runs) | 4 936 | 58% |
| CI + Factory guards on a push to `main` (81 merges) | 1 683 | 20% |
| Every other PR (79 PRs, 120 runs: 1.5 a PR) | 1 720 | 20% |
| Snyk, OWASP, Main guard | 116 | 1% |

`renovate.json` set `rebaseWhen: behind-base-branch`, and `updateNotScheduled` defaults to `true` (Renovate's docs:
"Renovate will perform certain "desirable" updates to _existing_ PRs even when outside of schedule"), so the weekend
`schedule` limited only when a branch is created: every merge to `main` rebased every open Renovate PR, at any hour,
and each rebase ran the full CI (~15 min) and Factory guards (~3 min). The five branches ran 29–57 times each. Their
runs decided nothing: the open ones are majors held by #0-71, which moves a major in compose, the tests and k8s at
once on a branch of its own (Redis 8: #614 superseded Renovate's #194), so a held PR's CI is never the one a merge
rests on.

**Decided (owner, 2026-11-12).**
1. `rebaseWhen: conflicted`: an open PR is rebased only when it conflicts with `main`. Renovate warns against it only
   with its automerge, which this repository does not use (`automerge: false` everywhere). `auto` would resolve to
   the same here (no automerge, no required up-to-date branch), but would silently turn back into
   `behind-base-branch` if either changed. The cost: a Renovate PR's CI can be older than `main`; before merging one,
   the owner ticks its rebase checkbox (or adds the `rebase` label) and waits for the new run, and `main`'s CI checks
   the merge result either way (`strict_required_status_checks_policy: false`, the same as for every other PR).
2. `dependencyDashboardApproval: true` on the major rule: no branch, no PR and no CI for a major until the owner
   ticks it in the Dependency Dashboard issue (on by `config:recommended`), which becomes the list of #0-71's image
   majors still to do. A ticked major of a GitHub Action or a CI tool pin (ADR-0033) comes as an ordinary Renovate PR,
   merged on its own CI, as before. `vulnerabilityAlerts` sets `dependencyDashboardApproval: false` (its default), so
   a security fix within a major is not held; but Renovate's docs do not say whether that block wins over the major
   package rule, nor whether `osvVulnerabilityAlerts`' PRs use it (read 2026-11-12, Renovate 44.236.4). If it does not,
   a CVE whose only fix is a new major waits in the dashboard instead of opening a PR at once. It is still reported by
   Snyk and OWASP Dependency-Check, and such a fix is a major we would move by hand under #0-71 anyway; Acceptance 3
   checks it on the first one.
3. Rejected: `updateNotScheduled: false` alone (still one full CI per open PR every weekend, for runs that decide
   nothing); skipping CI on `renovate/*` branches (a minor or patch PR is merged on its CI).
4. CI's own structure (the 7 small jobs billed as a minute each, the docs-only PRs) is measured again after this
   lands; a new push cancelling a running one is #0-231.

**Acceptance.**
1. `renovate.json` has `rebaseWhen: conflicted`, the major rule `dependencyDashboardApproval: true` and
   `vulnerabilityAlerts` `dependencyDashboardApproval: false`; README "Dependency Updates — Renovate" says what each
   does and how a PR is brought up to date before a merge.
2. After the merge: the next merges to `main` start no CI run on a `renovate/*` branch that does not conflict
   (checked by the owner with `gh run list --branch renovate/<name>` a week later), and the Dependency Dashboard
   issue lists majors as awaiting approval.
3. On the first vulnerability alert whose fix is a major: the owner records here whether Renovate opened its PR at
   once or held it in the dashboard, and README follows.

---

### 0-231. A new push to a pull request does not cancel its running CI

**Type:** ci · **Priority:** Low · **Status:** Open. From the same measurement as #0-230 (2026-11-12).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low
**Touches:** ci (.github/workflows/ci.yml, .github/workflows/factory-guards.yml), root (README.md "CI/CD",
.ai/context/infrastructure.md "CI gotchas")

**Problem.** Neither `ci.yml` nor `factory-guards.yml` declares `concurrency`, so a push to a PR's branch while its
runs are still going leaves them running to the end, billed in full, though their result is already stale. Over
the 18 days of #0-230 (Renovate's branches left out), 33 of 120 CI runs and 32 of 120 Factory guards runs were still
running when the next push came: 442 + 109 billable minutes. What pushed next: in 22 of the 33, `chore: close backlog
#…` from `/ship` (its step 7 needs the PR's number, so it pushes after opening the PR); in 7, the autopilot shipper's
`chore(factory): record PR for backlog #…`; the rest, fixes. The median gap between the two pushes was 0.3 minutes.
Saving: GitHub bills each job rounded up to a whole minute ("GitHub rounds the minutes and partial minutes each job
uses up to the nearest whole minute", docs.github.com, Actions runner pricing), so a run cancelled ~20 s in still costs
a minute for every job already started (about 7 in CI, 1 in Factory guards): about 7 of a CI run's ~14 minutes and 2
of Factory guards' 3 are saved, **~300 minutes in the 18 days, ~500 a month** (not the ~900 first estimated, which
assumed a cancelled run cost nothing).

**Decided (owner, 2026-11-12, after `/research`).** One workflow-level block, the same in both files:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}
  cancel-in-progress: ${{ github.event_name != 'push' }}
```

1. **A push to `main` is never cancelled, neither running nor pending.** `main-guard.yml` acts only on a run whose
   conclusion is `failure`, so a `cancelled` run of `main` would leave it unchecked without a word, and
   `scripts/factory/preflight.sh` reads the newest push run and refuses `completed/cancelled`, stopping the autopilot
   (#0-148). A push therefore takes a group of its own (`run_id`), not only `cancel-in-progress: false`: GitHub
   cancels a *pending* run of the same group whatever that flag says ("By default, any existing `pending` job or
   workflow in the same concurrency group will be canceled", docs.github.com, control workflow concurrency), so a
   shared `main` group would drop the middle of three quick merges. The comment above the block in `ci.yml` says so,
   so that nobody simplifies the group to `github.ref`.
2. **The PR's number, not `github.head_ref`** (the docs' example): a branch name is chosen by whoever opens the PR, a
   fork included, so two PRs whose branches had the same name would cancel each other; the number is GitHub's and
   unique.
3. **`pull_request` and `pull_request_review` share the PR's group in Factory guards.** The newer event always judges
   what holds now (the newest commit, or the owner's approval of it: "Changes that need the owner" can be red on
   `synchronize` and green on the review of the same commit), so the required check is always the newest event's
   finished run, never an older one ending after it.
4. **`github.workflow` in the group** keeps CI and Factory guards apart: one never cancels the other.
5. **Risk, accepted (low).** On a public repository anyone can submit a review, so a series of reviews could keep
   cancelling Factory guards on a PR. The last run always finishes, and every review already starts a run today
   (`pull_request_review` was a trigger before this change); recorded in the comment above the block in
   `factory-guards.yml`.
6. Rejected: job-level `concurrency` (eight blocks for no exception any job needs); `queue: max` (it cannot be combined
   with `cancel-in-progress: true`, and a push's own group already keeps every push run); making `/ship` and the
   shipper push once (a draft PR with CI skipped until `ready_for_review`: new triggers and an `if:` on every job, a
   skipped job counts as a passed required check, BLOCKED drafts would lose CI, and `.claude/` changes, all to save the
   ~7 minutes a cancelled run still costs).

**Acceptance.**
1. A second push to a PR cancels the first push's CI and Factory guards runs; the newest push's runs finish and
   are the required checks of the PR (`gh run list --branch <branch>`: the first `cancelled`, the second `success`).
2. Two quick merges to `main` both finish their CI (neither cancelled), and `main-guard.yml` reads each.
3. Lint Workflows (actionlint, zizmor) passes on both workflows.
4. The comment above each block says why a push takes its own group, and `factory-guards.yml`'s names the accepted
   risk of a series of reviews.

---

### 0-232. No check keeps the concurrency block of the pull request workflows

**Type:** ci · **Priority:** Low · **Status:** Open. From the architecture review of #0-231 (2026-11-13).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-231
**Touches:** ci (.github/scripts, .github/workflows/ci.yml lint-workflows)

**Problem.** #0-231 put the same workflow-level block in `ci.yml` and `factory-guards.yml`
(`group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.run_id }}`, `cancel-in-progress:
${{ github.event_name != 'push' }}`), and `.ai/context/infrastructure.md` "CI gotchas" says a new workflow that runs
on `pull_request` takes it too. Nothing checks either. A copy "simplified" to `github.ref` would put every push to
`main` in one group, where GitHub cancels a pending run whatever `cancel-in-progress` says, so the middle of three
quick merges would end `cancelled`: main-guard (which acts on `failure` only) would not see it, and preflight would
stop the autopilot (#0-148). A new `pull_request` workflow without the block would only cost minutes. Only review
catches either today.

**Approach.** A Ruby check in lint-workflows, like `check-runtime-setup.rb` (its own cases first): every workflow
under `.github/workflows/` whose `on:` has `pull_request` or `pull_request_review` declares exactly that block at the
workflow level, and no job-level `concurrency` overrides it; a workflow that must differ names its reason in a marker
comment the check reads.

**Acceptance criteria.**
AC1. Lint Workflows fails on a `pull_request` workflow without the block, with a group that does not end in
`github.run_id` off a pull request, or with `cancel-in-progress` true on a push, and passes on today's two workflows;
each case is a test of the check.

---

### 0-234. A refused second factory-ops call leaves no record the audit reads

**Type:** ci · **Priority:** Low · **Status:** Blocked — superseded by migration stage 4 (ADR-0055, 2026-11-13); was Open. From the architecture review (FAC-A03) of #0-169 (2026-11-13).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-169
**Touches:** factory (.claude/hooks/factory-ops-bash.sh, .claude/hooks/test-hooks.sh, scripts/factory/audit-data.sh,
.claude/agents/audit-pipeline.md)

**Problem.** Since #0-169 the hook refuses every factory-ops call after the run's first one. A refusal is the signal
that a script's output steered the agent (or that it retried), but it is written only to the hook's stderr in the
agent's transcript: the PR, the run's state and the pipeline audit cannot count it.

**Approach.** On that refusal, the hook appends one line (time, `agent_id`, the refused command's script name, never
its arguments) to a file under `.ai/runs/`; `audit-data.sh` counts the lines of the audited period, and the pipeline
analyst reads the count as a case.

**Acceptance criteria.**
AC1. A refused second call adds one line to the record and an allowed call adds none, shown by test cases; the
audit's data lists the count of the period.

---

### 0-236. The factory's runtime state lives in the working tree the agents' git commands act on

**Type:** security · **Priority:** Medium · **Status:** Blocked — superseded by migration stage 4 (ADR-0055, 2026-11-13); was Open. From review round 2 of #0-235 (owner, 2026-11-13).
**Autopilot:** human-only · **Risk:** high · **Complexity:** high · **Depends on:** —
**Touches:** factory (scripts/factory/ (state.sh, preflight.sh, seed-branch.sh, return-to-main.sh, _common.sh and their
tests), .claude/hooks/ (_lib.sh `base_ref`/`run_branch`/`seed_record`, guard-git-push.sh, factory-ops-bash.sh,
guard-protected-bash.sh, test-hooks.sh), .claude/settings.autopilot.json, .devcontainer/), root (.ai/rules/protected-paths.md
(owner), .ai/decisions/ (ADR-0034, 0044, 0047, 0052, 0053, 0054 and a new one), .gitignore), docs (README.md
"Infrastructure Hardening", docs/ai-factory.md)

**Problem.** What the factory trusts during a run, `.ai/runs/LOCK` (its base commit and branch), `.ai/runs/state.json`
(the breaker's counts), `.ai/runs/ops-calls/` (one call per factory-ops run, ADR-0053), `.ai/runs/SEED` and `.ai/STOP`,
lives in the working tree, ignored by `.gitignore`. Every allowed git command acts on that tree, so an agent reaches the
state without naming it (#0-235's two review rounds, each form checked): `git add -f .ai/runs` then `git rm -r -f`
deletes it; an agent that edits `.gitignore` (not protected) makes a plain `git add .ai/runs` stage it; `git mv .//.ai`
moves it; `git mv -f f .ai/runs//LOCK` overwrites the lock with a base the agent chose; `git switch` overwrites it from
a commit that tracks it. `git_runtime_unsafe` refuses the plain forms, a text heuristic that each round of review found
another way past (and `git log --output=.ai/runs//LOCK` forged the lock until the shell guard resolved `//`, round 3).
Round 4 named one more: `git log --format=… --output .ai/run?/LOCK` (git takes `--output <file>` as two words, checked)
names no protected path as text, and bash expands the glob to the lock; it is kept out only if Claude Code in `dontAsk`
refuses an unquoted glob under `Bash(git log *)`, as `check-agent-commands.rb` models it and as it models a path through
`..`, unmeasured (#0-214). With the state out of the working tree no glob of an allowed command reaches it. Without the lock `base_ref()` compares against a ref, the breaker's counts reset and a factory-ops
run gets a second call, with nothing in the PR's diff.

**Approach, to decide with the item.** Move the state out of the working tree, to a directory no allowed command can
name: Claude Code refuses an absolute or `~` path in `dontAsk` (the families of `check-agent-commands.rb`), git acts on
the working tree only, and the file tools' `guard-write-in-repo.sh` keeps writes inside the repository. Candidates: a
directory beside `/workspace` in the devcontainer (`/var/lib/factory/<repo>/`, owned by the same user) or
`$XDG_STATE_HOME/incident-platform/`; the scripts and hooks find it through one variable set by the devcontainer and
`preflight.sh` refuses a run without it. Then git's commands return to `SAFE_PREFIXES`, `git_runtime_unsafe` can go
(or stay a second line), and the runtime list of `protected-paths.md` names the new place. Code run through `./mvnw`
reaches it still (#0-116; the sandbox's `denyWrite`, #0-116's "Also", would bind it). Related: #0-202 (one working tree
for the owner and the bot).

**Acceptance criteria.**
AC1. The lock, the run state, the factory-ops marks, the seed record and the stop switch live outside the working tree,
found through one setting; a run without it stops at its preflight; shown by the factory scripts' and hooks' tests.
AC2. git's `add`, `rm`, `mv`, `switch` and `checkout -b` are `SAFE_PREFIXES` again with a reason that holds, and
`test-hooks.sh` shows that none of #0-235's forms reaches the state.
AC3. README "Infrastructure Hardening", ADR-0054 and `protected-paths.md` (owner) describe where the state lives and
what still reaches it (`./mvnw`, #0-116).

---

### 0-238. Migration stage 2: a build VM, provisioned as code, runs today's devcontainer

**Type:** ci · **Priority:** High · **Status:** In progress. Stage 2 of ADR-0055 (owner, 2026-11-13); its first step is a
spike of UTM, the owner's VM tool. Spike done 2026-11-13 (UTM failed S1, Lima passed S1–S3, ADR-0056); AC1–AC4 and
AC6 in the PR of `feat/0-238-build-vm`; AC5 after it is merged and the owner has logged in inside the VM.
**Autopilot:** human-only · **Risk:** high · **Complexity:** high · **Depends on:** #0-237
**Touches:** factory (the VM's provisioning and scripts, proposed under `scripts/factory-admin/build-vm/`, an owner-only
path that moves to the `factory` repository in stage 4; `.devcontainer/` only if the VM needs it), root
(.ai/decisions/ (a new ADR: the VM tool and the VM's layout), BACKLOG.md), docs (docs/ai-factory.md, README.md
"Infrastructure Hardening": where the autopilot runs and what isolates it)

**Problem.** The factory runs as a devcontainer on the owner's Mac. Three known gaps come from that place, not from the
factory's logic:
- **#0-116:** code an agent runs reaches the host's Docker, so a test can leave the devcontainer's firewall and read
  or start anything Docker on the Mac can;
- **#0-202:** the container bind-mounts the owner's checkout, so the owner and the bot share one `.git`, HEAD, index and
  every gitignored file (`docker/.env`, the `application-local.yml` files);
- **#0-225, the part frozen for this stage:** a secret file in that tree is one file tool away from an agent.
ADR-0055 moves the factory off the Mac in stages. Stage 2 is the first: the same devcontainer, unchanged, inside a VM
that holds only what the factory needs, created from code that a cloud VM can later read unchanged (stage C).

**Approach.**
1. **Spike: UTM** (UTM 4.7.4 on the owner's M1 Pro, 32 GB). `utmctl` has `start`, `stop`, `clone`, `delete`, `exec`
   and `ip-address`, but no `create`. Try, in this order, to create the VM from a script with no click in UTM's window:
   (a) AppleScript, if UTM's scripting creates a VM with a disk and a cloud-init seed; (b) `utmctl clone` of a base VM
   holding only Ubuntu's cloud image, with the seed attached by the script. The criteria, fixed now:
   - S1. The VM is created, and recreated from nothing, by one script in the repository, with no step in the GUI.
   - S2. Its contents come from one cloud-init `user-data` file (NoCloud seed, Ubuntu cloud image) that a cloud VM
     could read unchanged: no UTM-specific step inside the guest. (Reworded by ADR-0056: one provision script, which
     Lima runs as a provision and a cloud VM takes as its user-data; Lima reads no raw user-data.)
   - S3. In it, today's devcontainer starts (`devcontainer up`), its firewall comes up, and a test gate with
     Testcontainers passes (`./mvnw verify` of one module with a repository test).
   If S1 fails, the tool is Lima (a YAML file, `limactl create/start/delete`, the same cloud image and
   Virtualization.framework), checked against S1–S3 the same way. The ADR records the tool, the criteria and what the
   spike showed.
2. **The VM**: Ubuntu cloud image; `user-data` (a provision script, ADR-0056) installs Docker Engine (in the VM, not Docker Desktop), git, the
   devcontainer CLI and its runtime; the repository is cloned from `origin` inside the VM, a tree of its own with no
   gitignored file of the owner's (#0-202: the owner's checkout is no longer mounted); the bot's `gh` login and
   Claude Code's login are entered once into the VM's volumes, as today's devcontainer documents. Resources sized
   for the test gate (around 12–16 GB, `devcontainer.json`'s `hostRequirements` asks 16).
3. **The autopilot starts there**, the owner's sessions stay on the Mac. How Claude Code authenticates unattended stays
   open (ADR-0055 "Consequences"): in this stage the owner logs in interactively, as today, and starts each run.
4. **Exit (ADR-0055):** 3 autopilot items run on the VM with no environment problem. **Rollback:** the devcontainer on
   the Mac, unchanged, as it is today.

**Not this item.** The dispatcher and builder-app (stage 4), metrics (stage 3), the review VM (stage 5), the cloud
(stage C), a Docker API proxy or a firewall outside the container (#0-116's own options, decided with stage 4 and C).
What stage 2 changes for #0-116 is where Docker's root reaches: the VM, which holds no owner file, instead of the Mac;
#0-116 stays open until a boundary holds the code an agent runs. Sysbox in the build VM, which ADR-0055 leaves to its
stage, is decided with that boundary, not here: it is one of the ways to run the test gate's Docker without root over
the container (beside #0-116's Docker API proxy), and in stage 2 Docker runs on the VM itself.

AC1. The spike's result is in a new ADR: the VM tool, S1–S3 each passed or failed with what was run, and the reason
for the choice.
AC2. One script in the repository creates the build VM from nothing and another deletes it; the VM's contents come only
from its `user-data` file (a provision script, ADR-0056) and that script (S1, S2), and the steps the owner does by hand (logins, the bot's token) are
listed in `docs/ai-factory.md`.
AC3. The repository inside the VM is a clone of its own: no mount of the owner's checkout, no gitignored file of the
owner's (#0-202's concern, checked in the VM).
AC4. In the VM the devcontainer starts with its firewall and a test gate with Testcontainers passes (S3).
AC5. Three autopilot items run on the VM with no environment problem (ADR-0055's exit), each named here with its run id.
AC6. README "Infrastructure Hardening" and `docs/ai-factory.md` say where the autopilot runs and what isolates it;
#0-202 and #0-225 point at what this stage settled for them, and #0-116 at what it did not.

**Found by the spike.** The devcontainer image had no `unzip`, so in any fresh environment `./mvnw` downloaded
Maven's `.tar.gz` and checked it against the `.zip`'s `distributionSha256Sum`, and failed; fixed in
`.devcontainer/Dockerfile` with this item. S2 is reworded in ADR-0056: Lima takes no raw user-data, so the VM's
contents come from one script (`provision.sh`) that a cloud VM takes unchanged as its user-data.

### 0-239. The build VM's scripts have no repeatable test

**Type:** ci · **Priority:** Low · **Status:** Open. From review round 1 of #0-238 (general, finding 2; owner, 2026-11-14).
**Autopilot:** human-only · **Risk:** medium · **Complexity:** medium · **Depends on:** #0-238
**Touches:** factory (scripts/factory-admin/build-vm/, .github/scripts/ a new test and its CI step, both owner-only
paths), docs (docs/ai-factory.md "Build VM")

**Problem.** `scripts/factory-admin/build-vm/` (#0-238, ADR-0056) holds the behaviour the build VM's isolation rests
on, and nothing tests it but the runs recorded in ADR-0056: `create.sh` refusing an existing instance and a Node pin
that differs from `.node-version`, filling `@PROVISION_SH@`, and deleting the VM when Lima reports a mount, agent
forwarding or a port forward that is not ignored, the guest shows a host file system or an agent socket, or a check
cannot answer; `delete.sh` treating a missing instance as success; `provision.sh` changing nothing on its second
run; `verify-pins.sh` refusing a wrong digest, a wrong signer, a missing line or a declared dependency. An edit that
breaks one of them is seen only when the owner next creates a VM, or never, for the isolation checks, which pass
silently while Lima adds nothing. And `provision.sh`'s `NODE_VERSION` is a copy of `.node-version` that only
`create.sh` compares: Renovate can bump `.node-version` with CI green, and the next `create.sh` refuses (review round 2
of #0-238, architecture). ADR-0057 adds more of the same kind: `provision.sh`'s rootless setup and egress chain (fail
closed, no duplicate rule on a reboot), `create.sh`'s boundary checks, and `verify-pins.sh`'s Docker key check (the allow-list subset
check has its own test, `test-check-allowlists.sh`). And the filtered uid range (`1000-4294967294`, its floor 1000) is
written out in `provision.sh` (the chain, the subordinate-range check) and `create.sh` (three checks): a change to one
alone fails only at the next `create.sh` (review round 5 of #0-116, architecture).

**Approach.** The repository's pattern for a script that calls tools it cannot run in CI (`test-seed-scan.sh`,
`test-owner-login.sh`): a test under `.github/scripts/` that puts fake `limactl`, `docker` and `curl` first on the
`PATH`, each answering from a fixture and recording its calls, and runs the real script against them, one case per
behaviour above, each with its negative. `provision.sh` is tested for idempotence in an `ubuntu:24.04` container
with its downloads served from fixtures. Run in CI's Factory guards or Lint Workflows job, wherever the other
`factory-admin` tests run. Stage 4 moves these scripts to the `factory` repository: if this item is not done by then,
it moves with them.

AC1. A test runs `create.sh` and `delete.sh` against a fake `limactl` and covers each behaviour named above, with
the negative of each (a mount reported leads to `limactl delete` and exit 1).
AC2. A test runs `verify-pins.sh`'s checks on fixtures: a good set passes, a changed digest, a sum missing from a
signed file and a signature by another key each fail.
AC3. `provision.sh` run twice in a container changes nothing the second time (no download, no install).
AC4. The tests run in CI on every PR that touches `scripts/factory-admin/build-vm/`.
AC5. CI fails a PR on which `provision.sh`'s `NODE_VERSION` and `.node-version` differ (a Renovate bump of
`.node-version` then shows the pin to change in the same PR).

### 0-242. The build VM's listener check runs only when the VM is created

**Type:** security · **Priority:** Low · **Status:** Open. From review round 4 of #0-116 (security, finding 2; owner, 2026-11-14).
**Autopilot:** human-only · **Risk:** medium · **Complexity:** low · **Depends on:** #0-116
**Touches:** factory (scripts/factory-admin/build-vm/provision.sh and create.sh, owner-only), root (.ai/decisions/
ADR-0057 amended), docs (docs/ai-factory.md "Build VM")

**Problem.** `FACTORY-EGRESS` (ADR-0057) lets every uid from 1000 up reach the VM's own address on the ephemeral
ports, meant for the ports rootless Docker publishes there. `create.sh` refuses a VM where any other process listens
in that range on a non-loopback address, but it checks only when the VM is created and after its one reboot. A root
or system-uid service that starts listening there later (a package, a debugging server) is reachable by code a test
runs, and nothing notices until the VM is recreated.

**Approach.** Repeat the check where the chain is built: `factory-egress.sh` (every boot and every 30-minute refresh)
or `provision.sh` (every boot). On a stranger, fail closed the way a missing domain does (the egress unit fails, so
`factory`'s session and its Docker do not start) and log the listener; or narrow the loopback rule to the ports
rootlesskit itself publishes. Decide in an ADR-0057 amendment, tested on `factory-build` with a root `nc -l` on an
ephemeral port.

AC1. A root process listening on the VM's address in the ephemeral range, started after creation, is found at the
next boot or refresh, and `factory` cannot reach it from then on.
AC2. The behaviour and its availability cost are in ADR-0057 and `docs/ai-factory.md` "Build VM".

### 0-243. Two parsers read the devcontainer's allow-list

**Type:** ci · **Priority:** Low · **Status:** Open. From review round 4 of #0-116 (architecture, ARC-02; owner, 2026-11-14).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-116
**Touches:** ci (.github/scripts/check-web-access.sh and its test, owner-only), factory
(scripts/factory-admin/build-vm/check-allowlists.sh and its test, owner-only)

**Problem.** `.devcontainer/init-firewall.sh`'s `ALLOWED_DOMAINS` is read by `.github/scripts/check-web-access.sh`
(a list from column 0, no comment stripping, ended by a line starting with `)`) and by
`scripts/factory-admin/build-vm/check-allowlists.sh` (indent allowed, `#` comments stripped, a one-line list read).
A change of the list's format that one accepts and the other does not fails CI with a confusing message, or, worse,
makes one of them read fewer hosts than the file holds. Both fail closed on an empty list, so it is not a gap today.

**Approach.** One parser, a sourced function or a small script both call (`.github/scripts/` is owner-only and so is
`scripts/factory-admin/`; stage 4 of ADR-0055 moves the latter, so the shared one lives where both can reach it then),
with the stricter grammar of the two and its own fixture cases (indent, comment with parentheses, one-line list).

AC1. Both checks read `ALLOWED_DOMAINS` through the same code.
AC2. A test covers the grammar's cases, and both checks still pass on the repository's lists.

### 0-244. No review rule covers the build VM's own allow-list

**Type:** security · **Priority:** Low · **Status:** Open. From review round 4 of #0-116 (security, rule gap; owner, 2026-11-14).
**Autopilot:** human-only · **Risk:** low · **Complexity:** low · **Depends on:** #0-116
**Touches:** factory (.ai/rules/review/factory.md, a human-owned path)

**Problem.** FAC-S02 (`.ai/rules/review/factory.md`) has the reviewers check each host opened in `init-firewall.sh`
and the WebFetch allow-list for shared front ends and services that accept data. The build VM has a second egress
list of its own, `VM_ONLY_DOMAINS` in `provision.sh` (ADR-0057), which binds everything code a test runs can send, and
no rule names it: review round 4 of #0-116 found its push-capable registries (`registry-1.docker.io`, `ghcr.io`) and
`downloads.claude.ai`'s shared front end unnamed in the ADR only because a reviewer looked beyond the rule.

**Approach.** Extend FAC-S02 to every egress allow-list of the factory (the devcontainer's, the WebFetch one, the
build VM's `VM_ONLY_DOMAINS`), each entry reviewed for a shared front end and for a service that takes a push or an
upload with credentials of the sender's own, and named where its list's ADR lists what is left open.

Review round 5 of #0-116 found two neighbouring gaps to settle in the same change: no FAC-S rule names a firewall
other than the devcontainer's (`FACTORY-EGRESS` in the build VM), and FAC-A01 allows a copied list only where the last
line of defence must not parse the original, not where its consumer has no repository at run time (the VM's
`provision.sh`, ADR-0056 S2), which is why the build VM's copy exists.

AC1. FAC-S02 names `VM_ONLY_DOMAINS` (or every egress allow-list of the factory) and both kinds of host to look for.
AC2. FAC-S02 (or a new rule) covers every firewall of the factory, the build VM's `FACTORY-EGRESS` among them.
AC3. FAC-A01 names a copy kept because its consumer has no repository at run time, with the check it then needs.

### 0-245. Validation errors do not redact `apiKey` and `privateKey` fields

**Type:** bug · **Priority:** Medium · **Status:** Open. Found in `/ready #0-58` (2026-11-14).

**Problem.** `GlobalExceptionHandler` (`shared/exception`) replaces the rejected value of a sensitive field with
`[REDACTED]` in a 400 `VALIDATION_FAILED` body. `isSensitiveField` lower-cases the field name and checks it against
`SENSITIVE_FIELD_NAMES` with `contains`, but two of the set's entries are mixed-case, `apiKey` and `privateKey`, and a
lower-cased name never contains them. So a request field named `apiKey`, `privateKey` or `userApiKey` (anything not
also holding `token`, `secret`, `password`, `api_key`, `authorization` or `credential`) is echoed back in the error
body with its rejected value. A key's value is what the set exists to keep out of answers. `shared`, so every service.

**Approach.** Lower-case the set's entries (or compare case-insensitively), and test every entry, mixed-case names
among them. Check the services' request DTOs for other sensitive field names the set misses.

**Acceptance criteria.**
AC1. A field error on `apiKey`, `privateKey` or `userApiKey` answers `[REDACTED]` as its rejected value; a test in
`shared` covers every entry of the set in more than one case form.
AC2. The fields of the services' request DTOs that hold a secret are all matched, or the item names why one is not.

### 0-246. Service classes below 60% coverage, found with #0-57

**Type:** tech-debt · **Priority:** Low · **Status:** Open. Moved out of #0-58 in its `/ready` (2026-11-14).

**Problem.** Measured with #0-57 (instruction coverage), not tenant-critical: auth-service `IntegrationService`,
`TenantSettingsService`, `TenantSettings`, `TeamMember`, `Integration`; incident-service `IncidentWebSocketPublisher`,
`IncidentWebSocketController`, `IncidentEventOutboxPersistenceService`; notification-service `SlackActionService`,
`SlackMessageTs`; postmortem-service `GeminiClientImpl`. The numbers are from #0-57's time and not measured since.

**Approach.** Pick them up when they are next changed (CI's changed-lines gate asks for it). If an item is wanted for
them, measure again first and split by service: one PR per service, none of them a guard.

**Also, a stale comment (found in the `/review` of `/ready #0-25`, 2026-11-14).** auth-service's `SlackWorkspace`
Javadoc (`domain/SlackWorkspace.java:36-38`) says "backlog #0-25 exists only because `NotificationQueueEntry` skipped
[`@Version`] on a mutable entity". #0-25 decided state-guarded conditional UPDATEs instead, not `@Version`: when
auth-service's `SlackWorkspace` is next changed, the comment should say it carries `@Version` as a row several places
change over time, and point to the criterion in `.ai/context/architecture.md` (#0-25 AC5). The same words in
`V17__create_slack_workspaces.sql` stay: a migration on `main` is never edited.

