#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory-admin/build-vm/rollback-start.sh and rollback-exec.sh (backlog #0-277, ADR-0062 point 5),
# offline: `limactl` is a stub on PATH that answers `list` and, for `shell ... sudo -u factory -H env
# DOCKER_HOST=unix:///run/docker.sock <cmd>`, plays a scenario of factory's daemon from files under one temporary
# directory per case. A command without that DOCKER_HOST is refused by the stub, so a script that reached the daemon
# through factory's own Docker context would fail every case. What a case checks:
#   - start refuses a VM that is missing or not running, and arguments;
#   - before up, start refuses any container on the daemon (a run's, an unlabelled one, one labelled factory.rollback,
#     a stopped one) and a network or volume labelled factory.task, naming it, and runs no `devcontainer up` then;
#     and a daemon it cannot read;
#   - start runs `devcontainer up` with the label factory.rollback=1, then refuses and removes the rollback's container
#     when, after up, the daemon holds anything but that one running container (a run's network, an unlabelled
#     container), when two containers carry the label, or when the daemon cannot be read; and says so louder when the
#     removal fails;
#   - exec refuses with no running labelled container or with two, and passes the label to `devcontainer exec`.
# Run by .github/workflows/factory-guards.yml and .github/scripts/ci-local.sh.
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
START=$SRC/scripts/factory-admin/build-vm/rollback-start.sh
EXEC=$SRC/scripts/factory-admin/build-vm/rollback-exec.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

mkdir -p "$WORK/bin"
# limactl stub. $CASE holds the scenario, per phase (before or after `devcontainer up`): containers_<phase> (lines of
# `docker ps -a`), networks_<phase>, volumes_<phase> (what the factory.task filter lists), and rollback_id (the ids the
# rollback label filter lists); STUB_UP_ID (the container up makes, added to the after-listing), STUB_UP_RC,
# STUB_PS_FAIL (before|after: `docker ps -a` fails then), STUB_RM_RC. Every call is logged in $CASE/calls.
cat > "$WORK/bin/limactl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "--- $*" >> "$CASE/calls"
case $1 in
  list)
    if [ "$2" = --quiet ]; then cat "$CASE/instances"; exit 0; fi
    cat "$CASE/status"; exit 0 ;;
  shell) ;;
  *) echo "stub: unexpected $*" >&2; exit 2 ;;
esac
[ "$2" = --workdir ] && [ "$3" = / ] && [ "$4" = factory-build ] && [ "$5" = sudo ] && [ "$6" = -u ] && [ "$7" = factory ] \
  && [ "$8" = -H ] && [ "$9" = env ] && [ "${10}" = DOCKER_HOST=unix:///run/docker.sock ] \
  || { echo "stub: unexpected $*" >&2; exit 2; }
shift 10
phase=before; [ -f "$CASE/up-ran" ] && phase=after
case "$1 $2" in
  "docker ps")
    if [[ "$*" == *label=factory.rollback=1* ]]; then cat "$CASE/rollback_id" 2>/dev/null || true
    else
      [ "${STUB_PS_FAIL:-}" = "$phase" ] && { echo "stub: daemon unreachable" >&2; exit 1; }
      # A filter on factory.task keeps only a run's containers (named factory-task-* here), as the daemon would: a script
      # that filtered so would miss every other one.
      if [[ "$*" == *label=factory.task* ]]; then grep 'factory-task' "$CASE/containers_$phase" 2>/dev/null || true
      else cat "$CASE/containers_$phase" 2>/dev/null || true; fi
      if [ "$phase" = after ] && [ -n "${STUB_UP_ID:-}" ]; then echo "$STUB_UP_ID running rollback=1 roll"; fi
    fi ;;
  "docker network") cat "$CASE/networks_$phase" 2>/dev/null || true ;;
  "docker volume") cat "$CASE/volumes_$phase" 2>/dev/null || true ;;
  "docker rm") echo "$*" >> "$CASE/removed"; exit "${STUB_RM_RC:-0}" ;;
  "devcontainer up")
    touch "$CASE/up-ran"
    if [ -n "${STUB_UP_ID:-}" ] && [ ! -f "$CASE/rollback_id" ]; then echo "$STUB_UP_ID" > "$CASE/rollback_id"; fi
    exit "${STUB_UP_RC:-0}" ;;
  "devcontainer exec") echo "$*" >> "$CASE/exec" ;;
  *) echo "stub: unexpected command $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$WORK/bin/limactl"
export PATH="$WORK/bin:$PATH"

