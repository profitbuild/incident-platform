# ADR-0039: Claude Code blocks a call whose hook fails: every hook entry says `onFailure: "block"`, and the autopilot needs Claude Code 2.1.295 or newer (backlog #0-162)

- **Status:** Accepted (2026-10-25); point 3 amended by ADR-0065 (2026-11-21, #0-249): the preflight refuses any
  version but `.devcontainer/claude-code.pin`'s, and 2.1.295 is the floor of that pin
- **Backlog:** #0-162
- **Date:** 2026-10-25
- **Author:** human (owner chose option C of the research in two PRs, and for PR 2 a Ruby check, the running binary's version, a spike of an older version; written up by Claude Code in the owner's session)
- **Reversible:** yes

## Context

Claude Code blocks a tool call only when a PreToolUse hook exits 2. Any other exit, a hook that cannot start
(missing, not executable, no interpreter) and one that times out are non-blocking errors: "The action goes
ahead" (code.claude.com/docs/en/hooks.md, read 2026-10-24). PR 1 of #0-162 (PR #516) closed what a script can
see itself: every hook in `.claude/hooks/` sets an `EXIT` trap that turns any status but 0 and 2 into 2, loads
`_lib.sh` with `|| exit 2`, and refuses when its JSON parser fails, each shown by a row of the fail-closed table
of `.claude/hooks/test-hooks.sh`. A hook that never starts runs no trap.

Claude Code has a field for that case: `"onFailure": "block"` on a `command` (or `http`) hook makes a failure do
what exit code 2 does on its event, so on `PreToolUse` it blocks the tool call. The hooks reference (read
2026-10-25) counts as a failure: "**Can't start**: a command hook fails to start, for example because the script
or executable doesn't exist", an "**Exit code other than 0 or 2**", a "**Timeout**", and "**Invalid output**: the
JSON output can't be parsed or fails schema validation [...] Plain-text stdout from a command hook isn't a
failure"; "Requires Claude Code v2.1.295 or later". The field does nothing for "Background command hooks: command
hooks that set `async` or `asyncRewake`". The docs say nothing of an older version, nor whether a subagent's
frontmatter hooks honour it. Three
spikes, each with a hook entry pointing at a script that does not exist, and a control entry without the field:

| Spike | Where the entry is | Claude Code | With `onFailure: "block"` | Without |
|---|---|---|---|---|
| B (2026-10-24) | `claude -p --settings <file>` | 2.1.310 | blocked: `PreToolUse:Bash hook error: […no-such-hook-0-162.sh]: failed; blocking because onFailure is "block"` | ran |
| A (2026-10-25) | an agent's frontmatter, spawned by the Agent tool in an interactive session | 2.1.310 | blocked, same message | ran |
| C (2026-10-25) | `claude -p --settings <file>` | 2.1.294 (npm) | **ran**: the field is ignored without a warning | ran |

In spike C the file was still read: a hook of the same file that exits 2 blocked, on 2.1.294 as on 2.1.310. So an
older version does not reject the settings, it drops this one layer silently. All hooks write their messages to
stderr and nothing to stdout, so "invalid output" cannot block a hook that ran well; `guard-migrations.sh`'s two
documented warnings (`FAC-S04`) exit 0 and still let the edit through.

The devcontainer installs whatever Claude Code is current when its image is built (`DISABLE_AUTOUPDATER`), and
until now no check required a version.

## Decision

1. **Every hook entry** of `.claude/settings.json` (3), `.claude/settings.autopilot.json` (8) and the frontmatter
   of the agents in `.claude/agents/` (18, in 16 agents) has `"onFailure": "block"`. No skill or command declares
   hooks today; one that does is held to the same rule.
2. **Factory guards checks the entries** (`.github/scripts/check-hook-entries.rb`, tested by
   `test-hook-entries.sh`), parsing the JSON and the YAML rather than matching text (a field one indent off, or
   in flow style, is what Claude Code reads), in both settings files and the frontmatter of every agent, skill and
   command under `.claude/`, subdirectories included (Claude Code "scans `.claude/agents/` [...] recursively"):
   every entry of every event is a `command` hook with `onFailure: "block"`, not `async`/`asyncRewake`, its command is `"$CLAUDE_PROJECT_DIR"/.claude/hooks/<name>.sh` with arguments that hold
   no shell syntax (`|| true` would make a hook that never fails) and a `*` only inside single quotes (the shell
   would expand it into a list of files), an executable file with a row in the
   fail-closed table; no settings file sets `disableAllHooks`; and no file repeats a key in one map. Of a repeated
   key Ruby keeps the last value, and which one Claude Code's parser keeps, or whether it refuses the file, is not
   documented: `onFailure` written twice could pass the check and not hold in the session, so the check does not
   depend on either answer (review round 2). `test-hooks.sh` already fails a hook of the
   directory without a row; this fails a wired hook without one, so the two close the loop.
3. **The autopilot refuses an older Claude Code**: `scripts/factory/preflight.sh` stops on a version below 2.1.295,
   and on one it cannot read. The version is the running binary's (`$CLAUDE_CODE_EXECPATH --version`, the path
   Claude Code sets for its commands), or, when that is unset, the `claude` on PATH. A set path that does not
   answer, or does not answer within 10 seconds, refuses rather than falling back to PATH.

## Alternatives considered

- **Only the scripts (PR 1 alone).** A hook deleted or made non-executable by a change, or one that hangs past
  its timeout, would let every call through. Only Claude Code sees that a hook did not start.
- **A text check in bash, like `check-web-access.sh`.** It would accept `onFailure` written as a sibling of
  `hooks:` or of the matcher, which Claude Code ignores, and miss a flow-style entry. Ruby's Psych is on the
  runner already (`check-shell.rb`); the check needs no Ruby in the devcontainer, where it does not run.
- **The version from `claude --version` on PATH only.** That is the installed binary, which can differ from the
  running one after an update without a restart. `CLAUDE_CODE_EXECPATH` is not documented, so it is the first
  choice, not the only source; `AI_AGENT` (`claude-code_2-1-310_agent`) is undocumented and not a version format,
  rejected.
- **No version check, the devcontainer pins Claude Code instead.** A pin would need its own update path
  (ADR-0033's checksums and Renovate) and still say nothing of a session started outside the container. Possible
  later; the preflight check holds either way.

## Consequences

- A hook that cannot start, crashes or times out blocks the call in every session on 2.1.295 or newer. It blocks
  every call it matches: `read-scope.sh` runs on every Read of the owner's sessions (the verifier's scope), so a
  broken `read-scope.sh` stops every Read there until it is fixed (from an editor, or with `!` in the session).
  That is the point of failing closed, and the price.
- **Weaker layers, named (`FAC-A05`)**: on a Claude Code older than 2.1.295 the field does nothing and nothing
  says so; the autopilot does not start on one, the owner's own sessions are not checked (README "Infrastructure
  Hardening"). That a frontmatter hook honours the field is shown for agents of the Agent tool only, not for the
  agents a `Workflow` spawns (frontmatter hooks are not documented for them, though they ran in #0-160's spike r2)
  and frontmatter hooks never run in `claude -p`: session-level twins of the frontmatter guards are #0-164
  (done since, ADR-0041).
- A new hook entry, in either settings file or an agent's frontmatter, needs `onFailure: "block"` and a hook of
  the fail-closed table, or Factory guards fails; a new hook needs a row in that table (PR 1).
- What the check does not see: whether an agent that should have a hook has one (#0-164), and hooks a session
  gets from elsewhere (the user's own settings, a plugin).
