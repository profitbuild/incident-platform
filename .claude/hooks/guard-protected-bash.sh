#!/usr/bin/env bash
# ============================================================
# PreToolUse (Bash), autopilot sessions only: refuse shell commands that could write to a human-owned
# path. The Edit/Write deny rules in settings.autopilot.json cover the file tools; a shell command
# (`sed -i`, `cp`, a redirect) goes around them. This is a heuristic second line: the real gates are
# CODEOWNERS on the PR and the autopilot's changed-paths check before review.
#
# Protected: the paths of .ai/rules/protected-paths.md (their one list), its runtime-state list among them (.git/,
#            .ai/runs/LOCK and state.json, .ai/runs/ops-calls/, .ai/runs/isolation/, .ai/STOP). This copy stays a literal regex, so the last line does not
#            depend on parsing that file; .github/scripts/check-protected-paths.sh fails CI when it misses an
#            entry, and when it holds one the list lacks (backlog #0-168): it reads `protected=` below as a flat
#            alternation, one path per alternative, so keep it on one line with no group inside.
#            Fixed (backlog #0-122): .ai/audit/decisions.md was denied to Edit/Write but not covered here.
#            Fixed (backlog #0-233): .ai/runs/ops-calls/, the marks that give a factory-ops run its one call
#            (#0-169, ADR-0053), was not protected, so another agent's Bash could delete a mark and give a running
#            factory-ops a second call. Matched without its trailing `/`, so `rm -rf .ai/runs/ops-calls` counts
#            too. The marks themselves are made by factory-ops-bash.sh, a hook, which this guard does not see.
#            Backlog #0-252: .ai/runs/isolation/, the record of which agent type sent a run's isolation probe
#            (isolation-probe.sh, a hook, makes it), the same way: an agent's Bash must not make or replace one.
# A command that only reads (git diff/log/show, cat, grep, ls, head, tail, wc) passes.
# Also refused, whatever the verb: commands naming a secret (docker/.env, docker/secrets, application-local,
# credentials files, gh/ssh config) and `git diff --no-index`, which reads any file around the Read denies.
# `git grep` options that run a program or read files git does not track (the secrets) are refused too, and so are the
# git forms that remove or move the gitignored runtime state without naming it: `git add -f`, `git mv .ai`
# (git_runtime_unsafe, backlog #0-235).
# A label an agent may not set on a PR (`human:*`, the owner's; anything off the shipper's list) is refused on
# `gh pr|issue create|new|edit` in the forms gh accepts (gh_label_unsafe, backlog #0-126).
# Fails closed without jq or python3, when the git grep or gh label check itself fails (backlog #0-130), and when a
# pattern check cannot match (finds in _lib.sh: bash's own regex, no grep, backlog #0-132).
# ============================================================
set -uo pipefail
# Fails closed (backlog #0-162): Claude Code runs the call after any exit status but 2, so a crash (an unset
# variable under set -u, a missing command) and a helper that does not load refuse it here.
trap 'case $? in 0|2) ;; *) echo "BLOCKED by ${0##*/}: the guard failed (exit $?), so the call is refused" >&2; exit 2 ;; esac' EXIT
. "$(dirname "$0")/_lib.sh" || { echo "BLOCKED by ${0##*/}: cannot load _lib.sh" >&2; exit 2; }

input=$(cat)
cmd=$(json_get "$input" '.tool_input.command'); rc=$?
json_checked "$rc" "the autopilot's hooks"
[ -n "$cmd" ] || exit 0

secrets='(docker/\.env|docker/secrets|application-local|\.credentials|\.claude\.json|config/gh|\.ssh/|\.netrc|\.git-credentials|settings-security\.xml|--no-index)'
if finds "$cmd" "$secrets"; then
    block "the command names a secret file or reads files outside the repository's history (--no-index). Agents never read secrets."
fi
# A line continuation (backslash-newline) is joined by bash before it runs the command, so a pattern
# split across it (`git gr\<newline>ep`, `doc\<newline>ker/.env`) is seen by bash and not by these checks.
# No command an agent needs is written that way (review round 2, sec-b7d2).
case "$cmd" in *\\$'\n'*) block "a line continuation (backslash-newline) is not allowed: write the command on one line" ;; esac
# A check that fails (exit status not 0) refuses: its empty output does not mean "may run" (backlog #0-130).
why=$(git_grep_unsafe "$cmd") || block "the git grep check failed, so the command is refused${why:+: $why}"
[ -z "$why" ] || block "$why"
why=$(gh_label_unsafe "$cmd") || block "the gh label check failed, so the command is refused${why:+: $why}"
[ -z "$why" ] || block "$why"
# Backlog #0-235 (sec-4a1d): git's own way to the ignored runtime state, without naming it (`git add -f .ai/runs`, then
# `git rm -r -f .ai/runs`; `git mv .ai x`). The pattern check below only sees a command that names a protected path.
why=$(git_runtime_unsafe "$cmd") || block "the git runtime-state check failed, so the command is refused${why:+: $why}"
[ -z "$why" ] || block "$why"
if finds "$cmd" '(>|[[:space:]]tee[[:space:]]|sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|(^|[[:space:];&|])(cp|mv|rm|chmod|ln)[[:space:]])[^;&|]*[[:space:]](\./)?mvnw(\.cmd)?([[:space:]]|$)'; then
    block "the command may write to the Maven wrapper (mvnw), which every verification runs"
fi

protected='(\.ai/rules|\.ai/plan/|\.ai/audit/decisions\.md|\.claude/|\.github/|architecture-tests|AGENTS\.md|scripts/factory|\.devcontainer|\.mvn/|\.ruby-version|\.node-version|\.git/|\.ai/runs/LOCK|\.ai/runs/state\.json|\.ai/runs/ops-calls|\.ai/runs/isolation|\.ai/STOP)'
# The paths are matched as text, after the spellings a path resolves through without changing (review round 3 of
# #0-235): `//` is `/`, `/./` is `/`. Without it `git log --output=.ai/runs//LOCK`, an allowed read, overwrote the lock
# with a branch and a base the agent chose, and `mkdir -p .ai/runs//ops-calls/<id>` blocked a factory-ops run. `..`
# is not resolved here: Claude Code refuses a path through `..` whatever a rule says, and git_runtime_unsafe resolves
# git's own path arguments.
norm=$cmd
while [[ $norm == *//* ]]; do norm=${norm//\/\//\/}; done
while [[ $norm == */./* ]]; do norm=${norm//\/.\//\/}; done
finds "$norm" "$protected" || exit 0

# git's own writing options count as writes (backlog #0-131, review round 3): `--output=<file>` writes the file, and
# `--ext-diff`/`--textconv` run a program; an allow-listed read (`git log`, `git diff`, `git show`) could otherwise
# write the lock the push guard trusts. Their plain form only: a word spliced with quotes is #0-167's.
writes='(>|[[:space:]]tee[[:space:]]|sed[[:space:]]+(-[a-zA-Z]*i|--in-place)|perl[[:space:]]+-[a-zA-Z]*i|(^|[[:space:];&|])(cp|mv|rm|rmdir|ln|chmod|chown|truncate|install|touch|mkdir)[[:space:]]|git[[:space:]]+(checkout|restore|rm|mv|apply|am|stash|reset)|(python3?|ruby|node|perl)[[:space:]]|--output|--ext-diff|--textconv)'
if finds "$cmd" "$writes"; then
    block "the command may write to a human-owned path (.ai/rules/protected-paths.md lists them; also .git/ and the run state). Agents never change these; if the item needs it, stop and report NEEDS_HUMAN."
fi
exit 0
