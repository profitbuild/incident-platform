#!/usr/bin/env bash
# ============================================================
# Autopilot preflight. Prints one JSON object: {"ok": bool, "reasons": [...], "baseRef", "baseSha",
# "runId", "today", "state": {...}}. Exit 0 whenever it could decide (ok or not ok).
#
# Refuses to start when: .ai/STOP exists; the working tree is not clean; the current branch is not main
# or cannot fast-forward to origin/main; an open issue carries the `autopilot-stop` label; the latest CI
# run of a push to main did not succeed (or has a status gh does not document); the circuit breaker
# tripped (FACTORY_MAX_BLOCKED consecutive BLOCKED items); an audit is due (FACTORY_AUDIT_EVERY shipped items
# since the last one); the daily merge limit is reached (FACTORY_MAX_MERGES_PER_DAY); one of those three limits is
# not set (they come from settings.autopilot.json's env, with no default); another run holds the lock (younger than
# FACTORY_LOCK_HOURS, default 3); Docker is not reachable (the tests need it); Claude Code is not the version
# .devcontainer/claude-code.pin names, or does not say its version, or the pin is below 2.1.295 (the hooks' onFailure,
# backlog #0-162, #0-249); the run is not in the devcontainer, is not the
# bot's, or example.com is not refused (no firewall); the session was not started with main's
# .claude/settings.autopilot.json and .claude/settings.json (backlog #0-194, ADR-0052); its BASH_DEFAULT_TIMEOUT_MS or
# BASH_MAX_TIMEOUT_MS is below 30 minutes (the test gate's answer, backlog #0-250).
# Taking the lock, it removes the isolation probe's records of earlier runs (backlog #0-252).
# The breaker and the audit trigger create .ai/STOP, so the owner has to clear them on purpose.
# ============================================================
set -uo pipefail
. "$(dirname "$0")/_common.sh"
state_init
ensure_ignored

reasons=()
add() { reasons+=("$1"); }

# Fixed (backlog #0-194, ADR-0052): the three limits had defaults equal to the values settings.autopilot.json sets, so
# a session started without that file ran with the same numbers and nothing showed it. They come from its `env` only
# now; a limit that is not a number refuses, and the check it bounds is skipped rather than run against nothing (a
# breaker compared with an empty limit would trip and write .ai/STOP). The lock's age keeps its default: it is not a
# setting of the session.
MAX_BLOCKED=${FACTORY_MAX_BLOCKED:-}
AUDIT_EVERY=${FACTORY_AUDIT_EVERY:-}
MAX_MERGES=${FACTORY_MAX_MERGES_PER_DAY:-}
for limit in FACTORY_MAX_BLOCKED FACTORY_AUDIT_EVERY FACTORY_MAX_MERGES_PER_DAY; do
    is_int "${!limit:-}" || add "$limit is not set to a number: settings.autopilot.json's env sets it, so the session was not started with that file (claude --settings .claude/settings.autopilot.json; backlog #0-194)"
done
LOCK_HOURS=${FACTORY_LOCK_HOURS:-3}

# Fixed (backlog #0-250): Claude Code moves a foreground Bash command that reaches its timeout to the background
# instead of stopping it (2.1.x, tools reference), and a call without its own `timeout` has 2 minutes. factory-ops
# runs run-tests.sh with none and has one call per task (#0-169), so in the run of #0-58 (2026-11-15) the gate, a few
# minutes long, went to the background, its JSON never came back and the item stopped BLOCKED "test gate returned no
# result". settings.autopilot.json's env sets the default to 30 minutes, and the ceiling (BASH_MAX_TIMEOUT_MS, 10
# minutes unless set) to the same: the docs do not say whether the default is bounded by the ceiling (review round 1
# of #0-250), and with both set it does not matter. A session with less of either, or none, refuses here, before an
# item is locked, not at the gate.
GATE_TIMEOUT_MS=1800000
for timeout_var in BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS; do
    timeout_value=${!timeout_var:-}
    if ! is_int "$timeout_value" || [ "$timeout_value" -lt "$GATE_TIMEOUT_MS" ]; then
        add "$timeout_var is '$timeout_value', below $GATE_TIMEOUT_MS: a Bash call that reaches its timeout goes to the background and the test gate's answer is lost; settings.autopilot.json's env sets it, so start the session with that file (backlog #0-250)"
    fi
