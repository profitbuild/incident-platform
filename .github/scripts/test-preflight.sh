#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory/preflight.sh's reading of main's CI result (backlog #0-148), of Claude Code's
# version (backlog #0-162 PR 2, #0-249: the running binary's, exactly .devcontainer/claude-code.pin's, a pin no lower
# than 2.1.295), and of where and how the session was started
# (backlog #0-194, ADR-0052: the devcontainer, the bot's identity, the firewall, main's settings.autopilot.json and
# the limits it sets), in a temporary repository with gh, docker, claude and curl replaced by stubs on PATH (the
# real .ai/runs/ is never touched). Every case runs in the environment of a correct session (exported below) unless
# it unsets or changes one variable.
#
# The gh stub answers `gh run list` from a list of runs, newest first, filtered the way GitHub filters
# them: `--branch` by the run's head branch, `--event` by its event, then `--limit`. That is what made
# #0-148 possible: a fork pull request's run from a branch named `main` has head branch `main` too, and
# without `--event push` it was "the latest CI run on main".
# Run: .github/scripts/test-preflight.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

mkdir -p "$WORK/bin" "$WORK/repo/scripts/factory"
cp "$SRC"/scripts/factory/_common.sh "$SRC"/scripts/factory/preflight.sh "$SRC"/scripts/factory/settings-hash.sh \
    "$WORK/repo/scripts/factory/"

# gh: authenticated, no autopilot-stop issue, every label present, no merged autopilot PR today; runs
# from $RUNS (a JSON array, newest first).
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
jq_expr=. branch="" event="" limit=20
cmd="$1 $2"
shift 2
while [ $# -gt 0 ]; do
    case "$1" in
        --jq) jq_expr=$2; shift 2 ;;
        --branch) branch=$2; shift 2 ;;
        --event) event=$2; shift 2 ;;
        --limit) limit=$2; shift 2 ;;
        *) shift ;;
    esac
done
case "$cmd" in
    "auth status") exit 0 ;;
    "api user") printf '%s\n' "${GH_LOGIN-bot}" ;;
    "issue list"|"pr list") echo '[]' | jq -r "$jq_expr" ;;
    "label list") jq -n '[{name:"autopilot"},{name:"shadow"},{name:"blocked"},{name:"risk-high"},{name:"autopilot-stop"}]' | jq -r "$jq_expr" ;;
    "run list") printf '%s' "$RUNS" | jq --arg b "$branch" --arg e "$event" --argjson n "$limit" \
                    '[.[] | select(($b == "" or .headBranch == $b) and ($e == "" or .event == $e))] | .[:$n]' | jq -r "$jq_expr" ;;
    *) echo "gh stub: unexpected '$cmd'" >&2; exit 1 ;;
esac
STUB
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/docker"
# curl: exits $CURL_EXIT (7, "failed to connect", when unset: what the devcontainer's firewall answers for example.com).
# shellcheck disable=SC2016
printf '#!/bin/sh\nexit "${CURL_EXIT-7}"\n' > "$WORK/bin/curl"
chmod +x "$WORK/bin/curl"
# claude: prints $CLAUDE_VERSION_OUT as its version (a current one when unset); `running` is a second binary, the
# one CLAUDE_CODE_EXECPATH names in the cases that set it.
# The stub expands $CLAUDE_VERSION_OUT when it runs, not when it is written: single quotes meant.
# shellcheck disable=SC2016
printf '#!/bin/sh\nprintf "%%s\\n" "${CLAUDE_VERSION_OUT-2.1.310 (Claude Code)}"\n' > "$WORK/bin/claude"
printf '#!/bin/sh\necho "2.1.294 (Claude Code)"\n' > "$WORK/running"
# hangs: never answers (a binary stuck before it prints its version).
printf '#!/bin/sh\nsleep 30\necho "2.1.310 (Claude Code)"\n' > "$WORK/hangs"
chmod +x "$WORK/bin/gh" "$WORK/bin/docker" "$WORK/bin/claude" "$WORK/running" "$WORK/hangs"

