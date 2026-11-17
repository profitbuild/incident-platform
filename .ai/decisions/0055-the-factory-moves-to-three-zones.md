# ADR-0055: The factory moves to three zones, a GitHub queue and a ruleset merge, one stage at a time

- **Status:** Accepted (2026-11-13, by the owner, with the amendment of #0-237: the factory as a product of its own,
  stages T and N); amended by ADR-0056 (2026-11-14: the portable part of the VM is one provision script, not raw
  cloud-init user-data); amended 2026-11-17 by the owner (stage 3: the baseline from stage 2's transcripts, #0-205;
  #0-204 moves to stage 4)
- **Backlog:** stage 0 of this migration (the freeze below); each later stage gets its own item when its turn comes
  (stage 1: #0-237)
- **Date:** 2026-11-13
- **Author:** human (owner's decisions of 2026-11-13, drafted in an interactive session)
- **Reversible:** yes, stage by stage — every stage names its rollback, and one that needs more than a switch or a
  `git revert` is split

## Context

The factory runs as one Claude Code session in a devcontainer on the owner's Mac. Its boundary is text: hooks that
match the commands an agent writes (`guard-protected-bash.sh`, `readonly-bash.sh`, `write-scope.sh`,
`factory-ops-bash.sh`) and a `dontAsk` allow list. Each hardening item showed the same limit: #0-235 needed four review
rounds, each finding another spelling past the match (`git add -f`, an edited `.gitignore`, `.//.ai`,
`--output=.ai/runs//LOCK`, a quoted subcommand), and #0-236 records that the run state sits in the working tree every
allowed git command acts on. Code run through `./mvnw` reaches everything (#0-116), and the owner approves every PR.

The owner wants an autonomous factory with a human only where the risk is (high-risk lanes, intent, rules, a sample
after merge). Companies that publish how they do this (Stripe's devboxes, Ramp's sandboxes, Anthropic's Claude Code
sandbox) isolate each task in a fresh environment and keep credentials out of it; Claude Code's own documentation calls
argument-constraining Bash rules fragile and the sandbox the stronger layer.

incident-platform is the factory's proving ground, not its only product (owner, 2026-11-13): the factory is to build a
second application from nothing, a Java and Spring Boot backend with a React frontend, alongside this one. A factory
whose code, rules and gate know this repository's modules, tenants and Kafka topics would have to be copied for it, and
two copies drift (the three copies of the protected paths needed a check of their own, #0-168).

## Decision

**Target.**
- **Three zones, cut by trust and credentials, not by agent count.** The owner's Mac (the owner, a Backlog Creator,
  `/human-review` in a read-only fresh clone); a build VM, the only place where code an agent wrote runs (a dispatcher
  script holds the builder's credential; the implementer works in a fresh devcontainer per task with no GitHub
  credential); a review VM without Docker or Maven (panel, verifier, acceptance; it reads CI's artifacts, never the
  build VM's local gate).
- **Identities.** The owner; `bc-app`, `builder-app` and `review-app`, three GitHub Apps (short-lived installation
  tokens bound to the repositories each is installed on; the builder is an App, not the `lukaszplawiakbot` PAT); GitHub's ruleset is the only
  one that merges (required checks pinned to their app, `factory/review` from review-app, CODEOWNERS and
  `factory/human-gate` on the high-risk lane). No agent approves or merges. **No status the ruleset requires is set
  with builder-app's credential:** `factory/lane`, `factory-trace` and `factory/human-gate` come from GitHub Actions, and
  `factory/review` from review-app, each pinned to its app in the ruleset. builder-app's credential sits on the build
  VM, where agent-written code runs with Docker (root), so a status it could set is one an escaped test could set on its
  own PR (security review of this ADR, round 1).
- **Dispatchers are scripts, not agents.** They choose work, claim and lease, start and remove containers, check the
  result, push, open the PR and set statuses; agents plan, write code and review, and hold no token. One dispatcher per
  zone, so a claim needs no compare-and-swap (a local `flock`).
- **The queue is GitHub Issues + one Project**: `Feature` issues hold a brief, `Task` sub-issues are the work, native
  blocked-by dependencies, fields for status, risk, complexity and lease. `BACKLOG.md` and `BACKLOG-DONE.md` freeze as an
  archive once the queue moves.
- **The audit record stays in the repository.** Escape markers (`**Fixes:**` / `**Escaped from:**`), decision history and
  the owner's audit decisions stay in files changed only by the owner's PRs (ADRs, `.ai/audit/`): an issue's text can be
  edited by apps and leaves no history git keeps, so issues hold work state only (#0-129, #0-126 stay the model).
- **The factory is a product of its own, apart from the products it builds.** One organisation, `profitbuild`, holds
  the factory and its products; incident-platform moves into it in stage 1 (its Angular frontend stays on the owner's
  account, outside the factory). From stage 4 the factory's code lives in its own repository, `factory`: dispatchers,
  VM provisioning, the base task image, agent definitions, skills, the hooks that survive 6c, the review rules' core and
  one profile per stack (`spring-boot`, later `react`), the template of a product repository, and the ADRs about the
  factory written from then on (ADR-0050 to ADR-0055 stay where they were decided). A product repository holds only its
  adapter: its `CLAUDE.md` and `.ai/` knowledge, its own review rules (here: tenants, Kafka, outbox), a gate script
  with the one contract every gate keeps (the JSON of `run-tests.sh` today: `pass`, `fixable` or `stop` and an
  artifact), its task image, its protected paths, and the factory version and profile it runs, pinned and bumped by
  Renovate in a pull request the owner reviews. **builder-app is never installed on `factory`**: no agent can change
  its own rules, reviewers or dispatcher, by permission rather than by a hook's text match; `factory` is the
  organisation's most protected repository. How a product session loads the factory's agents and skills (a Claude Code
  plugin from `factory` is the first candidate) is decided in stage 4.
- **A new product starts with a foundation the owner leads.** Its first decisions (domain model, service boundaries,
  authentication, schema, frontend structure, the API contract) are irreversible, the kind the architect stops on;
  the owner makes them in interactive sessions, as ADRs, with a walking skeleton (one endpoint through every layer, one
  screen, CI green). The factory takes items once that skeleton exists. The new application is one repository
  (`backend/` and `frontend/`): a change to the API is one pull request and one review, not an order kept between two
  repositories.
- **Local first, portable from the first VM**: the VM is provisioned as code (cloud-init, which Lima and a cloud provider
  both read; amended by ADR-0056: Lima reads no raw user-data, so the portable part is one provision script, which Lima
  runs as a provision and a cloud VM takes as its user-data); the task image is built in CI and pulled from GHCR; dispatchers read their configuration from the
  environment only and keep no state of their own (it is in GitHub); logs and transcripts leave the machine. The move to
  a cloud VM, where the provider's firewall sits outside the VM, is its own stage.

**Stages**, each tested on real items of the application before the next starts; an item is created for a stage when
its turn comes:

| # | Stage | Exit | Rollback |
|---|---|---|---|
| 0 | Freeze hook hardening (below) | this ADR merged and set to Accepted by the owner | revert the statuses |
| 1 | Organisation `profitbuild`, incident-platform transferred (its frontend not); the owner read from `repository.json`, not the repository's owner (#0-237); `repository-settings.rb check` | one item merged the usual way | transfer back |
| 2 | Build VM (provisioned as code) running today's devcontainer | 3 items with no environment problem | the devcontainer on the Mac |
| 3 | Baseline metrics: agent calls, times, tokens, model, tools, refusals per agent call, from the runs' transcripts, kept off the build VM (#0-205; amended 2026-11-17: from stage 2's three runs, no new runs of the old path; #0-204's per-call commit trace moves to stage 4, where the dispatcher records it); a seed pattern for a removed positive control (PR #572; the next free id after #0-218's P-25 and P-26) | numbers for 3 items | revert |
| 4 | Dispatcher v0, in the new `factory` repository: the container has no token; push, PR and commit trailers by the dispatcher (#0-212), the trace of each agent call (#0-204) and its transcripts' summary (#0-205's script); builder-app (not on `factory`); the gate contract, incident-platform's adapter the first | 3 PRs opened by it | `shipBy: shipper` |
| 5 | review-app and the review VM, in shadow, then required; the review rules split into the factory's core, the `spring-boot` profile and the product's own | a `/seed-bugs` series on the new path catches at least what the old one did | drop the required check |
| 6a | `factory/lane`, `factory-trace`, `factory/human-gate`, CODEOWNERS (#0-153), `/human-review`; not required at first | lane agrees with the owner on 3 PRs | not required |
| 6b | Deterministic gates one at a time (#0-108 ArchUnit, Squawk, commitlint, TODO); each removes its rule from the prompts | each catches its seeded case | revert that gate |
| 7 | Issues + Project, all open items at once; dispatcher v1 reads the Project | 3 items taken, claimed and closed | export, switch back to the frozen file |
| T | Template of a product repository and its bootstrap: the baseline (ruleset, CODEOWNERS, protected paths, pinned tools, Renovate, secret scan, `repository-settings`) applied to a new repository in one command | a new empty repository passes `repository-settings.rb check` and Factory guards | delete the repository |
| 8 | Backlog Creator and features (sub-issues, flags), on a technical feature | one feature Done | tasks written by hand |
| N | The new application: its foundation led by the owner (may run from stage 2 on, it needs no factory), then onboarded from the template with the `react` profile | one backend and one frontend task through the factory, while incident-platform's run too | the owner's sessions only |
| 6c | Hook cleanup (after 8): boundary hooks removed; quality hooks (`guard-tests`, `guard-migrations`) become required CI checks first | a seeded series still caught | revert |
| H | Holdout: two jobs (image built without secrets, scenarios run with them), the service's logs never go back to the implementer | a feature's holdout green | not required |
| 9 | Private repository on GitHub Team; CI minutes measured first; no merge queue on Team private | a red check blocks a merge | public again, only before briefs reach issues |
| C | Build and review VMs to the cloud; heartbeat (dead man's switch), cost and token budgets | a week unattended | the local VMs |
| 10 | Auto-merge on the low-risk lane, 10–20% sampled after merge, migration switches removed | 9 of 10 PRs as the owner judges them | required approvals = 1 |

**Rules of the migration.** One factory change at a time, then 2–3 application items; the old path stays behind a
switch until the new one has passed; a review or security stage exits on a measure with known answers (`/seed-bugs`), not
on two panels agreeing; at least two application items for each factory item, counted by `audit-data.sh`. A factory change is checked on
incident-platform first, and, once stage N has passed, on the new application too, so it is not fitted to one product.

**Stage 0, the freeze.** Open items that harden what a later stage removes wait as `Blocked` (superseded by the stage
named): #0-236 (4), #0-225 (2 and 4), #0-211 (6c), #0-210 (6c), #0-214 (6c), #0-217 (4), #0-183 (5), #0-167 (6a),
#0-226 (4), #0-228 (4), #0-234 (4), #0-227 (6a), #0-213 (4), #0-201 (7).
Items a stage carries out point at it: #0-116 (2, then C), #0-202 (2), #0-205 (3), #0-204 (3, moved to 4 on 2026-11-17),
#0-212 (4), #0-153 (6a). Frozen on 2026-11-17, superseded by stage 4: #0-251, #0-253, #0-254.
The rest stay as they are; the `/seed-bugs` items (#0-171, #0-190, #0-218, #0-219) are wanted before stage 5.

## Alternatives considered

- **Keep hardening the hooks**: each round of #0-235 found another spelling; a text match cannot bound `./mvnw`, and every
  hour spent there is removed by stage 6c.
- **One VM for the implementer and the reviewer**: the implementer needs Docker for Testcontainers, and Docker is root on
  that VM, so test code could read the reviewer's key.
- **A repository, or a persistent VM, per agent**: forks to synchronise by hand, and state that piles up between runs;
  one repository with a fresh clone per task does neither.
- **An agent that approves and merges**: it adds a credential that can merge and no judgement the reviewer did not make.
- **The builder as the `lukaszplawiakbot` account**: a long-lived PAT on the build VM and a paid seat once private; an
  App's installation tokens expire within the hour. The App's private key, which mints them, does not expire and is
  revoked by hand, so it is the long-lived secret: stage 4 decides where it lives (outside the task containers) and how
  it rotates (an App holds up to 25 keys, so a new one can be added before the old is deleted). Costs: `repository-settings.rb`, the ruleset's actors and `audit-data.sh` (the bot's
  login) change in stage 4.
- **Audit markers in issues, counted by actor**: possible (as `human:*` labels are), but an issue body has no history git
  keeps, and the pipeline audit would read two sources.
- **Finish the factory inside incident-platform, copy it for the new application**: faster to start, then two
  factories, every fix made twice, and each copy's rules fitted to its product.
- **incident-platform as the factory's home, an adapter only in other products**: no new repository, but the
  factory's code stays in a repository builder-app writes to, guarded by text matches, and tied to this product's
  history and rules.
- **The new application as two repositories (backend, frontend)**: each could be versioned on its own, but every API
  change becomes two pull requests in an order kept across repositories, and #0-111 (the OpenAPI diff) a required gate
  from the first day; one team (the owner and the factory) gains nothing from the split.
- **The cloud first**: no second move and a stronger firewall, but cost, unattended Claude authentication and secrets in
  the first VM stage at once.

## Consequences

- New factory work is checked against this plan: an item that hardens a mechanism a stage removes is frozen, not done.
- The known gaps stay open, and named, until their stage: `./mvnw` (#0-116, stages 2 and C), git's route to the state
  (#0-236, stage 4), the owner's session (#0-167, stage 6a). The frozen gaps (#0-236, #0-167, #0-225) are acceptable
  only while every PR needs the owner's approval: stage 10 (auto-merge) does not start until the stage that closes each
  of them has passed its exit (security review of this ADR, round 2).
- Open, to decide at their stage: how Claude Code authenticates unattended on a VM (an API key or a subscription token,
  within the terms of use); the VM tool on the Mac (Lima, UTM or OrbStack); the high-risk path list in CODEOWNERS; the
  sample rate; Sysbox in the build VM.
- Earlier decisions each stage supersedes or amends, in that stage's own ADR: ADR-0052 (the preflight's bot identity,
  `FACTORY_BOT_LOGIN`) and ADR-0034 (the ruleset's actors and bypass) at stage 4, when builder-app replaces the bot;
  ADR-0053 (factory-ops' one call) at stage 4, when the dispatcher replaces factory-ops; ADR-0054 (the allow list's
  closed list, `git_runtime_unsafe`) and ADR-0050 (the agents' command lists) at stage 6c.
- Each stage from 4 on is written for more than one repository: configuration names the repository, the gate is the
  contract, no path of incident-platform is assumed. Stage 10's auto-merge is decided per repository.
- A reviewer recognises a violation as a stage started before its predecessor's exit, a stage without a rollback, a
  credential inside a task container, a status the ruleset requires set by builder-app, an audit marker written
  outside the repository, builder-app installed on `factory`, or factory code that names a product's paths, modules
  or rules.
