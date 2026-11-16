#!/usr/bin/env bash
# ============================================================
# PreToolUse (Bash), session level, autopilot sessions only (settings.autopilot.json): records which agent type
# Claude Code says sent the autopilot's isolation probe, so the isolation check compares a fact the runtime sets,
# not an answer of the model (backlog #0-252, ADR-0058).
#
#   isolation-probe.sh       the session-level entry; no arguments
#
# The probe is one exact command, `git rev-parse --verify --quiet isolation-probe-<run id>`, that the workflow asks
# review-general to run before any other work of the run. For it, and only for it, this hook:
#   1. takes the call's `agent_type` (set by Claude Code, never by the model: the spike of 2026-11-16 saw
#      "review-general" for an agent the workflow started with agentType review-general, "workflow-subagent" for one
#      started without);
#   2. records it as the symlink .ai/runs/isolation/<run id> -> <agent_type>, made by `ln -sn --` in one step, so the
#      first probe of a run wins and a later one (another agent, a retry) cannot replace it, as factory-ops-bash.sh's
#      marks (ADR-0053); only for the run that holds .ai/runs/LOCK, so a probe naming another run records nothing;
#   3. refuses the command (exit 2), recorded or not: it never runs, and the agent is told to answer.
# scripts/factory/isolation.sh reads the record for the workflow. Every other command passes untouched: this is not a
# guard, and a reviewer's `git grep isolation-probe` must not be refused.
#
# Fixed (backlog #0-252): the isolation check asked review-general to copy the opening of its own system prompt
# (#0-248), and in run wf_71cca984-ef4 (2026-11-16, build VM) the model declined to ("I won't copy my system
# instructions"), so a run whose isolation held stopped NOT_STARTED; on 2026-11-15 the same question had been
# answered. A check that depends on whether the model is willing is a coin toss. The probe asks the model only to run
# a command, which the spike's three agents all did, once each.
# Fails closed: no agent_type (the main session, or a Claude Code that stops sending it), no lock, a mark that is not
# a symlink: nothing is recorded, and the workflow, which finds no record, stops the run.
# ============================================================
set -uo pipefail
# Fails closed (backlog #0-162): Claude Code runs the call after any exit status but 2, so a crash (an unset
# variable under set -u, a missing command) and a helper that does not load refuse it here.
trap 'case $? in 0|2) ;; *) echo "BLOCKED by ${0##*/}: the guard failed (exit $?), so the call is refused" >&2; exit 2 ;; esac' EXIT
. "$(dirname "$0")/_lib.sh" || { echo "BLOCKED by ${0##*/}: cannot load _lib.sh" >&2; exit 2; }

[ "$#" -eq 0 ] || block "isolation-probe.sh takes no arguments, got: $*"
input=$(cat)
cmd=$(json_get "$input" '.tool_input.command'); rc=$?
json_checked "$rc" "the isolation probe"
probe='^git rev-parse --verify --quiet isolation-probe-([A-Za-z0-9_-]{1,64})$'
[[ $cmd =~ $probe ]] || exit 0
run=${BASH_REMATCH[1]}

agent=$(json_get "$input" '.agent_type'); rc=$?
json_checked "$rc" "the isolation probe"
[[ $agent =~ ^[a-z0-9-]{1,64}$ ]] \
    || block "the isolation probe of run $run came with no agent_type (the main session, or a Claude Code that does not send it): nothing is recorded, so the isolation check stops the run"
root=$(git rev-parse --show-toplevel 2>/dev/null) || block "cannot find the repository, so the isolation probe is not recorded"
lockfile="$root/.ai/runs/LOCK" locked=""
[ -f "$lockfile" ] || block "no run holds .ai/runs/LOCK, so the isolation probe of run $run is not recorded"
# `read` fails at a last line without its newline although it filled the variable: the variable decides.
read -r locked _ < "$lockfile" || [ -n "$locked" ] || block "cannot read .ai/runs/LOCK, so the isolation probe of run $run is not recorded"
[ "$locked" = "$run" ] || block "the isolation probe names run $run, the lock holds ${locked:-none}: nothing is recorded"

dir="$root/.ai/runs/isolation"
# Review round 1 (sec-3c8e): a symlink planted at the directory's name would put the record where the branch chose.
[ ! -L "$dir" ] || block "$dir is a symlink, so the isolation probe is not recorded"
mkdir -p "$dir" || block "cannot create $dir, so the isolation probe is not recorded"
# Records of runs that ended. preflight.sh removes them all as it takes the lock (review round 1, sec-3c8e), which is
# what keeps an earlier record from being read; this pruning, a day as for the factory-ops marks, only keeps the
# directory small between runs.
find "$dir" -maxdepth 1 -type l -mmin +1440 -delete 2>/dev/null || true
mark="$dir/$run"
# As factory-ops-bash.sh's marks (review round 1 of #0-169): anything at the name that is not a symlink refuses before
# `ln`, which would otherwise create the link inside a directory and exit 0; after it, only the link itself is trusted.
if [ -e "$mark" ] && [ ! -L "$mark" ]; then block "the isolation record $mark is not a symlink, so the probe is not recorded"; fi
ln -sn -- "$agent" "$mark" 2>/dev/null || true
[ -L "$mark" ] || block "the isolation record $mark is not a symlink, so the probe is not recorded"
recorded=$(readlink "$mark" 2>/dev/null) || block "cannot read the isolation record $mark"
echo "BLOCKED by ${0##*/}: the isolation probe of run $run is recorded (agent type: $recorded); the command is refused on purpose and does not run: answer your JSON now" >&2
exit 2