cd "$WORK/repo" || exit 1
git init -q -b main
printf '.ai/runs/\n.ai/STOP\n' > .gitignore
mkdir -p .claude
printf '{"permissions":{"defaultMode":"dontAsk"},"env":{"FACTORY_MAX_BLOCKED":"2"}}\n' > .claude/settings.autopilot.json
printf '{"permissions":{"deny":["Bash(gh pr merge *)"]}}\n' > .claude/settings.json
# The pin preflight holds the running version to (backlog #0-249): the claude stub's default version.
mkdir -p .devcontainer
printf '# a comment\nCLAUDE_CODE_VERSION=2.1.310\nCLAUDE_CODE_KEY=%040d\n' 0 > .devcontainer/claude-code.pin
git add -A && git -c user.name=t -c user.email=t@t commit -qm init
settings_sha=$(scripts/factory/settings-hash.sh .claude/settings.autopilot.json .claude/settings.json)

# The environment of a correct session: in the devcontainer, as the bot, started with this repository's
# settings.autopilot.json over its settings.json (their hash, the three limits and the two Bash timeouts its env sets).
# The two timeouts are read from this repository's own settings.autopilot.json, not written here (review round 1 of
# #0-250): a change that lowered them there would pass this file and refuse only at the next run's preflight.
real_settings="$SRC/.claude/settings.autopilot.json"
for timeout_var in BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS; do
    timeout_value=$(jq -r --arg v "$timeout_var" '.env[$v] // empty' "$real_settings") \
        || { echo "::error::cannot read $timeout_var from $real_settings"; exit 1; }
    export "$timeout_var=$timeout_value"
done
export FACTORY_DEVCONTAINER=1 FACTORY_BOT_LOGIN=bot GIT_AUTHOR_NAME=bot GIT_COMMITTER_NAME=bot \
    GIT_AUTHOR_EMAIL=1+bot@users.noreply.github.com GIT_COMMITTER_EMAIL=1+bot@users.noreply.github.com \
    FACTORY_MAX_BLOCKED=2 FACTORY_AUDIT_EVERY=10 FACTORY_MAX_MERGES_PER_DAY=5 FACTORY_SETTINGS_SHA256="$settings_sha"

# run_preflight <runs JSON> — prints preflight's JSON; removes the lock a passing run takes. $CV is the version the
# claude stub prints (unset: a current one), $EXEC the CLAUDE_CODE_EXECPATH (unset: none, as outside Claude Code),
# $WAIT how long preflight waits for it to answer, in tenths of a second.
run_preflight() {
    if [ -n "${EXEC:-}" ]; then
        RUNS=$1 PATH="$WORK/bin:$PATH" CLAUDE_CODE_EXECPATH=$EXEC FACTORY_CLAUDE_VERSION_WAIT=${WAIT:-100} \
            scripts/factory/preflight.sh
    elif [ -n "${CV+set}" ]; then
        RUNS=$1 PATH="$WORK/bin:$PATH" CLAUDE_VERSION_OUT=$CV env -u CLAUDE_CODE_EXECPATH scripts/factory/preflight.sh
    else
        RUNS=$1 PATH="$WORK/bin:$PATH" env -u CLAUDE_CODE_EXECPATH scripts/factory/preflight.sh
    fi
    rm -f .ai/runs/LOCK
}

# expect <name> <runs JSON> <jq expression that must be true of preflight's output>
expect() {
    local out
    out=$(run_preflight "$2")
    if printf '%s' "$out" | jq -e "$3" >/dev/null 2>&1; then ok "$1"; else fail "$1: '$3' is false for: $(printf '%s' "$out" | head -c 600)"; fi
}

push()   { printf '{"event":"push","headBranch":"main","status":"%s","conclusion":"%s"}' "$1" "$2"; }
forkpr() { printf '{"event":"pull_request","headBranch":"main","status":"%s","conclusion":"%s"}' "$1" "$2"; }
branchpr() { printf '{"event":"pull_request","headBranch":"fix/x","status":"%s","conclusion":"%s"}' "$1" "$2"; }

