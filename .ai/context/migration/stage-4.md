# ADR-0055 stage 4: dispatcher v0 — PLAN (written 2026-11-17)

The decisions are ADR-0060 (D1–D8); this file is how each step carries them out, so an item is written from its
section, not from memory. **A living plan:** an item that settles an open question or changes a step updates its
section in the same PR, as it updates `.ai/context/migration.md`. Items are created one at a time, as their turn comes;
4.1 (#0-267) is done; its review left #0-268 and #0-269, both done on 2026-11-19, and #0-269's review left #0-270,
done the same day (`/review factory#<n>`).

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
- **Left by its review, before 4.2:** #0-268 (done 2026-11-19: `factory` scans every commit for secrets before a
  merge, a required check, `factory` PR #5; `check-factory-copies.rb` in Lint Workflows here compares every copy
  with its original (ADR-0061), failing a pull request here only on a difference it brings, warning otherwise; the decision
  per control is #0-268's AC1 table), #0-269 (a session holding the owner's token
  is an admin no ruleset binds: `factory`'s code is written with an app of its own, `profitbuild-factory-dev`, ADR-0060
  D5 as amended). Moved to 4.2: the check that builder-app is not installed on `factory`.
- **Done (2026-11-19, #0-269):** the app `profitbuild-factory-dev` and the ruleset `tag-creation` (PR #657 and the
  owner's settings); `factory` PR #3: `.devcontainer/` (a clone in a volume of its own, the hour's token read-only
  from the host, HTTPS to GitHub and Anthropic only, a tripwire for credentials a client forwards), the host's
  `dispatcher/bin/dev-token.mjs` on `dispatcher/src/github/app-token.mjs`, `.claude/settings.json` with the denies
  that apply there and the test that keeps them. The key stays on the Mac's host (ADR-0060 D5 as amended). AC3's
  probes, run in that devcontainer, are in #0-269's Result. Left by its review: #0-270 (done 2026-11-19: `/review
  factory#<n>` reviews a `factory` pull request from files, `scripts/factory-admin/fetch-factory-pr.sh`; how a `factory`
  change is made, review and merge included, is `factory`'s CONTRIBUTING.md, factory PR #7); additions to #0-268 (three more copies, a deny for branch
  deletion by push in both repositories) and to #0-249 (`factory`'s Dockerfile installs Claude Code the same way).

## 4.2 builder-app — #0-271 (4.2a, the code) and #0-272 (4.2b, the app, the VM and the rulesets)

Split by the owner on 2026-11-19, after an analysis of the step. The cut follows the trust boundary:
- the code that reads the key is written and reviewed first, tested with a key made in the test, before the real key
  exists;
- then the app, the key on the VM and the rulesets that confine the app.

What the old single step also held moves to 4.5, where it describes real behaviour: ADR-0052 and ADR-0034 amended,
`audit-data.sh` reading `app/profitbuild-builder`, and the Issues permission (labels).

### 4.2a The code (#0-271, in `factory`) — done 2026-11-19, `factory` PR #9 (merge cdae18c5)

What was built, in `dispatcher/` (Node built-ins only):
- **Settings from the environment** (`src/config/builder-env.mjs`, ADR-0055 "environment only", the owner's choice in
  review round 1): `BUILDER_APP_ID`, `BUILDER_APP_INSTALLATION_ID`, `BUILDER_APP_KEY` (default
  `/home/dispatcher/.config/factory/builder-app.pem`), read from `process.env`.
  - The file `/home/dispatcher/.config/factory/env` is loaded by Node itself: `node --env-file=… dispatcher/bin/…`. A
    variable already set in the process's environment wins over the file.
  - That file is trusted as code is: it can set `NODE_OPTIONS` (`--require`), which runs code in the process that reads
    the key before any check of ours (tried in the owner's session). So only its owner writes it (4.2b checks the
    modes), and it never holds a secret, since every child of the dispatcher inherits `process.env`.
  - A refusal names the variable, never its value; an unknown `BUILDER_APP_*` is refused.