done

# Fixed (backlog #0-194, ADR-0052): nothing checked where the run starts. On the host, with a clean main, Docker up
# and no personal settings file, the autopilot started outside the firewall, with the owner's files, git identity and
# gh token. Each check reads a property that only the devcontainer gives, and names it when it is missing. They guard
# against a mistake, not an adversary: every signal can be set by hand.
# - FACTORY_DEVCONTAINER: devcontainer.json's containerEnv, so the session inherited the container's environment.
[ "${FACTORY_DEVCONTAINER:-}" = 1 ] \
    || add "not in the devcontainer (FACTORY_DEVCONTAINER is not 1): start the autopilot inside it, as docs/ai-factory.md \"Running it\" says (backlog #0-194)"
# - The bot's identity: FACTORY_BOT_LOGIN (containerEnv) is the account every commit and PR of a run must be; the
#   GIT_* names here, gh's login below (the token in the gh volume). Otherwise the PR is the owner's and the human:*
#   labels mean nothing.
bot=${FACTORY_BOT_LOGIN:-}
if [ -z "$bot" ]; then
    add "FACTORY_BOT_LOGIN is not set (devcontainer.json containerEnv): cannot check that the run is the bot's (backlog #0-194)"
else
    for id in GIT_AUTHOR_NAME GIT_COMMITTER_NAME; do
        [ "${!id:-}" = "$bot" ] || add "$id is '${!id:-}', not the bot '$bot': the run's commits would not be the machine account's (backlog #0-194)"
    done
    # GitHub attributes a commit by its email, not its name (review round 1): a bot name over the owner's address
    # would show as the owner's. The bot's address is its noreply one, <id>+<login>@users.noreply.github.com: digits
    # only before the `+` (review round 2: a glob `[0-9]*` let `1x+<login>@…` through), the login matched as text.
    noreply_suffix="+$bot@users.noreply.github.com"
    for id in GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL; do
        addr=${!id:-}
        account=${addr%"$noreply_suffix"}
        if [ "$account" = "$addr" ] || [ -z "$account" ] || ! is_int "$account"; then
            add "$id is '$addr', not the bot's noreply address (<id>$noreply_suffix): GitHub would attribute the run's commits to another account (backlog #0-194)"
        fi
    done
fi
# - The firewall: example.com, the host init-firewall.sh's own self-test expects to be unreachable. Its REJECT answers
#   at once (spike of 2026-11-12: curl exit 7 in 6 ms), so a correct run loses nothing; a firewall flushed after the
#   container started (backlog #0-116) refuses here too. Only "no connection" passes: 6 (no name), 7 (refused) and 28
#   (timed out, a DROP). Any other exit means a connection was made or curl failed in a way that says nothing, e.g. 35
#   or 60, a TLS error behind an intercepting proxy (review round 1), and refuses.
if ! command -v curl >/dev/null 2>&1; then
    add "curl is not installed: cannot check the devcontainer's firewall (backlog #0-194)"
else
    curl -sS -o /dev/null --max-time "${FACTORY_FIREWALL_PROBE_WAIT:-5}" https://example.com 2>/dev/null
    probe=$?
    case "$probe" in
        6|7|28) ;;
        0) add "example.com answers: the devcontainer's firewall is not applied (init-firewall.sh; backlog #0-194)" ;;
        *) add "example.com was not refused (curl exit $probe: a connection was made, or curl failed in another way): the firewall is not shown to be applied (init-firewall.sh; backlog #0-194)" ;;
    esac
fi
today=$(date -u +%F)
run_id=$(date -u +%Y%m%d-%H%M%S)

