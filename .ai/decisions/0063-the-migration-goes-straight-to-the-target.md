# ADR-0063: The factory's migration goes straight to the target: steps M1–M12, no shadow, no second path

- **Status:** Accepted (2026-11-21, by the owner, after review round 1 of #0-286); amends ADR-0055 (its stages, order, exits, rollbacks and rules of the migration, and two exceptions to its target's "dispatchers keep no state of their own": a seed run's ground truth until it is scored, and, if GraphQL names no actor of a Project field, the dispatcher's own record of who moved a task to `Ready`), ADR-0060 D7
  (one lock for the whole dispatcher, a push never forced, no merge in a branch) and D8 (the item named by the owner
  until stage 7), and ADR-0062 point 5 (the rollback shares the VM by time); amended for #0-299's plan (the architect's
  write scope at M2) and for #0-303 (2026-11-21: M2's per-task sweep and caches moved to M3.4, #0-285); amended for #0-301
  (2026-11-22: the credential proxy's core moved into M2 as #0-313, before #0-301's trial); amended for the new
  private product (2026-11-22, the owner: the order after M4, #0-285's way decided as a user per slot, the steps a
  first product does not need deferred; "Amended (2026-11-22, the new product)" below)
- **Backlog:** #0-286 (this replan); the steps' items #0-287 to #0-307 (M2 and M3 split per pull request); #0-303's
  amendment
- **Date:** 2026-11-21
- **Author:** human (the owner's decisions D1–D6 and G1–G5 of 2026-11-21, taken in an interactive session on an
  analysis of the migration against its target); written by Claude Code
- **Reversible:** yes, until M4. This ADR removes nothing built; each step it reorders or drops keeps its old plan in
  `migration/stage-4.md` and ADR-0055. From M4 on (D1) the old path is gone, and a step's rollback is a `git revert`
  of the factory pin or the owner's interactive session on the Mac, not a second runnable path.

## Context

ADR-0055's target (three zones, scripts not agents, a GitHub queue, a ruleset merge) still holds. Its way there
does not fit the owner's aim, which is to finish quickly. Intermediate states are of no interest to the owner and
may be skipped wherever skipping does not harm the migration. Reading stages 0–4 against the target
(`migration.md`, `stage-1.md` … `stage-4.md`) found the following:

- **Work built only to be thrown away.**
  - The rollback that shares the VM by time: `rollback-start.sh`/`rollback-exec.sh`, 35 test cases, refusals in
    `daemon.mjs`/`environment.mjs`, logins re-entered. It goes at stage 5's exit.
  - A `backlog-md` queue kind in the dispatcher, with `0-N` ids, the `/<id>-` branch lock, `next-item.sh` and
    `BACKLOG-DONE.md` edits by an agent (4.5). It goes at stage 7.
  - The whole autopilot flow, review panel included, ported into the build VM in 4.4, then moved again to the
    review VM in stage 5, after a shadow run.
- **Order.** The queue moves only at stage 7, after review and lanes. The boundary hooks stay until after stage 8,
  although a task container is already the boundary.
- **Runs.** 2–3 application items per factory change and 3 runs per exit multiply the runs of every intermediate
  state.
- **Plans.** A stage's plan is written only when the stage starts. Stages 5–10 have one line each ("gap: all of
  it"), so the order of work could not be read anywhere.

Stage 4 so far (2026-11-18 to 11-21) took 19 `factory` PRs and about 270 tests, and the dispatcher has made no
agent call yet (`PHASES = []`).

## Decision