- **The key** (`src/config/own-file.mjs`): `lstat` (a regular file, the process's own uid, no bit for group or
  others), then `open` with `O_NOFOLLOW|O_NONBLOCK` and `fstat` of the handle (the same inode, the same checks), so a
  swap to a symlink, a FIFO or a directory between the two is refused. It is read again at every mint.
- **The token** (`src/github/checked-token.mjs`, parametrised checks; `builder-token.mjs`, builder-app's values and
  the cache):
  - The API URL must be https, or http to loopback (`url-policy.mjs`, one rule for the API and the push URL), before
    the key is read.
  - The installation on incident-platform must carry the env's installation id and app id and exactly Contents write,
    Pull requests write and Metadata read.
  - The token is asked narrowed to `incident-platform` and those three. It must reach exactly
    `profitbuild/incident-platform` and hold exactly the three, and must not expire within 5 minutes. Any failure
    after the mint revokes it.
  - One token is held in memory and reused until 5 minutes before expiry; concurrent calls share one mint; a failure
    leaves nothing held; the old token is not revoked at a refresh (a push may be using it), and `revoke()` closes the
    source.
- **The push** (`gitPushCommand`, `libexec/git-askpass.sh`):
  - The token is in the git process's environment only, read by the askpass script for the push's own origin.
  - The environment is an allowlist (`PATH`, `HOME`, the proxy variables) plus `LC_ALL=C` and its own `GIT_*`.
  - `GIT_ALLOW_PROTOCOL=https` stops a URL rewritten to `ssh://` (with a `core.sshCommand` from `.git/config`) from
    reaching a program with the token; tried on git 2.54.
  - Global and system config off, hooks and fsmonitor off, credential helpers cleared, an explicit push URL.
  - Why the devcontainer keeps its file-reading credential helper is written in both scripts.
- **Errors:** `githubRequest` errors carry `status` (GitHub answered) or `kind` (`timeout`, `network`) with `cause`,
  never a credential: what #0-261's retries branch on.
- **`check-app`** (`bin/check-app.mjs`): mints, checks, expects 404 for an installation on `profitbuild/factory`,
  revokes; prints its eight lines and no token; exit 1 at the first failure, a failed final revoke included.
- **Tests:** 86, and 48 of 50 mutations caught (the two that live are each one half of the layered symlink guard;
  removing both is caught). `dev-token.mjs` is unchanged; moving it onto `checked-token.mjs` is #0-273.
