#!/usr/bin/env bash
# ============================================================
# Two follow-ups of measure-a-0313: a unix socket the container can open (group factory), and another slot's port
# published at random (-P, the way Testcontainers publishes: a port from the ephemeral range).
# As root on the build VM, while no dispatcher run is live:
#   limactl shell factory-build sudo bash -s < measure-c-0313.sh 2>&1 | tee ~/measure-c-0313.log
# Leaves nothing: the listeners, the dummy interface, the temporary egress rule, the user factory-t are removed on exit.
# ============================================================
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
if pgrep -u dispatcher -f 'cli.mjs run' >/dev/null; then echo "a dispatcher run is live: run this later" >&2; exit 1; fi

F=factory; T=factory-t; D=dispatcher; S=/run/m0285
fuid=$(id -u "$F")
vm_ip=$(ip -4 -o addr show "$(ip -4 route show default | awk '{print $5; exit}')" | awk '{print $4; exit}' | cut -d/ -f1)
P_OUT=18080; DUMMY=10.203.0.1
pids=(); rule_added=no

as_f() { runuser -u "$F" -- env XDG_RUNTIME_DIR="/run/user/$fuid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$fuid/bus" \
  DOCKER_HOST="unix:///run/user/$fuid/docker.sock" "$@"; }
tuid() { id -u "$T"; }
as_t() { local u; u=$(tuid); runuser -u "$T" -- env XDG_RUNTIME_DIR="/run/user/$u" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u/bus" \
  DOCKER_HOST="unix:///run/user/$u/docker.sock" "$@"; }

cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  [ "$rule_added" = yes ] && iptables -D FACTORY-EGRESS -d "$DUMMY/32" -p tcp --dport "$P_OUT" -j ACCEPT 2>/dev/null
  ip link del m0285 2>/dev/null
  if id "$T" >/dev/null 2>&1; then
    as_t docker rm -f m0285-pg >/dev/null 2>&1
    loginctl terminate-user "$T" 2>/dev/null; loginctl disable-linger "$T" 2>/dev/null
    systemctl stop "user@$(tuid).service" 2>/dev/null
    userdel -r "$T" 2>/dev/null
  fi
  rm -rf "$S"
}
trap cleanup EXIT

# How factory's rootless network runs (the unit's environment, and rootlesskit's own arguments).
echo "RESULT rootless_unit_env $(grep -h -E '^Environment' /home/$F/.config/systemd/user/docker.service 2>/dev/null | tr '\n' ' ')"
echo "RESULT rootlesskit_args $(pgrep -u "$F" -a rootlesskit | head -1 | cut -d' ' -f2- | tr -s ' ' | cut -c1-400)"
helper=$(as_f docker images --format '{{.Repository}} {{.ID}}' | awk '$1 == "buildpack-deps" {print $2; exit}')
[ -n "$helper" ] || { echo "no buildpack-deps image in factory's daemon (provision.sh pulls it)" >&2; exit 1; }
echo "RESULT helper_image_id $helper"

# --- the socket, group factory ------------------------------------------------------------------------------------
install -d -m 0750 -o "$D" -g "$F" "$S"
# shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
runuser -u "$D" -- node -e '
  const http = require("http"), fs = require("fs"); const p = process.argv[1];
  http.createServer((q, r) => r.end("ok")).listen(p, () => fs.chmodSync(p, 0o660));' "$S/api.sock" &
pids+=($!); sleep 1; chgrp "$F" "$S/api.sock"
echo "RESULT C.socket_mode $(stat -c '%U:%G %a' "$S/api.sock")"
echo "RESULT C.unix_socket $(as_f docker run --rm -v "$S/api.sock:/s/api.sock" "$helper" curl -s -o /dev/null -w '%{http_code}' --max-time 5 --unix-socket /s/api.sock http://proxy.invalid/ || true)"

# --- another slot's port published at random -----------------------------------------------------------------------
useradd --create-home --shell /bin/bash "$T"
loginctl enable-linger "$T"
u=$(tuid); for _ in $(seq 60); do [ -S "/run/user/$u/bus" ] && break; sleep 1; done
as_t dockerd-rootless-setuptool.sh install >/dev/null 2>&1 || { echo "rootless install for $T failed" >&2; exit 1; }
as_t docker pull -q postgres:16-alpine >/dev/null || { echo "pull failed" >&2; exit 1; }
as_t docker run -d --name m0285-pg -e POSTGRES_PASSWORD=m0285 -P postgres:16-alpine >/dev/null && sleep 6
port=$(as_t docker port m0285-pg 5432/tcp | awk -F: 'NR==1 {print $NF}')
echo "RESULT C.random_port $port"
# shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
as_f docker run --rm --add-host host.docker.internal:host-gateway "$helper" bash -c '
  for h in '"$vm_ip"' host.docker.internal; do
    if timeout 3 bash -c "</dev/tcp/$h/'"$port"'" 2>/dev/null; then echo "$h open"; else echo "$h closed"; fi
  done' | while read -r h v; do echo "RESULT C.other_slot_random_port.$h $v"; done
echo "RESULT done"
