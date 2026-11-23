#!/usr/bin/env bash
# ============================================================
# #0-285, option C: each slot's daemon publishes its ports on an address of its own, and FACTORY-EGRESS lets a
# slot's uid reach only its own address. On a temporary user `factory-t` (slot "2") beside `factory` (slot "1"):
#   - factory-t's daemon.json: "ip" and "host-gateway-ip" = 10.204.2.1 (a dummy interface made here);
#   - a temporary rule: factory-t's uid may reach 10.204.2.1 on lo; nothing else is added (the chain rejects the
#     private address for every other uid, as measure-a showed for 10.203.0.1);
#   - a PostgreSQL published at random (-P, the way Testcontainers does), then:
#       where it is bound (expected 10.204.2.1, not 0.0.0.0 or the VM's address);
#       reached from factory-t's own container through host.docker.internal and 10.204.2.1 (expected open);
#       reached from factory's container through 10.204.2.1, the VM's address and host.docker.internal (expected closed).
# As root on the build VM, while no dispatcher run is live:
#   limactl shell factory-build sudo bash -s < measure-d-0285.sh 2>&1 | tee ~/measure-d-0285.log
# Leaves nothing: the rule, the dummy interface and the user factory-t are removed on exit.
# ============================================================
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
if pgrep -u dispatcher -f 'cli.mjs run' >/dev/null; then echo "a dispatcher run is live: run this later" >&2; exit 1; fi

F=factory; T=factory-t; ADDR=10.204.2.1
fuid=$(id -u "$F")
vm_ip=$(ip -4 -o addr show "$(ip -4 route show default | awk '{print $5; exit}')" | awk '{print $4; exit}' | cut -d/ -f1)
rule=()

as_f() { runuser -u "$F" -- env XDG_RUNTIME_DIR="/run/user/$fuid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$fuid/bus" \
  DOCKER_HOST="unix:///run/user/$fuid/docker.sock" "$@"; }
tuid() { id -u "$T"; }
as_t() { local u; u=$(tuid); runuser -u "$T" -- env XDG_RUNTIME_DIR="/run/user/$u" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u/bus" \
  DOCKER_HOST="unix:///run/user/$u/docker.sock" "$@"; }

cleanup() {
  [ "${#rule[@]}" -gt 0 ] && iptables -D FACTORY-EGRESS "${rule[@]}" 2>/dev/null
  ip link del m0285d 2>/dev/null
  if id "$T" >/dev/null 2>&1; then
    as_t docker rm -f m0285-pg >/dev/null 2>&1
    loginctl terminate-user "$T" 2>/dev/null; loginctl disable-linger "$T" 2>/dev/null
    systemctl stop "user@$(tuid).service" 2>/dev/null
    userdel -r "$T" 2>/dev/null
  fi
}
trap cleanup EXIT

helper_f=$(as_f docker images --format '{{.Repository}} {{.ID}}' | awk '$1 == "buildpack-deps" {print $2; exit}')
[ -n "$helper_f" ] || { echo "no buildpack-deps image in factory's daemon" >&2; exit 1; }

ip link add m0285d type dummy && ip addr add "$ADDR/32" dev m0285d && ip link set m0285d up

useradd --create-home --shell /bin/bash "$T"
u=$(tuid)
# daemon.json before the daemon's first start, written as the user itself (provision.sh's rule for factory's).
# shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
runuser -u "$T" -- sh -c 'mkdir -p "$HOME/.config/docker" && printf "%s\n" "$1" > "$HOME/.config/docker/daemon.json"' \
  _ "{ \"ip\": \"$ADDR\", \"host-gateway-ip\": \"$ADDR\" }"
loginctl enable-linger "$T"
for _ in $(seq 60); do [ -S "/run/user/$u/bus" ] && break; sleep 1; done
as_t dockerd-rootless-setuptool.sh install >/dev/null 2>&1 || { echo "rootless install for $T failed" >&2; exit 1; }
rule=(-m owner --uid-owner "$u" -o lo -d "$ADDR/32" -j ACCEPT)
iptables -I FACTORY-EGRESS 1 "${rule[@]}"

as_t docker pull -q postgres:16-alpine >/dev/null || { echo "pull postgres failed" >&2; exit 1; }
as_t docker pull -q buildpack-deps:noble-scm >/dev/null || { echo "pull helper failed" >&2; exit 1; }
as_t docker run -d --name m0285-pg -e POSTGRES_PASSWORD=m0285 -P postgres:16-alpine >/dev/null && sleep 6
echo "RESULT D.published $(as_t docker port m0285-pg 5432/tcp | tr '\n' ' ')"
port=$(as_t docker port m0285-pg 5432/tcp | awk -F: 'NR==1 {print $NF}')
echo "RESULT D.listening $(ss -ltnH "sport = :$port" | awk '{print $4}' | tr '\n' ' ')"

probe() {  # who image addresses...
  local who=$1 img=$2; shift 2
  local run; [ "$who" = own_slot ] && run=as_t || run=as_f
  # shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
  $run docker run --rm --add-host host.docker.internal:host-gateway "$img" bash -c '
    p='"$port"'
    for h in "$@"; do
      if timeout 3 bash -c "</dev/tcp/$h/$p" 2>/dev/null; then echo "$h open"; else echo "$h closed"; fi
    done' _ "$@" | while read -r h v; do echo "RESULT D.$who.$h $v"; done
}
probe own_slot buildpack-deps:noble-scm host.docker.internal "$ADDR"
probe other_slot "$helper_f" "$ADDR" "$vm_ip" host.docker.internal
echo "RESULT done"
