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

**Every step keeps a record** (the owner's rule, 2026-11-20): in its stage's file, each step's section ends with a
**Record** of four parts, kept current by the PR that does, decides or drops part of the step, never after it:
- **Done:** what was built or settled, with its PRs;
- **Why:** the reason for each choice made (the owner's, or the analysis behind it);
- **Not done:** what the step's plan held and was not done, or was moved;
- **Why not:** for each, why, and where it went (an item, a later step, a stage).

A decision taken with the owner in a conversation goes into the record before the code that follows it lands. A
choice that changes an ADR's decision (narrows, extends or reverses it) is an amendment of that ADR, and the Record
names the amendment: the decision's history stays in the ADRs (ADR-0055), the Record says where it is and why.

Legend: **carries** = the item does the stage's work; **superseded** = frozen as `Blocked`, the stage removes what it
hardens; **before** = wanted done before the stage starts; **waits** = depends on the stage; **gap** = stage work with
no item yet.

## Where we are

Stages 0 to 3 are done. **Current: stage 4**: 4.1 done (2026-11-18, with #0-268, #0-269 and #0-270 on 2026-11-19);
4.2 done (4.2a 2026-11-19, 4.2b 2026-11-20); 4.3 in progress, split into #0-275..#0-278: 4.3a (#0-275) done 2026-11-20 by `factory` PR #15; 4.3b (#0-276) done 2026-11-20 by `factory` PR #16; 4.3c (#0-277) in progress, its way decided 2026-11-20 (ADR-0062: `docker` and `devcontainer` as `factory` through one sudo rule, the clone as a bundle into a work directory of `factory`'s): the VM's part in incident-platform's working PR, the dispatcher's in `factory` PR #18 (merged as `c5fe3264`), applied together by one VM recreation that moves `FACTORY_COMMIT` (the pull request after #672), then the trials; its end-state follow-ups #0-284 (4.4: the task container checked before anything runs) and #0-285 (before 4.6: what a task leaves in `factory`'s reach, before a task holds a credential). Each
step's record: `migration/stage-4.md`.

## Stages

### 0. Freeze hook hardening — DONE
ADR-0055 merged (PR #620), Accepted 2026-11-13.

### 1. Organisation `profitbuild`, repository transferred — DONE
#0-237 (PRs #623, #624, #625). Owner step still open: 2FA in the organisation.

### 2. Build VM, provisioned as code, running today's devcontainer — DONE
#0-238 (PR #627 … #650, ADR-0056, ADR-0057; exit: 3 autopilot runs, #0-58, #0-25, #0-23). Carried and narrowed, not
closed: #0-116 (the rest is stage C), #0-202 (settled for the VM), #0-225 (the VM's clone holds no owner secret; the
task container is stage 4). The Mac devcontainer stays the owner's own (stage 2's rollback); stage 4's rollback, today's autopilot in the VM's devcontainer, shares the VM by time with the dispatcher from 4.3c (ADR-0062 point 5).
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
`factory` PR #1), then, each created when its turn comes, 4.2 builder-app (split on 2026-11-19: #0-271 the code that mints and
checks its token, in `factory`, done 2026-11-19 by `factory` PR #9; #0-272 (done 2026-11-20, PRs #663 and #664) the app, its key on the VM, and five rulesets here that hold it to `factory/**` and `factory/**` to it
and keep tags to the admin, in two pull requests, the rulesets first (the first merged 2026-11-20, PR #663; the app
created that day; `factory` PR #13 its permissions as a file), and every app of the organization written as a file;
#0-274 a narrower egress list of `dispatcher`'s own (the VM's chain takes it already, its uid being an ordinary one); moved from 4.2 to 4.5, where a PR is first opened: ADR-0052 and ADR-0034 amended for the
app as a PR's author, `audit-data.sh` reading it, and the app's Issues permission), 4.3 the dispatcher's core
(split on 2026-11-20: #0-275 the foundation, with #0-261; #0-276 the push from a push repository the dispatcher owns; #0-277 Docker and the
task container; #0-278 the product's code from `main`; #0-273, done 2026-11-20 by `factory` PR #14, moved dev-token onto
the shared checks first; #0-280, from 4.3a's review, the gate's schema checked against `run-tests.sh` before 4.4 reads
a gate's answer; #0-281, from 4.3b's review, the credential checks held at the call that sends them and the scans' bounds; #0-282, incident-platform's task configuration for the container, with 4.3c (ADR-0062 point 4); #0-283, the image's firewall sudo rule and unpinned Claude Code, which reach every task since #0-282; #0-284, for 4.4, the task container checked before anything runs in it; #0-285, before 4.6, what a task leaves in `factory`'s reach outside the daemon), 4.4 the control flow ported with its tests, 4.5 push, PR, trailers and trace (#0-212, #0-204), 4.6 the
credential proxy and `stream-json` transcripts, 4.7 the adapter, the switch and the three runs of the exit.
ADR-0055: the container has no token; push, PR and commit trailers by the dispatcher; builder-app (never on `factory`);
the gate contract, incident-platform's adapter first. Exit: 3 PRs opened by it.
- before 4.2, from 4.1's review: #0-268 (done 2026-11-19: a required secret scan in `factory`, `factory` PR #5, and
  `check-factory-copies.rb` here comparing every copy with its original, failing a PR here only on a difference it
  brings, ADR-0061), #0-269 (done 2026-11-19,
  `factory` PR #3: `factory`'s code written in `factory`'s devcontainer with the hour's token of `profitbuild-factory-dev`,
  minted on the Mac's host, not with the owner's admin token; ADR-0060 D5 amended); from #0-269's review, #0-270 (done
  2026-11-19: `/review factory#<n>` reviews a `factory` pull request from files GitHub's API serves,
  `scripts/factory-admin/fetch-factory-pr.sh`; the procedure of a `factory` change is `factory`'s CONTRIBUTING.md).
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
- decided by ADR-0060, built by 4.1 to 4.7 (4.1 done by #0-267; no item yet past it): the `factory` repository (`profitbuild/factory`, 4.1); dispatcher v0 (claim,
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
- carries: review-app's required status is bound to review-app by `integration_id` in the ruleset of `main`. Every
  ruleset refuses review-app until it is listed as an `Integration`, since a role's bypass covers no app (the probe of
  2026-11-19, `migration/stage-4.md` "4.2").

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
- gap: the item id's format moves to the queue's kind: the dispatcher's CLI and its task schema take `^[0-9]+-[0-9]+$`,
  incident-platform's `BACKLOG.md` ids, which belong to the queue kind `backlog-md` (4.3a's review, `factory` PR #15); an
  issue's number is another, and a second product's queue may be a third.
- gap: the Issues/Project schema (Feature, Task, fields, blocked-by); the move of the open items; `BACKLOG.md` frozen as
  an archive; dispatcher v1; this map's item references moved to the issues, or the map frozen with `BACKLOG.md` (its
  "Keep it true" rule is prose, checked by nothing).

