# ADR-0055 stage 3: the baseline — DONE (2026-11-17)

## 1. Goal and exit

ADR-0055, as amended on 2026-11-17: "Baseline metrics: agent calls, times, tokens, model, tools, refusals per agent
call, from the runs' transcripts, kept off the build VM (#0-205; amended 2026-11-17: from stage 2's three runs, no new
runs of the old path; #0-204's per-call commit trace moves to stage 4, where the dispatcher records it); a seed pattern
for a removed positive control (PR #572; the next free id after #0-218's P-25 and P-26)". Exit: numbers for 3 items.
Rollback: revert.

Why it exists: stage 4 replaces how agents are run, and stage 5 how they are reviewed. Without numbers from the old
path, neither can say whether it made the factory cheaper, faster or worse.

## 2. What exists now

- `scripts/factory-admin/run-summary.sh <wf dir>` (owner-run; autopilot sessions may not run `scripts/factory-admin/`).
  From one workflow run's transcripts it prints `{"ok": true, "run": {...}, "calls": [...]}`: per agent call its type,
  phase, label and `answered` (from `journal.jsonl`), models, turns, tokens by kind, start and duration, tools,
  paths read and written, programs, refusals with the hook that gave them, other errors; per run the totals by agent
  type and model, refusals by hook, unanswered calls and wall time.
- `.github/scripts/test-run-summary.sh`, run by Factory guards ("Run summary tests").
- The owner's archive on the Mac, outside any repository: `~/factory-archive/` (the three runs' directories and their
  `wf_<id>.summary.json`).
- The baseline table in `BACKLOG-DONE.md` #0-205 "Baseline (AC4)".
- P-27 in `.ai/audit/benchmark/patterns.md` (general, GEN-03).

## 3. How it was done

1. Analysis (2026-11-17): stage 3 as written (#0-204 and #0-205 in today's workflow, 3 new runs) would build a recorder
   into code stage 4 replaces. Variant B was chosen: derive everything from the transcripts, which outlive the
   workflow, and use stage 2's three runs, whose transcripts were still on the VM.
2. Check on the VM, in the devcontainer: the three `wf_*` directories present (18, 24 and 22 agents), every assistant
   line with `model` and `usage`.
3. `.ai/context/migration.md` written first (PR #651), so the stages and their items are mapped before the work.
4. `run-summary.sh` and its test written, run on 46 local runs of the Mac (all summarised, 2 directories without an
   agent refused), mutation-checked.
5. Archive: in the devcontainer `tar -czf /tmp/stage2-runs.tgz <session>/subagents/workflows/<wf_id> …` from
   `~/.claude/projects/-workspace`; in the VM `docker cp <container>:/tmp/stage2-runs.tgz /tmp/`; on the Mac
   `limactl copy factory-build:/tmp/stage2-runs.tgz ~/factory-archive/`; then both temporary copies deleted (the
   container's had mode `rw-rw-rw-`).
6. The summaries computed, the baseline recorded in #0-205; ADR-0055 rows 3 and 4 amended; #0-204 moved to stage 4;
   #0-251, #0-253, #0-254 frozen as superseded by stage 4. Review: `/review 6`, `/review 127` rounds 1 and 2,
   `/review 2` round 3 (PR #652).
7. P-27 written from the real escape (PR #653).

## 4. The baseline

| Run | Item | Calls | Turns | Wall | Output tokens | Cache read | Calls by model (Haiku 4.5 / Sonnet 5.5 / Opus 5.5) | Refusals |
|---|---|---|---|---|---|---|---|---|
| `wf_5135023f-b7d` | #0-25, full run | 24 | 181 | 19 min | 117,862 | 12.3 M | 11 / 7 / 6 | `readonly-bash.sh` 5, a `dontAsk` denial 1 |
| `wf_207ec85e-4ad` | #0-58, resumed at the gate | 18 | 71 | 7 min | 31,309 | 1.4 M | 9 / 6 / 3 | `readonly-bash.sh` 3 |
| `wf_e5a616a0-073` | #0-23, full run | 22 | 120 | 11 min | 60,453 | 4.3 M | 0 / 18 / 4 | `readonly-bash.sh` 4 |

Each run also has one refusal by `isolation-probe.sh`, by design (ADR-0058). The implementer and the architect carry
most of the cost (in #0-25: implementation 60 turns and 54,744 output tokens, plan 25 turns and 21,051, against a
panel of 9 calls with 47 turns and 19,052); pick, preflight and acceptance stay under 10 turns and 4,000 output tokens
a phase.

## 5. Decisions made on the way

- The summary is derived, not recorded (#0-205's original reasoning: a logger hook records again what transcripts
  hold, sits on every call and stops a run when it fails).
- It refuses a transcript shape it does not know, as `seed-scan.sh` does (ADR-0044 decision 6). The two headers name
  each other; they differ on purpose on a malformed `journal.jsonl` (the scan reads on, the summary refuses).
- A command keeps its program, and one lower-case word only after a program that takes a subcommand (`git`, `gh`,
  `docker`, `kubectl`, `limactl`, `npm`, Maven, the factory's scripts): `echo <secret>` gives `echo` (review round 1,
  SEC-31); an option's value before the subcommand can take its place (`git -C repo status` gives `git repo`).
- Tokens per API message are the largest value of each `usage` field across its lines (372 messages checked, none
  differ today; review round 2, GEN-01).
- `audit-data.sh` reading the summaries moves to stage 4, where the dispatcher has one for every run; an agent given
  the archive's path is judged by FAC-S01 first (the archive holds raw transcripts).

## 6. What we learned

- Claude Code documents its transcript format as internal and changeable (code.claude.com/docs/en/sessions.md,
  cited in ADR-0060's Context): stage 4 captures `stream-json` per call
  (ADR-0060 D1, step 4.6) and `run-summary.sh` is the bridge until then.
- Verifier agents cannot reach transcripts or the VM; such claims were checked by hand on the archive.

## 7. How to use it again

`docs/ai-factory.md` "Measuring the reviewers and the pipeline", the bullet "A run's cost and behaviour": archive a
run's directory off the VM (unpack it as untrusted, into a directory of its own, plain `tar`, never `-P`), then
`scripts/factory-admin/run-summary.sh <dir>`.

## 8. Left open

- P-27's first `/seed-bugs` run, with #0-218's P-25 and P-26, before stage 5.
- #0-259 (a second model's review) and #0-260 (disputes with evidence) can now be measured against this baseline.
- No rule yet says what an archive or summary of transcripts may hold or where it may be published (security review
  of PR #652, rule gap; `.ai/rules/` is the owner's).

## 9. Sources

PRs #651, #652, #653; `BACKLOG-DONE.md` #0-205; ADR-0055 (amended), ADR-0044, ADR-0058; `BACKLOG.md` #0-204, #0-218,
#0-259, #0-260.
