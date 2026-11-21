# AI Workspace

> This directory contains structured knowledge for AI assistants working on Incident Platform, and the
> rules the AI factory (the autopilot that works through `BACKLOG.md`) is held to.
>
> The AI Workspace is treated as part of the production engineering system.
> Changes to this directory follow the same review standards as source code changes, and
> `.ai/rules/` is owned by the human maintainer (CODEOWNERS): agents read it and never edit it.

---

# Purpose

The purpose of the AI Workspace is to provide reliable project context for AI-assisted development.

AI assistants cannot always infer architectural intent, business constraints, engineering decisions, or historical context from source code alone.

This directory stores knowledge that helps AI assistants:

- understand the system before making changes,
- preserve architectural consistency,
- avoid introducing unnecessary complexity,
- make decisions aligned with project principles,
- collaborate effectively across different development tasks.

The goal is not to replace source code documentation.

The goal is to document the knowledge that cannot be reliably extracted from the codebase.

---

# Documentation Philosophy

The AI Workspace follows these principles:

## 1. Context over prompts

Project knowledge is more valuable than generic AI instructions.

The quality of AI output depends primarily on the quality of context provided to the assistant.

---

## 2. Document intent, not implementation

Source code explains **how** the system works.

AI documentation explains:

- why decisions were made,
- what constraints exist,
- what principles must be preserved,
- what alternatives were rejected.

---

## 3. Documentation is part of development

A feature is not considered complete if it changes system knowledge without updating relevant AI documentation.

Examples:

- new architectural pattern → update architecture context,
- new security rule → update security context,
- important technical decision → create ADR.

---

## 4. Less, read selectively

Every line an agent reads costs context and attention, and an instruction an agent does not need still
changes what it does. Files that load into every session (`CLAUDE.md`, `AGENTS.md`) stay short; the rest
is read by the task that needs it (the reading order below). Agents propose additions; a human writes
them. A rule that never catches anything is removed at the next audit.

---

# Workspace Structure

Directories are created when they provide real value. Current structure:

```text
.ai/
├── README.md                  ← this file: map, reading order, file contract
├── context/                   ← what the system is and which invariants hold
│   ├── project.md             ← purpose, domain, users, service map, index of decisions
│   ├── architecture.md        ← shared, persistence, decided patterns (moved from CLAUDE.md)
│   ├── security.md            ← tenant isolation and authentication (moved from CLAUDE.md)
│   ├── infrastructure.md      ← CI rules and supply chain (moved from CLAUDE.md)
│   ├── migration.md           ← the factory's migration: ADR-0063's steps M1–M12 mapped to backlog items; migration/ holds each step's plan
│   └── migration/             ← the records of finished stages (stage-1..4.md) and the plans of the remaining steps M2–M12 (m<N>.md), each written before its first item
├── decisions/                 ← ADRs: README.md is the index, _template.md the format
├── rules/                     ← HUMAN-OWNED criteria the agents are judged by
│   ├── review/                ← one file per review dimension + _common.md
│   ├── acceptance.md          ← what counts as evidence that an acceptance criterion holds
│   ├── ready.md               ← when a backlog item may be marked `ready` for the autopilot
│   ├── planning.md            ← order, Touches and follow-ups of the execution queue
│   ├── implementation.md      ← how the implementer works (calibrated by audits)
│   ├── protected-paths.md     ← the one list of paths no agent writes (scripts read it too)
│   └── audit.md               ← how audits rate findings and when they may recommend a change
├── plan/                      ← HUMAN-OWNED: the approved order of work
│   ├── README.md              ← what the queue is and who changes it
│   └── queue.md               ← execution queue (planner proposes via /plan-backlog, owner merges; created by the first plan)
├── audit/                     ← audit reports and the owner's decisions on them
│   ├── decisions.md           ← ledger: every recommendation and what the owner decided
│   └── benchmark/             ← seeded-defect patterns used to measure the reviewers
├── work/_template/            ← templates of the per-item working files
├── work/<item>/               ← EPHEMERAL: exists only on the item's branch, removed before merge
├── runs/                      ← raw logs of autopilot runs (gitignored)
└── STOP                       ← local kill switch (gitignored); present = the autopilot does not start
```

Not created yet, on purpose: `context/frontend.md` (no frontend in this repository yet),
`rules/frontend.md`, and the `agents/`, `playbooks/`, `workflows/` and `reviews/` directories of the
earlier target structure. Agent definitions live in `.claude/agents/` (one implementation, no
tool-neutral copy that could drift); review criteria live in `rules/review/`; workflows in
`.claude/workflows/`.

---

# Reading Order

Before making any implementation decision, read in this order, and only what your task needs.