echo "preflight.sh: main's CI result"
expect "a green push to main passes" "[$(push completed success)]" '.ok == true and .reasons == []'
expect "a red push to main stops" "[$(push completed failure)]" \
    '.ok == false and (.reasons | index("latest CI run on main: completed/failure"))'
expect "no run of main yet passes (the \"\" arm, not an unknown status)" "[]" '.ok == true and .reasons == []'
expect "a run of main in progress passes (the next preflight decides)" "[$(push in_progress "")]" '.ok == true'
expect "a queued run of main passes" "[$(push queued "")]" '.ok == true'
expect "a status gh does not document stops" "[$(push mystery "")]" \
    '.ok == false and (.reasons | index("unexpected CI status of main: mystery/"))'
expect "a newer red run of a fork's branch main does not stop a green main" \
    "[$(forkpr completed failure),$(push completed success)]" '.ok == true and .reasons == []'
expect "a newer fork run awaiting approval does not stop a green main" \
    "[$(forkpr completed action_required),$(push completed success)]" '.ok == true and .reasons == []'
expect "a newer green run of a fork's branch main does not hide a red main" \
    "[$(forkpr completed success),$(push completed failure)]" \
    '.ok == false and (.reasons | index("latest CI run on main: completed/failure"))'
expect "a pull request of this repository's own branch is not main's" \
    "[$(branchpr completed failure),$(push completed success)]" '.ok == true'

echo "preflight.sh: Claude Code's version, exactly the pin's (backlog #0-162, #0-249)"
green="[$(push completed success)]"
older='.ok == false and any(.reasons[]; contains("is older than 2.1.295"))'
unread='.ok == false and any(.reasons[]; contains("cannot read the version of Claude Code"))'
nopin='.ok == false and any(.reasons[]; contains("cannot read the pinned Claude Code version"))'
# other <version> — preflight refused a running <version> that is not the pin.
other() { printf '.ok == false and any(.reasons[]; contains("Claude Code %s is running, not the pinned"))' "$1"; }
# with_pin <pin file's content> <expect's arguments...> — runs one case with .devcontainer/claude-code.pin holding
# that content (an empty one: no file), committed so the tree stays clean, then puts the repository's pin back.
with_pin() {
    local content=$1; shift
    if [ -n "$content" ]; then printf '%s\n' "$content" > .devcontainer/claude-code.pin; else rm -f .devcontainer/claude-code.pin; fi
    git add -A && git -c user.name=t -c user.email=t@t commit -qm pin
    expect "$@"
    git reset -q --hard HEAD~1
}
expect "the pinned version passes (2.1.310 in this repository's pin)" "$green" '.ok == true and .reasons == []'
CV="2.1.311 (Claude Code)" expect "a newer version than the pin stops" "$green" "$(other 2.1.311)"
CV="2.1.309 (Claude Code)" expect "an older version than the pin stops" "$green" "$(other 2.1.309)"
CV="2.1.3100 (Claude Code)" expect "a version that only starts with the pin's stops" "$green" "$(other 2.1.3100)"
CV="2.1.295 (Claude Code)" with_pin "CLAUDE_CODE_VERSION=2.1.295" "the floor itself, pinned and running, passes" "$green" '.ok == true'
CV="2.1.1000 (Claude Code)" with_pin "CLAUDE_CODE_VERSION=2.1.1000" "a pin of 2.1.1000 is above the floor (numbers, not text)" "$green" '.ok == true'
CV="2.1.294 (Claude Code)" with_pin "CLAUDE_CODE_VERSION=2.1.294" "a pin below 2.1.295 stops (it ignores onFailure)" "$green" "$older"
CV="2.1.30 (Claude Code)" with_pin "CLAUDE_CODE_VERSION=2.1.30" "a pin of 2.1.30 stops (\"30\" sorts after \"295\" as text)" "$green" "$older"
with_pin "" "no pin file stops" "$green" "$nopin"
with_pin "CLAUDE_CODE_VERSION=latest" "a pin that is not x.y.z stops" "$green" "$nopin"
with_pin "CLAUDE_CODE_VERSION=2.1.310.1" "a pin of four fields stops" "$green" "$nopin"
with_pin "$(printf 'CLAUDE_CODE_VERSION=2.1.310\nCLAUDE_CODE_VERSION=2.1.311')" "a pin with two versions stops" "$green" "$nopin"
with_pin "# CLAUDE_CODE_VERSION=2.1.310" "a commented-out version is no pin" "$green" "$nopin"
CV="Claude Code" expect "an output without a version stops" "$green" "$unread"
CV="" expect "an empty output stops" "$green" "$unread"
CV="2.1.310.1 (Claude Code)" expect "a version of four fields stops" "$green" "$unread"
CV="2.99999999999999999999.0 (Claude Code)" expect "a field too long for a number stops" "$green" "$unread"
EXEC="$WORK/running" expect "the running binary decides, not the one on PATH" "$green" "$(other 2.1.294)"
EXEC="$WORK/no-such-claude" expect "a running binary that cannot answer stops (no fallback to PATH)" "$green" "$unread"
started=$SECONDS
EXEC="$WORK/hangs" WAIT=5 expect "a binary that hangs stops, not the preflight" "$green" "$unread"
if [ $((SECONDS - started)) -lt 20 ]; then ok "... and the preflight did not wait for it (the stub sleeps 30 s)"
else fail "the preflight waited $((SECONDS - started)) s for a binary that hangs"; fi

