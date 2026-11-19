# The factory's migration: map of stages and backlog items

ADR-0055 decides the stages, their order, exits and rollbacks; this file does not change them. It maps every open
backlog item that belongs to a stage onto it, and names the work of each stage that has **no item yet**. Items are
still created one at a time, when their stage comes (ADR-0055, "an item is created for a stage when its turn comes"):
a gap below is a reminder of what that item will have to cover, not an item.

**One file per stage** under `.ai/context/migration/`: for a finished stage the record of how it was done
([stage 1](migration/stage-1.md), [stage 2](migration/stage-2.md), [stage 3](migration/stage-3.md)), for the current
one its plan, step by step ([stage 4](migration/stage-4.md)). An item is written from its stage's plan, and a stage's
file is written before its first item.

**Keep it true.** A PR that creates, freezes or closes an item of a stage, or ends a stage, updates this file and its
stage's file in the same PR. A session working on the migration reads it first, then ADR-0055 and the items of the current stage.

Legend: **carries** = the item does the stage's work; **superseded** = frozen as `Blocked`, the stage removes what it
hardens; **before** = wanted done before the stage starts; **waits** = depends on the stage; **gap** = stage work with
no item yet.

## Where we are

Stages 0 to 3 are done. **Current: stage 4** (4.1 done on 2026-11-18, with #0-269 on 2026-11-19; 4.2 next:
#0-268 before it, #0-270 before its first PR to `factory`).

## Stages

### 0. Freeze hook hardening — DONE
ADR-0055 merged (PR #620), Accepted 2026-11-13.

### 1. Organisation `profitbuild`, repository transferred — DONE
#0-237 (PRs #623, #624, #625). Owner step still open: 2FA in the organisation.

### 2. Build VM, provisioned as code, running today's devcontainer — DONE
#0-238 (PR #627 … #650, ADR-0056, ADR-0057; exit: 3 autopilot runs, #0-58, #0-25, #0-23). Carried and narrowed, not
closed: #0-116 (the rest is stage C), #0-202 (settled for the VM), #0-225 (the VM's clone holds no owner secret; the
task container is stage 4). The Mac devcontainer stays the rollback.
- Follow-ups, open: #0-239 (the VM scripts' repeatable test; stage 4 moves the scripts), #0-242, #0-243 (one parser of
  the allow-list, before stage 4 moves `scripts/factory-admin/`), #0-244, #0-249 (pin Claude Code in the image).

### 3. Baseline metrics
ADR-0055 (amended 2026-11-17): agent calls, times, tokens, model, tools, refusals per agent call, from the runs'
transcripts, kept off the build VM; a seed pattern for a removed positive control.
- carries: #0-205 (Done, PR #652: `scripts/factory-admin/run-summary.sh`, the archive on the Mac, the baseline of stage 2's three
  runs `wf_207ec85e-4ad`, `wf_5135023f-b7d`, `wf_e5a616a0-073`, no new runs of the old path). The baseline, the
  exit's "numbers for 3 items", is recorded in #0-205's "Baseline (AC4)".
- carries: P-27 in `.ai/audit/benchmark/patterns.md` (PR #572's removed positive control, after #0-218's P-25 and
  P-26); its first `/seed-bugs` run is wanted before stage 5, with P-25 and P-26.
- waits: #0-259 (a second model's review, measured against this baseline), #0-260 (disputes with evidence: the panel
  does not change before the baseline).

### 4. Dispatcher v0, in the new `factory` repository — CURRENT
Decided in ADR-0060 (2026-11-17, Accepted by the owner on 2026-11-18): D1 the dispatcher runs each agent as its own
`claude -p` in a task container and the gate itself; D2 Node built-ins; D3 builder-app, key for user `dispatcher`; D4
Claude's API key behind a proxy; D5 public `factory`, loaded read-only as a plugin; D6 `.factory/adapter.json`; D7
checks before a push outside the container; D8 started by hand. The plan, step by step: `migration/stage-4.md`.
Items in order: 4.1 #0-267 (done 2026-11-18: ADR-0060 accepted, `profitbuild/factory` and its baseline, PR #655 and
`factory` PR #1), then, each created when its turn comes, 4.2 builder-app, 4.3 the dispatcher's core
(#0-261), 4.4 the control flow ported with its tests, 4.5 push, PR, trailers and trace (#0-212, #0-204), 4.6 the
credential proxy and `stream-json` transcripts, 4.7 the adapter, the switch and the three runs of the exit.
ADR-0055: the container has no token; push, PR and commit trailers by the dispatcher; builder-app (never on `factory`);
the gate contract, incident-platform's adapter first. Exit: 3 PRs opened by it.
- before 4.2, from 4.1's review: #0-268 (`factory`'s CI is a copy of incident-platform's, with no drift check and
  without part of its controls; its secret scan decided before 4.2), #0-269 (done 2026-11-19,
  `factory` PR #3: `factory`'s code written in `factory`'s devcontainer with the hour's token of `profitbuild-factory-dev`,
  minted on the Mac's host, not with the owner's admin token; ADR-0060 D5 amended); from #0-269's review, #0-270 (the
  review panel cannot review a change to `factory`).
- carries: #0-212 (`Factory-Run` / `Factory-Agent` trailers), #0-204 (the trace of each agent call and the commits it
  added, `--merge --auto`; moved from stage 3 on 2026-11-17), #0-261 (the dispatcher's written requirements: locks,
  state, retries, rate limits, the gate's pass summary).