## Step 1 — Understand the system

```
.ai/context/project.md            (always: purpose, service map)
```

## Step 2 — Understand the area you touch

| Your change touches | Read |
|---|---|
| a tenant id, authentication, a filter chain, an HTTP client between services, Kafka, a notification recipient, tenant status | `.ai/context/security.md` |
| `shared`, an entity, a repository, a migration, a scheduler, an outbox, retries | `.ai/context/architecture.md` |
| `.github/`, a Dockerfile, `k8s/`, `docker/`, a POM's plugins | `.ai/context/infrastructure.md` |
| the factory's migration (ADR-0055's target, ADR-0063's steps): a step, or an item that belongs to one | `.ai/context/migration.md`, then the step's `migration/m<N>.md` |

## Step 3 — Check previous decisions

```
.ai/decisions/README.md           (the index; then only the ADRs whose area you touch)
```

Existing decisions are respected unless a new ADR changes them.

## Step 4 — Check the rules you will be judged by

| Role | Read |
|---|---|
| implementer | `.ai/rules/implementation.md`, `.ai/rules/protected-paths.md`, the item's acceptance criteria; `.ai/rules/review/general.md`, `architecture.md`, `security.md` in full and `_common.md` (blocking criteria); from the other review files, the rules the plan lists, or the whole file when the autopilot asks for a self-check |
| reviewer of dimension D | `.ai/rules/review/_common.md` (with `.ai/rules/protected-paths.md`), `.ai/rules/review/<D>.md`; security and architecture also `factory.md` when the diff touches an Owner-only path (#0-161) |
| acceptance reviewer | `.ai/rules/acceptance.md` |
| architect | `.ai/rules/ready.md`, `.ai/rules/protected-paths.md`, all of `.ai/rules/review/` but `factory.md` (it selects the rules the implementer gets; no item reaches the factory's paths), `.ai/rules/planning.md` ("Touches") |
| planner | `.ai/rules/planning.md`, `.ai/rules/ready.md`, `.ai/rules/protected-paths.md`, `.ai/plan/queue.md` |
| ready-checker (`/ready`) | `.ai/rules/ready.md`, `.ai/rules/protected-paths.md` |
| auditor | `.ai/rules/audit.md` (the pipeline auditor: its "Pipeline audit"), `.ai/audit/decisions.md` |

---

# File Contract

Who writes and who reads each file. One writer per file per stage; `progress.md` is append-only.

| File | Written by | Read by |
|---|---|---|
| `BACKLOG.md` (item text, `ready`) | owner | picker, architect, acceptance-reviewer |
| `BACKLOG.md` (status `In progress` / `Blocked`) | autopilot (`start-item.sh` / shipper) | owner |
| `BACKLOG.md` (`**Touches:**`, added `**Depends on:**`) | planner, ready-checker (drafts) — owner approves by merge | planner, `next-item.sh`, `check-queue.sh` |
| `BACKLOG.md` (new `proposed` follow-up items) | shipper, from `handoff.md` "Follow-up needed" | owner (`/ready`) |
| `.ai/plan/queue.md` | planner (proposal, `/plan-backlog`) — **owner approves by merge**; autopilot never | `next-item.sh`, `check-queue.sh`, planner |
| `BACKLOG-DONE.md` (new row, and the item's section moved to its "Details") + removal from `BACKLOG.md` | shipper, `/ship` | everyone resolving `backlog #N` |
| `CLAUDE.md` inside `agent-editable` blocks | implementer | everyone |
| `CLAUDE.md` elsewhere, `AGENTS.md` | owner | everyone |
| `.ai/context/*` | owner; implementer in the same PR when the change creates the knowledge (reviewed by `review-docs`) | per reading order |
| `.ai/decisions/NNNN-*.md` | architect (`Proposed`, reversible decisions only), owner (`Accepted`) | implementer, reviewers |
| `.ai/rules/**` | **owner only** (deny rules + CODEOWNERS); audits only recommend | reviewers, implementer, architect, auditors |
| `.ai/rules/protected-paths.md` | **owner only** | the agents above; `changed-paths.sh` and `next-item.sh` (from the base commit), `check-queue.sh` (the base with `--ref`, the working tree in CI); `check-protected-paths.sh` (CI) compares the deny rules, the shell-write hook and CODEOWNERS with it |
| `.ai/work/<item>/progress.md` | every stage, append-only | autopilot on resume, every stage |
| `.ai/work/<item>/handoff.md` | implementer | reviewers, acceptance-reviewer |
| `.ai/work/<item>/proofs.md` | implementer | acceptance-reviewer |
| `.ai/runs/<item>/` (gitignored) | the test gate (`run-tests.sh`: test logs, the gate's artifact `gate-r*.json` and `dependency-tree-r*.txt`, also under `.ai/runs/manual/` for `/review`), autopilot | reviewers, acceptance-reviewer and the verifier (the artifact their task names, #0-160; the verifier reads nothing else, not even the logs, `read-scope.sh --name`); owner when debugging |
| `.ai/audit/<date>-<target>.md` (`reviewers`, `pipeline`) | audit workflow | owner |
| `.ai/audit/decisions.md` | `/apply-audit` (owner-run) | auditors |
| `.ai/audit/benchmark/patterns.md` | owner | `seed-bugs` workflow |
| `.ai/runs/benchmark/results.md` (gitignored) | `seed-record.sh`, one row per `/seed-bugs` run (#0-177) | owner, who lands a series' rows in `.ai/audit/benchmark/results.md` in one PR |
| `.ai/audit/benchmark/results.md` | owner (a series' PR) | `audit-data.sh` (the audit's seeded defects) |
| `.ai/runs/benchmark/clean.md` (gitignored) | `seed-record.sh --clean`, one row per clean `/seed-bugs` run (#0-180) | owner, who lands a series' rows in `.ai/audit/benchmark/clean.md` in one PR |
| `.ai/audit/benchmark/clean.md` | owner (a series' PR) | `audit-data.sh` (`seededClean`, the panel's false alarms on a rule's deliberate exception) |
| `.ai/STOP` | owner, circuit breaker | autopilot at start |
| PR description (verdicts in `<details>`), PR labels | shipper; `human:*` labels by the owner | auditors |

---

# Rules for AI Assistants

AI assistants working on Incident Platform should:

- understand existing architecture before proposing changes,
- prefer consistency over introducing new technologies,
- avoid unnecessary abstractions,
- avoid changing unrelated code,
- preserve security principles,
- consider backward compatibility,
- explain architectural trade-offs,
- identify risks before implementation.

AI assistants should not:

- introduce frameworks without justification,
- rewrite working code without clear benefit,
- create abstractions only for theoretical future needs,
- ignore existing architectural decisions,
- edit the rules they are judged by (`.ai/rules/`), their own configuration (`.claude/`) or CI
  (`.github/`).

How these apply per session: `CLAUDE.md` "Working style" governs interactive sessions with the owner;
an autopilot agent follows its definition in `.claude/agents/`.

---

# Core Engineering Principles

Incident Platform follows these principles:

## Simplicity

Prefer simple solutions that are easy to understand and maintain.

Complexity must have a clear business or technical justification.

---

## Explicit Architecture

Architectural boundaries, responsibilities and decisions should be visible.

Hidden complexity is considered technical debt.

---

## Security by Default

Security requirements are considered during design, not added afterwards.

---

## Production Mindset

Implementation decisions should consider:

- scalability,
- observability,
- failure scenarios,
- maintainability,
- operational impact.

---

## Incremental Evolution

The system evolves through small, controlled changes.

Avoid large rewrites unless there is a strong architectural reason.

---

# Updating AI Knowledge

When making changes to Incident Platform:

Ask:

> "Does this change introduce knowledge that an AI assistant cannot reliably infer from source code?"

If yes, update `.ai`.

| Change | Update |
|---|---|
| New service | `context/project.md` (service map), CLAUDE.md (ports), `context/architecture.md` |
| New technology or architectural decision | a new ADR in `decisions/` |
| New invariant on tenant isolation or authentication | `context/security.md` + ADR |
| New CI rule | `context/infrastructure.md` |
| New review criterion, or a criterion that keeps missing | `rules/review/<dimension>.md` (owner, usually via an audit) |
| New business workflow | `context/project.md` |

---

# Current AI Workspace Status

Current phase:

```
Phase 2 - AI factory, shadow mode
```

Implemented:

- AI Workspace structure, documentation principles, project context
- Context split by area; decisions as ADRs
- Review criteria per dimension, acceptance, readiness and audit rules
- Agents (`.claude/agents/`), the autopilot and audit workflows (`.claude/workflows/`)

Secret scanning: CI's Secret Scan job, on every commit a pull request adds (#0-109, ADR-0036); before the push,
not yet (#0-156).

Not implemented yet (tracked in `BACKLOG.md`): architecture tests (#0-108),
Maven Enforcer (#0-110), OpenAPI diff (#0-111), mutation testing (#0-112). The GitHub settings the
autopilot depends on are files in `.github/repository-settings/` (#0-113, ADR-0034). Until #0-116 and #0-153 are done
the autopilot runs in shadow mode only (it opens PRs, the owner merges). The phases are described in `docs/ai-factory.md`.