**Rules of the migration** (replace ADR-0055's "Rules of the migration"):
- **D1: one path.** The old build path (`/backlog-autopilot`, shipper, picker, the bot's PAT, the rollback that
  shares the VM) is removed at M4, once the dispatcher has opened and the owner has merged one PR.
  `factory-ops` and what `/seed-bugs` and `/audit` run through it stay until M6 ports them, since M6 exits on
  `/seed-bugs`, whose baseline on the old panel is run before M4 (review round 1 of #0-286). A step's rollback is a `git revert` of the factory pin or the owner's interactive session on the Mac.
- **D2: queue first.** GitHub Issues + Project (old stage 7) comes right after M4, before the review zone. While
  the repository is public, its items are as public as `BACKLOG.md`.
- **D3: no second port.** The review panel, verifier and acceptance are not ported into the build VM. Until M6
  the owner reviews the dispatcher's PRs with `/review` on the Mac.
- **D4: no shadow.** `factory/review` is required from the start of M6. Its exit is a `/seed-bugs` series with
  known answers (P-25..P-27).
- **D5: one item per exit.** One real item through the new path exits a step. Review and security steps still
  exit on `/seed-bugs`.
- **D6: hardening test.** A new hardening item is done in the migration only if, without it, a leak of
  builder-app's key yields more than a PR that waits. Otherwise it waits for M11 or after M12. That premise holds
  while every PR is read by the owner (the CODEOWNERS catch-all, until M12), so each deferred item is re-checked
  against it before auto-merge too (security review of #0-286).
- **Every step has a plan before its first item**, written in `migration/` for all remaining steps at once
  (#0-286), each with its parts, where (repository, VM, GitHub), order and exit.

**Steps** (ADR-0055's stages in brackets):

| Step | What | Exit |
|---|---|---|
| M1 (4.3d) | #0-278 as decided, no growth of the `backlog-md` kind; `factory` tag `v0.1.0` | one run to the end of the container |
| M2 (4.4, narrowed) | the build agents moved into `factory`'s plugin; the build zone's phases only (plan, implement, gate, test fixes, review fixes by finding id); the dispatcher commits with trailers; `stream-json` per call; per-task lock (the sweep's per-task scope and the caches with #0-285, M3.4: #0-303's option B); #0-280, #0-284, Claude Code pinned | a branch of commits, gate green |
| M3 (4.5–4.7) | push, PR, trace; the credential proxy, after #0-285 | one PR by builder-app merged by the owner |
| M4 (end of 4, part of 5) | the old build path removed (D1); `factory-ops` kept for `/seed-bugs` and `/audit` | VM with no rollback, CI green |
| M5 (7) | Issues + Project, all open items moved, `BACKLOG.md` frozen; dispatcher v1: claim, lease, Priority, 2 slots, rebase work, timer | 3 tasks taken from the Project and closed; two at once, one rebased after the other's merge |
| M6 (5 + 6a) | review VM, review-app, dispatcher review; `/seed-bugs` and `/audit` off `factory-ops`; lane, trace, human gate, CODEOWNERS, `/human-review` | `/seed-bugs` caught at least as by the old panel; lane agrees with the owner on 3 PRs; two reviews at once |
| M7 (6c) | boundary hooks removed; the quality hooks' CI counterparts (`Factory guards` rules 1, 2, 4) recorded with seeded cases (the architect's write scope leaves its hook earlier, at M2: amendment below) | a seeded series still caught |
| M8 (8) | `bc-app`, `/plan-feature` + `feature-planner`, `FeatureFlags` in `shared` | one Feature done |
| M9–M12 (9, H, C, 10) | private on Team; holdout; cloud; auto-merge on the low lane | as ADR-0055 |
| T, N | as ADR-0055 | as ADR-0055 |

ADR-0055's 6b gates (ArchUnit, Squawk, commitlint, TODO) are ordinary items from M5 on and block no step.

**Concurrency, priority, planning, review and audits** (G1–G5):
- **G1: two build slots from M5.** A fix round or a rebase is a task started from the PR's branch. No two runs
  of one task or PR, and no two tasks with overlapping `touches`.
  - A merge that moves a PR's base makes **rebase** work (after fixes, before new tasks): a rebase in the
    container and `push --force-with-lease`, only to `factory/**`, only by the dispatcher. Required checks are
    strict, and D7's check becomes "the base is current `main`" (G1-a).
  - In M5 both slots share `factory`'s daemon, a risk accepted while every PR is read by a person (G1-b, phase 1).
    Before M12, task isolation is chosen with #0-285's way: Sysbox's daemon inside the task container if a spike
    on Lima arm64 passes, else a VM user and rootless daemon per slot (phase 2).
- **G2: the queue's order.** Card order in the Project's Ready view plus a `Priority` field (P0–P2), read only
  when last changed by the owner or `bc-app`. The dispatcher's order is: fixes, rebase, P0, the rest. P0 takes
  the next free slot and never interrupts a running task.
- **G3: planning stays interactive.** Each planning skill is a skill (the conversation), an agent (a definition
  with a JSON schema of its answer) and a script that writes the result, so that an autonomous planner later is
  only a new kind of dispatcher task. `/ready` is unchanged until M5, where it writes to an issue; `/plan-feature`
  with `feature-planner` comes in M8. An autonomous planner gets no step. Its entry condition is "build slots
  idle for lack of Ready tasks".
- **G4: reviewers without Bash.** `review-*`, `acceptance-reviewer` and `verifier` hold `Read`, `Grep`, `Glob`
  (the verifier also `WebFetch` to its allow-list), never Bash as well: with Bash in its tools Claude Code drops Grep
  and Glob (tools reference; measured in M2.0, `m2.md`). The dispatcher prepares the review's workspace (diff, base
  and head files, issue, brief, CI artifacts).
  - Two review slots, one review per PR at a time, `factory/review` set on the SHA reviewed.
  - The head is read again before publishing; a moved head gets a comment, no status.
  - A global limit on concurrent agent calls in the review zone.
  - After a rebase with an identical `git patch-id --verbatim` of the whole `merge-base..head` diff, computed by
    the dispatcher, the verdict is carried to the new SHA without a model (the default ignores whitespace, which
    can change meaning). The owner's approval and the human gate are never carried. A different id is reviewed by
    `git range-diff`, not by an old-head..new-head diff, which would hold `main`'s changes (security review of
    #0-286).
- **G5: audits are task kinds of the dispatchers** (the owner, 2026-11-21).
  - `/audit` and `/docs-audit` run in the review zone, their agents read-only, on data the dispatcher prepares
    (PRs, labels, the repository's escape markers, the per-call trace of each PR body).
  - `/seed-bugs` spans both zones (the owner's choice (3), review round 4 of #0-286):
    - seeding and compiling run in a build task container;
    - the seeded branch is opened by builder-app as a **draft PR labelled `seed`**, its commit message free of the
      pattern. So CI runs on it exactly as on a real PR, with no new permission and no change to CI;
    - the review dispatcher takes it by the label and reports its findings as a non-required check run of
      review-app (`factory/seed-review`), never `factory/review`. That check run is the one channel, GitHub, the
      zones share;
    - the build dispatcher reads only review-app's check run, scores it, closes the PR and deletes the branch.
    - It cannot merge: it is a draft, `main` requires `factory/review`, which a seed PR never gets, and the owner's
      approval holds until M12.
    - The ground truth is kept in the build dispatcher's state until scored, a stated exception to ADR-0055's
      "dispatchers keep no state of their own", since a ground truth on GitHub would reach the review zone.
  - **Trigger (a): a pause.** Every `FACTORY_AUDIT_EVERY` (10) merged builder-app PRs since the last audit, the
    build dispatcher opens an `Audit` issue and takes no new task until the owner closes it. Fixes, rebases and
    reviews go on. Only an `Audit` issue opened by builder-app counts, and only the owner's login closing it ends
    the pause (other apps hold Issues write too).
  - **Report (a): through an issue, recorded in the repository.** The `Audit` issue is work state only (ADR-0055:
    "the audit record stays in the repository"). The review dispatcher writes the report into it.
    `/apply-audit` on the Mac:
    - reads it as data, checking that its last body edit is review-app's or the owner's;
    - takes the owner's decision per recommendation (accept, reject, modify, defer), as today;
    - opens the owner's PR, which writes the report's text to `.ai/audit/<date>-<target>.md` and every decision to
      `.ai/audit/decisions.md`.

    The record, the four-way decisions and the acceptance rate stay what they are now. No dispatcher acts on the
    report's text (review round 3 of #0-286).
  - Between M4 (the old preflight's "audit due" goes) and M6, the owner starts the audits by hand when the count
    is reached.

**Amended (2026-11-21, #0-299's plan, the owner's option (b)): the architect's write scope at M2.** The plugin's
architect carries no `readonly-bash` or `write-scope` hook (Claude Code ignores a plugin agent's frontmatter hooks,
and a hook in the container is the branch's to turn off). Its write scope moves to the dispatcher in M2.4 (#0-302):
each call's changed paths are held, outside the container, to the scope the product's adapter names (`writeScopes`).
The rest of M7's boundary hooks stay where they were, on the old path, until M7. The plugin carries none of the
quality hooks either (`guard-tests`, `guard-migrations`), and needs none: the required `Factory guards` already holds
every pull request, the dispatcher's too, for a deleted or weakened test and an edited applied migration (rules 1, 2,
4), and the dispatcher runs the gate itself (review round 3 of #0-299's plan).

**Amended (2026-11-21, #0-303's `/research`, the owner's option B): M2's per-task part.** M2 builds a lock per task,
a task's liveness by that lock, a state lock and `FACTORY_SLOTS` (1 until M5), with the whole-daemon sweep only while
no other task is live. The per-task sweep, the orphans and the Maven cache's layout move to M3.4 with #0-285, which
chooses the daemon's model (G1-b): on a shared daemon a task's code chooses names and labels, so a label-scoped sweep
is no boundary, and under a daemon per task most of it would be thrown away. G1's slots in M5 rest on both steps.

**Amended (2026-11-22, #0-301's `/research`, the owner's options K2, f1, g1): the credential proxy's core moves into
M2.** M2's exit and #0-301's trial (with #0-300's VM part) are real agent calls in a task container on the VM, and
ADR-0060 D4 keeps Claude's credential out of it. So the proxy's core, M3.5's first half, comes before that trial as
an item of its own, #0-313 (M2.7): a `node:http` proxy of `dispatcher` on the containers' host-gateway address (since
2026-11-23 a dummy address of its own with one rule, #0-313's measurement 2, ADR-0062 point 5 as amended) that
accepts only the running task's random token, swaps in the Console key (a workspace with a spend limit) and streams
to `api.anthropic.com`, counting usage per task. M3.4 (#0-285) still comes before the rest of M3.5; until it does,
a run that holds a token runs only on a VM made anew (`delete.sh`, `create.sh`) that has run nothing before it, so
nothing an earlier task left as `factory` meets one (one of #0-285's own options, for M2's few owner-named runs). Not a bare Console key
in the container, which ADR-0060 rejected: a leaked key works anywhere until revoked, a leaked task token only from
the VM and only while its task runs. The architect's write scope stays M2.4's (#0-302), with no check of its own in
#0-301 (f1): until #0-302 nothing is committed or pushed, and #0-302 is part of M2's exit.

**Amended (2026-11-22, the owner, in an interactive session: the new product).** The owner's next goal is a new
application, private, built through the factory: a Java and Spring Boot backend with a React frontend (ADR-0055 N).
The steps are reordered towards it, so the factory is whole when the product's first task comes and nothing is built
twice (a `backlog-md` queue for the new product, then its move to Issues; `/plan-feature` writing to `BACKLOG.md`, then
rewritten):
- **R1. #0-285's way is decided: a VM user and rootless daemon per slot, each slot wiped after each task** (G1-b's phase
  2 becomes its only phase; no Sysbox or nested-Podman spike). The wipe, by a root script after every task: the slot
  user's processes ended (`loginctl terminate-user`), its home made anew from a template (`~/.docker`, systemd user
  units, `daemon.json`), its Docker data-root removed (images, build cache, volumes), its files in `/tmp`, `/var/tmp`
  and `/dev/shm` removed; the order, the mark of a clean slot and the full list of places are #0-285's (review round
  1 of this amendment, security: the user manager kept down until the home is made anew, so a planted user unit never
  runs again; the mark root's; `/run/user/<uid>`, `/dev/mqueue`, the cron and at spools and every other directory a
  slot user can write; each slot's home 0700, out of the other slot's mounts; and a task's published ports out of the
  other slot's reach). This reverses the alternative rejected below, "a VM user per slot from M5", whose reason was
  that it "closes only concurrent tampering, not what a task leaves for the next": with the wipe it closes that too,
  and it ends #0-313 AC6's fresh VM before every run with a token, which a factory that takes its own work cannot
  keep (each VM made anew needs builder-app's key from the owner's Mac). What it does not close is ADR-0064's residual
  (a task's code is root in its own container through its slot's socket), within one task, as today; a nested runtime
  may come later as a further layer. Its cost, images and caches per slot and pulled again after a wipe, is measured
  in #0-285's trial (a root-owned image tarball or a local mirror). #0-285's ADR amends ADR-0062 (one `factory` user).
- **R2. The order after M4:**
  1. **M5 with #0-285 and #0-289's rest**: the queue in Issues for incident-platform (#0-291, #0-292, #0-293), its two
     slots on two slot users; #0-285 merged before `FACTORY_SLOTS=2`. M3 keeps #0-305 and #0-306;
  2. **M9 (Team) alongside M5**, before the new product: a private repository's ruleset needs GitHub Team, and the
     factory's controls rest on the ruleset (on Free a private repository has none, so builder-app could push to its
     `main`). Private are **the new product and `factory`** only; **incident-platform stays public, always** (the
     owner, 2026-11-22), so its CI keeps GitHub's runners without a minute limit. One seat, the owner's (the apps take
     none). **The new product's CI runs on GitHub's runners**, within Team's included usage and paid past it (about
     3,000–4,500 minutes a month at two slots, estimated, so a few dollars past the included amount): its runners are
     fresh for each job, it runs while the owner's Mac is off, and it leaves the Mac's memory to two slots (R4). Its
     minutes are measured after the first month. A self-hosted runner in a CI VM of its own on the Mac is an option
     for that measure, not a step: one job per runner (just-in-time), a fresh environment per job (a lasting runner
     could be poisoned by one PR and pass the next ones' bad code, the gate the factory rests on), none of the owner's
     keys, an egress filter, never on macOS itself and never in the build VM;
  3. **T, the new product's adapter, the `react` profile and the review rules split** into the factory's core, a
     profile and the product's own (the rules' part of ADR-0055 stage 5, moved before M6; the review VM stays M6). The
     new product's queue is Issues from its first item: no new code for the `backlog-md` kind (the reviewer's sign
     below holds);
  4. **M8 for the new product**: `bc-app`, `/plan-feature` and `feature-planner` writing to Issues. Not in it:
     `FeatureFlags` in incident-platform's `shared` (a new product's flags are a decision of its foundation) and M8.4's
     `factory-trace` check (the `Feature:` trailer only, until M6);
  5. **N**: the new product's first tasks through the factory. Its foundation, led by the owner, runs from now on, as
     ADR-0055 allows (it needs no factory);
  6. **M6, narrowed (M6-lite),** after N's first tasks: reviewers without Bash (M6.2), the review VM and review-app
     (M6.3), the dispatcher's review mode (M6.4), `factory/review` required (M6.5), the lanes, trace and human gate
     (M6.6); M6.1 came before N (step 3). M6.4b (audits and `/seed-bugs` as task kinds of the dispatchers,
     `factory-ops` removed) moves after M12: until then the owner starts the audits by hand and `factory-ops` stays.
     M6's exit keeps its `/seed-bugs` measure in a simpler form: the patterns planted by today's `/seed-bugs`, pushed
     as draft PRs labelled `seed` and reviewed by the review zone, each finding scored by the owner's session against
     the ground truth, which never reaches the review zone;
  7. **M12 right after M6**, on the low-risk lane alone with 10–20% sampled after merge: the owner's reading of every
     PR is the factory's bottleneck, and only M12 removes it. It needs M6 (its eight conditions: review-app approves,
     not the author; statuses bound to their apps; an approval bound to the head's SHA), not M11. **Until M12 the
     owner reads every PR's whole diff**, as D6's premise requires (review round 1 of this amendment, architecture
     and security: a summary read instead would let a PR opened with a leaked builder-app key, or a diff whose text
     steers the panel, merge on a summary, and D6's deferred items were never re-checked against that). What
     changes before M12 is the waiting only: GitHub's own auto-merge (`gh pr merge --auto`) merges a PR the owner
     approved once its checks pass, which relaxes nothing, since `main`'s ruleset already dismisses a stale approval
     and requires the last push's (`repository-settings/rulesets/main.json`). It needs `allow_auto_merge: true` in
     `repository-settings/repository.json`, the owner's `plan` and `apply`, with M3's first PR by builder-app.
- **R3. Deferred, with no step until the owner names one:** M7, M10, M11, #0-259 and #0-260 (M6's second model and
  disputes), #0-307, and #0-306's thresholds file. M12 is not deferred (R2.7); its eighth condition ("none while tasks
  on a shared daemon can change each other or leave state for a later task") is met by R1, and each D6 item is
  re-checked before it, as `m9-m12.md` states.
- **R4. The host's memory (32 GB) sets the slots in use.** macOS and the sessions take about 10–14 GB, so with CI on
  GitHub's runners the build VM takes 16 GiB for two slots (about 7 each, a multi-module Maven build with PostgreSQL
  and Kafka in Testcontainers), each slot user's slice limited (#0-315's, per slot) so one build cannot starve the
  other; not the 20 GiB M5 first planned. M6's review VM (3–4 GB) does not fit beside it: when M6 comes, the memory is
  balanced again before its plan is written (one slot during reviews, more memory, M11's cloud, or the review zone on
  GitHub's runners, which would put review-app's Claude key in CI and is a decision of its own).
- **R5. A trial VM of the factory.** The factory's changes that a VM shows (the proxy's address, the slots, a slot's
  wipe) are tried on a VM made for the trial from the same `create.sh` and `provision.sh`, then deleted, not on the
  VM the factory works on; it needs `create.sh` and `delete.sh` to take the instance's name (an item when #0-285's
  trial comes), and on 32 GB it runs while `factory-build` is stopped. Until then a measurement that needs the VM runs
  on `factory-build` while no run is live, with a temporary user it removes. A product's own test or staging
  environment is the product's, defined in its repository and run by the owner or its own CI/CD: the factory builds
  and never deploys, and holds no credential of it.

## Alternatives considered

- **ADR-0055's way unchanged.** It is safe, with a runnable rollback at every stage. It costs the work listed in
  Context, all of it removed later, and the owner's stated aim is the end state.
- **Issues after the review zone (old order).** The `backlog-md` kind, `next-item.sh` and the agent's backlog
  edits would have to be built into the dispatcher, then removed at stage 7.
- **A shadow review before it is required.** Two panels agreeing was never the exit (ADR-0055 already exits stage
  5 on `/seed-bugs`). The shadow phase would only keep the old panel running for longer.
- **An autonomous planner now.** It needs a new app, task kind and statuses, plus an asynchronous loop for its
  questions. Its only gain is the owner not waiting while a feature is cut into tasks, and the owner approves
  every plan anyway. The costliest error, a well-built wrong thing, is made at planning, where questions asked
  at once help most.
- **A VM user per slot from M5.** It costs about one item the size of 4.3c, plus images and caches ×N. It closes
  only concurrent tampering, not what a task leaves for the next (#0-285), and each PR is still read by the owner.
  **Reversed on 2026-11-22** ("Amended (2026-11-22, the new product)", R1): with each slot wiped after each task it
  closes what a task leaves for the next too, and it is what #0-285 now builds.
- **A merge commit `main` into the branch instead of a rebase.** It needs D7's "no merge" check loosened and
  leaves a non-linear history. `factory/**` belongs to builder-app alone, so a forced update there gives it
  nothing.

## Consequences

- `migration.md` maps steps M1–M12 and their items. `migration/m2.md` … `m8.md` and `m9-m12.md` are the steps'
  plans. `stage-4.md` stays the record of 4.1–4.3, with its 4.4–4.7 plan replaced by M2/M3.
- New items #0-287 to #0-307 carry the steps. M2 and M3 are split into one item per pull request (#0-299 to #0-307,
  under the umbrellas #0-287 and #0-288). M4–M8 are one item each, split from their plan file's parts when the step comes. Existing items move as `migration.md` states: #0-212 into #0-302 and #0-204
  into #0-306; #0-239, #0-242, #0-243, #0-244, #0-274, #0-279 and #0-281 wait for M11 or after M12 by D6.
- **Auto-merge (M12) gets an eighth condition:** none while tasks on a shared daemon can change each other or leave
  state for a later task.
- Until M4 the old path still runs, and the bot's PAT stays. ADR-0052, ADR-0034 and ADR-0053 are amended or
  superseded by #0-290 (M4), not here.
- A reviewer recognises a violation as:
  - new code for the `backlog-md` kind or the rollback that shares the VM;
  - a review phase ported into the build VM;
  - a step started without its plan file;
  - a hardening item done before M11 that fails D6;
  - a reviewer agent given `Bash`;
  - a `factory/review` set on a SHA not reviewed and not carried by an identical patch id.