echo "preflight.sh: where and how the session was started (backlog #0-194)"
# has <text> — a jq expression: preflight refused, and one of its reasons contains <text>.
has() { printf '.ok == false and any(.reasons[]; contains("%s"))' "$1"; }
expect "a correct session passes" "$green" '.ok == true and .reasons == []'
# Backlog #0-252 (review round 1, sec-3c8e): taking the lock removes every isolation record, so a record planted before
# the run, under the run id it gets (a time), cannot be read as its probe; a symlink at the directory's own name goes,
# not what it points to.
mkdir -p .ai/runs/isolation && ln -sn review-general .ai/runs/isolation/20990101-000000
expect "a passing session with an earlier isolation record passes" "$green" '.ok == true and .reasons == []'
if [ ! -e .ai/runs/isolation ] && [ ! -L .ai/runs/isolation ]; then ok "... and removed the isolation records"
else fail "a passing preflight left .ai/runs/isolation: $(find .ai/runs/isolation -maxdepth 1 2>&1 | head -3)"; fi
mkdir -p "$WORK/planted" && ln -sn review-general "$WORK/planted/r" && ln -s "$WORK/planted" .ai/runs/isolation
expect "a symlink at the records' directory passes" "$green" '.ok == true and .reasons == []'
if [ ! -L .ai/runs/isolation ] && [ -L "$WORK/planted/r" ]; then ok "... and removed the link, not what it points to"
else fail "the records' symlinked directory: $(find .ai/runs/isolation "$WORK/planted" -maxdepth 1 2>&1 | head -4)"; fi
mkdir -p .ai/runs/isolation && ln -sn review-general .ai/runs/isolation/20990101-000001
FACTORY_DEVCONTAINER='' expect "a refused session takes no lock" "$green" "$(has "not in the devcontainer")"
if [ -L .ai/runs/isolation/20990101-000001 ]; then ok "... and leaves the records alone (no run started)"
else fail "a refused preflight removed the isolation records"; fi
rm -rf .ai/runs/isolation
FACTORY_DEVCONTAINER='' expect "outside the devcontainer stops" "$green" "$(has "not in the devcontainer")"
FACTORY_BOT_LOGIN='' expect "no bot login stops" "$green" "$(has "FACTORY_BOT_LOGIN is not set")"
GIT_AUTHOR_NAME=owner expect "the owner's git author stops" "$green" "$(has "GIT_AUTHOR_NAME is 'owner', not the bot 'bot'")"
GIT_COMMITTER_NAME='' expect "no git committer stops" "$green" "$(has "GIT_COMMITTER_NAME is '', not the bot")"
GH_LOGIN=owner expect "gh logged in as the owner stops" "$green" "$(has "gh is logged in as 'owner', not the bot 'bot'")"
GH_LOGIN='' expect "gh that names no login stops" "$green" "$(has "gh is logged in as '?'")"
GIT_AUTHOR_EMAIL=owner@example.com expect "the owner's git author email stops" "$green" \
    "$(has "GIT_AUTHOR_EMAIL is 'owner@example.com', not the bot's noreply address")"
