#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory-admin/build-vm/rollback-start.sh and rollback-exec.sh, withdrawn by backlog #0-313
# (ADR-0062 point 5 as amended): each refuses every call, with or without arguments, saying it is withdrawn and where
# the old path runs now, and runs nothing: `limactl` is a stub on PATH that records any call, and no case may make one.
# Run by .github/workflows/factory-guards.yml and .github/scripts/ci-local.sh.
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

mkdir -p "$WORK/bin"
printf '#!/bin/sh\necho "$*" >> "%s/limactl-calls"\nexit 0\n' "$WORK" > "$WORK/bin/limactl"
chmod +x "$WORK/bin/limactl"

# refuses <script> <name> [args...]: exit non-zero, says it is withdrawn and points at the Mac, and calls no limactl.
refuses() {
    local script=$SRC/scripts/factory-admin/build-vm/$1 name=$2 out rc
    shift 2
    rm -f "$WORK/limactl-calls"
    out=$(PATH="$WORK/bin:$PATH" "$script" "$@" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then fail "$name: exit 0"
    elif ! grep -qF "withdrawn (backlog #0-313" <<<"$out"; then fail "$name: does not say it is withdrawn ($out)"
    elif ! grep -qF "devcontainer on the Mac" <<<"$out"; then fail "$name: does not say where the old path runs ($out)"
    elif [ -e "$WORK/limactl-calls" ]; then fail "$name: called limactl ($(cat "$WORK/limactl-calls"))"
    else ok "$name"; fi
}

echo "rollback-start.sh, rollback-exec.sh (withdrawn)"
refuses rollback-start.sh "start refuses"
refuses rollback-start.sh "start refuses with an argument" --force
refuses rollback-exec.sh  "exec refuses"
refuses rollback-exec.sh  "exec refuses a command" bash -lc true

if [ "$failures" -gt 0 ]; then echo "$failures rollback case(s) failed."; exit 1; fi
echo "All rollback cases passed."
