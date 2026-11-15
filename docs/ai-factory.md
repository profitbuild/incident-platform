# AI factory: runbook

How the autopilot works through `BACKLOG.md` unattended, what the owner does, and how to set it up.
The map of files and who may write them is in `.ai/README.md`; this document is the operating manual.

## In one picture

```
next-item.sh (code: ready follow-up → approved queue .ai/plan/queue.md, strictly in order → priority) → picker
  (checks the item, names the branch's slug; its prefix is the item's Type, from next-item.sh)
  → start-item.sh (code: the branch from the base commit, .ai/work/<item> from the template, the status, one commit)
    (on resume: resume-item.sh switches to the owner's branch before the picker, which only reads)
  → architect (plan, predicted modules, the rules the implementer must have in front of it)
  → implementer (Opus; implementer-light on Sonnet for Complexity: low)
  → self-check: rule files the diff calls for, from which the plan listed no rule → implementer reads and checks them
  → path gate (scripts/factory/changed-paths.sh)                                human-owned path, applied migration, POM supply chain,
                                                                                 build config, deleted/disabled tests, ready flag,
                                                                                 CLAUDE.md outside its blocks → BLOCKED
  → test gate (scripts/factory/run-tests.sh: ./mvnw verify of HEAD, clean tree)  fixable → implementer (≤2) · env failure → BLOCKED
       pass → artifact .ai/runs/<item>/gate-r<round>-<attempt>.json (HEAD, tests and JaCoCo per module, dependency:tree)
       for the reviewers and the acceptance reviewer; an unreadable report → BLOCKED (#0-160)
  → review panel, in parallel: general · architecture · security · performance · docs (+ migration, k8s when touched)
       invalid verdict → BLOCKED (fail closed) · NEEDS_HUMAN → BLOCKED · upheld dispute → BLOCKED
       blocking → implementer → test gate → the reviewers that blocked + security + general, on the delta
       (≤3 rounds) · same findings again → BLOCKED
  → verifier (when the panel approves and left claims unverified; #0-160, ADR-0037)
       gets only the claims, the commit and the gate's artifact, never the diff · reads only the gate's files ·
       WebFetch only https under OSV, GitHub advisories, Maven Central, Tomcat/Spring security pages, no query
       refuted → a blocking finding, back to the implementer (last round → BLOCKED) · unverifiable → BLOCKED,
       the owner accepts the ids they read by resuming with acceptUnverifiable: [ids] · every verdict in the PR
  → acceptance-reviewer        REJECT → one fix → tests → one delta round → acceptance again · NEEDS_HUMAN → BLOCKED (risk-high: owner merges)
  → shipper (outside the loop) PR with the full review record · item moved to BACKLOG-DONE.md · auto-merge only outside shadow mode
  → CI + Factory guards + CODEOWNERS on the PR · Main guard: red main → autopilot-stop issue
```

