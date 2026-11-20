#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/), on the Mac. Runs a command in the rollback's devcontainer on the build VM (backlog
# #0-277, ADR-0062 point 5), found by its label `factory.rollback=1`, as rollback-start.sh started it.
#
#   rollback-exec.sh [command...]     default: bash, interactive, as `dev`
#
# Through the label, never `devcontainer exec --workspace-folder` alone: that finds no container started with
# --id-label, and a following `up` would make a second, unlabelled one on the same credential volumes. It refuses when
# no running container carries the label (start one with rollback-start.sh), or more than one does. The daemon is
# reached by DOCKER_HOST, never through the current context of /home/factory/.docker, which the agent side writes.
# ============================================================
set -euo pipefail

NAME=factory-build
CLONE=/home/factory/incident-platform
LABEL=factory.rollback=1
SOCK=unix:///run/docker.sock

fail() { echo "rollback-exec.sh: $*" >&2; exit 1; }
command -v limactl >/dev/null || fail "limactl not found (brew install lima)"
as_factory() { limactl shell --workdir / "$NAME" sudo -u factory -H env "DOCKER_HOST=$SOCK" "$@"; }
ids=$(as_factory docker ps -q --filter "label=$LABEL") || fail "cannot read factory's daemon on $NAME"
[ -n "$ids" ] || fail "no running rollback container (label $LABEL): start one with rollback-start.sh"
[ "$(wc -l <<<"$ids")" -eq 1 ] || fail "more than one running container is labelled $LABEL: stop them and start again with rollback-start.sh"
[ "$#" -gt 0 ] || set -- bash
exec limactl shell --workdir / "$NAME" sudo -u factory -H env "DOCKER_HOST=$SOCK" devcontainer exec --workspace-folder "$CLONE" --id-label "$LABEL" "$@"
