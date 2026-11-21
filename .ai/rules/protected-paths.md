# Protected paths

Owned by the maintainer; agents never edit it. The paths no agent of the AI factory writes: the rules and
configuration the agents are judged and limited by, the factory's own gates, and the build files every
verification runs. A change to any of them is the owner's, so an item that must write one is not autopilot
work (`ready.md` point 3): it is `human-only`, or split so the owner does that part first.

**This file is the one list.** Who uses it:

- **Code** reads the lists between the markers below, from the base commit: `scripts/factory/changed-paths.sh`
  (a diff that touches them needs the owner), `next-item.sh` / `check-queue.sh` (an item whose
  `**Touches:**` names one never starts and cannot be queued) and `.github/scripts/check-factory-guards.sh`
  rule 6 (a PR changing the build configuration needs the owner; from the merge base).
- **Agents** read this file: `ready-checker` and `/ready` (the item is not autopilot work), the planner
  (not queued), the architect (stop before the implementer), the implementer (out of scope, stop), every
  reviewer (`NEEDS_HUMAN`, `.ai/rules/review/_common.md`).
- **`/review`** reads the Owner-only list as it is on `main` (its Step 2, `git show
  origin/main:.ai/rules/protected-paths.md`): a diff that touches one of its paths has `review-security` and
  `review-architecture` also read `.ai/rules/review/factory.md` (backlog #0-161, ADR-0038); when the list
  cannot be read, those rules apply.
- **Three copies stay**, because the last line of defence must not depend on parsing this file: the
  Edit/Write deny rules of `.claude/settings.autopilot.json`, the shell-write check of
  `.claude/hooks/guard-protected-bash.sh`, and `.github/CODEOWNERS` (the owner's review on a PR, for the
  owner-only list; the build-config list is guarded on PRs by rule 6 above, which reads this file).
  `.github/scripts/check-protected-paths.sh` fails CI when one of them misses an entry here — for
  CODEOWNERS, when the line GitHub applies (the last match) names no owner — and, the other way, when the deny
  rules or the hook protect a path none of these lists holds (backlog #0-168): a copy must not claim a
  protection the code that reads this file does not apply.

Fixed (backlog #0-122, found by #0-42's run, draft PR #477): the list existed in about ten places that had
drifted apart (the hook did not cover `.ai/audit/decisions.md`; a copy treated all of `CLAUDE.md` as
protected), and `/ready` marked an item `ready` whose criteria needed `.github/`, which only the
implementer then refused.

Format: one entry per line between the markers, `` - `<path>` — <why> ``. A path ending in `/` is a
directory and everything under it; any other path is one file.

## Owner-only

<!-- protected:start -->
- `.ai/rules/` — the rules every agent is judged by
- `.ai/plan/` — the execution queue the owner approves
- `.ai/audit/decisions.md` — the owner's decisions on audit recommendations
- `.claude/` — agent definitions, skills, workflows, hooks and the autopilot's permissions
- `.github/` — CI, the checks that guard `main`, CODEOWNERS
- `architecture-tests/` — the ArchUnit rules and their frozen store
- `AGENTS.md` — the instructions every assistant reads first
- `scripts/factory/` — the autopilot's deterministic gates
- `scripts/factory-admin/` — the owner's tools (breaker and audit counter reset, the local implementer, the seed-run scan)
- `.devcontainer/` — the sandbox and its firewall
- `.factory/` — the product's adapter: the dispatcher's gate, its trusted paths and the factory version it runs (backlog #0-278)
<!-- protected:end -->

## Build configuration

What every verification runs; a change could make a failing build pass.

<!-- build-config:start -->
- `.mvn/` — the Maven wrapper's configuration
- `mvnw` — the Maven wrapper
- `mvnw.cmd` — the Maven wrapper (Windows)
- `.ruby-version` — the Ruby every `.github/scripts/*.rb` check of CI runs on (ADR-0040)
- `.node-version` — the Node every JavaScript test of CI runs on (ADR-0043)
<!-- build-config:end -->

## Runtime state

The autopilot's own state and git's: not repository content (gitignored, or `.git/` itself), so no diff or
`**Touches:**` names them and the code above does not read this list; the deny rules and the hook protect them,
and `check-protected-paths.sh` checks that they do (backlog #0-168).

<!-- runtime:start -->
- `.git/` — the repository itself: refs, config, hooks
- `.ai/runs/LOCK` — the lock that keeps a second autopilot run away
- `.ai/runs/state.json` — the run state and the breaker's count
- `.ai/runs/ops-calls/` — one mark per factory-ops run, which gives it its one call (backlog #0-169, ADR-0053; protected since #0-233)
- `.ai/runs/isolation/` — which agent type sent a run's isolation probe, as Claude Code named it (backlog #0-252, ADR-0058)
- `.ai/STOP` — the autopilot's stop switch (set by the breaker, the audit trigger or the owner)
<!-- runtime:end -->

## Partly protected

- `CLAUDE.md` — only its `agent-editable` blocks are the implementer's (today: "Commands"). Not in the
  lists above, because an item may legitimately change a block. `changed-paths.sh` compares the text
  outside the blocks; an item that must change that text is not autopilot work, and the architect stops it.