GIT_COMMITTER_EMAIL=1+other@users.noreply.github.com expect "another account's noreply address stops" "$green" \
    "$(has "GIT_COMMITTER_EMAIL is '1+other@users.noreply.github.com'")"
GIT_AUTHOR_EMAIL=1x+bot@users.noreply.github.com expect "a noreply address whose id is not digits stops" "$green" \
    "$(has "GIT_AUTHOR_EMAIL is '1x+bot@users.noreply.github.com'")"
GIT_AUTHOR_EMAIL=+bot@users.noreply.github.com expect "a noreply address without an id stops" "$green" \
    "$(has "GIT_AUTHOR_EMAIL is '+bot@users.noreply.github.com'")"
GIT_AUTHOR_EMAIL=1+bot@users.noreply.github.com.evil expect "text after the noreply address stops" "$green" \
    "$(has "GIT_AUTHOR_EMAIL is '1+bot@users.noreply.github.com.evil'")"
CURL_EXIT=0 expect "example.com answering (no firewall) stops" "$green" "$(has "example.com answers")"
CURL_EXIT=28 expect "example.com timing out (a DROP firewall) passes" "$green" '.ok == true'
CURL_EXIT=6 expect "example.com not resolving passes" "$green" '.ok == true'
CURL_EXIT=35 expect "a TLS error after a connection (curl 35) stops" "$green" "$(has "curl exit 35")"
CURL_EXIT=60 expect "a certificate error after a connection (curl 60) stops" "$green" "$(has "curl exit 60")"
# No curl at all: a PATH of every command the preflight finds today but curl (the stubs first, then each directory of
# PATH linked command by command), so nothing else it needs goes missing.
mkdir -p "$WORK/nocurl"
for d in "$WORK/bin" $(printf '%s' "$PATH" | tr ':' ' '); do
    for f in "$d"/*; do
        n=${f##*/}
        [ "$n" = curl ] || [ -e "$WORK/nocurl/$n" ] || { [ -x "$f" ] && [ ! -d "$f" ] && ln -s "$f" "$WORK/nocurl/$n"; }
    done
done
out=$(RUNS=$green PATH="$WORK/nocurl" env -u CLAUDE_CODE_EXECPATH scripts/factory/preflight.sh 2>/dev/null)
rm -f .ai/runs/LOCK
if printf '%s' "$out" | jq -e "$(has "curl is not installed")" >/dev/null 2>&1; then ok "no curl stops"
else fail "no curl: not refused as such: $(printf '%s' "$out" | head -c 400)"; fi
FACTORY_SETTINGS_SHA256='' expect "a session without settings.autopilot.json stops" "$green" \
    "$(has "the session was not started with .claude/settings.autopilot.json")"
FACTORY_SETTINGS_SHA256=0000 expect "a session with other settings stops" "$green" \
    "$(has "the session's settings are not main's")"