- superseded: #0-213, #0-217, #0-225 (the task container), #0-226, #0-228, #0-234, #0-236.
- also: a summary per agent call from the `stream-json` records (the successor of #0-205's `run-summary.sh`, ADR-0060
  amending ADR-0055), and `audit-data.sh` reads the summaries (#0-205's draft AC3, moved here).
- superseded on 2026-11-17: #0-251 (lock stale after 3 h: a `flock` per task, #0-261), #0-253 (a guard keeps the lock
  of a run it stopped), #0-254 (shipper keeps a draft's "(BLOCKED)" title: the dispatcher opens the PR). #0-258 (a
  factory change first run on a real item) names itself superseded by the dispatcher's own canary.
- related: #0-256 (PR description opens with the problem; with #0-254, the template moves to `factory`), #0-239,
  #0-243 (the scripts move).
- decided by ADR-0060, built by 4.1 to 4.7 (4.1 done by #0-267; no item yet past it, apart from #0-268 and
  #0-270): the `factory` repository (`profitbuild/factory`, 4.1); dispatcher v0 (claim,
  lease, containers, push, PR; no status the ruleset requires is set with builder-app's
  credential, ADR-0055; v0 sets none); builder-app and its key; the gate contract and the adapter;
  loading the factory as a read-only plugin; Claude's credential behind a proxy; the ADRs it amends (ADR-0055, ADR-0052,
  ADR-0034, ADR-0050, ADR-0058; ADR-0053 superseded at the exit).

### 5. review-app and the review VM, shadow then required
Exit: a `/seed-bugs` series on the new path catches at least what the old one did.
- before: #0-171, #0-190, #0-218, #0-219 (the `/seed-bugs` items), #0-178 (a missed real defect becomes a pattern).
- waits: #0-262 (review-app's comment format), #0-259 (its adoption).
- superseded: #0-183.
- gap: review-app; the review VM (no Docker, no Maven, reads CI's artifacts); the review rules split into the factory's
  core, the `spring-boot` profile and the product's own.

### 6a. Lane, trace, human gate, CODEOWNERS, `/human-review`
Exit: lane agrees with the owner on 3 PRs.
- carries: #0-153 (paths that need the owner's review).
- superseded: #0-167, #0-227.
- gap: `factory/lane`, `factory-trace`, `factory/human-gate` from GitHub Actions; `/human-review` in a read-only clone.

### 6b. Deterministic gates, one at a time
Exit: each catches its seeded case.
- carries: #0-108 (ArchUnit).
- waits: #0-263 (a bug fix's test run on the code before the fix), #0-112 (mutation testing, placed here by the tstack
  analysis).
- gap: Squawk, commitlint, the `TODO` reference check, each removing its rule from the prompts.

### 7. Issues + Project, all open items at once; dispatcher v1 reads the Project
Exit: 3 items taken, claimed and closed.
- superseded: #0-201.
- waits: #0-265 (a task back after a pause), #0-261's GraphQL rate-limit requirement.
- gap: the Issues/Project schema (Feature, Task, fields, blocked-by); the move of the open items; `BACKLOG.md` frozen as
  an archive; dispatcher v1; this map's item references moved to the issues, or the map frozen with `BACKLOG.md` (its
  "Keep it true" rule is prose, checked by nothing).

### T. Template of a product repository and its bootstrap
Exit: a new empty repository passes `repository-settings.rb check` and Factory guards.
- gap: all of it.

### 8. Backlog Creator and features (sub-issues, flags)
Exit: one feature Done.
- gap: all of it.

### N. The new application (Spring Boot + React), foundation led by the owner
May run from stage 2 on; needs no factory. Exit: one backend and one frontend task through the factory.
- gap: all of it (the owner's interactive sessions and ADRs first: domain, boundaries, auth, schema, API contract).

### 6c. Hook cleanup (after 8)
Exit: a seeded series still caught.
- superseded: #0-210, #0-211, #0-214.
- gap: boundary hooks removed; `guard-tests` and `guard-migrations` become required CI checks first; ADR-0054 and
  ADR-0050 amended.

### H. Holdout
Exit: a feature's holdout green.
- gap: all of it (two jobs; the service's logs never go back to the implementer).

### 9. Private repository on GitHub Team
Exit: a red check blocks a merge.
- related: #0-230, #0-231, #0-232 (CI minutes, measured first), #0-264 (merge on a moved base; no merge queue on Team
  private).

### C. Build and review VMs to the cloud
Exit: a week unattended.
- carries: #0-116 (its remaining part: the provider's firewall outside the VM).
- gap: heartbeat (dead man's switch), cost and token budgets.

### 10. Auto-merge on the low-risk lane
Exit: 9 of 10 PRs as the owner judges them.
- waits: #0-264, #0-153.
- before (ADR-0055 "Consequences"): the stages that close #0-236 (4), #0-167 (6a) and #0-225 (2 and 4) have passed
  their exits.

## Factory items in no stage

Done whenever they pay off, outside the stage order: #0-255 (an approval re-runs the whole Factory guards job; more
needed once builder-app opens PRs), #0-257 (a handoff from an earlier run taken as fact), #0-221, #0-224.
Pre-migration CI work the owner listed (2026-11-13): #0-69 (Snyk scan), #0-2 (compose smoke required), #0-152 B.