[ -f .ai/STOP ] && add "STOP file present: $(head -c 300 .ai/STOP | tr '\n' ' ')"
# Personal allow rules would merge into the dontAsk session and widen what agents may run.
[ -f .claude/settings.local.json ] && add ".claude/settings.local.json exists: its allow rules would apply to the autopilot; move it out of the workspace (it is personal, see docs/ai-factory.md)"

# Fixed (backlog #0-162 PR 2, ADR-0039): every hook entry says `"onFailure": "block"`, so that a hook that cannot
# start or times out refuses the call instead of letting it through. Claude Code honours the field from 2.1.295;
# 2.1.294 ignores it without a word (spike of 2026-10-25), and the devcontainer installs whatever version is
# current when its image is built. The version is the running binary's (CLAUDE_CODE_EXECPATH, which Claude Code
# sets for its commands), or the one on PATH when that is unset; one that cannot say its version refuses. A field
# has at most six digits: a longer one is not a version, and would reach `[ -gt ]` past what bash compares (review
# round 1).
# Amended (backlog #0-249, ADR-0065): the devcontainer installs exactly the version .devcontainer/claude-code.pin names,
# and the running binary must be that one, not merely 2.1.295 or newer: a container built from an older commit runs
# another version, which ADR-0064's measurements (the hooks, the agents' tools) were not made on. 2.1.295 stays the
# floor of the pin itself. The pin is read from this checkout (main, as the preflight requires), never sourced.
MIN_CLAUDE_CODE=2.1.295
PIN_FILE=.devcontainer/claude-code.pin
# version_at_least <x.y.z> <x.y.z> — the first is the second or newer, field by field as numbers.
version_at_least() {
    local IFS=.
    # shellcheck disable=SC2206
    local a=($1) b=($2) i
    for i in 0 1 2; do
        [ "${a[i]}" -gt "${b[i]}" ] && return 0
        [ "${a[i]}" -lt "${b[i]}" ] && return 1
    done
    return 0
}
# claude_version <binary> — the first line its --version prints, or nothing when it has not answered within
# FACTORY_CLAUDE_VERSION_WAIT tenths of a second (default 100): a binary that hangs must refuse, not hang the
# preflight (review round 2). Bash only, as macOS has no timeout(1).
claude_version() {
    local out pid i
    out=$(mktemp) || return 1
    "$1" --version >"$out" 2>/dev/null &
    pid=$!
    for ((i = 0; i < ${FACTORY_CLAUDE_VERSION_WAIT:-100}; i++)); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rm -f "$out"; return 1
    fi
    wait "$pid" 2>/dev/null
    head -1 "$out"; rm -f "$out"
}
pinned=""
if [ "$(grep -c '^CLAUDE_CODE_VERSION=' "$PIN_FILE" 2>/dev/null)" = 1 ]; then
    pinned=$(sed -n 's/^CLAUDE_CODE_VERSION=//p' "$PIN_FILE")
fi
if ! [[ "$pinned" =~ ^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$ ]]; then
    add "cannot read the pinned Claude Code version: $PIN_FILE must have one CLAUDE_CODE_VERSION=x.y.z line (backlog #0-249)"
    pinned=""
elif ! version_at_least "$pinned" "$MIN_CLAUDE_CODE"; then
    add "the pinned Claude Code $pinned ($PIN_FILE) is older than $MIN_CLAUDE_CODE: it ignores the hooks' onFailure, so a hook that cannot start would let the call through (backlog #0-162)"
fi
claude_bin=${CLAUDE_CODE_EXECPATH:-$(command -v claude 2>/dev/null)}
claude_out=$([ -n "$claude_bin" ] && claude_version "$claude_bin")
if [[ "$claude_out" =~ ^([0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6})([^0-9.]|$) ]]; then
    if [ -n "$pinned" ] && [ "${BASH_REMATCH[1]}" != "$pinned" ]; then
        add "Claude Code ${BASH_REMATCH[1]} is running, not the pinned $pinned ($PIN_FILE): rebuild the devcontainer from main (backlog #0-249)"
    fi
