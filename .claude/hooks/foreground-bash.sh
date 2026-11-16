#!/usr/bin/env bash
# ============================================================
# PreToolUse (Bash) in the frontmatter of the implementers (implementer, implementer-light): refuse a command run in
# the background (`run_in_background: true`). The implementer's turns are its budget (`maxTurns`); a command in the
# background returns at once, and the agent then spends a turn on every look at its output.
#
#   foreground-bash.sh                   the frontmatter hook
#   foreground-bash.sh --agent <names>   its session-level twin in both settings files, for those agents' calls
#                                        only (frontmatter hooks are not promised to a Workflow's agents, #0-164,
#                                        ADR-0041; check-hook-entries.rb keeps the two equal)
#
# Fixed (backlog #0-206): run wf_c1597fde-23e (#0-199) started a full `verify` in the background and checked its
# output with `grep` 26 times; the implementer spent its 120 turns, ended without an answer and the run stopped with
# the lock held. A test the implementer runs blocks until it ends (the Bash tool's timeout reaches 30 minutes, the
# autopilot settings' BASH_MAX_TIMEOUT_MS, backlog #0-250), and the gate the autopilot trusts is its own
# scripts/factory/run-tests.sh after the implementer anyway.
# Fails closed.
# ============================================================
set -uo pipefail
# Fails closed (backlog #0-162): Claude Code runs the call after any exit status but 2, so a crash (an unset
# variable under set -u, a missing command) and a helper that does not load refuse it here.
trap 'case $? in 0|2) ;; *) echo "BLOCKED by ${0##*/}: the guard failed (exit $?), so the call is refused" >&2; exit 2 ;; esac' EXIT
. "$(dirname "$0")/_lib.sh" || { echo "BLOCKED by ${0##*/}: cannot load _lib.sh" >&2; exit 2; }

only=""
if [ "${1:-}" = --agent ]; then
    [ "$#" -ge 2 ] && [ -n "$2" ] || block "foreground-bash.sh --agent needs agent names"
    only=$2
    shift 2
fi
[ "$#" -eq 0 ] || block "foreground-bash.sh takes no arguments but --agent <names>, got: $*"
input=$(cat)
if [ -n "$only" ] && ! applies_to_agent "$only" "$input"; then exit 0; fi
background=$(json_get "$input" '.tool_input.run_in_background'); rc=$?
json_checked "$rc" "this agent's Bash guard"
case "$background" in
    ''|false|False) exit 0 ;;   # jq prints false, the python3 fallback False
    *) block "run the command in the foreground (no run_in_background): it returns when it ends, so there is no output to poll, and every look at a background command's output spends one of your turns. For a long test run, give the Bash call a timeout (up to the autopilot settings' BASH_MAX_TIMEOUT_MS, 30 minutes) and narrow it with -pl <module> -am -Dtest=<Class> (-am builds shared from the branch, backlog #0-222); the autopilot's own test gate runs the full set after you (backlog #0-206)." ;;
esac