# Settings that cannot be hashed (here a project settings file that is not JSON) refuse, never pass.
cp .claude/settings.json "$WORK/settings.json.keep"
printf 'not json' > .claude/settings.json
expect "settings that cannot be hashed stop" "$green" "$(has "cannot hash .claude/settings.autopilot.json and .claude/settings.json")"
cp "$WORK/settings.json.keep" .claude/settings.json
for limit in FACTORY_MAX_BLOCKED FACTORY_AUDIT_EVERY FACTORY_MAX_MERGES_PER_DAY; do
    out=$(unset "$limit"; run_preflight "$green")
    if printf '%s' "$out" | jq -e "$(has "$limit is not set to a number")" >/dev/null 2>&1; then ok "no $limit stops"
    else fail "no $limit: not refused: $(printf '%s' "$out" | head -c 400)"; fi
done
# The Bash timeouts (backlog #0-250): below 30 minutes the gate's command goes to the background and its answer is
# lost. The green case above ran with this repository's own values, so they are not below it either.
for timeout_var in BASH_DEFAULT_TIMEOUT_MS BASH_MAX_TIMEOUT_MS; do
    out=$(unset "$timeout_var"; run_preflight "$green")
    if printf '%s' "$out" | jq -e "$(has "$timeout_var is '', below 1800000")" >/dev/null 2>&1; then ok "no $timeout_var stops"
    else fail "no $timeout_var: not refused: $(printf '%s' "$out" | head -c 400)"; fi
    out=$(export "$timeout_var=120000"; run_preflight "$green")
    if printf '%s' "$out" | jq -e "$(has "$timeout_var is '120000', below 1800000")" >/dev/null 2>&1
    then ok "$timeout_var of 2 minutes (Claude Code's default Bash timeout) stops"
    else fail "$timeout_var of 2 minutes: not refused: $(printf '%s' "$out" | head -c 400)"; fi
    out=$(export "$timeout_var=30m"; run_preflight "$green")
    if printf '%s' "$out" | jq -e "$(has "$timeout_var is '30m', below 1800000")" >/dev/null 2>&1
    then ok "$timeout_var that is not a number of milliseconds stops"
    else fail "$timeout_var of 30m: not refused: $(printf '%s' "$out" | head -c 400)"; fi
    out=$(export "$timeout_var=3600000"; run_preflight "$green")
    if printf '%s' "$out" | jq -e '.ok == true and .reasons == []' >/dev/null 2>&1; then ok "a longer $timeout_var passes"
    else fail "a longer $timeout_var: refused: $(printf '%s' "$out" | head -c 400)"; fi
done
FACTORY_MAX_BLOCKED=two expect "a limit that is not a number stops" "$green" "$(has "FACTORY_MAX_BLOCKED is not set to a number")"
if [ -f .ai/STOP ]; then fail "a missing limit wrote .ai/STOP (the breaker ran against no limit)"; rm -f .ai/STOP
else ok "... and a missing limit did not trip the breaker (no .ai/STOP)"; fi

# The settings hash itself (settings-hash.sh): formatting and key order do not change it, its own field is left out,
# any other change does change it.
# h <autopilot settings> [project settings] — the hash, over $WORK/p.json when no project file is given.
printf '{"permissions":{"deny":["Bash(x)"]}}' > "$WORK/p.json"
h() { scripts/factory/settings-hash.sh "$1" "${2:-$WORK/p.json}"; }
printf '{"env":{"A":"1","FACTORY_SETTINGS_SHA256":"x"},"permissions":{"defaultMode":"dontAsk"}}' > "$WORK/s1.json"
printf '{\n  "permissions": { "defaultMode": "dontAsk" },\n  "env": { "A": "1" }\n}\n' > "$WORK/s2.json"
printf '{"env":{"A":"2"},"permissions":{"defaultMode":"dontAsk"}}' > "$WORK/s3.json"
if [ "$(h "$WORK/s1.json")" = "$(h "$WORK/s2.json")" ]; then ok "settings-hash: key order, layout and its own field do not count"
else fail "settings-hash: the same settings hash differently"; fi
if [ "$(h "$WORK/s1.json")" != "$(h "$WORK/s3.json")" ]; then ok "settings-hash: a changed env value changes it"
else fail "settings-hash: a changed env value left the hash as it was"; fi
printf '{"permissions":{"deny":["Bash(y)"]}}' > "$WORK/p2.json"
if [ "$(h "$WORK/s1.json" "$WORK/p.json")" != "$(h "$WORK/s1.json" "$WORK/p2.json")" ]; then
    ok "settings-hash: a change to the project settings (settings.json) changes it"
