# The factory's migration: map of steps and backlog items

The target is ADR-0055's "Target". The way there is ADR-0063: steps M1–M12, one path at a time and no second one,
the Issues queue before the review zone, no shadow review, one item per exit. ADR-0055's stage numbers appear in
brackets. This file maps every open backlog item that belongs to a step onto it. It does not change ADR-0063's
decisions.

**One plan file per step, written before its first item** (ADR-0063, all of them written at once by #0-286). M2 and M3
are split into one item per pull request now; M4–M8 are one item each, split when the step comes, from its file's parts:
- [M2](migration/m2.md), [M3](migration/m3.md), [M4](migration/m4.md), [M5](migration/m5.md),
  [M6](migration/m6.md), [M7](migration/m7.md), [M8](migration/m8.md), [M9–M12](migration/m9-m12.md);
- the records of finished stages: [stage 1](migration/stage-1.md), [stage 2](migration/stage-2.md),
  [stage 3](migration/stage-3.md), and [stage 4](migration/stage-4.md) for 4.1–4.3 and M1.

A step's file holds its parts in order. Each part says what is built, where (`factory`, incident-platform, the VM,
GitHub settings, the owner's hands), what it needs first and how it is checked. The file closes with the step's exit
and its owner's steps. An item is written from its step's file.

**Keep it true.** A PR that creates, moves or closes an item of a step, or ends a step, updates this file and that
step's file in the same PR. A session working on the migration reads this file first, then ADR-0063, ADR-0055's
target, and the current step's file.

**Every part of a step keeps a record** (the owner's rule, 2026-11-20). Its section ends with a **Record** of four
parts, kept current by the PR that does, decides or drops part of it:
- **Done:** what was built or settled, with its PRs;
- **Why:** the reason for each choice;
- **Not done:** what the plan held and was not done;
- **Why not:** why, and where it went.

A decision taken with the owner in a conversation goes into the record before the code that follows it. A choice that
changes an ADR's decision is an amendment of that ADR, and the Record names it.

Legend:
- **carries:** the item does the step's work;
- **superseded:** frozen as `Blocked` because the step removes what the item hardens;
- **waits:** depends on the step;
- **deferred (D6):** hardening that waits for M11 or after M12, because without it a leaked builder-app key still
  yields no more than a PR that waits.

## Where we are

- Stages 0 to 3 are done, and stage 4's 4.1, 4.2 and 4.3a–d (records in `stage-1.md` … `stage-4.md`).
- **M1 done** (4.3d, #0-278, 2026-11-21): `factory` PR #20, PR #678 and its trial on the VM (`stage-4.md` "4.3").
- **Current: M2** (`migration/m2.md`): M2.0 (#0-299) done 2026-11-21, `factory` PR #21; #0-300 (M2.1's spike) and
  #0-284 done 2026-11-22; #0-303 done 2026-11-22; #0-301's code done 2026-11-22 (`factory` PR #26, pinned `v0.1.5`),
  its first call on the VM (AC4) after #0-313; next #0-313 and #0-302.
- The old path (`/backlog-autopilot` in the VM's devcontainer, the rollback that shares the VM by time) still runs
  until M4.
- **Order after M4 since 2026-11-22 (ADR-0063 as amended for the new product):** M5 with #0-285 (a user per slot,
  wiped after each task) and #0-289's rest; M9 alongside M5; then T, the new product's adapter, the `react` profile
  and the review rules split; M8 for the new product; N's first tasks; M6-lite (M6.4b, audits and `/seed-bugs` as
  task kinds, after M12); M12 right after it (low lane). Deferred:
  M7, M10, M11, #0-259,
  #0-260, #0-307, #0-306's thresholds. The new product's foundation (N), led by the owner, runs from now on.
  incident-platform stays public always; on the host's 32 GB, two slots in a 16 GiB build VM, each slot limited, and
  M6's review VM balanced again when it comes (R4).

## Done

- **0. Freeze hook hardening:** ADR-0055 (PR #620).
- **1. Organisation `profitbuild`:** the repository transferred, #0-237 (PRs #623–#626). The owner's step still open:
  2FA in the organisation.
- **2. Build VM:** Lima `factory-build`, `provision.sh`, rootless Docker as `factory`, egress allow-list (ADR-0056,
  ADR-0057), #0-238 (PRs #627–#650).
- **3. Baseline:** #0-205 (PR #652), from stage 2's three runs; P-27.
- **4.1–4.3c.** In order:
  - the `factory` repository (#0-267);
  - builder-app's code and the app itself, its key on the VM and five rulesets (#0-271, #0-272);
  - the dispatcher's foundation (#0-275), push (#0-276), Docker and the task container (#0-277, #0-282; ADR-0062);
  - from 4.1's review: #0-268, #0-269, #0-270, #0-273.

## Steps

### M1. The product's code from `main` (4.3d), DONE 2026-11-21
- carries: #0-278, as decided on 2026-11-21, with no growth of the `backlog-md` queue kind. `factory`'s first tag is
  `v0.1.0`.
- Done: the `factory` side, `factory` PR #20 (2026-11-21):
  - the adapter and the product's files read as blobs of `main`'s base (`src/product/base-tree.mjs`,
    `adapter-from-base.mjs`);
  - the product's commands run in the task container only (`commands.mjs`);
  - a branch that changes `trustedPaths` refused (`trusted-paths.mjs`, `checkChangedPaths`, on `withTaskObjects`);
  - `main` fast-forwarded with builder-app's token (`git/main-fetch.mjs`);
  - the open-PR item lock (`github/item-lock.mjs`);
  - `run --item 0-N | --resume <branch>`, with `--adapter` gone;
  - `check-app --adapter-from-repo`.
- Done, this repository's side (branch `ci/0-278-adapter-from-main`, `stage-4.md` "Done for 4.3d"):
  - `.factory/adapter.json` (Owner-only);
  - the lock fixture's original, run through `next-item.sh`'s definition, held equal to `factory`'s copy;
  - `install-builder-app.sh` on `--adapter-from-repo`;
  - the adapter validated in CI against its version, the tag checked at `FACTORY_COMMIT`;
  - `FACTORY_COMMIT` at `b5e29d83`;
  - `maven-settings.xml` read beside `_common.sh`.
- `factory`'s tag `v0.1.0` at `b5e29d83`: created by the owner on 2026-11-21, `verify-pins.sh` passed.
- Trial (2026-11-21): the VM recreated at `b5e29d83`, `check-app --adapter-from-repo` passed, and one run
  (`20261121T121255Z-adc1c7`) reached the end of its task container from base `a492170c`, the daemon swept after it.
- Exit: one run to the end of the task container from `main`'s base.
- Plan: `stage-4.md` "4.3", the decisions for 4.3d.

### M2. The build zone's flow in the dispatcher (4.4, narrowed): `migration/m2.md`, CURRENT
- umbrella: #0-287. Split into one item per pull request (2026-11-21), in order:
  - #0-299 (M2.0, the build agents in `factory`'s plugin);
  - #0-300 (M2.1, the spike; decided 2026-11-21, ADR-0064: managed settings, `--restricted` by measurement, the init
    event as the isolation check; spike in `factory`'s container done, F3 chosen, `factory` PR #23; done 2026-11-22,
    its VM part moved to #0-301);
  - #0-301 (M2.2–M2.3, the agent call and the phases; decided 2026-11-22: K2, f1, g1; code done 2026-11-22,
    `factory` PR #26, pinned `v0.1.5`, with AC6 against the pinned tag; its first call on the VM, AC4, after #0-313);
  - #0-302 (M2.4, the dispatcher's commits; #0-212 folded in; decided 2026-11-22, ADR-0060 D7 amended);
  - #0-303 (M2.5, per task: the task's lock, its liveness, the state lock, `FACTORY_SLOTS`; its sweep's scope and
    the Maven cache moved to M3.4, #0-285, the owner's option B, 2026-11-21; done 2026-11-22, `factory` PR #25,
    pinned `v0.1.4`);
  - #0-304 (M2.6, what 4.3a–c left);
  - #0-313 (M2.7, the credential proxy's core before the first real call; split from #0-289, ADR-0063 as amended
    for #0-301, 2026-11-22; widened 2026-11-22 by the review of opencomputer: the task's allowlist without
    Anthropic, the proxy's missing parts, `ANTHROPIC_UNIX_SOCKET` measured);
  - #0-315 (`factory`'s slice limited, before the next trial on the VM; the review of opencomputer; done 2026-11-22:
    `provision.sh`'s drop-in checked by `create.sh`, PR #699; AC2's trial dropped `MemoryHigh`, which hung a runaway
    and the daemon instead of an OOM kill);
  - the review of opencomputer (2026-11-22): what it changes and why, `migration/opencomputer.md`.
- carries too: #0-280 (the gate's schema against `run-tests.sh`; done, PR #680), #0-284 (decided 2026-11-21, ADR-0062 amended; the container checked before anything
  runs; code merged in `factory` PR #22 and #24, pinned `v0.1.3`; done 2026-11-22, AC8's second trial
  passed after the first was refused on `OomScoreAdj`; follow-ups #0-308 and #0-310,
  #0-309 moved to M3.4), #0-249 and #0-283 (Claude Code pinned, `dev`'s firewall rule; done 2026-11-21, ADR-0065;
  `factory`'s own devcontainer #0-311).
- part: #0-261's per-task baseline and the gate's short summary (in #0-301).
- superseded at M4 by its removal: #0-213, #0-217, #0-226, #0-228, #0-234, #0-236.

### M3. Push, PR, trace and the credential proxy (4.5–4.7): `migration/m3.md`
- umbrella: #0-288. Split into one item per pull request (2026-11-21), in order:
  - #0-305 (M3.1–M3.2, the checks before a push, push and PR);
  - #0-306 (M3.3, the trace and `audit-data.sh`; #0-204 folded in);
  - #0-285 (moved to M5 on 2026-11-22, before its two slots, decided as a user per slot wiped after each task; was
    M3.4, what a task leaves for the next task's credential, before the proxy; with it the daemon's model,
    the orphans' sweep, the Maven cache and #0-309, from #0-303; nested rootless Podman added as an option to compare,
    with limits per container and a socket per task, 2026-11-22);
  - #0-289 (moved to M5 with #0-285 on 2026-11-22; was M3.5, what is left of the proxy after #0-313: #0-274, the shared daemon's token, the transcripts; the
    task allow-list without Anthropic's hosts moved to #0-313's AC7 on 2026-11-22);
  - #0-307 (M3.6, the factory pin from one source; deferred on 2026-11-22, no step).
- the dispatcher's pull requests are held by the required `Factory guards` (rules 1, 2, 4), so the plugin's
  implementer needs no `guard-tests`/`guard-migrations` hook (`m3.md` "Before").
- related: #0-256 (the PR description opens with the problem).

### M4. The old path removed: `migration/m4.md`
- carries: #0-290.
- before: the `/seed-bugs` baseline of P-25..P-27 on the old panel (M6's measure).
- keeps: `factory-ops` and what `/seed-bugs` and `/audit` run through it, until M6 ports them.
- audits: from M4 to M6 the owner starts them by hand at the count (`m4.md` M4.1b).
- closes, as done by stage 4's dispatcher: #0-213, #0-217, #0-225, #0-226, #0-228, #0-234, #0-236, #0-251, #0-253, #0-254.
  #0-258 names itself superseded by the dispatcher's own canary.
- ADR-0053 is superseded by ADR-0060. ADR-0052 and ADR-0034 are amended for builder-app alone. ADR-0062 point 5 is
  reversed by ADR-0063.

### M5. Issues + Project and dispatcher v1 (7): `migration/m5.md`
- carries:
  - #0-291 (the queue's schema in GitHub and its trust rule);
  - #0-292 (the open items moved, `BACKLOG.md` frozen);
  - #0-293 (dispatcher v1: claim, lease, Priority, two slots, rebase work, timer);
  - #0-261's remainder (the GraphQL rate limit);
  - #0-265 (a task back after a pause).
- superseded: #0-201.
- waits: #0-264 (strict checks are part of #0-293; a merge queue is not available on Team private).
- The item id moves from `0-N` (the `backlog-md` kind) to an issue's number. This map's references move to the
  issues, or this file freezes with `BACKLOG.md`.

### M6. The review zone and the lanes (5 + 6a): `migration/m6.md`
- carries:
  - #0-294 (the review VM, review-app, the dispatcher's review, reviewers without Bash, two slots; since 2026-11-22
    M6-lite: `/seed-bugs` and `/audit` as task kinds and `factory-ops`' removal, M6.4b, after M12);
  - #0-295 (`factory/lane`, `factory-trace`, `factory/human-gate`, CODEOWNERS, `/human-review`);
  - #0-153 (the paths that need the owner);
  - #0-262 (review-app's comment format);
  - #0-259 and #0-260 (a second model, disputes with evidence; deferred since 2026-11-22).
- before: #0-171, #0-190, #0-218, #0-219 (the `/seed-bugs` items) and #0-178.
- superseded: #0-183, #0-167, #0-227.
- review-app's required status is bound to it by `integration_id`. Every ruleset refuses review-app until it is
  listed as an `Integration` (the probe of 2026-11-19, `stage-4.md` "4.2").

### M7. Hook cleanup (6c): `migration/m7.md`
- carries: #0-296.
- superseded: #0-210, #0-211, #0-214.
- ADR-0054 and ADR-0050 are amended.

### M8. Planning and features (8): `migration/m8.md`
- carries: #0-297 (`bc-app`, `/plan-feature` and `feature-planner`, the brief, the `Feature:` trailer; for the new
  product since 2026-11-22, without `FeatureFlags` in incident-platform's `shared` and without M8.4's check).
- An autonomous planner has no step. It enters when build slots stand idle for lack of Ready tasks (ADR-0063 G3).

### Factory items in no step
Open factory items no step carries, done when their turn comes in the queue:
- #0-255, #0-257, #0-221, #0-224, #0-69, #0-2 and #0-152 B;
- #0-316 (the product's `CLAUDE.md` as a short starting point) and #0-317 (a file-size ratchet in `factory`'s CI),
  from the review of opencomputer (`migration/opencomputer.md`).
- #0-318 (git's stderr out of a stop's reason in `base-tree.mjs`), from the review of `factory` PR #26 (#0-301).

They were listed in the stage map's "Factory items in no stage" before ADR-0063. Each is re-read against its step
when it is taken, since a step may have removed what it changes.

### Gates, from M5 on (6b), as ordinary items
- #0-108 (ArchUnit), #0-263 (a bug fix's test run on the code before the fix), #0-112 (mutation testing), and
  Squawk, commitlint and the `TODO` reference check (no items yet).
- Each removes its rule from the prompts. None blocks a step.

### M9–M12: `migration/m9-m12.md` (#0-298, split into items as each step comes)
- **M9, private on GitHub Team (9):** since 2026-11-22 alongside M5; private are the new product and `factory`,
  incident-platform stays public always; the new product's CI on GitHub's runners, its minutes measured after the
  first month (ADR-0063 as amended for the new product, R2);
  - related: #0-264; #0-230, #0-231, #0-232 no longer a condition (incident-platform's CI stays on GitHub's runners);
  - `factory`'s anonymous fetches become a token's (#0-314); incident-platform's clone stays anonymous;
  - carries: #0-314 (`factory` private too, its anonymous fetches with a read token).
- **M10, holdout (H).**
- **M11, the cloud (C):**
  - carries: #0-116's remaining part;
  - deferred here (D6): #0-239, #0-242, #0-243, #0-244, #0-274, #0-279, #0-281.
- **Before M12, with #0-285's way: tasks isolated from each other (ADR-0063 G1-b phase 2; done by #0-285 in M5 since
  2026-11-22, a user per slot wiped after each task, so what follows is the record of the options).** A Sysbox spike on Lima
  arm64; if it passes, Sysbox; else a VM user and rootless daemon per slot. #0-285 also compares nested rootless
  Podman in the task container (2026-11-22, `migration/opencomputer.md`); choosing it would amend G1-b.
- **M12, auto-merge on the low-risk lane (10).** The conditions below.
- **T** (template of a product repository) and **N** (the new application) as ADR-0055.
  - T carries #0-272's five rulesets as the template's, with every app listed as an `Integration` and a file under
    `apps/` for each.
  - Open: with a second product, where the organization's app list lives.

### Conditions for auto-merge (M12)

Set by the analysis of 4.2 (2026-11-19), the eighth by ADR-0063. No single key may be enough to merge into `main`, so
a leaked builder-app key yields at most a PR that waits. Before auto-merge is switched on:
1. **The author is not the approver.** builder-app (build VM) pushes; review-app (M6, review VM, another key)
   approves. This waits for ADR-0034's phase 3, since the approval `main` requires today is the code owner's (the
   CODEOWNERS catch-all, one approval).
2. **Every required status is bound to its app** by `integration_id`, so no other credential sets one of the same
   name.
3. **An approval is bound to the head's SHA**, so a new push needs a new one. Whether it is a status or a review with
   `require_last_push_approval` is M6's choice. A verdict carried by an identical patch id (ADR-0063 G4) is set by the
   review zone's dispatcher, never by builder-app. It is an identical `git patch-id --verbatim` of the whole
   `merge-base..head` diff, and the owner's approval and the human gate are never carried.
4. **"Low risk" is decided by GitHub** (a ruleset or a required check over the changed paths), never by the
   dispatcher's word. CODEOWNERS still takes the owner for the Owner-only paths.
5. **builder-app writes only `factory/**`**, and tags are the admin's (#0-272's rulesets).
6. **The approval that lets a pull request merge is one no app can give** by holding Pull requests write: a code
   owner's review or a ruleset's required reviewer. An app's approval counts as a required review (#0-272's probe P2),
   so with one plain approval builder-app could approve the bot's or Renovate's pull requests.
7. **Whoever merges may delete the head branch.** GitHub deletes it as the merger (#0-272's probe P1), so a branch
   under `branches` or `renovate` merged by an actor outside their bypass stays.
8. **No task can change another task or leave state for a later one** (ADR-0063 G1-b): the isolation before M12 is
   built and tried.

- waits: #0-264, #0-153.
- before: the steps that close #0-236 (M2–M4), #0-167 (M6) and #0-225 (stage 2 and M2–M4) have passed their exits;
  and every hardening item D6 deferred is re-checked, since D6 rests on a PR the owner reads.