- **Left for a real app** (#0-272's AC5): GitHub's 404 for `factory`, the narrowed token's one repository, and
  `metadata: read` in its answer.

### 4.2b The app, the key and the confinement (#0-272, in incident-platform and on GitHub)

- **Owner (GitHub, organisation `profitbuild`):** a GitHub App `profitbuild-builder`:
  - no webhook;
  - repository permissions Contents read and write, Pull requests read and write, Metadata read. Nothing else: no
    Issues until 4.5, no Checks, no Statuses, no Workflows, no Administration;
  - installed on incident-platform only.
- **The order (the owner's choice A2, 2026-11-19):** two pull requests, the confinement first (the rulesets below, no
  app needed), then the app, the key and the VM, so the key never exists without the rulesets.
- **VM (`scripts/factory-admin/build-vm/provision.sh`, moving to `factory`):**
  - a system user `dispatcher`, its home and `.config/factory` mode 700; `factory` cannot read them;
  - a clone of `profitbuild/factory` as `dispatcher`, at a commit pinned in `provision.sh` until 4.7's tag, so
    `check-app` has code to run;
  - the key at `/home/dispatcher/.config/factory/builder-app.pem` and the ids in `/home/dispatcher/.config/factory/env`,
    both mode 600, written by `build-vm/install-builder-app.sh` (the owner's, on the Mac), which then runs `check-app`
    as `dispatcher`;
  - **one copy of the key** (E2): sent on stdin straight into its file (`sudo -u dispatcher sh -c 'umask 077; cat >
    …'`), never through `/tmp`, and the download deleted. A new VM gets a new key and the old one is deleted on
    GitHub, so recreating the VM is a rotation;
  - `dispatcher`'s access to `factory`'s rootless Docker moved to 4.3 (F2): nothing in 4.2b uses it.
- **Commits and the PR** (4.5) are authored as `profitbuild-builder[bot]` with its noreply address
  (`<bot user id>+profitbuild-builder[bot]@users.noreply.github.com`).
- **Rulesets of incident-platform** (new; `main`'s was the only one), bypass mode `always`:
  - **`branches`:** every branch but `main`, `factory/**` and `renovate/**`, with creation, update, deletion and
    non_fast_forward. The bypass is the role Write (the owner and the bot account);
  - **`renovate`:** `renovate/**`, the same rules; the role Write and Renovate as an `Integration` (2740). Renovate
    gets its own namespace, as builder-app does (C2);
  - **`tags`:** update, deletion and non_fast_forward, no bypass; **`tag-creation`:** creation, the admin role. As
    `factory`'s two (D2): a bypass applies to every rule of its ruleset;
  - **`factory`** (the second pull request, once builder-app's id exists): `factory/**`, the rules of `branches`;
    builder-app as an `Integration` and the admin role. Without it every actor with Contents write may write
    builder-app's branches, which 4.3 fetches into its trusted clone.

  All are files in `.github/repository-settings/rulesets/`; `repository.json` also lists the writers (Write or
  Maintain), whom the role Write's bypass reaches. `repository-settings.rb` checks them, and builder-app's
  installation against `apps/profitbuild-builder.json`, which `check-factory-copies.rb` compares with `factory`'s
  JSON of `BUILDER_PERMISSIONS` (G2).
- **ADR-0034 amended (in #0-272's PR).** It says today that `main` is guarded by one ruleset and that only the settings
  guarding `main` are files. The amendment adds:
  - the rulesets and their bypass actors (four in the first pull request, `factory` in the second);
  - the probes' findings (below);
  - the writers, and `repository-settings.rb check` widened to them and, in the second pull request, to builder-app's
    installation.

  ADR-0060's Consequences, as amended on 2026-11-19, put this part of ADR-0034 at 4.2b and the rest at 4.5.
- **Rotation:** a second key added, the dispatcher switched, the old key deleted; quarterly, and at once on any doubt.

### What a probe settled before 4.2b (2026-11-19), and what follows from it

**Why.** Confining builder-app by a ruleset works only if a bypass given to a repository role does not also let an app
through. GitHub's documentation does not say either way (its pages on rulesets, the rules and the REST
`bypass_actors`), so it was tried.

**How.** On `factory`, with the dev app `profitbuild-factory-dev`, whose installation token holds Contents write, the
case builder-app will be. A temporary ruleset 27640580 on `refs/heads/probe/**` held the rules creation, update and
deletion; the owner created it, changed it and deleted it.

| Bypass of the ruleset | Who pushed | Result |
|---|---|---|
| role Write | the dev app | refused: `GH013 … Cannot create ref due to creations being restricted` |
| role Write | the owner (admin) | passed by bypass |
| role Write and the dev app as `Integration` | the dev app | passed by bypass (the positive control: the rule holds against an app, and only the missing entry refused it) |

**What it shows.** A role's bypass does not cover an app, which passes only as an `Integration` of its own. A role's
bypass covers the roles above it.

**What follows for the factory:**
- **4.2b:** builder-app can be held to `factory/**` with no entry of its own. The owner and the bot account pass by
  the role; Renovate, an app, must be listed by name, or its branches are refused too.
- **Every app added later** (review-app at stage 5, any other) is refused by every ruleset until it is listed. Adding
  it is a decision, made in `.github/repository-settings/` and checked, never a side effect of a role.
- **Stage 5:** review-app's required status is bound to review-app by the ruleset's `integration_id`, as Actions' are
  today (15368). builder-app (no Checks, no Statuses) cannot set it, and an app with Statuses could not either.
- **Stage 10:** the conditions for auto-merge in `.ai/context/migration.md` rest on these facts.
- **Stage T:** the template of a product repository carries the rulesets (`branches`, `renovate`, `tags`,
  `tag-creation`, and `factory` from #0-272's second pull request), its own app as the confined author.
- **What the probe did not show:**
  - deletion was tried by the owner only, and whether the dev app deleted its branch before the ruleset went is not
    recorded;
  - update and non_fast_forward were not tried at all.

  AC6 of #0-272 tries every rule with builder-app's real tokens.

**Two more, from the analysis of 4.2b (2026-11-19, on `factory`, base branch `probe-base`, all cleaned up):**

| Probe | Setup | Result |
|---|---|---|
| P1, `delete_branch_on_merge` under a `deletion` rule | ruleset on `refs/heads/probe/**`, rule deletion only; the owner merges | no bypass: the head branch stayed (60 s); bypass "role Write": deleted |
| P2, an app's approval | ruleset on `probe-base`: one approval, no code owner's; the owner's pull request | the dev app's approval made it APPROVED and mergeable |

- **P1:** GitHub deletes a merged pull request's head branch as the one who merged it. The owner's and the bot's
  merges still clean up (they are in the bypass); `factory/**` is under no ruleset. A branch under `branches` or
  `renovate` merged by an app, or by an auto-merge in an app's name, stays: stage 10's concern.
- **P2:** an app's approval counts. Today the code owner's review (`* @lukaszplawiak` on every path) is what keeps
  builder-app (Pull requests write) from approving the bot's or Renovate's pull requests into a merge. Stage 10's
  conditions in `.ai/context/migration.md` now name it.

## 4.3 The dispatcher's core

- **CLI:** `node dispatcher/src/cli.mjs run [--item 0-N] [--resume <branch>] --adapter <product>/.factory/adapter.json`.
  Configuration from the environment only (ADR-0055): `FACTORY_STATE_DIR`, `FACTORY_REPO_DIR` (the product clone the
  dispatcher reads `main` from), the app's ids (`BUILDER_APP_*`, 4.2a), `FACTORY_PROXY_ADDR`, and today's limits
  `FACTORY_MAX_BLOCKED`, `FACTORY_AUDIT_EVERY`, `FACTORY_MAX_MERGES_PER_DAY` (no defaults, ADR-0052 point 5).
- **Docker for the dispatcher** (moved from 4.2b, the owner's choice F2): `dispatcher` drives `factory`'s rootless
  Docker (`/run/user/<factory uid>/docker.sock`), control of `factory`'s containers, never the reverse. Open: how. An
  ACL on the socket must be set at every start of the daemon (`/run/user/<uid>` is a tmpfs, and the daemon's unit is
  `factory`'s own, which code a test runs can change, ADR-0057), so the setting belongs to a root-owned unit; the
  alternative is a sudoers rule letting `dispatcher` run `docker` as `factory`. Tested here, where `docker exec` is
  first used.
- **Carried from #0-271's review** (`factory` PR #9; the code holds them as preconditions, 4.3 makes them checks):
  - **A trusted clone for the push.** The token goes only to a git run in a clone the dispatcher owns, whose
    `.git/config` no agent's uid can write. The task's commits are fetched into it. The rest of an agent-written
    config can still send the token elsewhere: `http.proxy`, `http.<url>.sslVerify`, `http.sslCAInfo`,
    `http.curloptResolve`, `include.path`, and a section named after the push URL itself (`remote."<url>".pushurl`,
    `.proxy`).
  - **Refspecs pinned** to the task's own branch under `factory/**`: today only a leading `-` is refused, so `+` (force)
    and `:ref` (delete) pass, bounded only by #0-272's rulesets.
  - **The product from the adapter:** `BUILDER_REPOSITORY` and `PUSH_URL` are incident-platform's in 4.2a; they come
    from `.factory/adapter.json`'s `repository` (ADR-0060 D6). The checks already take it as a parameter.
  - **Children from an allowlisted environment:** every process the dispatcher starts (task containers, `claude -p`)
    gets an environment built like `gitPushCommand`'s, never `process.env`, which holds the settings.
  - **The env file holds no secret,** ever: anything there reaches `process.env`.
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
  The label call is the first that needs builder-app's Issues permission, added to the app here, not at 4.2 (#0-272);
  whether Pull requests write alone suffices for a PR's labels is checked then, not assumed.
  No status the ruleset requires is set with builder-app's credential (ADR-0055); v0 sets none. The body is written by
  an agent with `ship-record`'s format and checked here.
- **Moved here from 4.2 (2026-11-19, ADR-0060's Consequences as amended):**
  - ADR-0052 amended: the preflight's identity is the app's on the dispatcher's path, the bot's on the rollback;
  - ADR-0034 amended: the app is no bypass actor and needs none, since its PRs wait for the owner's review like the
    bot's;
  - `audit-data.sh` reads the PR author `app/profitbuild-builder` as well as the bot's login.
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
- **The copy check's reference:** with the pinned `factory` tag in `.factory/adapter.json`,
  `check-factory-copies.rb` (#0-268) compares with that tag instead of `factory@main`.
- **Exit:** three items from the queue, each a PR opened by builder-app, reviewed and accepted, merged by the owner.
  Then: ADR-0053 marked superseded by ADR-0060; #0-236, #0-251, #0-253, #0-213, #0-217, #0-226, #0-228, #0-234 closed
  as done by stage 4; the bot account and `factory-ops` kept for the rollback until stage 5's exit;
  `.ai/context/migration.md` and this file record the runs (as `stage-3.md` does).

## Owner's steps, in order

1. ADR-0060 Accepted; `profitbuild/factory` created with its baseline (4.1). Done 2026-11-18.
2. The confinement and the app (4.2b, #0-272), in this order:
   1. the four rulesets and the writers applied (`repository-settings.rb plan`, then `apply`, from the branch just
      before the merge; pull request 1);
   2. builder-app created and installed on incident-platform, its key on the VM, the `factory` ruleset applied
      (pull request 2), after 4.2a's code is merged in `factory` (#0-271).
3. A Console workspace with a spend limit and its key on the VM (4.6).
4. Merging each item's PRs; the three exit runs started by hand (4.7).

## Open questions, all in one place

| Step | Question | Proposal |
|---|---|---|
| 4.1 | Licence of `factory` | settled 2026-11-18: Apache-2.0 |
| 4.1 | `repository-settings` files for `factory` now or at stage T | settled 2026-11-18: stage T |
| 4.2 | Key rotation cadence | settled 2026-11-19: quarterly, and at once on any doubt (#0-272) |
| 4.2 | Does a role's ruleset bypass cover an app? | settled 2026-11-19 by a probe: no (4.2, "What a probe settled") |
| 4.5 | Does Pull requests write alone allow a PR's labels? | checked at 4.5, before Issues is added |
| 4.3 | `next-item.sh`'s `gh pr list` without a token | the dispatcher passes the open PRs as a file |
| 4.3 | Shared `~/.m2` cache | accept in v0 |
| 4.4 | Running a plugin's named agent as `-p`'s main thread; hooks in that mode; the isolation check's successor | a spike first |
| 4.5 | Retitling a reused draft | the dispatcher sets the conventional title |
| 4.6 | No login needed with the base URL and auth token; the cost per run | a spike first; computed from the baseline |
| 4.6 | A task's token used by another task or after its end | bound to the task's lifetime and container address |
