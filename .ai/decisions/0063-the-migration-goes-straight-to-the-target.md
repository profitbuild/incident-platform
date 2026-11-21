# ADR-0063: The factory's migration goes straight to the target: steps M1–M12, no shadow, no second path

- **Status:** Accepted (2026-11-21, by the owner, after review round 1 of #0-286); amends ADR-0055 (its stages, order, exits, rollbacks and rules of the migration, and two exceptions to its target's "dispatchers keep no state of their own": a seed run's ground truth until it is scored, and, if GraphQL names no actor of a Project field, the dispatcher's own record of who moved a task to `Ready`), ADR-0060 D7
  (one lock for the whole dispatcher, a push never forced, no merge in a branch) and D8 (the item named by the owner
  until stage 7), and ADR-0062 point 5 (the rollback shares the VM by time)
- **Backlog:** #0-286 (this replan); the steps' items #0-287 to #0-307 (M2 and M3 split per pull request)
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
| M2 (4.4, narrowed) | the build agents moved into `factory`'s plugin; the build zone's phases only (plan, implement, gate, test fixes, review fixes by finding id); the dispatcher commits with trailers; `stream-json` per call; per-task lock and per-`runId` sweep; #0-280, #0-284, Claude Code pinned | a branch of commits, gate green |
| M3 (4.5–4.7) | push, PR, trace; the credential proxy, after #0-285 | one PR by builder-app merged by the owner |
| M4 (end of 4, part of 5) | the old build path removed (D1); `factory-ops` kept for `/seed-bugs` and `/audit` | VM with no rollback, CI green |
| M5 (7) | Issues + Project, all open items moved, `BACKLOG.md` frozen; dispatcher v1: claim, lease, Priority, 2 slots, rebase work, timer | 3 tasks taken from the Project and closed; two at once, one rebased after the other's merge |
| M6 (5 + 6a) | review VM, review-app, dispatcher review; `/seed-bugs` and `/audit` off `factory-ops`; lane, trace, human gate, CODEOWNERS, `/human-review` | `/seed-bugs` caught at least as by the old panel; lane agrees with the owner on 3 PRs; two reviews at once |
| M7 (6c) | boundary hooks removed; `guard-tests`/`guard-migrations` as required CI checks | a seeded series still caught |
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
  (the verifier also `WebFetch` to its allow-list). The dispatcher prepares the review's workspace (diff, base
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