else
    add "cannot read the version of Claude Code (${claude_bin:-no claude on PATH}): it must be the pinned ${pinned:-version} (backlog #0-249)"
fi

[ -z "$(git status --porcelain)" ] || add "working tree is not clean"
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = main ] || add "current branch is $branch, not main"
if git remote get-url origin >/dev/null 2>&1; then
    git fetch --quiet origin main 2>/dev/null || add "git fetch origin main failed"
    if [ "$branch" = main ] && [ -z "$(git status --porcelain)" ]; then
        git merge --ff-only --quiet origin/main 2>/dev/null || add "main cannot fast-forward to origin/main"
    fi
fi
base=$(base_ref)
base_sha=$(git rev-parse --verify --quiet "$base" 2>/dev/null || echo "")

# Fixed (backlog #0-194, ADR-0052): a session reads --settings once, at its start (spike of 2026-11-12 on 2.1.295: a
# rule and an env value changed in the file mid-session did not apply, 15 s later), and this preflight's own
# fast-forward above can change the file seconds before the first agent (#0-197's run, 2026-11-06: the picker ran under
# the old cp rule). settings.autopilot.json carries a hash of itself without that field and of .claude/settings.json,
# which the session loads under it (settings-hash.sh); the session's env holds the value of the files it loaded.
# Computed here, after the fast-forward, from main's files, the two differ when the session started with another file
# or none, or before main's last change to either.
want_settings=$("$(dirname "$0")"/settings-hash.sh .claude/settings.autopilot.json .claude/settings.json 2>/dev/null || echo "")
if [ -z "${FACTORY_SETTINGS_SHA256:-}" ]; then
    add "the session was not started with .claude/settings.autopilot.json (FACTORY_SETTINGS_SHA256 is not set): start it with claude --settings .claude/settings.autopilot.json (backlog #0-194)"
elif [ -z "$want_settings" ]; then
    add "cannot hash .claude/settings.autopilot.json and .claude/settings.json (scripts/factory/settings-hash.sh failed)"
elif [ "$FACTORY_SETTINGS_SHA256" != "$want_settings" ]; then
    add "the session's settings are not main's .claude/settings.autopilot.json and .claude/settings.json (changed since the session started, or other files were loaded): start a new session (backlog #0-194)"