else fail "settings-hash: a change to settings.json left the hash as it was"; fi
printf 'not json' > "$WORK/bad.json"
if out=$(h "$WORK/bad.json" 2>/dev/null); then fail "settings-hash: a file that is not JSON printed '$out'"
else ok "settings-hash: a file that is not JSON fails"; fi
if out=$(h "$WORK/s1.json" "$WORK/no-such.json" 2>/dev/null); then fail "settings-hash: a missing project file printed '$out'"
else ok "settings-hash: a missing project settings file fails"; fi

# check-settings-hash.sh (Factory guards): the file's field must be its hash. It runs from the real repository root,
# so it is given absolute paths here.
check="$SRC/.github/scripts/check-settings-hash.sh"
jq --arg h "$(h "$WORK/s2.json")" '.env.FACTORY_SETTINGS_SHA256 = $h' "$WORK/s2.json" > "$WORK/good.json"
if "$check" "$WORK/good.json" "$WORK/p.json" >/dev/null 2>&1; then ok "check-settings-hash: a file that carries its hash passes"
else fail "check-settings-hash: a file that carries its hash failed"; fi
jq '.env.A = "changed"' "$WORK/good.json" > "$WORK/stale.json"
if out=$("$check" "$WORK/stale.json" "$WORK/p.json" 2>&1); then fail "check-settings-hash: a change that left the field passed"
elif printf '%s' "$out" | grep -q "set the field to that value"; then ok "check-settings-hash: a change that left the field fails, naming the value"
else fail "check-settings-hash: unexpected message: $out"; fi
if "$check" "$WORK/good.json" "$WORK/p2.json" >/dev/null 2>&1; then fail "check-settings-hash: a change to settings.json that left the field passed"
else ok "check-settings-hash: a change to settings.json that left the field fails"; fi
if "$check" "$WORK/s2.json" "$WORK/p.json" >/dev/null 2>&1; then fail "check-settings-hash: a file without the field passed"
else ok "check-settings-hash: a file without the field fails"; fi
if "$check" >/dev/null 2>&1; then ok "check-settings-hash: this repository's settings.autopilot.json carries its hash"
else fail "check-settings-hash: this repository's settings.autopilot.json does not carry its hash: $("$check" 2>&1)"; fi

# The hash is compared after the preflight's fast-forward (review round 1): main moved on with a change to the
# settings since the session started, so the session's value is the old files'. Compared before the fast-forward, the
# old files on disk would match it and the stale session would pass. Last, as it gives the repository an origin.
echo "preflight.sh: the settings are main's after the fast-forward"
git init -q --bare -b main "$WORK/origin.git"
git remote add origin "$WORK/origin.git"
git push -q origin main
git clone -q -b main "$WORK/origin.git" "$WORK/other"
(
    cd "$WORK/other" || exit 1
    printf '{"permissions":{"defaultMode":"dontAsk","allow":["Bash(new)"]},"env":{"FACTORY_MAX_BLOCKED":"2"}}\n' \
        > .claude/settings.autopilot.json
    git -c user.name=t -c user.email=t@t commit -qam "settings change on main" || exit 1
    git push -q origin main || exit 1
) || fail "could not push a settings change to the test origin (the case below would not test the fast-forward)"
expect "a session started before main changed its settings stops, after the fast-forward" "$green" \
    "$(has "the session's settings are not main's")"
if git diff --quiet HEAD origin/main; then ok "... and the preflight did fast-forward to that main"
else fail "the preflight did not fast-forward main before comparing"; fi

if [ "$failures" -gt 0 ]; then echo "$failures preflight test(s) failed"; exit 1; fi
echo "All preflight tests passed."
