# ADR-0038: A change to the factory is judged by its own rule file, `factory.md`, read by security and architecture only when the diff touches an Owner-only path (backlog #0-161)

- **Status:** Accepted (2026-10-24)
- **Backlog:** #0-161
- **Date:** 2026-10-24
- **Author:** human (owner chose B′ and, after the research, the trigger and the architect's exception; written up by Claude Code in the owner's session)
- **Reversible:** yes

## Context

A finding blocks only when it cites a rule of its own dimension by id (`.ai/rules/review/_common.md`, "When a
finding is blocking"). The rule files judged the services' code only — `security.md` tenant isolation and the
security chain, `architecture.md` boundaries and decided patterns — so a defect in the AI factory (a hook that
exits 1 instead of 2, which Claude Code runs past; an agent given the network; a list copied without a check)
could only be non-blocking. Every round of the review of #0-160 reported it as `ruleGap`, from security,
architecture and general.

Who reads the rule files decides what any new one costs: the reviewer reads `_common.md` and its own file; the
implementer `general.md`, `architecture.md` and `security.md` in full for every item; the architect all of
`.ai/rules/review/` (`.claude/agents/architect.md`). And no autopilot item can change the factory: its paths
are on the Owner-only list of `.ai/rules/protected-paths.md`, so `pathGate` stops such a diff before the panel
and `next-item.sh` never starts an item whose Touches names one. Rules for the factory judge, in practice, the
owner's manual `/review`.

## Decision

- **One rule file, `.ai/rules/review/factory.md`, with ids of two existing dimensions**: `FAC-S01`…`FAC-S06`
  belong to security (`FAC-S01` is the rule of two: no agent reading text someone else controls may both reach
  a secret and send data out; then the network, tools and scopes, guards that fail closed, secrets out of
  reach, the owner's denies), `FAC-A01`…`FAC-A05` to architecture (one list per control, agents' answers that
  fail closed, every stage in the PR record, guards at session level, a weakened layer named). Its section 3
  names what Factory guards and Lint Workflows already check, so reviewers do not repeat a script. **Amended by
  #0-115 (2026-10-28):** section 3 is gone; each check is the "Backed by" of the rule it backs (`_common.md`'s
  labels), so a reviewer reads a rule and what checks it in one place, and the "Check:" line says what the check
  misses. The linters that back no rule are named in one paragraph without an id.
- **Read only when the diff touches a path of the Owner-only list**, the list as it is on `main` (`/review` reads
  `origin/main`, and an unreadable list means the rules apply) — not a list of the file's own. `_common.md` names
  the exception to "nothing else from `.ai/rules/review/`"; `security.md`, `architecture.md`, the two reviewers'
  definitions and `review-procedure` say when; `/review` decides it in its Step 2 and tells both reviewers
  (Step 4). **Amended by #0-270 (2026-11-19, the owner):** for a pull request of `profitbuild/factory`
  (`/review factory#<n>`) it is read every time, whatever its paths. The Owner-only list draws the factory's edge
  in this repository's layout; in `factory` every path is factory code, and its core, `dispatcher/` (builder-app's
  key and tokens from 4.2), matches no entry, so the trigger would have judged it without `FAC-` rules (review round
  1 of #0-270). Still decided by `/review` alone, in its `factory#<n>` section; no second path list.
- **Nobody else reads it**: the architect reads every rule file but `factory.md`, the implementer never does
  (`implementation.md`); `RULE_FILE_OF` maps `FAC` to `factory` only so that an id is never dropped.
- **Knowledge without ids** in `.ai/context/security.md`, "AI factory": why the rules are what they are (the
  rule of two applied to the reviewers and the verifier, where each list lives, what each layer is worth).

## Alternatives considered

- **The rules in `security.md` and `architecture.md`**: the implementer reads both in full for every item, for
  rules about paths it may never change — a cost on every autopilot run for nothing.
- **Rules with ids in `.ai/context/security.md`**: agents may edit `.ai/context/`, and a rule that blocks must
  not live in a file the judged change can rewrite (#0-153); the ids would also map to no rule file.
- **A new dimension `factory`**: an agent, a gate and an audit dimension for changes that reach only the
  owner's `/review` — too few for the audit's three cases, and the findings are security's and architecture's
  in kind.
- **A trigger list of `factory.md`'s own** (only `.claude/`, `scripts/factory/`, `.devcontainer/`): a second
  copy of the protected paths, the drift #0-122 removed from ten places. The Owner-only list is wider
  (`architecture-tests/`, `AGENTS.md`, `.ai/plan/`), which costs a read, not a wrong verdict.
- **Each reviewer deciding from `protected-paths.md` on its own**: what the review of #0-161 found in the
  first draft; `/review` gates migration and k8s by code, so it decides this one too.

## Consequences

- A defect in the factory can block, by a `FAC-` id, in the owner's `/review`; a change outside the Owner-only
  paths costs the reviewers, the implementer and the architect nothing new to read.
- `FAC-` findings stay out of the audit's rule selection (`.ai/rules/audit.md`): they never occur in an
  autopilot run, whose records the audit reads.
- The rules for CI workflows (`.ai/context/security.md`, "CI workflows") still have no ids: #0-136, which may
  follow this form.
- Factory guards checks lists, not prose: the trigger sentence is repeated in eight files (`_common.md`,
  `security.md`, `architecture.md`, `factory.md`, the two reviewers' definitions, `review-procedure`,
  `/review`), and nothing but review keeps them alike.
- `/review` pre-approves exactly the one `git show` it needs, never `git show *`: `--output=<file>` writes
  anywhere, and the owner's session has no Bash hook (review round 2; the older `git diff *` is #0-165). Since
  #0-165 (ADR-0042) `/review` pre-approves exact commands only; a hook for every session is #0-167.
- A reviewer recognises a violation as: a second list of the factory's paths, `factory.md` read by an agent
  other than security and architecture or its trigger decided elsewhere than `/review` Step 2, a `FAC-` rule
  that repeats a check of section 3 (since #0-115: a check named apart from the rule it backs), or a factory rule
  with an id outside `factory.md`.