### T. Template of a product repository and its bootstrap
Exit: a new empty repository passes `repository-settings.rb check` and Factory guards.
- carries: #0-272's five rulesets (the product's builder app held to `factory/**` and `factory/**` to it, tags to the admin), with any app the
  product uses listed as an `Integration` (a role's bypass covers no app), and a file under `apps/` for every app
  installed (an installation no file names fails `check`). Open: the list is the organization's, so with a second
  product each repository would hold its own copy, compared with GitHub but not with each other; where it lives then
  (one repository of the organization's settings, or each product its own apps) is stage T's to decide (review round 1
  of #0-272's second pull request).
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
- conditions, before auto-merge is switched on (2026-11-19, the analysis of 4.2): no single key may be enough to merge
  into `main`, so a leaked builder-app key yields at most a PR that waits:
  1. the author is not the approver: builder-app (build VM) pushes; review-app (stage 5, review VM, another key)
     approves. This waits for ADR-0034's phase 3, since the approval `main` requires today is the code owner's (the
     CODEOWNERS catch-all, one approval);
  2. every status the ruleset requires is bound to its app by `integration_id`, so no other credential sets one of the
     same name;
  3. an approval is bound to the head's SHA, so a new push needs a new one. Whether it is a status or a review with
     `require_last_push_approval` is stage 5's choice;
  4. "low risk" is decided by GitHub (a ruleset or a required check over the changed paths), never by the dispatcher's
     word; CODEOWNERS still takes the owner for the Owner-only paths;
  5. builder-app writes only `factory/**`, and tags are the admin's (#0-272's rulesets);
  6. the approval that lets a pull request merge is one no app can give by holding Pull requests write: a code owner's
     review or a ruleset's required reviewer. An app's approval counts as a required review (#0-272's probe P2), so
     with one plain approval builder-app could approve the bot's or Renovate's pull requests;
  7. whoever merges may delete the head branch: GitHub deletes it as the merger (#0-272's probe P1), so a branch
     under `branches` or `renovate` merged by an actor outside their bypass stays.
- waits: #0-264, #0-153.
- before (ADR-0055 "Consequences"): the stages that close #0-236 (4), #0-167 (6a) and #0-225 (2 and 4) have passed
  their exits.

## Factory items in no stage

Done whenever they pay off, outside the stage order: #0-255 (an approval re-runs the whole Factory guards job; more
needed once builder-app opens PRs), #0-257 (a handoff from an earlier run taken as fact), #0-221, #0-224.
Pre-migration CI work the owner listed (2026-11-13): #0-69 (Snyk scan), #0-2 (compose smoke required), #0-152 B.
