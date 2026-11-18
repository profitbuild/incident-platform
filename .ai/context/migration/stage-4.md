# ADR-0055 stage 4: dispatcher v0 — PLAN (written 2026-11-17)

The decisions are ADR-0060 (D1–D8); this file is how each step carries them out, so an item is written from its
section, not from memory. **A living plan:** an item that settles an open question or changes a step updates its
section in the same PR, as it updates `.ai/context/migration.md`. Items are created one at a time, as their turn comes;
4.1 (#0-267) is done, and its review left #0-268 and #0-269, both before 4.2.

Exit (ADR-0055): 3 PRs opened by the dispatcher. Rollback: today's `/backlog-autopilot` in the devcontainer, kept
working until stage 5's exit. Rule of the migration: one factory change at a time, then application items.

## The picture at the end of stage 4

```
Mac (owner) ── limactl ──▶ build VM (Lima factory-build)
                             ├─ user dispatcher: node dispatcher, its state dir, builder-app key, Anthropic key,
                             │   the credential proxy, a clone of `factory` at the pinned tag, a clone of the product
                             └─ user factory: rootless Docker ──▶ task container (one per task, removed after)
                                   /workspace = the task's clone; /opt/factory = `factory` read-only (--plugin-dir)
                                   no GitHub token, no Anthropic key; ANTHROPIC_BASE_URL = the proxy
GitHub: builder-app pushes the branch and opens the PR on incident-platform; never installed on `factory`
```

Per task: claim → fresh clone and container → per phase one `claude -p` per agent (dispatcher records head before and
after, `stream-json` saved) → gate by `docker exec` → checks outside the container (D7) → push and PR as builder-app →
state recorded → container removed.

## 4.1 The `factory` repository and the accepted ADR — item #0-267

- **Owner:** set ADR-0060 to Accepted. `gh repo create profitbuild/factory --public`; secret scanning and push
  protection on; Actions: SHA pinning required, default token read-only, workflows cannot approve PRs; a ruleset on
  `main` (pull request, code owner review, the CI check required, no force push, no deletion); `.github/CODEOWNERS`
  `* @lukaszplawiak`. Choose the licence (open).
- **Skeleton:** `README.md` (what `factory` is, ADR-0055 and ADR-0060 by link), `.node-version` (incident-platform's),
  `dispatcher/package.json` (`"type": "module"`, no dependencies), `dispatcher/src/`, `dispatcher/test/smoke.test.mjs`,
  `.github/workflows/ci.yml`: `node --test`, actionlint, shellcheck, zizmor at incident-platform's pins
  (`ACTIONLINT_VERSION`, `SHELLCHECK_VERSION`, `ZIZMOR_VERSION` in its `ci.yml`), installed the way
  `install-pinned-tool.sh` does (a copy until stage T makes the template).
- **Shows it:** #0-267 AC1–AC4.
- **Done (2026-11-18, #0-267):** ADR-0060 Accepted (PR #655); `profitbuild/factory` created by the owner with `gh api`
  alone, each setting read back. Beyond the list above: a ruleset on every tag (no update, no deletion, no bypass),
  since a product loads the factory at a pinned tag; the required checks `Test` and `Lint Workflows` bound to GitHub
  Actions (`integration_id` 15368), added after their first run; merge commits only; no issues, wiki or projects;
  Dependabot alerts, private vulnerability reporting, immutable releases; Actions limited to GitHub's own; fork runs
  wait for approval; a direct push to `main` refused (the ruleset's positive control). The skeleton also holds
  `.github/actions/setup-node` and `.github/zizmor.yml` (copies, as `install-pinned-tool.sh`) and `LICENSE`
  (Apache-2.0). Factory PR #1; AC3's failing half by the draft PR #2, closed unmerged.
- **Settled:** the licence, Apache-2.0 (the owner, 2026-11-18); `repository-settings` files for `factory` at stage T,
  the owner's `gh api` read of 2026-11-18 being AC2's evidence until then.
- **Left by its review, before 4.2:** #0-268 (`factory`'s CI is a copy with no drift check and without part of
  incident-platform's controls; the secret scan decided before 4.2), #0-269 (a session in the `factory` clone has
  none of the owner's denies). Moved to 4.2: the check that builder-app is not installed on `factory`.

## 4.2 builder-app

- **Owner (GitHub, organisation `profitbuild`):** create a GitHub App `profitbuild-builder`: no webhook; repository
  permissions Contents read and write, Pull requests read and write, Issues read and write (labels on PRs), Metadata
  read; nothing else (no Checks, no Statuses, no Workflows, no Administration). Install it on incident-platform only.
  Generate a private key; on the VM: user `dispatcher` (provision.sh, see below), the key at
  `/home/dispatcher/.config/factory/builder-app.pem`, `chmod 600`, and `FACTORY_APP_ID`, `FACTORY_INSTALLATION_ID` in
  `/home/dispatcher/.config/factory/env` (mode 600).
- **VM (`scripts/factory-admin/build-vm/provision.sh`, moving to `factory`):** a system user `dispatcher`, its home
  mode 700; `factory` cannot read it. The dispatcher drives `factory`'s rootless Docker through its socket
  (`/run/user/<factory uid>/docker.sock`) by a group ACL: control of `factory`'s containers, never the reverse.
- **Code (`dispatcher/src/github/app-token.mjs`):** a JWT (`iat` = now − 60 s, `exp` = now + 9 min, `iss` = app id)
  signed RS256 with `node:crypto`; `POST /app/installations/{id}/access_tokens` narrowed to the one repository and the
  permissions above; cached until 5 minutes before expiry; never written to disk. `git push` gets it through
  `GIT_ASKPASS` (a script printing an env var of the git process only), never in a URL or argv. Commits and the PR are
  authored as `profitbuild-builder[bot]` with its noreply address (`<bot user id>+profitbuild-builder[bot]@users.noreply.github.com`).
- **incident-platform changes (same item):** ADR-0052 amended (the preflight's identity is the app's, for the
  dispatcher path; the bot's stays for the rollback); ADR-0034 amended (the app is not a bypass actor; it needs none:
  its PRs wait for the owner's review like the bot's); `repository-settings.rb` knows the app's installation (it is
  on incident-platform, not on `factory`); `audit-data.sh` reads the PR author `app/profitbuild-builder` as well as
  the bot's login.
- **Tests:** a JWT verified against a key pair generated in the test; the token request against a fake server
  (`node:http`); a test that the token is absent from argv, from the environment of every child but git's, and from
  the state directory.
- **Shows it also:** `gh api repos/profitbuild/factory/installation` with the app's JWT answers 404: the app is not on
  `factory` (moved from #0-267's AC2, which could not check an app that did not exist yet).
- **Open:** rotation cadence (proposal: a new key each quarter, the old deleted after the switch); where the stage-C
  secret store is.

## 4.3 The dispatcher's core

- **CLI:** `node dispatcher/src/cli.mjs run [--item 0-N] [--resume <branch>] --adapter <product>/.factory/adapter.json`.
  Configuration from the environment only (ADR-0055): `FACTORY_STATE_DIR`, `FACTORY_REPO_DIR` (the product clone the
  dispatcher reads `main` from), the app's ids, `FACTORY_PROXY_ADDR`, and today's limits `FACTORY_MAX_BLOCKED`,
  `FACTORY_AUDIT_EVERY`, `FACTORY_MAX_MERGES_PER_DAY` (no defaults, ADR-0052 point 5).
- **State (`$FACTORY_STATE_DIR`, outside any repository):** `lock` (one `flock` for the whole dispatcher in v0: one
  task at a time), `state.json` (the breaker's counts and history, the semantics of today's `state.sh`),
  `tasks/<runId>/task.json` (`runId`, `item`, `branch`, `baseSha`, `phase`, `round`, `calls[]`, `status`, `pr`),
  written to a temporary file and renamed. A restart resumes a task at its last completed phase; every phase is safe to
  run twice (an existing PR for the branch is found before one is created).
- **Retries (#0-261):** every GitHub call through one helper: 5xx, 429, a timeout or a DNS error is retried with
  backoff and jitter (1 s doubling to 60 s), not counted as an attempt; ten in a row stop the task as BLOCKED with the
  reason. The GraphQL rate limit (`rateLimit { remaining resetAt }`) is read before a GraphQL pass; v0 uses REST.
- **Adapter (`factory/schemas/adapter.schema.json`):** `repository`, `gate` (command and its contract), `changedPaths`
  (command), `queue` (`{"kind": "backlog-md", "files": [...]}` until stage 7), `protectedPaths` (file), `trustedPaths`
  (the product's scripts the dispatcher runs from `main`, which a task branch may not change; incident-platform:
  `["scripts/factory/"]`), `taskImage`,
  `profile`, `factoryVersion`. **Gate contract (`factory/schemas/gate.schema.json`):** today's `run-tests.sh` JSON:
  `status` (`pass` | `fixable` | `stop`), `exitCode`, `modules`, `log`, `head`, `artifact`, `summary[]`.
- **Task container:** a fresh clone of the product at the base into `$FACTORY_STATE_DIR/tasks/<runId>/work`, owned by
  the uid the container's `dev` maps to (as `create.sh` does today); `devcontainer up --workspace-folder <work>` with
  `factory` mounted read-only at `/opt/factory`; `~/.claude` a per-task volume (nothing to log in to, D4); `~/.m2` a
  shared cache volume (open: a task can poison it for the next; proposal: accept in v0, per-task copy if a seeded case
  shows it). `docker rm -f` and the volume removed at the end, BLOCKED or not.
- **Product code from `main` only (D6):** the adapter's commands and `trustedPaths` are read from the base commit
  (for incident-platform: `next-item.sh`, `changed-paths.sh`, `run-tests.sh`); the queue command runs in a short-lived
  container from `main` too. The dispatcher names no product path itself (ADR-0055).
- **Tests:** the lock refuses a second run; a killed run resumes at its phase and opens no second PR; a retried 503 is
  not counted, ten are a block; the adapter and gate schemas refuse a missing field.
- **Open:** `next-item.sh` calls `gh pr list` for its locks and there is no token in a container (proposal: the
  dispatcher passes the open PRs as a file, a change to `next-item.sh`'s arguments).

## 4.4 The control flow, ported

- **From `backlog-autopilot.js` into `dispatcher/src/flow/`:** the phases (preflight, pick, plan, implement, review
  rounds with the path gate and the test gate, verify, acceptance, ship), the JSON schemas of each answer, `as()`
  (an agent that ends without its answer is a stop), `stopItem`, the limits (`MAX_ROUNDS` 3, `MAX_TEST_FIXES` 2,
  `MAX_AGENT_CALLS` 45), the breaker, `notify.sh`'s events. `factory-ops` calls become plain function calls.
- **One agent call:** `docker exec <task> claude -p --plugin-dir /opt/factory --output-format stream-json --verbose
  --json-schema <schema> --permission-mode dontAsk --settings /opt/factory/settings/autopilot.json --max-turns <its
  frontmatter's> "<prompt>"`, stdout saved to `tasks/<runId>/calls/<n>-<agent>.jsonl`; the answer is `structured_output`,
  absent means no answer. The run stops if the init event lists a `plugin_errors` entry or not the expected agent and
  tools.
- **Agents do not commit; the dispatcher does**, after each call that changed the tree: `git add -A` and a commit whose
  message comes from the answer, with the `Factory-Run` and `Factory-Agent` trailers (#0-212). So the trace (head before
  and after) is the dispatcher's own, and agents lose git's writing commands (#0-236's forms).
- **Tests:** `test-autopilot-workflow.mjs`'s whole runs against a fake agent, ported to `node:test` with an injected
  `runAgent`; each stop reaches `stopItem` with its stage.
- **Open, to settle by a spike at the start of 4.4:** how `claude -p` runs a named agent of a plugin as its main
  thread (`--agent <name>`, or the definition's body as `--append-system-prompt-file` with its tools and model);
  whether hooks of the plugin run in that mode (they stay a second layer until 6c); what replaces ADR-0058's isolation
  probe (proposal: the init event's agent and tools).

## 4.5 Push, PR, trailers and trace

- **Checks before a push (D7), outside the container,** on the task's clone: `merge-base base HEAD` is the recorded
  base, `rev-list --merges base..HEAD` is empty; `changed-paths` from `main` over `base..HEAD`: an Owner-only path stops
  the task, `needsHuman` sets the owner's label; no path of the adapter's `trustedPaths` changed; every commit carries both trailers and
  the run's `Factory-Run`; the PR body has `Autopilot run <runId>`, `Rounds: <n>`, `Scope: <category>` and the
  acceptance verdict JSON, the fields `audit-data.sh` reads.
- **Push and PR:** `git push` as builder-app (4.2); `GET /pulls?head=profitbuild:<branch>` first, then `POST /pulls`
  or `PATCH`, labels by the issues API (`autopilot`, `shadow`, `risk-high`, `blocked`), a draft for a BLOCKED task.
  No status the ruleset requires is set with builder-app's credential (ADR-0055); v0 sets none. The body is written by
  an agent with `ship-record`'s format and checked here.
- **Trace (#0-204):** one row per agent call in a `<details>` block: agent, phase, round, duration, tokens, commits added.
- **Backlog edits** (moving the item to `BACKLOG-DONE.md`) stay an agent's file edits, committed by the dispatcher.
- **Tests:** each check refuses its planted case (a merge, a protected path, a missing trailer, a body without
  `Rounds:`); an existing PR is reused, not duplicated.
- **Open:** how a reused draft is retitled (#0-254's case, now the dispatcher's own code).

## 4.6 The credential proxy and the transcripts

- **Owner:** a Console workspace for the factory with a monthly spend limit; an API key in it, at
  `/home/dispatcher/.config/factory/anthropic.key` (mode 600).
- **Proxy (`dispatcher/src/proxy/`):** a `node:http` server on the address the containers reach (`host-gateway-ip`,
  ADR-0057), a port of its own; it accepts a request only with the task's token (a random value per task, given to the
  container as `ANTHROPIC_AUTH_TOKEN`, with `ANTHROPIC_BASE_URL` pointing at the proxy), replaces it with the key and
  streams to `api.anthropic.com`; it records each response's usage per task. A container's other requests to Anthropic
  hosts are removed from the task allow-list.
- **Transcripts:** the `stream-json` files of 4.4 are the record; a summary per call from them (the successor of
  `run-summary.sh`, which reads the files Claude Code documents as internal); the task's directory is archived off the
  VM by the owner (`limactl copy`) until stage C ships it.
- **Tests:** a request without the task's token is refused; the key never reaches a response or a log; streaming passes
  through unchanged (a fake upstream); usage is summed per task.
- **Open (security, from the review of ADR-0060):** a task's token is valid only while its task runs and only from
  its container's address; the proxy refuses another task's token; task containers cannot reach each other (one Docker
  network per task, or inter-container traffic dropped).
- **Open, to settle by a spike:** that Claude Code with `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` needs no login;
  the cost of a run at the Console's prices, from stage 3's baseline (#0-205) and the proxy's own counts.

## 4.7 The adapter, the switch and the three runs

- **incident-platform:** `.factory/adapter.json` (the gate `scripts/factory/run-tests.sh`, changed-paths
  `scripts/factory/changed-paths.sh`, queue `BACKLOG.md` and `.ai/plan/queue.md`, protected paths
  `.ai/rules/protected-paths.md`, the devcontainer image, profile `spring-boot`, the pinned `factory` tag), validated
  by Factory guards against `factory`'s schema.
- **The switch:** the owner starts either path; both read the same queue, and an open PR is a lock for both. Only one
  runs at a time (the owner's rule until the timer of stage 7).
- **Exit:** three items from the queue, each a PR opened by builder-app, reviewed and accepted, merged by the owner.
  Then: ADR-0053 marked superseded by ADR-0060; #0-236, #0-251, #0-253, #0-213, #0-217, #0-226, #0-228, #0-234 closed
  as done by stage 4; the bot account and `factory-ops` kept for the rollback until stage 5's exit;
  `.ai/context/migration.md` and this file record the runs (as `stage-3.md` does).

## Owner's steps, in order

1. ADR-0060 Accepted; `profitbuild/factory` created with its baseline (4.1). Done 2026-11-18.
2. builder-app created and installed on incident-platform; its key on the VM (4.2).
3. A Console workspace with a spend limit and its key on the VM (4.6).
4. Merging each item's PRs; the three exit runs started by hand (4.7).

## Open questions, all in one place

| Step | Question | Proposal |
|---|---|---|
| 4.1 | Licence of `factory` | settled 2026-11-18: Apache-2.0 |
| 4.1 | `repository-settings` files for `factory` now or at stage T | settled 2026-11-18: stage T |
| 4.2 | Key rotation cadence | quarterly |
| 4.3 | `next-item.sh`'s `gh pr list` without a token | the dispatcher passes the open PRs as a file |
| 4.3 | Shared `~/.m2` cache | accept in v0 |
| 4.4 | Running a plugin's named agent as `-p`'s main thread; hooks in that mode; the isolation check's successor | a spike first |
| 4.5 | Retitling a reused draft | the dispatcher sets the conventional title |
| 4.6 | No login needed with the base URL and auth token; the cost per run | a spike first; computed from the baseline |
| 4.6 | A task's token used by another task or after its end | bound to the task's lifetime and container address |
