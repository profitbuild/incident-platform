# ADR-0052: The preflight refuses a run outside the devcontainer, not the bot's, or not on main's settings files

- **Status:** Proposed
- **Backlog:** #0-194 (R-2026-11-11-pipeline-01)
- **Date:** 2026-11-12
- **Author:** human (owner's decision on the options of `/research 0-194`, drafted in an interactive session)
- **Reversible:** yes — the checks are lines of `preflight.sh`, the two `containerEnv` entries and one `env` entry

## Context

`scripts/factory/preflight.sh` refused a run for a dozen reasons, none of them where it ran or how its session was
started. Three runs show what that cost (#0-194):
- 2026-11-01: `/backlog-autopilot` started in the owner's host session (macOS, auto mode). It stopped only because
  `.claude/settings.local.json`, an `autopilot-stop` issue and Docker happened to refuse it. Otherwise it would have
  run outside the firewall, with the owner's files, git identity and `gh` token.
- 2026-11-01, `wf_a2e7e1c8-3d2`: the devcontainer, but a session without `settings.autopilot.json`. It ran for 24
  minutes and 20 agents with none of the file's denies or hooks, and the limits silently took `preflight.sh`'s
  defaults, which equal the file's values.
- 2026-11-06, `wf_0a53ed01-13c`: a session started at 20:27Z, before PR #589 changed the file's `cp` rule. The
  preflight's own `git merge --ff-only origin/main` brought the new file to disk at 21:42Z, and the picker ran
  under the old rule.

A spike on 2026-11-12 in the devcontainer (Claude Code 2.1.295, `claude -p`) showed two facts:
- A session reads its `--settings` file once. A rule added to the file and an `env` value changed in it during the
  session did not apply, 15 s later.
- An `env` value of that file reaches the Bash of a subagent (the Agent tool).

The firewall answers `example.com` with a REJECT in 6 ms.

## Decision

The preflight refuses, naming the missing signal, when:
1. **not in the devcontainer**: `FACTORY_DEVCONTAINER` is not `1`. It is set by `devcontainer.json` `containerEnv`.
2. **not the bot**: `FACTORY_BOT_LOGIN` (`containerEnv`, next to the `GIT_*` it names) is unset, or `GIT_AUTHOR_NAME`,
   `GIT_COMMITTER_NAME` or `gh api user`'s login differs from it, or `GIT_AUTHOR_EMAIL` or `GIT_COMMITTER_EMAIL` is
   not its noreply address (`<id>+<login>@users.noreply.github.com`). GitHub attributes a commit by its email.
3. **no firewall**: `curl https://example.com` (the host of `init-firewall.sh`'s self-test) exits with anything but
   6, 7 or 28 ("could not resolve", "refused", "timed out"), or curl is missing. Any other exit, a TLS error after a
   connection included, refuses.
4. **not main's settings**: `FACTORY_SETTINGS_SHA256` is unset, or differs from `scripts/factory/settings-hash.sh`
   computed after the fast-forward. The value is the sha256 of two lines: `jq -cS` of
   `.claude/settings.autopilot.json` without that one field, and `jq -cS` of `.claude/settings.json`, which every
   session loads under it (the session-level guard twins, the owner's denies). The first file carries the value in its
   own `env`, so the session holds the value of the files it loaded.
5. **a limit is missing**: `FACTORY_MAX_BLOCKED`, `FACTORY_AUDIT_EVERY` or `FACTORY_MAX_MERGES_PER_DAY` is not a
   number. They have no default; a check bounded by a missing limit is skipped, never run against nothing.
6. **a short Bash timeout** (added by backlog #0-250, decided by the owner, recorded there): `BASH_DEFAULT_TIMEOUT_MS`
   or `BASH_MAX_TIMEOUT_MS` is not a number of at least `1800000` (30 minutes), both set in the same `env`. Claude
   Code moves a foreground command that reaches its timeout to the background, and factory-ops, with one call per
   task, then loses the test gate's answer.

Factory guards' "Autopilot settings carry their hash" (`check-settings-hash.sh`) fails a change to either file that
leaves the field stale, and prints the value to put in.

## Alternatives considered

- **A SessionStart hook writes the hash to `CLAUDE_ENV_FILE`.** Nothing to keep up to date, but three problems:
  - The docs do not say that a subagent's Bash (the preflight runs in factory-ops) sees those variables.
  - The docs do not say that hooks of a `--settings` file run.
  - It records the file at the session's start. If a later Claude Code reloads settings, every fast-forward that
    changes them would refuse a session that is in fact current.
- **A presence marker in `env` only** (`FACTORY_AUTOPILOT_SETTINGS=1`). It catches a session without the file, not a
  stale one (the third case), so it does not meet #0-194 AC2.
- **Comparing the three limits in `env` with the file's.** It catches only a change to `env`, not to a rule, and the
  third case was a rule.
- **Only the marker for the devcontainer.** It says the environment came from the container, not that its two
  protections hold. The bot's identity and the firewall probe check those directly, at the cost of one `gh` call and
  6 ms.
- **A firewall probe only.** It misses a host without network access, and says nothing about identity.
- **Hashing `settings.autopilot.json` alone** (round 1 of the review): `settings.json` holds the session-level twins of
  the agents' guards and the merge and approve denies, and a fast-forward that changes it would leave an earlier
  session on the old file unnoticed. Both are hashed into the one value instead.
- **Treating only curl's exit 0 as "no firewall"** (round 1): a TLS error after a connection (35, 60) would pass.
- **Refusing curl's exit 6 ("could not resolve") too** (round 2): the firewall lets DNS through to the container's
  own resolver only, so a name it does not answer is a refusal there, and refusing it could stop correct runs. A host
  with broken DNS and open egress passes this probe, but the devcontainer marker and the bot's identity still refuse
  it.

## Consequences

- Every change to `settings.autopilot.json` or `settings.json` updates `env.FACTORY_SETTINGS_SHA256`. Factory guards
  names the value.
- The hash covers the two settings files of the repository, not the container user's `~/.claude/settings.json` or
  managed settings (round 2 of the review). An allow rule added there would not show. This gap is older than this
  ADR: deny rules still take precedence over it, and closing it is a decision of its own.
- The value depends on jq's printing. jq 1.6 and 1.7 print some number literals differently, and neither file has a
  number today. A difference between two jq versions fails closed: the preflight refuses.
- After such a change reaches `main`, a session started earlier refuses until it is restarted, even when the
  preflight's own fast-forward brought the change. That is the intended outcome: the session runs the old rules.
- A change to `containerEnv` needs a rebuild of the container (`devcontainer up --remove-existing-container`).
- Every signal can be set by hand. The checks stop a mistake, not an adversary, and code an agent runs can still
  leave the firewall (#0-116).
- Whether a Workflow-spawned agent's Bash sees the settings' `env` was not tested apart from the Agent tool. If it
  did not, the first run would refuse at the preflight (fail closed), not run unchecked.
- A reviewer recognises a violation as a refusal removed or turned into a warning, a default given back to a limit,
  or a change to the settings file without its hash.
- Refusal 6 (#0-250) lets every Bash call of the autopilot wait 30 minutes, so a run can last longer than before, while
  the lock still turns stale `FACTORY_LOCK_HOURS` (3) after the run started: a run that long, still working, could be
  taken over by another session's preflight. Backlog #0-251.