n=0
new_case() {
  n=$((n+1)); CASE=$WORK/case$n; export CASE; mkdir -p "$CASE"
  echo factory-build > "$CASE/instances"; echo Running > "$CASE/status"; : > "$CASE/calls"
  unset STUB_UP_ID STUB_UP_RC STUB_PS_FAIL STUB_RM_RC
}
run() { OUT=$("$@" 2>&1); RC=$?; }
expect_fail() {  # <name> <text>
  if [ "$RC" -eq 0 ]; then fail "$1: exit 0, wanted a refusal ($OUT)"
  elif ! grep -qF -- "$2" <<<"$OUT"; then fail "$1: output lacks '$2' ($OUT)"
  else ok "$1"; fi
}
up_ran() { grep -q -- 'devcontainer up' "$CASE/calls"; }
no_up() { if up_ran; then fail "$1: devcontainer up ran"; else ok "$1: no up"; fi; }
removed() { if grep -q "docker rm -f $1" "$CASE/removed" 2>/dev/null; then ok "$2: the rollback's container removed"
            else fail "$2: the rollback's container was not removed"; fi; }

echo "rollback-start: what it refuses before up"
new_case; run "$START" extra; expect_fail "an argument" "usage:"
new_case; : > "$CASE/instances"; run "$START"; expect_fail "no VM" "no instance factory-build"
new_case; echo Stopped > "$CASE/status"; run "$START"; expect_fail "a stopped VM" "is Stopped, not Running"
while IFS='|' read -r what file line; do
  new_case; echo "$line" > "$CASE/$file"; run "$START"
  expect_fail "before up, $what" "$line"; no_up "$what"
done <<'CASES'
a run's container|containers_before|c1 running rollback= factory-task-r1
an unlabelled container a task left|containers_before|c2 running rollback= lurker
a container a task labelled factory.rollback|containers_before|c3 running rollback=1 fake-rollback
an earlier rollback's stopped container|containers_before|c4 exited rollback=1 old-rollback
a run's network|networks_before|network n1 factory-task-r1
a run's volume|volumes_before|volume factory-task-r1-claude
CASES
new_case; STUB_PS_FAIL=before run "$START"; expect_fail "before up, a daemon it cannot read" "cannot read factory's daemon"; no_up "unreadable daemon"
new_case; echo "c4 exited rollback=1 old" > "$CASE/containers_before"; run "$START"
expect_fail "a refusal names the commands that clear it" "cli.mjs sweep"
if grep -qF -- "docker rm <id>" <<<"$OUT"; then ok "  and docker rm for an earlier rollback"
else fail "the refusal does not name docker rm ($OUT)"; fi

echo "rollback-start: up and the check after it"
new_case; STUB_UP_ID=abc123 run "$START"
if [ "$RC" -eq 0 ] && grep -q -- 'devcontainer up --workspace-folder /home/factory/incident-platform --id-label factory.rollback=1' "$CASE/calls"; then
  ok "an empty daemon: up with the label factory.rollback=1, exit 0"
else fail "clean start: exit $RC ($OUT)"; fi
new_case; echo "network n1 factory-task-r2" > "$CASE/networks_after"; STUB_UP_ID=abc123 run "$START"
expect_fail "after up, a run that began meanwhile" "a dispatcher run began while the rollback started"; removed abc123 "a run began"
new_case; echo "c9 running rollback= lurker" > "$CASE/containers_after"; STUB_UP_ID=abc123 run "$START"
expect_fail "after up, a container beside the rollback's" "holds more than the rollback's container"; removed abc123 "a container beside"
new_case; printf 'abc123\nzzz999\n' > "$CASE/rollback_id"; STUB_UP_ID=abc123 run "$START"
expect_fail "after up, two labelled containers" "more than one running container is labelled"; removed zzz999 "two labelled"
new_case; STUB_UP_ID=abc123 STUB_PS_FAIL=after run "$START"
expect_fail "after up, a daemon it cannot read" "cannot read factory's daemon after up"; removed abc123 "unreadable after up"
new_case; echo "network n1 factory-task-r2" > "$CASE/networks_after"; STUB_UP_ID=abc123 STUB_RM_RC=1 run "$START"
expect_fail "after up, the removal failing" "could not be removed: remove it before logging in"
new_case; run "$START"; expect_fail "no labelled container after up" "no running container labelled factory.rollback=1"
new_case; STUB_UP_RC=1 run "$START"; expect_fail "up failing" "devcontainer up failed"

echo "rollback-exec"
new_case; run "$EXEC"; expect_fail "no rollback container" "start one with rollback-start.sh"
new_case; printf 'abc123\nzzz999\n' > "$CASE/rollback_id"; run "$EXEC"; expect_fail "two rollback containers" "more than one running container"
new_case; echo abc123 > "$CASE/rollback_id"; run "$EXEC" gh auth status
if [ "$RC" -eq 0 ] && grep -q -- '--id-label factory.rollback=1 gh auth status' "$CASE/exec"; then ok "exec through the label, the command passed"
else fail "exec: exit $RC ($OUT)"; fi
new_case; echo abc123 > "$CASE/rollback_id"; run "$EXEC"
if grep -q -- '--id-label factory.rollback=1 bash' "$CASE/exec" 2>/dev/null; then ok "exec defaults to bash"; else fail "exec default: $OUT"; fi

if [ "$failures" -gt 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "All cases passed."
