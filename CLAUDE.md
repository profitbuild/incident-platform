# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

<!-- agent-editable:start commands — the implementer may correct this block when a command changes; everything outside agent-editable blocks is human-owned (CODEOWNERS) -->

```bash
# The whole docker-compose stack: infrastructure, monitoring, the log pipeline (Loki, Alloy, a Docker socket proxy)
# and the services — needs docker/.env with the three passwords (see below). It builds the jars first
# (`make build`): the images only package <service>/target/*.jar and compile nothing (backlog #0-141, ADR-0030)
make dev-up                 # start        make dev-down   # stop
make dev-reset              # stop + wipe volumes (clean DB)

# Build / test
./mvnw clean install -DskipTests        # full build; required after changing `shared`
./mvnw test -pl incident-service        # one module
./mvnw test -pl incident-service -am -Dtest=IncidentFsmTest    # one class (-am: `shared` from the branch, not ~/.m2, backlog #0-222)
./mvnw test -pl incident-service -am -Dtest=IncidentFsmTest#methodName
./mvnw verify -pl shared,service-parent,auth-service,ingestion-service,incident-service,notification-service,escalation-service,postmortem-service,oncall-service
                                        # what CI runs (tests + JaCoCo)

# Run a service locally (needs `make dev-up` and application-local.yml first)
./mvnw spring-boot:run -pl incident-service -Dspring-boot.run.profiles=local
make run-incident           # same thing; run-ingestion / run-escalation / run-notification / run-postmortem also exist
                            # (no run-auth or run-oncall target — use ./mvnw spring-boot:run -pl <service> ...)

# Validate k8s manifests the way CI does: the Kubernetes version and the schemas' commit are read from the
# validate-k8s-manifests job's `env` in ci.yml (backlog #0-76; without them kubeconform validates against
# the newest Kubernetes, from a moving branch); CI renders with kubectl at that same version
kubectl kustomize k8s/overlays/dev | kubeconform -strict -summary \
  -kubernetes-version "$(sed -n 's/^ *KUBERNETES_VERSION: *//p' .github/workflows/ci.yml)" \
  -schema-location "$(sed -n 's/^ *KUBECONFORM_SCHEMA_LOCATION: *//p' .github/workflows/ci.yml)" -

# CI's Lint Workflows and Factory guards jobs on the working tree, in Docker (backlog #0-166): the workflows' own steps,
# on the Ruby of .ruby-version, the linters at ci.yml's pins (x86_64, run through emulation on an arm64 Mac), the rest native; one line per step, every
# step runs after a failure; --job lint-workflows|factory-guards, --step <text> (repeatable), --rebuild. The steps that
# need a GitHub token (check-pinned-tools.sh, repository-settings.rb check) are skipped: run them as below
.github/scripts/ci-local.sh
# Lint the workflows and scripts the way CI's lint-workflows job does (backlog #0-146, #0-147, #0-149): it matches CI
# only with the actionlint, shellcheck and zizmor versions that job pins; the first line prints them next to the ones on your PATH
grep -E '^ *(ACTIONLINT|SHELLCHECK|ZIZMOR)_VERSION:' .github/workflows/ci.yml; actionlint -version | head -1; shellcheck --version | sed -n 2p; zizmor --version
actionlint -shellcheck="$(command -v shellcheck)"; zizmor --offline --persona regular .
# shellcheck of every tracked .sh file and the composite actions' steps (new files count once `git add -N`), and no download
# outside install-pinned-tool.sh; a meant finding is disabled at its line with its reason, never by a .shellcheckrc;
# and every step that runs Ruby or Node comes after .github/actions/setup-ruby or setup-node, CI's pinned versions (backlog #0-166,
# ADR-0040; #0-163, ADR-0043);
# the .rb checks need the Ruby of .ruby-version on the host (rbenv/asdf/chruby read it; the macOS system Ruby is not supported)
ruby .github/scripts/check-shell.rb "$(command -v shellcheck)"; ruby .github/scripts/check-downloads.rb; ruby .github/scripts/check-runtime-setup.rb
# profitbuild/factory's copies of this repository's pins, scripts and denies against a clone of it (backlog #0-268,
# ADR-0061): as a push, so differences are warnings; CI fails a pull request only on a difference it brings
.github/scripts/test-check-factory-copies.sh; d=$(mktemp -d) && git clone -q --depth 1 https://github.com/profitbuild/factory.git "$d" && ruby .github/scripts/check-factory-copies.rb "$d"
# The autopilot workflow's logic (backlog #0-163): its helpers and whole runs against a fake agent(), on the Node of
# .node-version (ADR-0043; Node's built-in modules only, no npm)
node .github/scripts/test-autopilot-workflow.mjs
# Secrets in the commits a branch adds, the way CI's secret-scan job does (backlog #0-109, ADR-0036): betterleaks at the
# BETTERLEAKS_VERSION in ci.yml; a line that holds no secret takes `gitleaks:allow` and its reason
.github/scripts/secret-scan.sh "$(command -v betterleaks)" "$(git merge-base origin/main HEAD)" HEAD
# Every CI tool pin (`# renovate:` + *_VERSION + *_SHA256) against its publisher (ADR-0033); needs gh and jq, and gpg for Snyk's
.github/scripts/check-pinned-tools.sh
# GitHub's ruleset of main, environments, repository settings, admins and secrets against .github/repository-settings/,
# and every secret a job reads inside an environment that holds it (backlog #0-113, #0-154, ADR-0034, ADR-0035);
# with the owner's token it also compares what CI cannot see; `plan`, then `apply`, after changing a file (the owner's own
# commands: sessions are denied them)
ruby .github/scripts/repository-settings.rb check
```

`make test-unit` (`-Dgroups="unit"`) is in the Makefile but no test carries a JUnit `unit` tag — it runs nothing. Use `./mvnw test`.
<!-- agent-editable:end commands -->

### Local run prerequisite

Every service needs `src/main/resources/application-local.yml` (gitignored, never committed). At minimum `jwt.secret` (≥64 chars — services refuse to start without it). auth-service also needs `mfa.encryption-key` and `slack.encryption-key` (two separate 32-byte keys), postmortem-service `gemini.api-key`, incident-service `websocket.allowed-origins`. Full templates in README "Step 2". Use ASCII hyphens only in these files — em dashes break Spring Boot's YAML loading.

`make dev-up` (and every `docker compose` command) also needs `docker/.env`: `cp docker/.env.example docker/.env`. `DB_PASSWORD` and `POSTGRES_ADMIN_PASSWORD` are required — compose refuses to start without them (backlog #0-78) — and so is `GRAFANA_ADMIN_PASSWORD`, empty in the template on purpose: Grafana reads every tenant's logs, listens on `127.0.0.1` only, and its password applies to a new `grafana_data` volume only (#0-94 step 2). A service run with `spring-boot:run` doesn't read that file: the six services with a database need `spring.datasource.password` in `application-local.yml` (or an exported `DB_PASSWORD`) — `application.yml` has no default (backlog #0-66), and a missing one shows up as `password authentication failed`, not as a placeholder error.

## Architecture

Maven multi-module: `shared` (library) + `service-parent` (POM-only) + 7 runnable Spring Boot services. Java 21, virtual threads enabled.

| Service | API | Mgmt | Role |
|---|---|---|---|
| auth-service | 8087 | 8097 | users, teams, API keys, MFA, integrations, tenant provisioning (modular monolith) |
| ingestion-service | 8081 | 8091 | alert normalization, Redis dedup, bucket4j rate limiting, Integration API key auth |
| incident-service | 8082 | 8092 | incident FSM, CQRS, WebSocket, central audit consumer |
| notification-service | 8083 | 8093 | Slack / email / SMS channels |
| escalation-service | 8084 | 8094 | `@Scheduled` + ShedLock escalation chain |
| postmortem-service | 8085 | 8095 | Gemini-generated postmortems |
| oncall-service | 8086 | 8096 | on-call schedules |

Event flow: `alerts.raw`/`alerts.resolved` (ingestion → incident) → `incidents.lifecycle` (incident → notification, escalation, postmortem; ingestion-service consumes nothing; escalation-service also publishes `IncidentEscalatedEvent` back onto it, which incident-service's `IncidentEscalationEventConsumer` reads to update `escalationLevel`) ; every service produces to `audit.events`, consumed only by incident-service's `AuditEventConsumer`. Each service that dead-letters has its own topic (`alerts.dead-letter`, `incidents.dead-letter`, `escalation.dead-letter`, `notification.dead-letter`, `postmortem.dead-letter`).

Details of `shared`, persistence and the decided patterns: `.ai/context/architecture.md`. Tenant
isolation and authentication: `.ai/context/security.md`. CI rules ("CI gotchas"): `.ai/context/infrastructure.md`.
Which service owns what: `.ai/context/project.md` ("Service Map").

## Invariants: the short version

Each line is a rule that has been broken before. The full rules, and why, are in the file named after
it — read that file before changing code in its area (`.ai/README.md` has the reading order per task).

- **A tenant comes from authentication**, travels in the data, and is never taken from a request body or
  an unsigned header. Every query is tenant-scoped. → `.ai/context/security.md`
- **Kafka**: send only through `TenantRecords.forTenant`; resolve the tenant **per record** with
  `TenantKafkaRecordResolver`; clear `TenantContext` in `finally`; acknowledge only once processed or
  dead-lettered (`DeadLetterPublisher.deadLetterThenAcknowledge`). → `security.md`, `architecture.md`
- **Async** work goes through `TenantAwareTaskDecorator`, never a plain executor. → `security.md`
- **Service-to-service HTTP**: `ServiceTokenProvider.getToken(tenantId, ServiceNames.<TARGET>)`, a
  connect/read timeout, and a fail-open fallback calls `ClientFallbackMetrics.record`. → `security.md`
- **A forked `SecurityFilterChain`** re-wires CORS and `PUBLIC_PATHS`, adds `ApiKeyAuthFilter` itself, and
  ends in `authenticatedExceptPurposeTokens()`. Prefer extending the shared chain. → `architecture.md`
- **Tenant content reaches only members of that tenant**; no platform-wide destination. → `security.md`
- **Changing `shared` changes all 7 services.** → `architecture.md`
- **Migrations**: number after the highest `V<n>` of that service only; `ddl-auto` is `validate`; no
  superuser rights; never edit a migration that is already on `main`. → `architecture.md`
- **Decided patterns**: outbox for `incidents.lifecycle` and audit events, ShedLock on every
  `@Scheduled` job that changes shared state (a per-replica job says why in its Javadoc), `@Version Long`
  left uninitialised, `clearAutomatically` always with `flushAutomatically`, deadline-bounded retries.
  → `architecture.md`, `.ai/decisions/`
- **Nothing under `src/main/resources`** carries a Spring profile or a literal secret. → `infrastructure.md`
- **Logs** are one ECS JSON object per line, set by `shared` (`StructuredLoggingDefaults`); nothing deployed
  changes the format, and no log line carries a token, secret, password, key or raw payload. → CLAUDE.md
  "Conventions" (Logs)
- **Before proposing an alternative** (Spring State Machine, Kafka Streams, full CQRS, RS256/Keycloak),
  read README "Design Decisions": they were rejected on purpose.

## AI factory

Work from `BACKLOG.md` can run unattended through the autopilot (`/backlog-autopilot`, a dynamic
workflow in `.claude/workflows/`), in the order of the approved queue `.ai/plan/queue.md`
(`/plan-backlog` proposes it). Its agents, rules and limits are described in `.ai/README.md` and
`docs/ai-factory.md`. Three things matter in any session:

- `.ai/rules/` and `.ai/plan/` are human-owned: agents read them and never edit them (the planner only
  proposes, in a PR). Changes to them, to `.claude/` and to `.github/` go through the owner
  (CODEOWNERS; `/apply-audit` for audit recommendations). The full list of paths no agent writes is
  `.ai/rules/protected-paths.md`; an item whose `**Touches:**` names one never reaches the autopilot.
- The factory is migrating to ADR-0055's target one step at a time (ADR-0063's M1–M12): `.ai/context/migration.md` maps
  each step to its backlog items and its plan file (`.ai/context/migration/m<N>.md`). Read it before any migration work;
  a PR that changes a step's items updates it and the step's file.
- The "Working style" below is for interactive sessions with the owner. An autopilot agent cannot ask:
  it follows its own definition in `.claude/agents/` (decide and record a reversible choice in an ADR,
  stop the item as BLOCKED on an irreversible or ambiguous one).

## Conventions

- **Comment culture**: classes and non-obvious decisions carry Javadoc explaining *why*, including the bug or backlog item that motivated them (`<h2>Fixed (backlog #75): ...</h2>`). Match this density — a change that reverses an earlier decision should say so where the old reasoning lived. Backlog items are referenced as `backlog #N` in commits, Javadoc and config comments; open items are recorded in `BACKLOG.md`, finished ones in `BACKLOG-DONE.md` (new items are `backlog #0-1`, `#0-2`, ...; the older `backlog #1`–`#82` exist only as references in code). A `TODO` must cite an item — add it to `BACKLOG.md` first.
- **Commits**: Conventional Commits with a service scope — `fix(incident-service): ...`, `feat(oncall): ...`, `refactor: ...`. Branches: `fix/…`, `feat/…`, `refactor/…`, `docs/…`, `ci/…`, `perf/…` (an autopilot item's from its Type, `scripts/factory/_backlog.sh`); work lands on `main` via PR.
- **Tests**: `<Class>Test` next to its package under `src/test/java`; Mockito for unit tests, Testcontainers (`postgres:16-alpine`) for repository integration tests, and `apache/kafka` (the compose tag) where only a real broker shows the behaviour (`DeadLetterPublisherKafkaIntegrationTest`, backlog #0-96) — those need Docker running. Coverage is enforced twice (backlog #0-57): `jacoco:check` needs 60% LINE per module in `verify`, and on a PR `diff-cover` needs 60% of the changed Java lines covered, summed over the whole diff (excluded: `*Config`, `*Application`, `dto`, domain events). The madrapps coverage report is informational only and goes to the job summary, not a PR comment (the workflow's `permissions:` keeps the token read-only, backlog #0-59). JaCoCo counts only a module's own tests, so a change to `shared` needs tests in `shared`. Surefire's `<argLine>` must keep `@{argLine}` first, or the JaCoCo agent is dropped and both checks silently skip.
- **Logs**: every service logs one JSON object per line in ECS (`shared`'s `StructuredLoggingDefaults`, backlog #0-94); a service whose logs would not be ECS refuses to start (`StructuredLoggingGuard`: a format other than `ecs`, a Logback file, a reshaped `logging.structured.json.*`), so nothing deployed sets any of them. The one way past it is `platform.logging.plain-text: true` (with an empty console format, for plain text): meant for a developer's gitignored `application-local.yml` (README "Step 2"); the guard cannot tell where it came from, so set elsewhere (a deployment's environment) it works too and is logged as a WARN at every start, and only CI's sixth structural rule keeps it out of tracked files. The encoder escapes every value, so a log line can carry a value from outside; what it must not carry is a token, a secret, a password, a key or a raw payload (a provider's text goes to the log only, never to a tenant-readable record: #0-93). In docker-compose, Alloy ships every `incident-*` container's lines to Loki, read in Grafana (#0-94 step 2): its labels, networks and limits are in `.ai/context/infrastructure.md` "Log pipeline"; read it before changing `docker/` or a log label. Nothing in k8s (#0-106). Trace ids are #0-94's step 3.
- **Security inventory**: README "Infrastructure Hardening" lists every platform security control by area and every known gap with its backlog item (first written from the 2026-09-30 audit). A change that adds, removes or weakens a control, or closes a gap, updates that section in the same PR.
- **`.ai/`**: project knowledge for AI assistants and the rules the AI factory works by (`.ai/README.md` is the map and the file contract). Its stated rule: if a change introduces knowledge not inferable from source, update `.ai/` as part of the change; a new decision is an ADR in `.ai/decisions/`.

## Working style (read before implementing anything)

> Applies to interactive sessions with the owner. Autopilot agents follow `.claude/agents/<name>.md`
> and `.ai/rules/` instead (see "AI factory" above).

- **Analysis before code.** For anything beyond a trivial one-line fix:
    1. Describe the current state and its impact on the rest of the system.
    2. Note how this class of problem is typically handled in production systems
       (current best practices, not what's "trendy").
    3. Check whether a similar problem is already solved elsewhere in this codebase —
       decide whether to align with that existing solution for consistency, or whether
       fixing this one thing should also touch the related parts for consistency.
    4. Present each reasonable option with pros/cons — don't silently pick one.
    5. State your recommended approach and why.
- **No shortcuts.** Production-correct over convenient. Don't suggest
  `validate-on-migrate: false`, disabling a check, or a quick workaround to make
  something pass — fix the actual cause. If a proper fix is significantly more work
  than a shortcut, say so explicitly and let me decide, don't default to the easy path.
- **Git commands ready to paste.** When a change is done, give me the exact
  `git add` / `git commit` / branch commands to run — Conventional Commits, scoped
  per service as noted above — not just a description of what to do.
- **Production-grade code quality bar** applies to every change in this repo,
  including learning/throwaway experiments unless I explicitly say otherwise:
  proper error handling, no swallowed exceptions, tests for new logic, no
  `TODO`/`FIXME` left without a backlog reference.
- **Don't guess silently on ambiguity.** If a request could reasonably mean two
  different things (which service, which layer, whether to touch the DB schema),
  ask rather than assuming the simpler interpretation.
- **Delete the branch after every merge.** Once a PR is merged, GitHub deletes its
  branch on `origin` (`delete_branch_on_merge`, backlog #0-113); delete it locally
  (`git branch -d <branch>`) after switching back to `main` and pulling, and check
  that `git ls-remote --heads origin <branch>` prints nothing (if it does,
  `git push origin --delete <branch>`). Don't let merged branches accumulate.
  A PR that needs the bypass of the ruleset of `main` (the owner's own PR touching
  a code owner's path, or one whose CI is red for an outside reason) is merged by
  the owner, typing `! gh pr merge <n> --merge --admin --match-head-commit <sha>`:
  sessions are denied the bypass (`.claude/settings.json`, ADR-0034). On "zmerguj"
  for such a PR, give the owner that command with the head SHA of the commit
  reviewed (the bypass skips the review of the last push, so a commit pushed onto
  the branch after the review would merge unread, #0-131). Give it only once
  `gh pr checks <n>` is green, or name the red job and the outside reason it is red
  for: the bypass skips the required checks too, and an "Enforced by" in
  `factory.md`, should one be added, would rest on this (backlog #0-115). Changing
  the settings
  (`repository-settings.rb plan`/`apply`, `gh api` on the rulesets, `gh repo edit`)
  and approving a PR (`gh pr review`) are the owner's commands too.
