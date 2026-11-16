#!/usr/bin/env bash
# ============================================================
# The agent type that sent a run's isolation probe, as .claude/hooks/isolation-probe.sh recorded it from Claude
# Code's `agent_type` (backlog #0-252, ADR-0058).
#   isolation.sh <run id>
#     {"agentType": "<type>"}                      the probe's record, the symlink .ai/runs/isolation/<run id>
#     {"agentType": null, "reason": "<why>"}       no record: the probe was not sent, not seen or not recorded; or
#                                                  a record older than the lock, so not this run's probe
#     {"error": "<why>"} and exit 1                a run id that is not one, no lock, or a record that cannot be read
# The workflow goes on only when the type is review-general's; it reads nothing else of the agent's.
# Fixed (backlog #0-252, review round 1, sec-3c8e): a record is a symlink anyone who could write .ai/runs/ before the
# run could have planted under a predictable run id (a time). preflight.sh removes every record as it takes the lock,
# and this takes only a link whose own time (`find -P`, not the target's: the link points to a type name, not a file)
# is newer than the lock: a record from before the run is not this run's, even where the removal did not happen.
# ============================================================
set -uo pipefail
. "$(dirname "$0")/_common.sh"
fail() { jq -n --arg e "$1" '{error: $e}'; exit 1; }
run=${1:-}
[ "$#" -eq 1 ] && [[ $run =~ ^[A-Za-z0-9_-]{1,64}$ ]] || fail "usage: isolation.sh <run id>"
lock="$RUNS_DIR/LOCK" mark="$RUNS_DIR/isolation/$run"
[ -f "$lock" ] || fail "no run holds $lock, so no isolation record is this run's"
[ ! -L "$RUNS_DIR/isolation" ] || fail "$RUNS_DIR/isolation is a symlink, so its records are not the probe's"
if [ -L "$mark" ]; then
    type=$(readlink "$mark") || fail "cannot read the isolation record $mark"
    [[ $type =~ ^[a-z0-9-]{1,64}$ ]] || fail "the isolation record $mark holds no agent type"
    newer=$(find -P "$mark" -prune -newer "$lock" 2>/dev/null) || fail "cannot compare the isolation record $mark with $lock"
    if [ -n "$newer" ]; then jq -n --arg t "$type" '{agentType: $t}'
    else jq -n --arg r "the isolation record of run $run is older than the lock, so it is not this run's probe" '{agentType: null, reason: $r}'; fi
elif [ -e "$mark" ]; then
    fail "the isolation record $mark is not a symlink"
else
    jq -n --arg r "no isolation probe was recorded for run $run" '{agentType: null, reason: $r}'
fi