Every arrow is code in `.claude/workflows/backlog-autopilot.js`; agents do the work, the script decides.
That code is tested without a model (backlog #0-163): `.github/scripts/test-autopilot-workflow.mjs`, in Factory
guards, runs its helpers and whole runs against a fake `agent()` that answers each agent and factory script as a
scenario says, so a branch that stops fail-closed today cannot start letting an item through unnoticed.
A BLOCKED item becomes a draft PR labelled `blocked`, which is also the lock that keeps the picker away
from it.

## Phases

| Phase | What | Done when |
|---|---|---|
| 0 | Prepare items: `/ready #0-N` per item (numbered acceptance criteria, risk, complexity, `ready`) | ~10 items `ready` on `main` |
| 1 | Use the panel by hand: `/review` (same agents and rules as the autopilot; it runs the same test gate on the working tree first) | you trust its findings on your own changes |
| 1b | Plan the order: `/plan-backlog` proposes `.ai/plan/queue.md` (order, Touches, why); you edit and merge it | a queue you agree with is on `main` |
| 2 | **Shadow mode** (default): `/backlog-autopilot` opens PRs, never merges; you merge, and label the bot's PRs from your own account (#0-126) (`human:agree`, `human:fp-<dim>`, `human:missed-<dim>`; optionally `human:introduced-<stage>`) | ~10 PRs, and you agreed with the merge decision in ≥ 9 |
| 3 | Auto-merge, after #0-116 (code an agent runs must not be able to drop the devcontainer's firewall) and the decision on which paths need the owner's review (#0-153: `.dockerignore`, `.ai/context/`, `.ai/decisions/`); #0-113's bot account and rulesets are in place: set `allow_auto_merge` to `true` in `.github/repository-settings/repository.json`, set `required_approving_review_count` to 0 in `rulesets/main.json`, and remove the shadow-mode `*` line of `.github/CODEOWNERS` (#0-153 decides which paths stay owned; a PR touching none then merges on green checks), and `apply` them (Setup step 3), after checking that the bot's token still has no `workflow` scope (`gh auth status` as the bot: with it, the bot could push a workflow whose token reports a required check, ADR-0034), in `.claude/settings.autopilot.json` remove `Bash(gh pr merge *)` from `deny` (keep the `--admin` deny) and add `Bash(gh pr merge * --squash --auto)` to `allow`; run with `{"shadow": false}` | — |
| 4 | Audits every 10 items (the preflight stops with "audit due"): `/audit` runs both targets — `reviewers` (one analyst per dimension) and `pipeline` (backlog #0-121: every case traced from the stage that introduced it to the one that detected it, with why each stage between let it through) — one report each | acceptance of recommendations stays in 40–80% |
| 5 | Later: cloud runs; a stage of the pipeline audit gets its own analyst only when the data shows it produces most of the cases. Never: two items at once (#0-114, decided against) | — |

**Migration (ADR-0055, 2026-11-13).** Phase 3 as written above, auto-merge from today's devcontainer, is not taken:
the factory moves stage by stage to three zones (the owner's Mac, a build VM where only the dispatcher holds a
credential, a review VM), a GitHub Issues queue and a merge by the ruleset alone, with the owner's approval left on the
high-risk lane and a sample after merge. Each stage gets its backlog item when its turn comes; until then this runbook
describes the factory as it runs. Hook hardening that a stage removes is frozen (stage 0: the items marked
`Blocked — superseded by migration stage N`).

## Setup (once)

1. **Devcontainer** (`.devcontainer/`). Docker Desktop: give the VM 16–20 GB (the build VM below runs with 12 GiB, a
   choice ADR-0056 explains), and restrict *Settings →
   Resources → File sharing* to the directory that holds your projects — the container can reach the
   host's Docker (Testcontainers needs it), and whoever controls Docker can mount any shared directory.
   Without an IDE: `npm i -g @devcontainers/cli`, then `devcontainer up --workspace-folder .` and
   `devcontainer exec --workspace-folder . bash` (`.devcontainer/devcontainer-lock.json` pins the
   docker-outside-of-docker feature by digest). Always enter with `devcontainer exec`: the container's
   main process runs as root, so a plain `docker exec` without `-u dev` lands as root. The firewall starts with the container and tests
   itself; `example.com` must be unreachable, and the start log ends with `Firewall up: … IPv6 closed`
   (or `not present`). If its setup fails, it blocks all traffic and says `FIREWALL SETUP FAILED`.
2. **Logins inside the container** (stored in named volumes, so a rebuild keeps them): `claude` (your
   subscription) and the **bot account's** token (#0-113), not yours: `gh auth login --with-token` (paste,
   Enter, Ctrl-D); `git push` uses that token through the credential helper set in the image (no `gh auth
   setup-git`, whose setting a rebuild would lose). The token: a fine-grained one cannot name a repository
   owned by another user's personal account (its "Resource owner" offers only the bot), so it is a
   **classic** token with the `repo` and `read:org` scopes (`gh` refuses a classic token without
   `read:org`; the bot belongs to no organisation, so it reads nothing) and **without** `workflow` (GitHub
   then refuses a push that changes `.github/workflows/`). The bot reaches nothing but this repository, so
   `repo` reaches no further — keep it that way (a classic token follows every repository the bot is later
   invited to). Give the token an expiry (90 days) and replace it before then: a classic token does not
   expire unless told to. The commit identity (the bot and its `…@users.noreply.github.com` address), git's
   trust of `/workspace` and its credential helper come from `devcontainer.json` and the image: nothing to
   set by hand, and a rebuild keeps them. On the bot account, *Settings → Emails → Keep my email addresses
   private* and *Block command line pushes that expose my email* keep a real address out of the history
   even if a commit gets past these variables. You work in the same container as the bot: a commit you make
   there is the bot's too. `.claude/settings.local.json` is personal: its allow rules would merge into the
   autopilot's `dontAsk` session, so the preflight refuses to start while it exists in the workspace (the
   container mounts the same directory). It is gitignored and never committed; keep it out of the workspace
   (rules you want on the host belong in `~/.claude/settings.json` there, which the container does not
   see).
3. **GitHub** (#0-113, ADR-0034): the bot as a collaborator with Write (not Admin); the labels listed in
   #0-113 (created 2026-10-09). The rest is files in `.github/repository-settings/`, never set in the UI:
   the ruleset `main` (a PR with your approval of its last push: `.github/CODEOWNERS` names you for every path
   until phase 3, every CI job and
   "Factory guards" as required checks, no force-push or deletion), the repository settings
   (`delete_branch_on_merge` on, `allow_auto_merge` off until phase 3) and the admins (you alone). The
   ruleset's one bypass is the admin role, at merge only: you merge your own PRs, or a PR whose CI is red for
   an outside reason, with `! gh pr merge <n> --merge --admin --match-head-commit <sha>`, typed by you, with
   the head commit you read (the bypass also skips the review of the last push: without the SHA a commit the
   bot pushed onto your branch afterwards, #0-131, would merge unread). Claude Code sessions are denied the
   bypass, every write to the ruleset and `gh pr review` (an approval of theirs would be yours), since they use your login. To change a setting: edit its file in a
   PR, then with your own (admin) token run `! ruby .github/scripts/repository-settings.rb plan` and `apply` from that branch just before
   merging it; the PR's Lint Workflows checks GitHub against its files and is red until then, and other open
   PRs, checked against main's files, are red from the `apply` to the merge (re-run them after). A setting
   changed in the UI turns every PR's Lint Workflows red. CI's token sees neither the bypass actors, nor the
   repository settings, nor the admins: `ruby .github/scripts/repository-settings.rb check`, run with your
   token, compares those too. The scans' secrets (`SNYK_TOKEN`, `NVD_API_KEY`) live in the environment
   `scans`, which only `main` may use (ADR-0035), never as repository secrets: `apply` creates the environment
   and its branch policy but writes no secret, so you set their values in Settings → Environments → `scans`
   and delete any repository-level copy (Settings → Secrets and variables → Actions); until then `check`
   lists what is left, and a token you replace goes there, not to the repository.
4. **Before the first run**, in an autopilot session, run `/workflow-authoring` and check two things in
   `.claude/workflows/backlog-autopilot.js` (and the same constant in `audit.js`, `docs-audit.js`,
   `seed-bugs.js`): `AGENT_TYPE_OPTION`, the `agent()` option that selects a custom agent (not in the
   public docs we checked), and the call shape of `parallel()` in `runAll()`. The preflight's isolation
   check stops the run if the first is wrong.
5. Optional: export `FACTORY_NTFY_TOPIC` (a long random string) on the host before starting the
   container, for phone notifications; the container passes it on and the firewall then allows the ntfy
   host (`FACTORY_NTFY_SERVER`, default ntfy.sh). Only event names and item/PR numbers are sent.

## Build VM

Stage 2 of ADR-0055 (#0-238, ADR-0056): the same devcontainer, inside a Lima VM on the Mac, so the Docker a test
reaches is the VM's and the repository is a clone of its own, not your checkout. The files are in
`scripts/factory-admin/build-vm/`; the Mac needs Lima (`brew install lima`) and, for `verify-pins.sh`, Docker.
Until AC5 of #0-238 is met the devcontainer on the Mac (Setup above) stays the way back.
The VM's Docker is rootless (ADR-0057, #0-116, #0-240): its daemon runs as `factory`, so root in any container,
the devcontainer's included, is `factory` in the VM, and root's chain `FACTORY-EGRESS` filters everything any uid
from 1000 up sends, `factory` and its subordinate range among them (a copy of the devcontainer's allow-list plus the
VM's own: image registries, Ubuntu's archive; nothing on the Mac, none of the VM's own listeners but the ports Docker
publishes, no IPv6). Every DNS query of those uids goes to the VM's own resolver (dnsmasq,
`factory-dns.service`), which adds the addresses it answers for a listed name, or a subdomain of one, to the filter's
set before the asker gets them: a set resolved every 30 minutes failed the first autopilot run's image pulls on
CloudFront's changing addresses (#0-247). A domain added to or removed from the devcontainer's `init-firewall.sh`
changes the copy in `factory-egress.sh` in `provision.sh` too: Factory guards and `create.sh` refuse the two apart.

1. **Create:** `scripts/factory-admin/build-vm/create.sh`. It refuses an instance that exists (`delete.sh` first),
   downloads Ubuntu's image once (Lima checks the pinned sha256), runs `provision.sh` (Docker CE rootless for user
   `factory`, its egress filter, git, Node at `.node-version`, the devcontainer CLI), checks the boundary (the rootful
   daemon masked, `factory`'s rootless and filtered, the Mac rejected, `example.com` unreachable, GitHub reachable),
   restarts the VM once and checks it again (what holds only on a fresh VM fails there), and clones
   `github.com/profitbuild/incident-platform` (anonymously, while it is public) into
   `/home/factory/incident-platform`, owned by the uid the devcontainer's `dev` maps to under rootless Docker.
   Nothing of the Mac is mounted and no VM port is forwarded to it: `create.sh` checks the started VM and deletes it if
   Lima added a mount, SSH agent or X11 forwarding, a port forward, a network or the Mac's proxy variables (from
   `~/.lima/_config/default.yaml` or `override.yaml`, which Lima merges into every instance: keep both free of those
   keys), or if a check cannot answer; a failure anywhere before the clone is done deletes the VM too. It also refuses a
   copy to the Mac, an extra disk, provision or probe. Run it from an up-to-date `main`: the VM's contents come from
   your checkout's `provision.sh`, its clone from GitHub's `main`, and `create.sh` warns when the two differ. Measured
   2026-11-14: about 65 s from Lima's cache, the reboot included.
2. **Enter**, always as `factory`, the user of the rootless daemon (`docker` needs no `DOCKER_HOST`: the default
   socket is its): `limactl shell factory-build sudo -iu factory`, then `cd incident-platform`. Never `docker` as
   root in the VM (`sudo docker`): `/run/docker.sock` leads to `factory`'s daemon, which code a test runs can replace
   through `factory`'s own systemd unit, so root's client would talk to that code (ADR-0057).
3. **Start the devcontainer:** `devcontainer up --workspace-folder .`, then `devcontainer exec --workspace-folder . bash`;
   the firewall's start log and `example.com` check are as in Setup 1. For phone notifications export
   `FACTORY_NTFY_TOPIC` in the VM's shell before `up` (Setup 5); its host is not in the VM's allow-list: add it to
   `VM_ONLY_DOMAINS` in `provision.sh` (the only list `check-allowlists.sh` lets hold it) in a PR, then recreate the
   VM. Not there by default: ntfy.sh is a publishing service, a channel out for code a test runs.
4. **Check the clone** (#0-202), inside the devcontainer (the clone is `dev`'s, not `factory`'s):
   `git status --ignored --short` prints nothing: no `docker/.env`, no `application-local.yml`, no
   `.claude/settings.local.json` of yours.
5. **Log in inside the devcontainer**, as in Setup 2: `claude` (it prints a URL; open it on the Mac and paste the
   code back) and the bot's token with `gh auth login --with-token`. Both are kept in the devcontainer's volumes,
   on the VM's disk: `delete.sh` removes them with it, and you enter them again after the next `create.sh`.
6. **Run the autopilot** there as in "Running it". Your own sessions stay on the Mac, in your checkout. The local
   model ("Local model" below) is not reached from the VM: `OLLAMA_URL`'s `host.docker.internal` is the VM there, so
   `localReview` reports `Ollama not reachable` and skips (ADR-0056); the VM's filter rejects the Mac (ADR-0057).

**Changing the VM:** its contents only in `provision.sh`, its size or image only in `factory-build.yaml`, then
`delete.sh` and `create.sh`: a VM is recreated, never patched by hand. Every pin is bumped by hand (Renovate does not
read these files) and `verify-pins.sh` must print five `verified:` lines in the same PR:
- the image: the two `images:` lines (Ubuntu's dated directory under `cloud-images.ubuntu.com/releases/noble/` and
  the file's sha256 from its `SHA256SUMS`);
- Node: `NODE_VERSION` and its two sha256 (`linux-arm64`, `linux-x64`, from nodejs.org's `SHASUMS256.txt`), with
  `.node-version` in the same change (`create.sh` refuses the two apart);
- the devcontainer CLI: `DEVCONTAINER_CLI_VERSION` and its sha512 (npm's `dist.integrity`, in hex);
- Docker's apt key: `DOCKER_KEY_FPR`, which changes only when Docker rotates its key, confirmed in three places first;
- Docker CE: `DOCKER_VERSION` and `CONTAINERD_VERSION`, versions of Docker's noble repository
  (`apt-cache madison docker-ce` in the VM lists them).
**Stopping it** (12 GiB of RAM while it runs): `limactl stop factory-build`; `limactl start factory-build` brings it
back with the clone and the logins.

## Running it

```bash
# inside the devcontainer, on a clean main
claude --settings .claude/settings.autopilot.json
> /backlog-autopilot                                   # next ready item, shadow mode
> /backlog-autopilot #0-25                             # a specific item
> /backlog-autopilot #0-25 refactor/0-25-…             # resume after you resolved a BLOCKED item
```

Claude Code hands a workflow the words typed after its command as one string; each workflow reads them in a fixed
order and checks them as it checks the object's fields (backlog #0-175, as `/seed-bugs` since #0-174). A count it
cannot read starts nothing, with the usage. `/backlog-autopilot` takes no word, `#0-N`, or `#0-N <branch>`;
`shadow`, `maxRounds`, `localReview` and `acceptUnverifiable` are object fields only: a word that follows the
command is never one of them, so ask the session in a plain message to run the workflow with the object
(`{"item": "#0-25", "branch": "refactor/0-25-…", "acceptUnverifiable": ["ver-1a2b3c4d"]}`), which it passes to the
Workflow tool as its `args`. `/audit <since> <date> [target]
[dimension…]` (target `all`, the default, `reviewers` or `pipeline`; each dimension one of the panel's) and
`/docs-audit <date>` take dates as `YYYY-MM-DD`.

One item per run. The session settings make it `dontAsk`: everything not allowed is refused, nobody is
asked. `/workflows` shows progress; `p` pauses, `x` stops.

The preflight refuses a run started any other way, before the first agent (backlog #0-194, ADR-0052), and names
what it missed:
- **not in the devcontainer**: `FACTORY_DEVCONTAINER` (its `containerEnv`) is not `1`;
- **not the bot**: `GIT_AUTHOR_NAME`, `GIT_COMMITTER_NAME` or `gh`'s login is not `FACTORY_BOT_LOGIN`, or
  `GIT_AUTHOR_EMAIL` or `GIT_COMMITTER_EMAIL` is not its noreply address (`<id>+<login>@users.noreply.github.com`);
- **no firewall**: `example.com` is not refused: only curl's "could not resolve", "connection refused" and
  "timed out" pass;
- **not this session's settings**: the session's `FACTORY_SETTINGS_SHA256` is unset (started without
  `--settings .claude/settings.autopilot.json`) or is not the hash of `main`'s `settings.autopilot.json` and
  `settings.json`. A session reads its settings once, when it starts: after a change to either reaches `main`, even
  through the preflight's own fast-forward, start a new session. The three limits (`FACTORY_MAX_BLOCKED`, `FACTORY_AUDIT_EVERY`, `FACTORY_MAX_MERGES_PER_DAY`) have no
  default either.

After changing `settings.autopilot.json` or `settings.json`, put the value `scripts/factory/settings-hash.sh` prints
into `settings.autopilot.json`'s `env.FACTORY_SETTINGS_SHA256`; Factory guards ("Autopilot settings carry their hash") fails the PR until you do.
After changing the devcontainer's `containerEnv`, rebuild the container.

A BLOCKED item is resumed with `branch` (and `acceptUnverifiable` for the claims you read), as a new run from a
clean `main`, never with `resumeFromRunId`: the settings allow `Workflow(backlog-autopilot)` by name only, not a
run's saved `scriptPath`, and a run's journal belongs to the session that started it. The new run skips pick, plan
and implement and runs the gate, the panel, the verifier and the shipper again (PR #576, backlog #0-194). The
switch to the branch is code, before the picker (`scripts/factory/resume-item.sh`, backlog #0-215): a branch named as an
item's (`<type>/0-<n>-<slug>`) that exists locally and holds that item's `.ai/work/0-<n>/progress.md`, from a clean
`main` at the base commit. The item is the one the branch names; an `item` that names another is refused before
anything moves.

**Which item.** Code decides, not an agent: `scripts/factory/next-item.sh` reads `BACKLOG.md`,
`BACKLOG-DONE.md` and `.ai/plan/queue.md` on the run's base commit and the open PRs, and takes, in order:

1. a `ready` **follow-up** whose parent is done — work an item showed was needed runs right after it;
2. the **approved queue**, strictly in order: its first row that is not done, if it can start (ready,
   its status Open, dependencies done, no open PR or branch). If it cannot, nothing starts — in shadow mode the autopilot
   waits for your merge of the previous item, so every item is built on code you have reviewed;
3. without a queue file, `ready` items by **priority**.

An item whose `**Touches:**` names a path of `.ai/rules/protected-paths.md` (the one list of what no
agent writes) never starts, whatever its Risk, and `check-queue.sh` refuses to queue it: it could only end
BLOCKED at the implementer, as #0-42 did (backlog #0-122). Make it `human-only` or split it
(`.ai/rules/ready.md` point 3). A bare `ci` in Touches counts as protected: name the path in the
parentheses. The autopilot's deny rules, its shell-write hook and CODEOWNERS keep literal copies of that
list; the "Factory guards" check fails when one stops covering it.

`/backlog-autopilot #0-25` (or `{"item": "#0-25"}`) overrides the choice (the item still has to be ready, unblocked and unlocked). When
nothing can start, the run ends with `NOTHING_TO_DO` and names the row and why.

**Which rules the implementer reads.** The panel judges every change against the full files of
`.ai/rules/review/` (but `factory.md`, the rules for the factory itself: security and architecture read it only
when a diff touches an Owner-only path of `protected-paths.md`, which no autopilot item does — in practice the
owner's `/review`, backlog #0-161). The implementer reads `general.md`, `architecture.md` and `security.md` in full for
every item; from `performance.md`, `migration.md`, `k8s.md` and `docs.md` it reads the rules the architect
listed in the plan, each with why it applies. After implementing, `changed-paths.sh` maps the diff onto
rule files (a migration → `migration.md`, a Kafka listener or a repository → `performance.md`, an endpoint
or a `.md` → `docs.md`, a manifest or POM → `k8s.md`); a file from which the plan listed no rule sends
the implementer back to read it in full and check its change (`self-check`) before the panel sees it.
This runs once, after implementing; later fix rounds are judged by the panel. A
missed rule then costs a self-check, not a review round; the PR records which rules were planned and
which self-check ran, and the audit counts selection misses (`.ai/rules/audit.md`).

**Which implementer.** `Complexity: low` items go to `implementer-light` (the same definition, on
Sonnet), the rest to `implementer` (Opus) — the implementer is the most expensive agent of a run. A
light implementer that finds the item is not small stops it, so you can re-rate it.

## Planning the order

`/plan-backlog` (interactive, in your normal session) asks the `planner` agent for a queue: the items in
order, a `**Touches:**` line per item (modules and packages it will change, found in the code), the
reasoning per item, and what was left out and why. `scripts/factory/check-queue.sh` rejects an
inconsistent proposal (a dependency queued after its dependant, a human-only or design item, an unknown
module); the skill shows you the table, applies your
changes, and commits it on a `plan/<date>` branch. **Your merge is the approval**; the queue is
human-owned like `.ai/rules/` (CODEOWNERS, denied to the autopilot), and CI re-checks it on every PR.
Rules: `.ai/rules/planning.md`.

**Scope that grows.** An implementer that finds more work than the item planned finishes the item and
describes the rest under "Follow-up needed" in its handoff; the shipper adds each as a backlog item with
`**Autopilot:** proposed` and `**Follow-up of:**` in the same PR, and you get a notification. `/ready` it
and merge: once its parent is merged too, it runs next. Work without which the item itself cannot pass
stops the item (BLOCKED) instead.

**Scope, measured three times.** Each PR shows "Scope": the item's Touches (predicted at `/ready`), the
architect's modules (predicted just before implementing) and the areas the diff reached, with a
category — `consistent`, `backlog-estimate-off`, `plan-off`, `implementation-drift`, `unclear-item`
(`.ai/rules/audit.md` explains each). A prediction holds when the diff stays within it; which one failed
says which stage was off. Nothing is blocked on it. Touches is an experiment with
an exit criterion (`.ai/rules/planning.md`): if it never teaches anything, it goes.

**Stopping it**: create `.ai/STOP` (local), or open an issue labelled `autopilot-stop` (works from a
phone). The preflight also refuses to start when: main's CI is red (the latest run of a push to main; a
fork pull request's run from a branch named `main` does not count, backlog #0-148), the working tree is
dirty, 2 items in a row were BLOCKED, an audit is due, the daily merge limit (5) is reached, another run
holds the lock (`scripts/factory/state.sh unlock` clears a stale one), or Claude Code is older than 2.1.295
(the hooks' `onFailure: "block"`, backlog #0-162, ADR-0039).

The breaker and the audit counter are reset only by the owner, outside the autopilot session (which may
not run `scripts/factory-admin/`): after resolving the BLOCKED items, delete `.ai/STOP` and run
`scripts/factory-admin/state-reset.sh blocked`; after an audit, `/apply-audit` runs
`scripts/factory-admin/state-reset.sh audit`. The run state lives in `.ai/runs/` (gitignored): `LOCK`
holds the run id, the base commit every gate compares against and the run's branch, the only one the
autopilot may push (#0-131), `state.json` the counters and the
history (for a BLOCKED item also its draft PR and the phase that stopped it, which the audit reads).

## The owner's routine

| When | What | Time |
|---|---|---|
| per new item | `/ready #0-N`: confirm criteria, risk, complexity, Touches; merge the backlog change | 5 min |
| per follow-up | a PR created `proposed` items: `/ready` the ones you want next, delete or re-plan the others | 5 min |
| when the queue is done, or every ~10 items | `/plan-backlog`, edit, merge | 15–20 min |
| daily, in shadow mode | review and merge the autopilot's PRs; **label each one** `human:*` from your own account (see below) | 10–20 min |
| when it happens | BLOCKED draft PRs: decide, fix or split, then resume with `branch` | 5–20 min |
| every 10 items | `/audit <since> <date>`, tick decisions in the report, `/apply-audit <report>`, merge its PR | 20–30 min |
| every 10–15 items | `/docs-audit <date>`; look at the architecture as a whole (what no single review sees) | ~1 h |
| sometimes | do an item yourself, then `/review` and `/ship` — the knowledge should end up in you, not only in the repository | — |

Spot checks must be real (read the diff, run the tests), or the `human:*` labels measure nothing.
Add the labels from your own GitHub account: the audits count a `human:*` label only when the owner (the one
admin of `.github/repository-settings/repository.json`, backlog #0-237) added it (backlog #0-126) — one added by the bot counts for nothing, and while the autopilot runs on your own login
(shadow mode before the bot account) no label counts at all, since the autopilot then acts with your token. To
confirm a label someone else added, remove it and add it again yourself.

## What isolates what

The agents' instructions are not a boundary; these are, each with its limit:

| Layer | Stops | Does not stop |
|---|---|---|
| `dontAsk` + deny rules (`settings.autopilot.json`) | file-tool writes to human-owned paths and to the gates' own files; WebSearch, and WebFetch beyond the verifier's six hosts; force pushes, merges, `gh api` | what a shell command does indirectly — hence the hooks; which agent fetches, and which path of an allowed host: a rule matches the host only, for every agent |
| Hooks (`.claude/hooks/`, tested by `test-hooks.sh`) | skipped verification, `exec:` goals, shell writes to protected paths, file-tool writes outside the repository (and `..` or a symlink as the last component), any `git grep` option outside an allow-list (abbreviated, quoted or expanded forms included), a line continuation (backslash-newline) in any command, pushes other than the run's own branch (recorded in `.ai/runs/LOCK`, #0-131), running tampered factory scripts, secret reads, an architect's commit other than `-m "<subject>"` with the attribution trailer (no `-F`, which would put any file it can read into a message the shipper pushes, #0-203), a command an implementer runs in the background (its turns are its budget, #0-206); WebFetch by any agent but the verifier, and by the verifier outside its path prefixes or with a query string (`webfetch-allowlist.sh`, on `agent_type`, #0-160; in the owner's sessions, `--interactive`, only the verifier's fetches are checked); each agent's read-only or write-scoped guard both in its frontmatter and as a twin in both settings files on `agent_type` (#0-164, ADR-0041), so a Workflow's agent keeps it even if Claude Code stops running frontmatter hooks for it | a shell command shaped to get past a pattern: they are heuristics; a twin when Claude Code sends no `agent_type` (the frontmatter hook stays for that); data in a URL path to an allowed host (the verifier reads only the gate's artifacts in `.ai/runs/`, so it has little to send) |
| Gates on commits (`changed-paths.sh` before review, CI "Factory guards" on the PR) | the same changes once committed, whatever produced them | — the PR is the last and most reliable line |
| The ruleset of `main` (#0-113, ADR-0034, `.github/repository-settings/`) | a push to `main` without a PR (anyone's), a merge with a red or missing required check, without an approval of the last push, or of a code owner's path without the owner's (anyone's but the owner's) | the owner's token can merge any PR (the admin role's bypass, at merge; Claude Code sessions are denied it); a bypass actor or an admin added in the UI is seen only when the owner runs `repository-settings.rb check` |
| Devcontainer + firewall | the agents' own commands: access to your host account, files and credentials; network beyond Anthropic, GitHub, Maven Central and the verifier's advisory hosts (OSV, Tomcat, Spring: open to the whole container, by IP, so also to other sites a CDN serves from those IPs) (IPv4; IPv6 only loopback; a failed setup blocks everything) | **code an agent runs** (a test): Testcontainers needs the host's Docker, and Docker access is root over the devcontainer itself, so such code can drop the firewall, start a container outside it, or read files the agents' tools may not (#0-116, accepted for shadow mode only); data through DNS the resolver forwards; GitHub itself as a channel |
| Build VM (`factory-build`, Lima, ADR-0056 and ADR-0057; when the autopilot runs there, "Build VM") | the reach of that code to the Mac's files, the VM and the network: the Docker it uses is rootless, so root in any container it starts is the unprivileged `factory` in the VM (no change to the VM's firewall, `/etc` or root's files), and root's `FACTORY-EGRESS` lets every uid from 1000 up (`factory`, its subordinate range) reach only the VM's own resolver, the ports Docker publishes on the VM's address and an allow-list of names (with their subdomains; no private, shared or loopback network), whose addresses the resolver adds as it answers them (#0-247): not the Mac (its loopback services, #0-240), not the VM's network, not a host outside the list, with `--network host` either; the VM mounts nothing of the Mac and holds a clone of its own (#0-202) | what `factory` holds: the devcontainer's volumes with the bot's token and Claude Code's login (stage 4 of ADR-0055); data through DNS, and through any site a shared front end in the list serves (Cloudflare, CloudFront: Docker Hub, download.docker.com, downloads.claude.ai), and the registries that take a push with the pusher's own credentials (Docker Hub, ghcr.io), as for the devcontainer's advisory hosts; a listed name allows its subdomains too; a flaw in the resolver, which holds `CAP_NET_ADMIN`, would reach the chain (ADR-0057) |

## Measuring the reviewers and the pipeline

- **Owner labels** on PRs are the ground truth the audit needs, counted only when the owner added them (#0-126,
  above); without them confidence stays `medium`
  and security/architecture rules can never be relaxed. `human:introduced-<stage>` (optional) confirms or
  corrects where the pipeline audit says a case started.
- **Pipeline cases** are derived by `scripts/factory/audit-data.sh` from what the pipeline records (BLOCKED,
  extra rounds, scope off, acceptance, owner labels, BLOCKED runs without a PR) — nobody logs them by hand.
- **Seeded defects**: `/seed-bugs P-01 <merged sha> <run id>` (or args `{"pattern": "P-01", "commit": "<merged
  sha>", "runId": "<id>"}`; the command passes its words as one string, #0-174; a session runs the version of the
  workflow it loaded at its start, so after a change to `seed-bugs.js` start a new session, or pass the file as
  `scriptPath`) plants a known defect from
  `.ai/audit/benchmark/patterns.md` on a throwaway branch, has all seven reviewers review it (k8s since #0-115's
  `k8s.md`) and records who caught it in the gitignored
  `.ai/runs/benchmark/results.md` (`scripts/factory/seed-record.sh`). Start it from a clean `main` at `origin/main`, with no
  autopilot run: `scripts/factory/seed-branch.sh` builds the branch from `main` (the change's code reverted as its base,
  then back), never from the merged commit, whose hooks and agents the session would otherwise run on (#0-173,
  ADR-0044). Choose a host that passes both of its refusals: its code still reverts on `main` (`git diff --binary
  <parent> <sha> -- <code> | git apply -R --check`) and none of its files is the evaluator's (a protected path or
  `CLAUDE.md`). The seeder commits nothing (#0-172, ADR-0047): its Bash is read-only git (`readonly-bash.sh`) and its
  Edit reaches only the change's files (`write-scope.sh --seed`, from the run's record `.ai/runs/SEED`, which also gives
  `guard-migrations.sh` the run's base, so a migration the change added can be planted in). `scripts/factory/seed-check.sh`
  confirms the tree after the seeder (on the branch at the change's commit, its edit uncommitted and in the change's
  files only, and its rule and dimension its pattern's row of `patterns.md` on `origin/main`, #0-180; it returns the
  edit's hunks, the run's ground truth, with at most two unedited places the seeder names, #0-181), and
  `scripts/factory/seed-fold.sh` makes the change and the edit one commit before the panel runs. Then
  `scripts/factory/seed-compile.sh` compiles the modules the edit reaches, offline, with their tests (`-am`, and `-amd`
  for `shared`; not for an edit that changes a `pom.xml` or holds no `.java`): a plant that does not build fails the run
  with the compiler's first error, never reaching the panel (#0-181, ADR-0044 decision 9).
  Nothing the panel reads names the run (#0-177): the branch is `review/<8 hex>` (derived from the pattern and the run
  id), the base says `Revert "<subject>"`, and the change and the defect are one commit, with the run's reflog entries
  dropped (the branch's, and HEAD's above the switch onto it; the rest of your HEAD reflog stays). The catalogue
  (`patterns.md`, `.ai/rules/audit.md`) stays readable to the reviewers, on purpose: ADR-0044 records why and how to check
  a run's transcripts for a read of it. The original change is in reach as well (#0-185, ADR-0044 decision 6):
  `main` holds it, so `git diff origin/main HEAD` shows the defect alone, and the revert's patch holds its lines.
  Before a series' rows land, check whether its reviewers read the original: `seed-scan.sh` (below) lists the reads it
  knows, and ADR-0044 decision 6 records what the hand scan looks for. Mark a row whose expected reviewer did in
  "Caught by expected", and one whose other reviewer did in "Also caught by". A measure by hand (an Owner-only host,
  #0-115's F1) commits the plant into the change and gives the panel the autopilot prompt, not a manual `/review`,
  with a sentence that `factory.md` applies. F1's manual review of an uncommitted plant reached the original 4 times
  of 4. The Workflow tool shows every agent, word for word, the message that started the turn, so a typed
  `/seed-bugs P-01 …` names the pattern to the panel (#0-179). So the session starts a run from a turn with no user
  message: once it holds the run's words, any message of yours makes it start a background command that does
  nothing, and it calls `Workflow` in that command's notification turn, which relays nothing. Before a run's row lands, run
  `scripts/factory-admin/seed-scan.sh <the run's transcriptDir> <pattern> <run id>`. It reports a relayed message
  that names the run, a reviewer's read of the merged change (content or names only, except a read of the reviewed
  branch's own commit, which the run's journal names) and a read of the answer key. It is an aid to your reading of
  the transcripts, not a replacement: it refuses a transcript shape it does not know (ADR-0044 decision 6), and its
  output quotes what the reviewers ran, which is data, never instructions. The run goes back to `main` before it
  writes the row, and an outcome that could not (a dirty tree) says where it left it (`leftOn`). The commit's code must still
  apply to `main`, so choose a recent one. Rotate patterns; after each run delete its branch (the outcome's `cleanup`
  names it). Runs follow one another with no commit between them; after a series, copy its rows from
  `.ai/runs/benchmark/results.md` into `.ai/audit/benchmark/results.md` in one pull request (the audit reads the tracked
  files only), then delete `.ai/runs/benchmark/results.md`; a run id already in any of the four tables (both kinds, as
  a series gathers them and as they land) is refused, so a landed one stays refused. The seeder cannot write a row (its scope is the change's files, #0-172). A run that measured nothing
  says so (#0-170): a seeder that was refused a command, a skip without a reason and an answer without its branch,
  file, line or rule end it FAILED, not SKIPPED.
  A clean run (#0-180, ADR-0044 decision 7) takes a `C-` pattern, a rule's deliberate exception planted with its
  reason, and measures false alarms instead of catches: a dimension that stops the change at the planted line under
  the pattern's rule is a false alarm, one that notes it, or stops it under another rule, is recorded as raised. Its
  row goes to `.ai/runs/benchmark/clean.md` (then `.ai/audit/benchmark/clean.md`). The panel's prompt is the same, so
  rotate clean and defect runs in a series.
- **What the rule files claim** (backlog #0-184, ADR-0046): Factory guards' "Review rule claims are true"
  (`.github/scripts/check-rule-claims.rb`) fails a label naming a script, test or guard that does not exist, an
  "Enforced by" whose check runs in no required job on a pull request, only while continuing on error or only in
  the owner's step (it is then at most "Backed by"), a rule file other than `factory.md` naming the measure (`benchmark`, `seeded`, `seeder`,
  `/seed-bugs`, `patterns.md`, a pattern id; ADR-0044), and a pattern citing a missing or retired id of its
  dimension's file (`FAC-S` is security's, `FAC-A` architecture's). It reads backticked names only: a label's
  plain words, and a synonym of the measure, are still the reviewer's and the owner's to see.
- **Escaped defects**: an item that fixes a defect an earlier item introduced carries
  `**Fixes:** #0-N · **Escaped from:** <stage>` — `review-<dimension>` when the panel missed it, or the pipeline
  stage that let it in (BACKLOG.md conventions); the pipeline audit counts the markers added in its period. A
  marker counts only when it reached `main` in a PR the owner opened (#0-129; the others are listed as
  `unverifiedEscapes`), so add it on your own branch, not through an autopilot PR; Factory guards fails a marker
  without its `**Fixes:** #0-<digits>` part (#0-128).

## Pinned versions

Agent models are full ids in `.claude/agents/*.md`; Claude Code is pinned to the version the
devcontainer image was built with (`DISABLE_AUTOUPDATER=1`). The preflight refuses one older than 2.1.295, the
first that honours the hooks' `onFailure: "block"` (an older one ignores the field silently, ADR-0039). The devcontainer's docker-outside-of-docker
feature is pinned by digest in `.devcontainer/devcontainer-lock.json` (`devcontainer upgrade` moves it).
Treat an upgrade of any of them like a dependency
upgrade: change it on purpose, then run a few seeded defects and compare `results.md` before trusting it.

## Local model (experimental, optional)

`scripts/factory/local-review.sh` (advisory second opinion in the PR, never blocks; the autopilot runs
it with `{"localReview": true}`) and `scripts/factory-admin/local-implement.sh` (you run it by hand, for a
`Complexity: low` item while your limit is exhausted; the branch stays local and is reviewed later by the
normal panel with `/backlog-autopilot #0-N <branch>`). Both point Claude Code at Ollama on the host (`OLLAMA_URL`). Measure first: with the test stack running, a 27B model may not fit
next to it in 32 GB.

## Cloud (later)

Everything is files in the repository, so the same setup can run elsewhere: Claude Code routines (check
first that the cloud environment can run Docker for Testcontainers) or GitHub Actions with this
devcontainer image. Check the current rules for subscription usage of non-interactive runs before
moving, and keep `--settings .claude/settings.autopilot.json` wherever it runs. ADR-0055 makes this stage C of the
migration: the build and review VMs move to a cloud provider (its firewall outside the VM), provisioned from the same
file as the local VM (`provision.sh`, taken as cloud-init user-data, ADR-0056), with a heartbeat and cost and token budgets.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `NOT_STARTED: agent isolation check failed: the reviewer can edit files` (or `did not list its tools`) | `AGENT_TYPE_OPTION` is wrong: reviewers ran as general-purpose agents (or the answer was malformed: run again) |
| `NOT_STARTED: agent isolation check failed: the reviewer's instructions are not review-general's` | `AGENT_TYPE_OPTION` is wrong, or `REVIEW_GENERAL_OPENING` in the workflow no longer opens `.claude/agents/review-general.md` (its test says which) (#0-248) |
| a resumed run stops at the pick: `no local branch <branch> to resume` | the branch is only on origin (a new VM's clone has `main` alone): in the devcontainer, `git fetch origin <branch>:<branch>` on `main`, then resume |
| `NOT_STARTED: label '…' does not exist` | create the labels of #0-113 |
| a hook says "factory scripts were changed on this branch" | `scripts/factory/` differs from the base commit in `.ai/runs/LOCK` (or `origin/main` without a run) — either the branch touched it (owner's decision) or `main` moved on: rebase the branch by hand |
| every run `BLOCKED: test environment failure` | Docker not reachable from the container, or the firewall blocks Maven Central |
| `permission denied while trying to connect to the docker API` inside the container | the container's main process must run as root (`"containerUser": "root"` in `devcontainer.json`) for the docker-outside-of-docker feature to proxy the socket to `dev`; rebuild with `devcontainer up --workspace-folder . --remove-existing-container` |
| `mkdir: cannot create directory '/home/dev/.m2/wrapper': Permission denied` (or `gh` cannot store its login) | a volume created before the image made its mount point, so it is root's: remove it if it is empty (`docker volume rm incident-platform-m2` / `incident-platform-gh`) and start the container again; to keep its contents (a Maven cache, a login), give it to `dev` instead: `docker run --rm -v incident-platform-m2:/v alpine chown -R 1000:1000 /v` |
| `FIREWALL SETUP FAILED: all traffic is blocked` at container start | a required domain did not resolve or GitHub's IP ranges could not be fetched; the message above it names the cause. Fix it and restart the container (an optional domain only warns) |
| a reviewer "returned no valid verdict" | it answered prose instead of JSON; check its transcript; repeated → audit finding |
| `BLOCKED: <agent> gave no answer (last agent call without an answer: <agent>: …)` | the agent ended without its JSON, usually its `maxTurns` spent (#0-206): the item is stopped like any block (draft PR when the run has a branch, state recorded with the stage, notification). Read its transcript for where the turns went, often refused commands (a hook names what to use instead); resume the branch once fixed |
| `BLOCKED: picker failed: …` | a command of the picker was refused or failed (#0-206), not an empty queue: the reason quotes it. The picker creates no branch since #0-209; were one named anyway, the reason says so (`next-item.sh` skips the item while that branch exists: delete it, or resume it with `branch`). On resume the item is the one the branch names, so the stop is recorded against it |
| `BLOCKED: could not resume #0-N on <branch>: …` | `resume-item.sh` refused to switch to the branch (#0-215): the reason quotes it (a tree that is not a clean main at the base commit, no local branch of that name, a branch holding no `.ai/work/0-N/progress.md`). It changes nothing: the tree stays on main and the branch as it was. `…: no answer` means factory-ops ended without the script's answer: check `git status -sb` |
| `BLOCKED: could not start #0-N on <branch>: …` | `start-item.sh` refused to start the item (#0-209): the reason quotes it (a tree that is not a clean main at the base commit, a branch or `.ai/work/<item>` that exists, an item not `ready` or not `Open` on the base commit). It leaves no branch and no work directory behind, so once the cause is gone the next run can take the item again; if its own cleanup failed, the reason names the branch left. `could not start …: no answer` is the exception: factory-ops ended without the script's answer (killed, out of turns), and a branch it may have made is left: check `git branch --list '*/0-N-*'` |
| `NOTHING_TO_DO` | the reason names the next queue row and why it cannot start: not `ready` on main, a dependency not done, a path the autopilot may not write ("make it human-only or split it"), or an open PR/branch (a lock — usually the previous item waiting for your merge). "The approved queue is done" → `/plan-backlog` |
| `NOT_STARTED: the queue on main is invalid` | a merged change broke `.ai/plan/queue.md` (e.g. an item it lists was removed); `scripts/factory/check-queue.sh` names the rows — fix them or re-plan |
| a hook blocks a legitimate command | read the hook's message; the hooks are tested by `.claude/hooks/test-hooks.sh` — fix the hook and its test together |
| an agent spends its turns on refused calls (`dontAsk`) | it composed a command its definition does not name (a pipe to cut output, `cat`, `sed -i`, an absolute path): the definition's "How commands run here" and its marked command list name the allowed forms, and Factory guards (`check-agent-commands.rb`, #0-207) checks each against the hooks and the allow rules; add a form the agent really needs to the list; if no rule matches it, a new allow rule in `settings.autopilot.json` is the owner's change (an Owner-only file, judged by FAC-S03), never a session's |
