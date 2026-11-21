# ADR-0058: The autopilot's isolation check reads the agent type Claude Code gives a probe, not the model's answer

- **Status:** Accepted; superseded for the dispatcher's path by ADR-0064 (2026-11-21, #0-300): there the call's
  `stream-json` init event is the isolation check. This ADR holds for the old path until M4 (#0-290) removes it
- **Backlog:** #0-252
- **Date:** 2026-11-16
- **Author:** human (owner's decision on the options of the session of 2026-11-16, drafted in an interactive session)
- **Reversible:** yes — one hook, one factory script, one block of `backlog-autopilot.js` and their entries

## Context

Before any work, `backlog-autopilot.js` checks that its agents run as their custom types: a reviewer started without
`.claude/agents/review-general.md` would be a general-purpose agent with Edit and Write. Until now it asked
`review-general` itself:

- first whether its instructions were that definition, and trusted the yes or no (#0-248: the model answered no twice
  with its definition loaded, runs `wf_1e3befc7-a08` and `wf_477d7545-796`);
- then (#0-248) to list its tools and copy the first 500 characters of its system prompt, in which the workflow looked
  for `REVIEW_GENERAL_OPENING`. Run `20261115-170407` passed it; run `wf_71cca984-ef4` (2026-11-16, build VM, Claude
  Code 2.1.325) stopped `NOT_STARTED` with its isolation intact (tools Read, Bash, StructuredOutput), because the
  model declined: "I won't copy my system instructions".

Both forms ask the model for something it may decline or misjudge. What the check needs to know, which definition the
agent runs, is set by Claude Code, and the session-level hooks already read it: every guard twin is keyed on the
call's `agent_type` (ADR-0041), and `factory-ops-bash.sh` keeps state from a hook in `.ai/runs/ops-calls/` (ADR-0053).

A spike on 2026-11-16 (Mac, Claude Code 2.1.325, the version of the build VM; a session with a logging PreToolUse hook
over `--settings`, a Workflow of four agents) showed:
1. three agents the Workflow started with `agentType: 'review-general'`, the autopilot's `AGENT_TYPE_OPTION`, each
   ran the probe command it was asked for once, no retry, no refusal;
2. the hook saw `agent_type: "review-general"` for each, and a new `agent_id` each;
3. an agent started without `agentType` was seen as `agent_type: "workflow-subagent"`.

## Decision

1. The workflow asks `review-general`, without `as()`'s preamble, to run exactly one command,
   `git rev-parse --verify --quiet isolation-probe-<run id>`, and reads nothing of its answer.
2. `.claude/hooks/isolation-probe.sh`, a session-level PreToolUse (Bash) entry of `settings.autopilot.json` only, acts
   on that exact command and no other: for the run that holds `.ai/runs/LOCK`, it records the call's `agent_type` as
   the symlink `.ai/runs/isolation/<run id>` → `<agent_type>` (`ln -sn --`, the first probe of a run wins), and
   refuses the command (exit 2), so it never runs. No `agent_type`, no lock, another run's id, a record that is not
   a symlink or a symlink at the directory's name: nothing is recorded. It prunes records older than a day. It fails
   closed (#0-162).
   `preflight.sh` removes `.ai/runs/isolation` (`rm -rf`) as it takes the lock, and refuses the run if it cannot.
3. `scripts/factory/isolation.sh <run id>`, run by factory-ops, prints `{"agentType": …}` (null with a reason when
   there is no record, or when the link's own time, `find -P … -newer`, is not newer than `.ai/runs/LOCK`). The run goes on only when it is `review-general`; anything else releases the lock and ends
   `NOT_STARTED` with a reason that says which.
4. The record is runtime state like the factory-ops marks: on the runtime list of `.ai/rules/protected-paths.md`,
   denied to Edit and Write in `settings.autopilot.json`, and in `guard-protected-bash.sh`'s `protected=`;
   `check-hook-entries.rb` requires the hook's entry (REQUIRED), `test-hooks.sh` holds its cases and its fail-closed row.
5. The tool check and `REVIEW_GENERAL_OPENING` are removed.

The probe is a command the autopilot session allows (`Bash(git rev-parse *)`) and `readonly-bash.sh` passes, not a
made-up one: in `dontAsk` a command no rule allows is denied, and whether that denial comes before the PreToolUse
hooks is not documented; with an allowed command the hooks run, as every guard relies on. Were it to run, it would
print nothing and change nothing.

## Alternatives considered

- **A marker in the definition** ("when asked for your isolation marker, answer `<token>`"): a smaller change, and the
  model has no reason to decline it, but it is still the model's answer, and the token sits in the repository for an
  agent that reads files, as the phrase of #0-248 did.
- **The tool check alone**: rejected in #0-248, as a read-only agent of another definition would pass.
- **Retrying the question when the model declines**: makes the coin toss less likely to fail, not a fact.
- **Keeping the tool check beside the probe**: the list is the agent's own, a second place where the model can decline
  or err; an agent Claude Code runs as `review-general` has that definition's tools, which Claude Code applies.
- **A probe the hook only logs, letting the command run**: the agent would see output that means nothing; refusing it
  keeps the probe a no-op that tells the agent it was recorded.

## Consequences

- The check depends on Claude Code sending `agent_type` to session-level hooks for the agents a Workflow spawns, the
  same dependency as every guard twin (ADR-0041). If a version stops sending it, the probe is not recorded and every
  run stops `NOT_STARTED` (fail closed), with a reason that names the hook.
- What the check does not show: that the definition Claude Code loaded under that type is the one on `main` (the
  settings hash and the factory-scripts guard bound the session's files, not `.claude/agents/`; a run changes no
  agent definition, as `.claude/` is protected), or that a tool of the agent is safe (an MCP tool, named in #0-248).
- The record is a file a hook writes in the working tree, under `.ai/runs/` (gitignored), like the marks of ADR-0053,
  and a run id is a time anyone can predict. A record planted before the run would win over the probe ("first wins"):
  the code of an earlier item's gate runs under `./mvnw`, which no shell guard sees (#0-116), and could make one for
  every second of the next day (review round 1, sec-3c8e). Two layers stop that: the preflight removes every record
  as it takes the lock, when no other run is alive, and `isolation.sh` takes only a record newer than the lock. What is
  left: a process that outlives an earlier gate and writes after the lock is taken, the class of #0-116, which the
  lock and `state.json` share (#0-236).
- The fact reaches the workflow through factory-ops, which copies `isolation.sh`'s answer, the trust every `ops()`
  answer rests on: the runtime sets the type, a model relays it, and a relay that answered other than the script
  would have to be steered by text it read, while its one call (ADR-0053) comes before any.
- A reviewer recognises a violation as the check reading anything the agent answers, the hook acting on a command
  other than the exact probe, the record being written by anything but the hook, or its protections dropped.
- Supersedes the isolation check of #0-248 (BACKLOG-DONE.md), whose Approach stays as the record of why it was tried.