fi

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    stops=$(gh issue list --label autopilot-stop --state open --json number --jq 'length' 2>/dev/null || echo "?")
    if ! is_int "$stops"; then add "could not list autopilot-stop issues"
    elif [ "$stops" -gt 0 ]; then add "$stops open issue(s) labelled autopilot-stop"; fi
    labels=$(gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null || echo "")
    for l in autopilot shadow blocked risk-high autopilot-stop; do
        grep -qx "$l" <<<"$labels" || add "label '$l' does not exist (backlog #0-113)"
    done
    # Fixed (backlog #0-148): `--branch` matches a run's head branch, a name a pull request's author
    # chooses, so the latest run "on main" could be a fork pull request's from a branch named `main`: a red
    # or not yet approved one could stop the autopilot, a green one hide a red main. A push to this repository
    # is the only run that is main's (a push to a fork runs in the fork). main-guard.yml filters the same.
    # No run at all prints nothing (`// empty`), so it reaches the "" arm, not `*` as "null/null".
    ci=$(gh run list --workflow ci.yml --branch main --event push --limit 1 --json status,conclusion --jq '.[0] // empty | "\(.status)/\(.conclusion)"' 2>/dev/null || echo "?")
    case "$ci" in
        completed/success|"") ;;  # green, or no run of main yet
        completed/*) add "latest CI run on main: $ci" ;;
        "?") add "could not read CI status of main" ;;
        requested/*|queued/*|pending/*|waiting/*|in_progress/*) ;;  # not finished: the next preflight decides
        *) add "unexpected CI status of main: $ci" ;;
    esac
    merged=$(gh pr list --label autopilot --state merged --search "merged:>=$today" --json number --jq 'length' 2>/dev/null || echo "?")
    if ! is_int "$merged"; then add "could not count today's merged autopilot PRs"
    elif is_int "$MAX_MERGES" && [ "$merged" -ge "$MAX_MERGES" ]; then add "daily merge limit reached ($merged/$MAX_MERGES)"; fi
    if [ -n "$bot" ]; then
        login=$(gh api user --jq .login 2>/dev/null || echo "")
        [ "$login" = "$bot" ] || add "gh is logged in as '${login:-?}', not the bot '$bot': the run's PRs would not be the machine account's (backlog #0-194)"
    fi
else
    add "gh is not installed or not authenticated (the autopilot opens PRs with it)"
fi

blocked=$(jq -r '.consecutiveBlocked' "$STATE_FILE")
shipped=$(jq -r '.shippedSinceAudit' "$STATE_FILE")
{ is_int "$blocked" && is_int "$shipped"; } || { add "state file unreadable"; blocked=99; shipped=0; }
if is_int "$MAX_BLOCKED" && [ "$blocked" -ge "$MAX_BLOCKED" ]; then
    add "circuit breaker: $blocked items BLOCKED in a row"
    [ -f .ai/STOP ] || printf 'circuit breaker: %s items BLOCKED in a row (%s). Resolve them, then delete this file and run scripts/factory-admin/state-reset.sh blocked.\n' "$blocked" "$today" > .ai/STOP
fi
if is_int "$AUDIT_EVERY" && [ "$shipped" -ge "$AUDIT_EVERY" ]; then
    add "audit due: $shipped items shipped since the last audit"
    [ -f .ai/STOP ] || printf 'audit due: %s items shipped since the last audit (%s). Run /audit <since> <date>, decide, run /apply-audit, then delete this file.\n' "$shipped" "$today" > .ai/STOP
fi

lock="$RUNS_DIR/LOCK"
if [ -f "$lock" ]; then
    age_h=$(( ( $(date +%s) - $(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock") ) / 3600 ))
    if [ "$age_h" -lt "$LOCK_HOURS" ]; then add "another run holds the lock: $(cat "$lock")"; fi
fi

docker info >/dev/null 2>&1 || add "Docker is not reachable (Testcontainers tests need it)"

ok=true
[ "${#reasons[@]}" -eq 0 ] || ok=false
# Fixed (backlog #0-252, review round 1, sec-3c8e): the isolation check trusts the record .ai/runs/isolation/<run id>
# that isolation-probe.sh makes, first one wins, and a run id is a time anyone can predict. A record made before this run
# (by code of an earlier item's gate under ./mvnw, which no shell guard sees, #0-116) would win over the real probe. No
# other run is alive once the lock is taken, so every record goes before it is: whatever is there then is this run's
# probe. `rm -rf` removes a symlink planted at the directory's own name, not what it points to. isolation.sh also takes
# only a record newer than the lock.
if [ "$ok" = true ]; then
    if [ -z "$base_sha" ]; then ok=false; reasons+=("could not resolve the base commit")
    elif ! rm -rf "$RUNS_DIR/isolation" || [ -e "$RUNS_DIR/isolation" ] || [ -L "$RUNS_DIR/isolation" ]; then
        ok=false; reasons+=("cannot clear $RUNS_DIR/isolation, the isolation probe's records, before the run (backlog #0-252)")
    else echo "$run_id $base_sha" > "$lock"; fi
fi

jq -n --argjson ok "$ok" --arg base "$base" --arg sha "$base_sha" --arg run "$run_id" --arg today "$today" \
      --slurpfile state "$STATE_FILE" \
      --args '{ok:$ok, reasons:$ARGS.positional, baseRef:$base, baseSha:$sha, runId:$run, today:$today, state:$state[0]}' \
      ${reasons[@]+"${reasons[@]}"}
