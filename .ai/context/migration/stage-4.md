# ADR-0055 stage 4: dispatcher v0 — PLAN (written 2026-11-17)

The decisions are ADR-0060 (D1–D8); this file is how each step carries them out, so an item is written from its
section, not from memory. **A living plan:** an item that settles an open question or changes a step updates its
section in the same PR, as it updates `.ai/context/migration.md`. Items are created one at a time, as their turn comes;
4.1 (#0-267) is done; its review left #0-268 and #0-269, both done on 2026-11-19, and #0-269's review left #0-270,
done the same day (`/review factory#<n>`).

Each step's section ends with its **Record** (done, why, not done, why not; `.ai/context/migration.md`, "Every step
keeps a record"), updated by the PR that changes it.

Exit (ADR-0055): 3 PRs opened by the dispatcher. Rollback: today's `/backlog-autopilot` in the devcontainer, kept
working until stage 5's exit; from 4.3c on it shares the VM by time with the dispatcher (only while no dispatcher run
is active, the owner's logins entered again before it), since no credential may live on the VM's daemon while the
dispatcher runs (ADR-0062 point 5). Rule of the migration: one factory change at a time, then application items.

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

## 4.1 The `factory` repository and the accepted ADR — item #0-267, done 2026-11-18

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

**Record (4.1, done 2026-11-18; its follow-ups 2026-11-19).**
- **Done:** ADR-0060 Accepted (PR #655); `profitbuild/factory` created and read back (rulesets `main`, `tags`,
  `tag-creation`; required checks `Test`, `Lint Workflows`, `Secret Scan`; Actions and repository settings above);
  the skeleton (factory PR #1); the secret scan and the copies check (#0-268); the dev app and its devcontainer
  (#0-269); `/review factory#<n>` and CONTRIBUTING.md (#0-270).
- **Why:** ADR-0060 D5: a public `factory` holding no builder credential, changed only through the owner's reviewed
  pull requests; tags immutable because a product loads `factory` at a pinned tag; `factory`'s code written by an app
  of its own because a session with the owner's token is an admin no ruleset binds (#0-269); a copy of a control kept
  in step with its original from here, since this repository leads (ADR-0061).
- **ADRs changed:** ADR-0060 Accepted (PR #655) and its D5 amended (the dev app, #0-269); ADR-0061 new (#0-268, the
  product checks `factory`'s copies and leads); ADR-0038 amended (#0-270, `factory.md` applies to every `factory` pull
  request).
- **Not done:** `repository-settings` files for `factory`; the organisation's two-factor requirement; a comparison of
  the dev app's identity in two files; a probe of a release on an existing tag.
- **Why not:** the settings files at stage T, the owner's choice of 2026-11-18 (the `gh api` read-back is the
  evidence until then); two-factor postponed by the owner in the session of 2026-11-19 ("next step first"; no item: README "Known gaps"
  names it, and stage 9's checks raise it again); the dev app's identity deferred to stage T by
  ADR-0061 (its app id and permissions: #0-279, since `apps/` gave them an offline counterpart); no tag exists on
  `factory` yet, so the probe waits for the first one (stage T).

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
  removing both is caught). `dev-token.mjs` moved onto `checked-token.mjs` with `factory` PR #14 (#0-273, done
  2026-11-20); its ids and permissions against `apps/profitbuild-factory-dev.json` are #0-279.
- **Left for a real app** (#0-272's AC5): GitHub's 404 for `factory`, the narrowed token's one repository, and
  `metadata: read` in its answer.

**Record (4.2a, done 2026-11-19).**
- **Done:** the settings from the environment, the key's file checks, the checked and cached token, the push through
  askpass with an allowlisted environment and `GIT_ALLOW_PROTOCOL=https`, errors carrying `status`/`kind`,
  `check-app` (factory PR #9, three review rounds).
- **Why:** the code that reads the key is written, reviewed and tested with a key made in the test before the real
  key exists (the owner's split of 4.2, 2026-11-19); "environment only" as ADR-0055 says, Node's own `--env-file` so no
  parser is ours (the owner's choice in review round 1).
- **ADRs changed:** ADR-0060's Consequences amended (2026-11-19, the owner's split of 4.2 into #0-271 and #0-272:
  when each amendment of ADR-0034 and ADR-0052 lands); the code carried out ADR-0060 D3 and ADR-0055's "environment
  only" without changing them.
- **Not done:** dev-token on the shared checks; the trusted clone (now the push repository, 4.3b), the pinned refspec, the repository from the
  adapter and children from an allowlist as checks (the code holds them as preconditions); the checks only a real
  app can show.
- **Why not:** dev-token kept by #0-271's AC4 to keep its review on builder-app, done by #0-273 (factory PR #14,
  2026-11-20); the push's checks need the adapter and the task clone, so 4.3b (#0-276); the real app's checks were
  #0-272's AC5, met 2026-11-20.

### 4.2b The app, the key and the confinement (#0-272, in incident-platform and on GitHub) — done 2026-11-20, PRs #663 and #664

- **Owner (GitHub, organisation `profitbuild`):** a GitHub App `profitbuild-builder`:
  - no webhook;
  - repository permissions Contents read and write, Pull requests read and write, Metadata read. Nothing else: no
    Issues until 4.5, no Checks, no Statuses, no Workflows, no Administration;
  - installed on incident-platform only.

  Created 2026-11-20: app id 5844656, installation 183942865 (`apps/profitbuild-builder.json`), read back through the
  organization's installations. Its key is generated only when `install-builder-app.sh` runs, so the download lies on
  the Mac for minutes.
- **Pull request 1:** the four rulesets and the writers, merged 2026-11-20 (PR #663; applied by the owner
  before the merge, `check` on `main` after it: AC1); `factory` PR #13, `BUILDER_PERMISSIONS` in
  `dispatcher/src/github/builder-permissions.json`, merged 2026-11-20 (merge `3888a900`, the dispatcher's pin).
- **The order (the owner's choice A2, 2026-11-19):** two pull requests, the confinement first (the rulesets below, no
  app needed), then the app, the key and the VM, so the key never exists without the rulesets.
- **VM (`scripts/factory-admin/build-vm/provision.sh`, moving to `factory`):**
  - a user `dispatcher` with an ordinary uid (H2 of the analysis of pull request 2, 2026-11-20): the egress chain takes
    every uid from 1000 up, so its traffic passes the chain `factory`'s does; a system uid would reach any host. No
    subordinate range, no login shell, no group but its own; its home and `.config/factory` mode 700, so `factory`
    cannot read them;
  - a clone of `profitbuild/factory` as `dispatcher`, at a commit pinned in `provision.sh` until 4.7's tag (I1), so
    `check-app` has code to run; `verify-pins.sh` checks the commit is on `factory`'s `main`, and `provision.sh` refuses
    a boot whose clone is not a clean checkout of it;
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
    builder-app's branches, which 4.3's push writes and a resumed task reads back.

  All are files in `.github/repository-settings/rulesets/`; `repository.json` also lists the writers (Write or
  Maintain), whom the role Write's bypass reaches. `repository-settings.rb` checks them, and every app installed on the
  organization against its file in `apps/` (J1, after a probe showed the owner's token lists them: permissions,
  events, `repository_selection`; the repositories of a selection it cannot list). `check-factory-copies.rb` compares
  `apps/profitbuild-builder.json`'s permissions with `factory`'s `builder-permissions.json` (G2). Writing the files
  found Renovate on every repository of the organization, `factory` included; narrowed by the owner on 2026-11-20.
- **ADR-0034 amended (in #0-272's PR).** It says today that `main` is guarded by one ruleset and that only the settings
  guarding `main` are files. The amendment adds:
  - the rulesets and their bypass actors (four in the first pull request, `factory` in the second);
  - the probes' findings (below);
  - the writers, and `repository-settings.rb check` widened to them and, in the second pull request, to builder-app's
    installation.

  ADR-0060's Consequences, as amended on 2026-11-19, put this part of ADR-0034 at 4.2b and the rest at 4.5.
- **Rotation:** a second key added, the dispatcher switched, the old key deleted; quarterly, and at once on any doubt.
  Its cost, written down (the owner's question, 2026-11-20): each new key takes the owner, since only GitHub's UI
  generates an app's key, and the download must be dragged into a terminal (`com.apple.macl`); and the key has one copy,
  on the VM's disk, so every recreated VM needs one, and until 4.7's tag every move of the `factory` pin is a change of
  `provision.sh`, so a recreated VM. A few minutes each time; stage C's secret store keeps the key across VMs, leaving
  the quarterly rotation. Updating the pin without a new VM would patch a VM by hand, which docs/ai-factory.md rules
  out: a decision of its own if the cost grows.

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

**Record (4.2b, done 2026-11-20: PRs #663 and #664, `factory` PR #13).**
- **Done:**
  - five rulesets here: `branches`, `renovate`, `tags`, `tag-creation`, `factory` (builder-app and the admin role); the
    writers in `repository.json`;
  - every app installed on the organization as a file under `apps/`, checked by `repository-settings.rb`, and a
    ruleset's `Integration` actor tied to one; Renovate narrowed from every repository to this one;
  - the app `profitbuild-builder` (app 5844656, installation 183942865); its permissions one list with `factory`'s
    `builder-permissions.json` (`check-factory-copies.rb`);
  - the user `dispatcher` on the VM, `factory` cloned at a pinned commit, `install-builder-app.sh`, `verify-pins.sh`'s
    sixth pin;
  - live, from the branch: the VM recreated, the key installed, `check-app` passed, AC6 tried as builder-app and the
    bot, AC7, the egress (#0-272's Result).
- **Why:** the confinement before the key, so the key never exists without it (A2); Renovate in a namespace of its own
  (C2); tags as `factory`'s (D2); one copy of the key, on the VM (E2); one source for the permissions (G2); an
  ordinary uid for `dispatcher`, so the VM's egress chain takes it (H2); the pin on `factory`'s `main` until 4.7's tag
  (I1); every installation as a file once the owner's token proved it can list them (J1, probe P3).
- **ADRs changed:** ADR-0034's "Amendment (#0-272)" (the rulesets beyond `main`, their bypass actors, the probes'
  findings, the writers, and with the second pull request the ruleset `factory`, the apps as files and the
  `Integration` check); ADR-0061 amended (builder-app's permissions, its fifth comparison).
- **Not done:** a narrower egress list for `dispatcher`; a comparison of which repositories a selected installation
  holds; `dispatcher`'s access to `factory`'s Docker; the Issues permission and the PR-author parts; a secret store
  for the key; the VM recreated after review round 3's last fix of `provision.sh`.
- **Why not:** the shared chain already refuses every host off its list, the Mac and private networks, and no list
  stops a key sent through GitHub, so a list of its own is #0-274 (Low); GitHub lists a selection's repositories to
  no `gh` token (probe P4, 403 even with `read:user`), so it is a named gap and `check-app` proves builder-app's;
  nothing in 4.2b used Docker, so 4.3c (F2, #0-277); the labels and the author are 4.5's, where a PR is first opened;
  a secret store is stage C's; the fix changes only what a failing `git status` does, so the VM is recreated at the
  next move of the `factory` pin (noted in #0-272's Result).

## 4.3 The dispatcher's core

Split on 2026-11-20 (the owner's choice A), one `factory` pull request each, in this order:
- **4.3a, #0-275:** CLI and configuration, state and lock, the retries (#0-261), the adapter's and the gate's
  schemas; no Docker, no VM. Done 2026-11-20, `factory` PR #15 (merge `51ce6928`).
- **4.3b, #0-276:** done 2026-11-20, `factory` PR #16 (merge `3c588db3`). "Carried from #0-271's review" below: the push repository the dispatcher owns, the pinned refspec, the repository from
  the adapter, children from an allowlisted environment; how, decided with the owner on 2026-11-20 (the Record's
  "Decided for 4.3b").
- **4.3c, #0-277:** "Docker for the dispatcher" (decided with the owner on 2026-11-20, ADR-0062; the Record's "Decided
  for 4.3c") and the task container; with it #0-282, incident-platform's task configuration for that container (each
  needs the other: #0-282's check is #0-277's, #0-277's trial on the VM runs #0-282's configuration).
- **4.3d, #0-278:** "Product code from `main` only" and `next-item.sh`'s open pull requests as a file.

- **CLI:** `node dispatcher/src/cli.mjs run [--item 0-N] [--resume <branch>] --adapter <product>/.factory/adapter.json`.
  Configuration from the environment only (ADR-0055): `FACTORY_STATE_DIR`, `FACTORY_REPO_DIR` (the product clone the
  dispatcher reads `main` from), the app's ids (`BUILDER_APP_*`, 4.2a), `FACTORY_PROXY_ADDR`, and today's limits
  `FACTORY_MAX_BLOCKED`, `FACTORY_AUDIT_EVERY`, `FACTORY_MAX_MERGES_PER_DAY` (no defaults, ADR-0052 point 5).
- **Docker for the dispatcher** (moved from 4.2b, the owner's choice F2): `dispatcher` drives `factory`'s rootless
  Docker (`/run/user/<factory uid>/docker.sock`), control of `factory`'s containers, never the reverse. Open: how. An
  ACL on the socket must be set at every start of the daemon (`/run/user/<uid>` is a tmpfs, and the daemon's unit is
  `factory`'s own, which code a test runs can change, ADR-0057), so the setting belongs to a root-owned unit; the
  alternative is a sudoers rule letting `dispatcher` run `docker` as `factory`. Tested here, where `docker exec` is
  first used. Decided 2026-11-20: the sudo rule (ADR-0062; the Record's "Decided for 4.3c").
- **Carried from #0-271's review** (`factory` PR #9; the code holds them as preconditions, 4.3 makes them checks):
  - **A push repository the dispatcher owns.** The token goes only to a git run in a repository the dispatcher made,
    whose config no agent's uid can write; the task's commits reach it as a bundle, never by a fetch from the task's
    clone (the Record's "Decided for 4.3b"). What an agent-written config could do there (`http.proxy`,
    `http.<url>.sslVerify`, `http.sslCAInfo`, `http.curloptResolve`, `include.path`, a section named after the push URL
    itself, `remote."<url>".pushurl`, `.proxy`) is what its allowlist's tests plant (#0-276 AC1).
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
- **Retries (#0-261):** every GitHub call of the dispatcher's run through one helper (two by design outside it, the
  Record below: `check-app`, the owner's quick check, and the mint, which 4.4's flow wraps whole): 5xx, 429, a timeout or a DNS error is retried with
  backoff and jitter (1 s doubling to 60 s), not counted as an attempt; ten in a row stop the task as BLOCKED with the
  reason. The GraphQL rate limit (`rateLimit { remaining resetAt }`) is read before a GraphQL pass; v0 uses REST.
- **Adapter (`factory/schemas/adapter.schema.json`):** `repository`, `gate` (command and its contract), `changedPaths`
  (command), `queue` (`{"kind": "backlog-md", "files": [...]}` until stage 7), `protectedPaths` (file), `trustedPaths`
  (the product's scripts the dispatcher runs from `main`, which a task branch may not change; incident-platform:
  `["scripts/factory/"]`), `taskImage`,
  `profile`, `factoryVersion`. **Gate contract (`factory/schemas/gate.schema.json`):** today's `run-tests.sh` JSON:
  `status` (`pass` | `fixable` | `stop`), `exitCode`, `modules`, `log`, `head`, `artifact`, `summary[]`.
- **Task container:** a fresh clone of the product at the base into a work directory of `factory`'s (ADR-0062: not
  `$FACTORY_STATE_DIR`, which the daemon cannot reach), owned by the uid the container's `dev` maps to (as `create.sh`
  does today: here by a one-shot container, ADR-0062 point 2); `devcontainer up --workspace-folder <work>` with
  `factory` mounted read-only at `/opt/factory`; `~/.claude` a per-task volume (nothing to log in to, D4); `~/.m2` a
  shared cache volume (open: a task can poison it for the next; proposal: accept in v0, per-task copy if a seeded case
  shows it). At the end, BLOCKED or not, and at the next run's start: every container and network of the daemon, every
  volume but `~/.m2`, and the work directory removed (ADR-0062 point 7).
- **Product code from `main` only (D6):** the adapter's commands and `trustedPaths` are read from the base commit
  (for incident-platform: `next-item.sh`, `changed-paths.sh`, `run-tests.sh`); the queue command runs in a short-lived
  container from `main` too. The dispatcher names no product path itself (ADR-0055).
- **Tests:** the lock refuses a second run; a killed run resumes at its phase and opens no second PR; a retried 503 is
  not counted, ten are a block; the adapter and gate schemas refuse a missing field.
- **Open:** `next-item.sh` calls `gh pr list` for its locks and there is no token in a container (proposal: the
  dispatcher passes the open PRs as a file, a change to `next-item.sh`'s arguments).

**Record (4.3, in progress: split 2026-11-20, PR #665; 4.3a done 2026-11-20, `factory` PR #15; 4.3b decided with the
owner 2026-11-20, before its code, and done the same day, `factory` PR #16).**
- **Done:** the split into #0-275..#0-278 (above), in an order where each part is reviewed on its own and the first two
  need neither Docker nor the VM; #0-273 first (dev-token on the shared checks), so 4.3b changes one API with two
  callers rather than leaving a third copy.
- **Decided for 4.3a (#0-275) with the owner, 2026-11-20, before its code:**
  - **The lock:** Node opens `$FACTORY_STATE_DIR/lock` (0600, `O_NOFOLLOW`) and runs `/usr/bin/flock -n -x 3` on that
    descriptor. Why: Node has no `flock`; a lock file with a pid (#0-251, #0-253's failures) can go stale or outlive a
    killed run; an abstract socket can be taken first by another user of the VM. `flock(2)` belongs to the open file,
    which Node holds: the kernel frees it when the process dies, and a live run cannot lose it. The lock file's
    `dev` and `ino` are checked against its path after locking.
  - **One lock for the whole dispatcher in v0:** a narrowing of ADR-0060 D7's lock per task, equivalent while one task
    runs at a time; ADR-0060 D7 amended by #0-275's closing pull request (its Touches). Probed 2026-11-20 in a Linux
    container: `flock(1)` exits 0 and the lock stays with Node's descriptor, a second lock is refused meanwhile, and
    `kill -9` of Node frees it.
  - **A secret-shaped value refused anywhere in the environment** (PEM, `ghs_`, `ghp_`, `gho_`, `ghu_`, `ghr_`,
    `github_pat_`), not only in `FACTORY_*` and `BUILDER_APP_*`: the env file reaches `process.env` whole. The
    refusal names the variable alone.
  - **The breaker stops `run`** when `consecutiveBlocked` reaches `FACTORY_MAX_BLOCKED`. A `state.json` that does not
    exist is a first run and starts at zero; one that exists and cannot be read or holds the wrong types trips the
    breaker, and the refusal tells the owner what to do, since the reset is the owner's.
  - **Retries:** 5xx, 429, a timeout or a network error (DNS included); `Retry-After` honoured at 429, at most 60 s;
    a 403 only when it carries `retry-after` or `x-ratelimit-remaining: 0` (GitHub's secondary limit arrives as 403
    or 429), a plain 403 returned at once. One helper around `githubRequest`, so one policy; `check-app` does not
    retry (the owner wants a quick answer), the flow of 4.4 wraps the mint.
  - **`FACTORY_STATE_DIR` is made by the VM's provisioning** (700, `dispatcher`'s; #0-277), and the dispatcher only
    refuses one that is not so, rather than fixing it quietly.
  - **`BUILDER_APP_KEY` keeps its default path:** ADR-0052 point 5's "no defaults" names the three limits; and
    ADR-0055's "configuration from the environment only" holds, since the variable overrides it and the default is
    a path, no secret: the key itself is a file of `dispatcher`'s (ADR-0060 D3), checked at every read.
- **Done in 4.3a (`factory` PR #15, merge `51ce6928`; three review rounds, 163 tests, mutations of every check caught but
  one equivalent):** `dispatcher/src/cli.mjs run`; settings through one mechanism (`config/settings.mjs`, `builder-env`
  and `factory-env` on it); the state directory, atomic writes, the breaker, tasks and phases; the lock; the retry
  helper; the adapter's and the gate's schemas and a validator of a subset of draft 2020-12 that refuses any keyword
  it does not check. #0-261's requirements this step builds, each with its test:
  - **the lock:** one `flock(2)` on `$FACTORY_STATE_DIR/lock` through the run's descriptor; a second run refused, a
    killed one (SIGKILL) leaves it free, a live one never loses it, the inode checked after locking
    (`lock.test.mjs`: "AC2: a second run is refused while another process holds the lock, and a killed run leaves it
    free", "a lock file removed or replaced while a run takes it is refused"; `cli.test.mjs`: "AC2: a second run while
    one holds the lock is refused; once that run is killed, a run goes ahead");
  - **state that survives a restart:** `tasks/<runId>/task.json` and `state.json` written to a temporary file and
    renamed; a restart resumes at the phase after the last completed one, a phase run twice writes the same state
    (`tasks.test.mjs`: "AC3: a run killed between two phases resumes at the next one", "AC3: a run killed inside a
    phase runs it again, and the phase run twice writes the same state"; `state.test.mjs`: "a write is atomic");
  - **retries:** every GitHub call of the flow through `withRetries`/`githubCall`; 5xx, 429, a rate-limit 403, a
    timeout and a network error retried with backoff (1 s doubling to 60 s), jitter and `Retry-After`, not counted;
    ten in a row block the task with the reason; 404, 422 and a plain 403 are not retried (`retry.test.mjs`, its
    "AC4" cases; `tasks.test.mjs`: "AC4/#0-261: GitHub out of reach in a phase blocks the task with the reason").
- **Decided while building it:**
  - a `state.json` that cannot be read is left as it is, not overwritten with a tripped count as `state.sh` does:
    the refusal tells the owner to repair it or remove it knowingly (removing it resets the counts and history), so
    nothing the owner may want to read is lost;
  - `/usr/bin/flock` (util-linux) is needed on every host that runs the dispatcher (the VM has it: util-linux 2.39.3);
  - the breaker refuses `--resume` too (ADR-0060 D7 as amended);
  - the adapter's paths refuse control characters and line separators as well as `..` (review round 1, sec-4a81:
    a `..` after a line break passed the first pattern, and `path.join` then left the product); a command's first
    argument is a script of the product, with a `/`, so never a program found on `PATH`; the repository's name is
    neither `.` nor `..`;
  - the secret shapes need a boundary and a token's length, and include `sk-ant-` (the Anthropic key reaches
    `dispatcher` at 4.6); a token glued to a letter or `_` is not caught, a stated price of the boundary, this check
    being a second layer behind "no secret in the environment".
- **ADRs changed:** ADR-0060 D7 amended: v0's one lock for the whole dispatcher (this step's closing PR; its Status
  line and index row name #0-275).
- **Decided for 4.3b with the owner (2026-11-20, `/research` of #0-276, before its code):**
  - **No git with the dispatcher's rights in a repository an agent wrote**, for the push or for anything else: an
    agent-written `.git/config`, `.gitattributes` or hook can make git run a program (`core.fsmonitor`, a filter's
    driver, `diff.external`, `core.pager`, a hook) as `dispatcher`, the uid that reads builder-app's key; a local
    `fetch` from the task's clone runs `upload-pack` there and reads its `objects/` (git's 2024 local-clone fixes are
    this class). The model of this repository's review guard (`git -C` refused, `factory` pull requests reviewed as
    files, #0-270). ADR-0060 D7 amended (#0-276).
  - **The task's commits cross as a bundle** (`git bundle create`, run by the task's own git, in its container, which
    holds no credential): a file, data, read by the dispatcher, which checks the bundle's own objects, and only those,
    with an explicit strict check before any ref names them (`index-pack --strict` or the like on the bundle's pack: a
    plain `fsck` is `--full` by default and walks `alternates`, so all of `main`'s history at each read, and could
    refuse an old object there). The check never rests on git's `fsckObjects` settings when reading a bundle (probed
    2026-11-20 on Ubuntu 24.04's git 2.43.0, the VM's: a commit with no author email passed `git fetch <bundle>` with
    `transfer.fsckObjects` and with `fetch.fsckObjects`, and `fsck --strict` refused it). Its prerequisites are exactly
    the commit the dispatcher names (the recorded head for a call's bundle, the base for the push's), one ref, the
    task's branch. It leaves the container on `docker exec`'s stdout (`git bundle create -`) into the dispatcher's own
    directory, never as a file in a directory an agent writes (a swap or a link between the check and the read). SHAs unchanged, so the trailers and the
    trace hold. Not `format-patch`/`am` (new SHAs, the trace lost) and not a local `fetch` (above).
  - **One way in from the container** (review round 2 of these decisions): the container's bundles go only into the
    task's own repository under `$FACTORY_STATE_DIR`, one per call, each checked against the recorded head (below);
    the push repository is filled from that repository, by a bundle the dispatcher makes there of `<base>..<recorded
    head>`, never by a bundle from the container. The checks of the push repository then stand behind the ones on
    the way in, a second layer, not the only one.
  - **A fresh push repository per push:** `git init --bare` under `$FACTORY_STATE_DIR`, `objects/info/alternates` onto
    `FACTORY_REPO_DIR` (the dispatcher's own clone of `main`, for the base's objects), the dispatcher's bundle read in
    and checked the same way, the checks, the push, removed, after a refused push too. Nothing in it lives from one push to the next. Through `alternates`
    `FACTORY_REPO_DIR`'s objects feed every push, so it is inside the trust boundary: a task's clone shares no inode
    with it (a local `git clone` hardlinks `objects/`, and the task clone is given to the container's uid; #0-277).
  - **Its config by an allowlist, not a denylist:** before the token is asked for, the push repository's config
    (read as a file, with no system or global config) holds exactly what a reference `git init --bare`, made by the
    same git at the same moment, holds: keys and values (macOS's git adds `core.ignorecase` and
    `core.precomposeunicode`, so the list is the git's own, never a constant); every other key refuses the push,
    `include.*` and the keys #0-271's review named among them. A denylist is never complete.
  - **The refspec built by the code:** the call takes `{ sha, branch }`, `sha` 40 hex and the bundle's ref, `branch`
    the task's own; the refspec is `<sha>:refs/heads/factory/<branch>`, no `+`, no `:<ref>`; a task's fix is a new
    commit, so no force push in v0.
  - **The product from the adapter:** `repository` gives `BUILDER_REPOSITORY` and `PUSH_URL`; the token checks take
    them already.
  - **One builder of every child's environment** (`childEnv`): each caller names its allowlist (the push: `PATH`,
    `HOME`, the proxy variables; `flock`: none); a static test refuses any function of `node:child_process` in `src/`
    (`spawn`, `exec`, `execFile`, `fork` and their `Sync` forms) whose `env` is not built by it, the shape of `builder-static.test`. `gitPushCommand`'s and `lock.mjs`'s two ways today become one.
  - **For 4.4 and 4.5, the trace stays the dispatcher's** (review round 1 of these decisions, arc-4c7e: a commit made
    by the container's git runs the agent's hooks and config, and a process an agent left running can rewrite commits
    between calls):
    - after a call, the commit is made in the task's container by its git with the dispatcher's own flags
      (`-c core.hooksPath=/dev/null`, `--no-verify`, no fsmonitor), the trailers it gives, and the author and
      committer it gives (`user.name`, `user.email`: a container's config could set any identity, the owner's
      included, which GitHub shows on the pull request's commits);
    - the container then hands over a bundle of `<recorded head>..HEAD` (stdout, as above), read and checked into the
      task's own repository; the dispatcher accepts it only as exactly one new commit whose only parent is the head it
      recorded (a merge with it as one of two parents is refused here, not first by 4.5's `rev-list --merges`), whose
      message and trailers are exactly the ones it gave and whose author and committer are the ones it gave, and only
      then records the new head. The trace is the chain of heads it recorded, never `git rev-parse` in the container;
    - the checks before a push (`merge-base`, `rev-list --merges`, `changed-paths`, the trailers) run in the push
      repository after the dispatcher's bundle is read in, never in the task's clone, with the base and the head passed as
      SHAs (a fresh bare repository has no refs and an unborn `HEAD`); the branch's commits must be exactly the
      recorded chain, each `Factory-Agent` the agent of the call recorded for it.
    What a process in the container changes in the tree before a commit is still that call's work: attribution is the
    dispatcher's, the content is the container's, as before.
- **Done in 4.3b (`factory` PR #16, merge `3c588db3`, head `fd6d933f`; five review rounds, the last all APPROVE;
  219 tests, on CI's git 2.56.1 and, as an ordinary user, on Ubuntu 24.04's git 2.43.0, the VM's; 65 mutations, 64
  caught, 1 equivalent):** the push-side decisions of "Decided for 4.3b" above, as decided (those for 4.4 and 4.5,
  the task's own repository and the trace, are carried in 4.4's "Carried from 4.3b's decisions"):
  - `src/git/run-git.mjs`: the one starter of git, `/usr/bin/git` by its full path, `GIT_DIR` given (but for
    `git init --bare <path>`, which makes it), no hooks, fsmonitor, credential helper or commit-graph,
    `protocol.allow=never`, no system or global config, output and time bounded; a static test holds that no other
    module starts git, and none starts `flock` but `lock.mjs`;
  - `src/process/child-env.mjs` (`childEnv`): every child's environment from an allowlist; a static test holds every
    `node:child_process` call of `src/` to it;
  - `src/git/bundle.mjs`: one reader of bundles, its header parsed by the dispatcher (exactly one prerequisite, the
    commit given, and one ref at the sha given), the bundle's own objects through `git index-pack --strict`, the ref
    descending from the prerequisite (`merge-base --is-ancestor`); 4.4 reuses it with the recorded head;
  - `src/git/config-allowlist.mjs`: the push repository's config equal to a reference `git init --bare`'s by the same
    git, keys and values as a multiset, checked after init and again before the token is asked for;
  - `src/github/push.mjs` (`pushTask`): a fresh push repository per push under `tasks/<runId>/push/`, removed after
    any end; its alternates onto `FACTORY_REPO_DIR`, whose `objects`, `objects/info` and `objects/pack` must be the
    dispatcher's, writable by no one else, with no alternates of their own; the refspec the code's;
  - one rule for the host a credential goes to (`pinnedOrLoopback`, `url-policy.mjs`): GitHub's exact origin, or a
    test's loopback http; the API (`checkApiUrl`, `check-app --api`, `dev-token --api`, the mint, the token source) and
    the push (`gitHost`, held in `gitPushCommand` where the token is handed over) both through it;
  - the repository and the push URL from the adapter; the token source names its repository and `pushTask` refuses
    another; one rule of a task's branch for the push and the CLI;
  - its CI: a job `Test (git 2.43)`, the owner's commits (`ubuntu:24.04` pinned by digest, bash, the whole suite as a
    user that is not root, any git but 2.43 failing it), a required check of `factory`'s `main` since 2026-11-20.
- **Decided while building 4.3b (2026-11-20, the owner, on the plan and the reviews):**
  - `check-app --repository <owner/name>`, required, not `--adapter`: on the VM no adapter is a file until 4.3d. Its
    caller here, `install-builder-app.sh`, passes it when `FACTORY_COMMIT` moves past `factory` PR #16 (#0-277 AC8);
    until then the VM runs the pinned `check-app`;
  - `loadBundle` checks that the ref descends from the prerequisite: a header's prerequisite does not stop a pack
    carrying a history of its own (plan review);
  - the bundle check is `index-pack --strict` on the bundle's own pack, never `fsckObjects` (git 2.43 lets a bad
    commit through a fetch of a bundle; shown again by the job) nor `fsck --full` (it walks `alternates`);
  - the API's host was pinned too (review round 4: the verifier refuted the claim that `checkApiUrl` took only
    GitHub's; it took any https host, so `--api` could send the app's JWT anywhere, a fault older than this step);
  - the tests on git 2.43 run as an ordinary user (root ignores a directory's mode); no test is skipped there;
  - Docker Hub (the job's image) and Ubuntu's archive (its git, through apt's signed index) are sources of
    `factory`'s CI, accepted by the owner (review round 4's `NEEDS_HUMAN`), held in ADR-0060's Consequences.
- **ADRs changed (4.3b):** ADR-0060 D7 amended before the code (#0-276, PR #668); ADR-0060's Consequences amended by
  this step's closing PR (the new sources of `factory`'s CI).
- **Decided for 4.3c with the owner (2026-11-20, `/research` of #0-277 and review round 1 of the decisions, before its
  code; ADR-0062):**
  - **`docker` and `devcontainer` run as `factory`, never as `dispatcher`,** through one sudoers rule
    (`/etc/sudoers.d/factory-dispatcher`, no `.` in the name since `#includedir` skips such a file, 0440, `visudo -c`):
    exactly the two programs by full path, as `factory`, with no prompt (`sudo -n`), `env_reset`, no `setenv`; no rule for
    `factory`. Why not an ACL on the socket: the `devcontainer` CLI would parse the product's configuration and run
    its host side as `dispatcher`, the uid of builder-app's key, and `factory` can restart its daemon or change its
    runtime directory's ACL at any moment. The precedent is `create.sh`'s own `sudo -u factory ... docker`. No secret
    in such a call's arguments, which sudo logs (4.6's token: stdin or the like, decided there).
  - **The work directory lives and dies by one-shot containers** of `factory`'s daemon, the helper image
    `buildpack-deps:noble-scm` (Docker official, git 2.43 and coreutils: probed) pinned by digest: under
    `/home/factory/tasks` (700, `factory`'s), a helper mounting the parent makes `<runId>/`, writes the bundle from
    its stdin to a file (git reads no bundle from a pipe: probed on the VM's git), `git clone -b base` (a bundle of a
    bare sha is empty, one with no `HEAD` checks out nothing: probed), `chown -R -h 1000:1000`; removal is
    `rm -rf <runId>` from the parent (dot entries and the directory itself), at the end and at the next run's start.
    Why: git as a third program would read `factory`'s agent-writable `~/.gitconfig`; the dispatcher has no root to
    `chown`, and outside the user namespace `factory` cannot remove what `dev` wrote; the daemon cannot reach
    `$FACTORY_STATE_DIR`; `rm -rf <dir>/*` (round 1's) leaves `.git` and every dot entry.
  - **One factory checkout, root's:** `/opt/factory-checkout` at `FACTORY_COMMIT` (`root:root`, 0755) by
    `provision.sh`, checked at boot; mounted read-only at `/opt/factory`, and the dispatcher runs from it too. Why: the
    dispatcher's clone under its 0700 home cannot be mounted by the daemon, and a copy of `factory`'s could be rewritten
    by one task's test for the next.
  - **The container's configuration is the dispatcher's, from a task configuration the product ships for it**
    (review round 2): `taskImage` names it (incident-platform's is #0-282), the dispatcher reads it from the base in
    `FACTORY_REPO_DIR` (as data, its own JSONC reader), checks it against a closed list (the build, `remoteUser`, the
    in-container commands; `capAdd` from `NET_ADMIN`/`NET_RAW`; `--add-host` to `host-gateway`; listed `containerEnv`
    keys; features by id and lockfile digest, `docker-outside-of-docker`'s socket accepted by name) and writes the
    override through the helper's stdin; `mounts`, `workspaceMount`, `updateRemoteUserUID: false`, `containerUser` its
    own; anything else refused, `initializeCommand` included. Why: incident-platform's interactive configuration mounts
    the bot's token and Claude's login and carries the bot's environment, and a list over it would put a product's
    needs into the factory's code.
  - **No credential on `factory`'s daemon while the dispatcher runs; the rollback shares the VM by time** (review
    rounds 2 to 5): `rollback-start.sh` refuses while a `factory.task` object exists, labels the rollback's container
    `factory.rollback=1`, and checks again after `up` and before the logins (removing its container if a run began);
    every rollback command goes through the label (`rollback-start.sh`, `rollback-exec.sh`); the dispatcher refuses to
    start while a running container carries that label, makes itself visible (the task's labelled network) and checks
    again before creating the task container, so a rollback still building is seen by one side; a refusal names what
    it found and `cli.mjs sweep`; otherwise its sweep removes everything but
    `factory-dispatcher-m2` (containers, then networks, then volumes, the result checked), the rollback's credential
    volumes, a killed run's leftovers and anonymous volumes included, so each run after a rollback erases its logins.
    Why: a test with the Docker socket mounts any volume of the daemon itself; the Mac's devcontainer (round 1's
    choice) would reopen #0-240 and #0-116; a refusal on "a credential volume exists" (round 2's) never let the sweep
    run (arc-9c51), and one on "a running container without the task's label" (round 3's) took a killed run's
    Testcontainers for a rollback and locked both paths (arc-5e17): a label is positive, never inferred.
  - **The task image in v0 is built on the VM from the product's task configuration** (ADR-0055 until stage C):
    `taskImage` is its path, bounded (no leading `-`, inside the clone); the dispatcher records the built image's ID in
    `task.json` and runs the task's containers from it; the image holds `timeout`. First decided as "by registry
    digest"; corrected the same day before any code (the owner, on the analysis of the environments' VM): an image
    built on the VM has an ID but no registry digest, which comes when CI builds and publishes the image. The ID and the
    helper's digest stop a tag swap and a changed pull, no more: the image store is on the agent's side.
  - **Ends:** a call runs under `timeout -s TERM -k <grace> <limit>` inside the container, since `docker exec` without a
    tty forwards no signal (probed 2026-11-20); past it, `docker kill` by the label `factory.task=<runId>`, the output
    no longer awaited, the task BLOCKED. At the end and at the next run's start every container and network of the
    daemon, every volume but `factory-dispatcher-m2`, and the work directory are removed, in that order, the result
    checked.
  - **The dispatcher runs from the root-owned checkout:** its clone in its home retired, `install-builder-app.sh`'s
    `check-app` path moved, the checkout's fetch root's (stated in `provision.sh`).
  - **`~/.m2` shared in v0**, as proposed above.
- **Tried for 4.3c before its code (2026-11-20, #0-282):** incident-platform's task configuration
  (`.devcontainer/task.json`) brought up on the VM as `factory` with an override of the dispatcher's fields (no
  `/opt/factory`, no per-task `~/.claude`): built, firewall up, only the workspace, `~/.m2` and the feature's socket
  mounted, the configuration directory's lockfile used under `--frozen-lockfile`, one Testcontainers test class green.
  Found: the image's `devcontainer.metadata` label carries the listed feature's whole entry (`id`, `securityOpt`,
  `entrypoint`, the socket mount, `customizations`); ADR-0062 point 4 amended so #0-277's check accepts exactly the
  entry the factory's list holds for that id and lockfile digest, and nothing else (#0-282 "Tried on the VM"). The
  image's sudo rule for the firewall and its unpinned Claude Code reach every task too: #0-283.
- **Not done:** 4.3c, 4.3d; and, from 4.3a's review, `taskImage` bounded, symlinks under the adapter's paths, a
  reason without GitHub's text, resuming by `runId` or one running task at most, a blocked task counted by the
  breaker, a retried mint's leftover token, a script whose last segment is `.`, the item-id format tied to the
  queue's kind, and a check that `gate.schema.json` matches what `run-tests.sh` prints.
- **Not done, from 4.3b's reviews:** a refused bundle's objects left in the repository it was read into; `repoDir`
  bound to the adapter's `repository`; `FACTORY_REPO_DIR`'s loose-object directories and pack files checked, and who
  may write it; `check-app` taking the repository from the adapter once the adapter is a file; the host checked in
  `app-token.mjs`'s request helper, with redirects refused, and `dev-token`'s `mint` and `revokeQuietly` through it;
  the static scans' named bounds and their missing functions; the git 2.43 job's floor of tests; its uid comment;
  one update path for the `ubuntu:24.04` digest kept in two places, and one for the helper image's digest (ADR-0062
  point 8).
- **Why not, from 4.3b's reviews:** the first two matter only for 4.4's long-lived task repository and its caller
  (4.4, "Carried from 4.3b's decisions"); who may write `FACTORY_REPO_DIR` and the adapter's file are 4.3d's (#0-278
  AC7, AC8); the rest is defence in depth behind controls that hold today, an item of its own (#0-281).
- **Why not:** one item at a time (#0-277 next); `taskImage` is read first by 4.3c (#0-277), the adapter's paths by
  4.3d (#0-278), the reason, the resume, the breaker's count, the mint's retries and the running of a command by 4.4's
  flow (its section, "Carried from 4.3a's review"); the item id belongs to the `backlog-md` queue, so it moves with
  the queue's kind before a second product or stage 7 (`migration.md`, stage 7's gap); the gate's schema and its
  producer are two repositories, so their check is an item of its own (#0-280).

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
- **Agents do not commit; the dispatcher does**, after each call that changed the tree, in the task's container
  (its git with the dispatcher's flags, never a git with the dispatcher's rights in the task's clone; each commit read
  back as a bundle and checked against the recorded head: 4.3's "Decided for 4.3b"): `git add -A` and a
  commit whose message comes from the answer, with the `Factory-Run` and `Factory-Agent` trailers (#0-212). So the trace (head before
  and after) is the dispatcher's own, and agents lose git's writing commands (#0-236's forms).
- **Tests:** `test-autopilot-workflow.mjs`'s whole runs against a fake agent, ported to `node:test` with an injected
  `runAgent`; each stop reaches `stopItem` with its stage.
- **Open, to settle by a spike at the start of 4.4:** how `claude -p` runs a named agent of a plugin as its main
  thread (`--agent <name>`, or the definition's body as `--append-system-prompt-file` with its tools and model);
  whether hooks of the plugin run in that mode (they stay a second layer until 6c); what replaces ADR-0058's isolation
  probe (proposal: the init event's agent and tools).

- **Carried from 4.3b's decisions (2026-11-20), to state in this step's item:** the task's own repository under
  `$FACTORY_STATE_DIR` (4.3's "Decided for 4.3b": the one way in from the container) is new here: how it gets the
  base's objects for the first call's bundle (`alternates` onto `FACTORY_REPO_DIR`, as the push repository's), that
  its config is the dispatcher's and held as the push repository's is, and when it is removed; whether a refused
  bundle's objects may stay in it (`loadBundle` indexes the pack before the ref and ancestry checks: harmless for the
  push repository, which is removed) or a scratch repository reads it first; `pushTask`'s first production caller
  binds `repoDir` to the adapter's `repository` (a commit's parent may be anywhere in the alternates) and passes no
  test-only option (the scan's bounds: an options object built elsewhere, a spread, a parameter reassigned).
- **Carried from 4.3a's review (`factory` PR #15), to build here:** a BLOCKED task's `reason` never carries GitHub's
  text into a pull request; a new task refused while one is `running`, or resume by `runId` (a task killed before its
  branch is recorded can be resumed by neither today); `blockTask` counts the block in `state.json`, so an outage
  trips the breaker; a mint retried after a timeout may leave a token unrevoked (it expires within the hour: revoke
  what can be found, or accept it knowingly); a command is spawned with the product's root as `cwd` and its script
  joined to it, and a script whose last segment is `.` is refused. #0-280 (the gate's schema checked against
  `run-tests.sh`) lands before this step first reads a gate's answer.

**Record (4.4):** not started; it waits for 4.3.

## 4.5 Push, PR, trailers and trace

- **Checks before a push (D7), outside the container,** in the push repository after the task's bundle is read into it
  (4.3b), never in the task's clone, the base and the head passed as SHAs; the branch's commits exactly the chain of
  heads 4.4 recorded, each `Factory-Agent` the agent of its call: `merge-base base HEAD` is the recorded
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
- **Backlog edits** (moving the item to `BACKLOG-DONE.md`) stay an agent's file edits, committed by the dispatcher as
  any call's are (in the container, read back as a bundle: 4.4).
- **Tests:** each check refuses its planted case (a merge, a protected path, a missing trailer, a body without
  `Rounds:`); an existing PR is reused, not duplicated.
- **Open:** how a reused draft is retitled (#0-254's case, now the dispatcher's own code).

**Record (4.5):** not started; it waits for 4.4.

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

**Record (4.6):** not started; `FACTORY_PROXY_ADDR` and #0-274 (a narrower egress list) are wanted here.

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

**Record (4.7):** not started.

## Owner's steps, in order

1. ADR-0060 Accepted; `profitbuild/factory` created with its baseline (4.1). Done 2026-11-18.
2. The confinement and the app (4.2b, #0-272), in this order:
   1. the four rulesets and the writers applied (`repository-settings.rb plan`, then `apply`, from the branch just
      before the merge; pull request 1). Done 2026-11-20;
   2. builder-app created and installed on incident-platform (done 2026-11-20); then, from pull request 2's branch (done 2026-11-20, PR #664):
      the VM recreated (`delete.sh`, `create.sh`: Lima reads `provision.sh` only when it creates the VM, and the new
      one adds `dispatcher` and its clone; the bot's token and Claude Code's login are entered again), the key
      generated and `install-builder-app.sh` run, the `factory` ruleset applied, AC6's tries; then the merge.
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
