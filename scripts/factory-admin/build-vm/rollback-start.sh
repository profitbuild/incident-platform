#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/), on the Mac. Starts the rollback's devcontainer on the build VM (backlog #0-277,
# ADR-0062 point 5): today's /backlog-autopilot, in the VM's devcontainer, while the dispatcher is not running. For a
# VM made from a provision.sh of #0-277 and on, with a FACTORY_COMMIT that carries #0-277's dispatcher code (its
# refusal on the label below, and `cli.mjs sweep`).
#
#   rollback-start.sh
#
# The rollback and the dispatcher share the VM by time, since no credential may be on `factory`'s daemon while a task
# runs (a test holding the Docker socket can mount any volume of that daemon). So, before the owner's logins go in:
#   - before `up`, factory's daemon must hold no container at all, in any state, and no network or volume labelled
#     `factory.task`. Not only a run's labelled objects: a task's code that holds the socket can leave an unlabelled
#     container behind (a killed run never reaches its sweep), or one it labelled `factory.rollback` itself, which `up`
#     would take as the rollback's own; either could mount the credential volumes once the owner logs in (review round
#     1 of #0-277's VM part). A refusal names what it found: a leftover of a run goes with the dispatcher's `cli.mjs
#     sweep`, and a stopped container of an earlier rollback with `docker rm` (its logins stay in their named volumes);
#   - it starts the devcontainer of the VM's clone (/home/factory/incident-platform, create.sh's) with the positive
#     label `factory.rollback=1` (`devcontainer up --id-label`), the one signal the dispatcher refuses to start on;
#   - once `up` has returned, and before the owner is told to log in, it checks again: the daemon must hold exactly one
#     container, running, the labelled one `up` made, and no `factory.task` network or volume. A dispatcher run that
#     began while the image was building has made itself visible by then (its labelled network, ADR-0062 point 5); then,
#     or on anything else found, the rollback's container is removed and the script refuses.
# Every docker and devcontainer command here reaches the daemon by DOCKER_HOST (the /run/docker.sock link, as the
# dispatcher's sudo rule; create.sh's checks name the daemon's own socket), never through the current context of
# /home/factory/.docker, which the agent side writes.
# What it cannot see: anything a dispatcher task left in factory's reach but a container or a factory.task object (its
# home, a Docker CLI plugin the devcontainer CLI runs on the VM, a systemd unit, the clone, an unlabelled named volume,
# the image store and build cache this script's own `up` builds from). A rollback with the owner's
# logins after a dispatcher run starts on a VM made anew (ADR-0062's Consequences, accepted for the migration).
# Then log in inside it (rollback-exec.sh) as docs/ai-factory.md "Build VM" says. When the rollback is done, stop its
# container (`limactl shell factory-build sudo -u factory -H env DOCKER_HOST=unix:///run/docker.sock docker stop <id>`,
# the id this script prints); the next
# dispatcher run removes it and its volumes, the logins with them. A bare `devcontainer up` or `exec
# --workspace-folder` would not find the labelled container and would make a second, unlabelled one on the same
# credential volumes: every devcontainer command of the rollback goes through this script and rollback-exec.sh.
# ============================================================
set -euo pipefail

NAME=factory-build
CLONE=/home/factory/incident-platform
LABEL=factory.rollback=1
SOCK=unix:///run/docker.sock

fail() { echo "rollback-start.sh: $*" >&2; exit 1; }
[ "$#" -eq 0 ] || fail "usage: rollback-start.sh (no arguments)"
command -v limactl >/dev/null || fail "limactl not found (brew install lima)"
instances=$(limactl list --quiet) || fail "cannot list Lima's instances"
grep -qx "$NAME" <<<"$instances" || fail "no instance $NAME (create.sh first)"
status=$(limactl list --format '{{.Status}}' "$NAME") || fail "cannot read $NAME's status"
[ "$status" = Running ] || fail "$NAME is $status, not Running (limactl start $NAME)"

as_factory() { limactl shell --workdir / "$NAME" sudo -u factory -H env "DOCKER_HOST=$SOCK" "$@"; }

# containers: every container of factory's daemon, any state, one per line: id, state, rollback label, name.
containers() { as_factory docker ps -a --no-trunc --format '{{.ID}} {{.State}} rollback={{.Label "factory.rollback"}} {{.Names}}'; }
# task_others: a run's networks and volumes (labelled factory.task), one per line, or a failure (no answer is no pass).
task_others() {
  local n v
  n=$(as_factory docker network ls --filter label=factory.task --format 'network {{.ID}} {{.Name}}') || return 1
  v=$(as_factory docker volume ls --filter label=factory.task --format 'volume {{.Name}}') || return 1
  printf '%s\n' "$n" "$v" | sed '/^$/d'
}

all=$(containers) || fail "cannot read factory's daemon"
others=$(task_others) || fail "cannot read factory's daemon"
if [ -n "$all" ] || [ -n "$others" ]; then
  fail "factory's daemon is not empty: a dispatcher run is on, or a killed run or an earlier rollback left these.
A run's leftovers: the dispatcher's \`cli.mjs sweep\`; an earlier rollback's stopped container:
  limactl shell $NAME sudo -u factory -H env DOCKER_HOST=$SOCK docker rm <id>   (its logins stay in their volumes)
$(printf '%s\n' "$all" "$others" | sed '/^$/d')"
fi

as_factory devcontainer up --workspace-folder "$CLONE" --id-label "$LABEL" >/dev/null \
  || fail "devcontainer up failed for $CLONE"
ids=$(as_factory docker ps -q --no-trunc --filter "label=$LABEL") || fail "cannot read the rollback's container"
[ -n "$ids" ] || fail "no running container labelled $LABEL after devcontainer up"

# remove_and_fail <reason>: the rollback's container(s) removed, then the refusal (or, if that fails, a louder one).
remove_and_fail() {
  local id
  for id in $ids; do
    as_factory docker rm -f "$id" >/dev/null 2>&1 \
      || fail "$1; and the rollback's container $id could not be removed: remove it before logging in"
  done
  fail "$1; the rollback's container was removed, log in nowhere"
}
[ "$(wc -l <<<"$ids")" -eq 1 ] || remove_and_fail "more than one running container is labelled $LABEL"
all=$(containers) || remove_and_fail "cannot read factory's daemon after up"
others=$(task_others) || remove_and_fail "cannot read factory's daemon after up"
[ -z "$others" ] || remove_and_fail "a dispatcher run began while the rollback started:
$others"
[ "$all" = "$ids running rollback=1 ${all##* }" ] || remove_and_fail "factory's daemon holds more than the rollback's container after up:
$all"
echo "rollback-start.sh: the rollback's devcontainer runs (container ${ids:0:12}, label $LABEL); enter it with rollback-exec.sh"
