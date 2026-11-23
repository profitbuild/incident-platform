#!/usr/bin/env bash
# ============================================================
# Part A again (#0-313 measurement 2) and B's port test (#0-285), after the first run's helper reference failed
# ("invalid reference format": the helper image is pulled by digest, so its tag is <none>; it is used by ID here).
# As root on the build VM, while no dispatcher run is live:
#   limactl shell factory-build sudo bash -s < measure-a-0313.sh 2>&1 | tee ~/measure-a-0313.log
# Leaves nothing: the listeners, the dummy interface, the temporary egress rule, the user factory-t are removed on exit.
# ============================================================
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
if pgrep -u dispatcher -f 'cli.mjs run' >/dev/null; then echo "a dispatcher run is live: run this later" >&2; exit 1; fi

F=factory; T=factory-t; D=dispatcher; S=/run/m0285
fuid=$(id -u "$F")
vm_ip=$(ip -4 -o addr show "$(ip -4 route show default | awk '{print $5; exit}')" | awk '{print $4; exit}' | cut -d/ -f1)
read -r eph_lo _ < /proc/sys/net/ipv4/ip_local_port_range
P_OUT=18080; P_EPH=$((eph_lo + 1000)); DUMMY=10.203.0.1
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

# --- A. the proxy's address ---------------------------------------------------------------------------------------
ip link add m0285 type dummy && ip addr add "$DUMMY/32" dev m0285 && ip link set m0285 up
install -d -m 0750 -o "$D" -g "$F" "$S"
listen() {  # host port | path unix
  # shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
  runuser -u "$D" -- node -e '
    const http = require("http"); const [h, p] = process.argv.slice(1);
    const s = http.createServer((q, r) => r.end("ok"));
    if (p === "unix") s.listen(h, () => require("fs").chmodSync(h, 0o660)); else s.listen(Number(p), h);' "$@" &
  pids+=($!)
}
listen 127.0.0.1 "$P_OUT"; listen "$vm_ip" "$P_OUT"; listen "$vm_ip" "$P_EPH"; listen "$DUMMY" "$P_OUT"; listen "$S/api.sock" unix
sleep 1
probe() {  # label
  # shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
  as_f docker run --rm --add-host host.docker.internal:host-gateway -v "$S/api.sock:/s/api.sock" "$helper" sh -c '
    c() { curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$@" || true; }
    echo "slirp_10.0.2.2:'"$P_OUT"' $(c http://10.0.2.2:'"$P_OUT"'/)"
    echo "host.docker.internal:'"$P_OUT"' $(c http://host.docker.internal:'"$P_OUT"'/)"
    echo "host.docker.internal:'"$P_EPH"'(ephemeral) $(c http://host.docker.internal:'"$P_EPH"'/)"
    echo "vm_ip:'"$P_OUT"' $(c http://'"$vm_ip"':'"$P_OUT"'/)"
    echo "dummy_'"$DUMMY"':'"$P_OUT"' $(c http://'"$DUMMY"':'"$P_OUT"'/)"
    echo "unix_socket $(c --unix-socket /s/api.sock http://proxy.invalid/)"' | while read -r k v; do echo "RESULT A.$1.$k ${v:-000}"; done
}
probe chain_as_is
iptables -I FACTORY-EGRESS 1 -d "$DUMMY/32" -p tcp --dport "$P_OUT" -j ACCEPT && rule_added=yes
probe with_dummy_rule
iptables -D FACTORY-EGRESS -d "$DUMMY/32" -p tcp --dport "$P_OUT" -j ACCEPT && rule_added=no

# --- B. another slot's published port -------------------------------------------------------------------------------
useradd --create-home --shell /bin/bash "$T"
loginctl enable-linger "$T"
u=$(tuid); for _ in $(seq 60); do [ -S "/run/user/$u/bus" ] && break; sleep 1; done
as_t dockerd-rootless-setuptool.sh install >/dev/null 2>&1 || { echo "rootless install for $T failed" >&2; exit 1; }
as_t docker pull -q postgres:16-alpine >/dev/null || { echo "pull failed" >&2; exit 1; }
as_t docker run -d --name m0285-pg -e POSTGRES_PASSWORD=m0285 -p 15432:5432 postgres:16-alpine >/dev/null && sleep 6
echo "RESULT B.published_by_factory-t $(as_t docker port m0285-pg 2>/dev/null | tr '\n' ' ')"
# shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
as_f docker run --rm --add-host host.docker.internal:host-gateway "$helper" bash -c '
  for h in '"$vm_ip"' host.docker.internal 10.0.2.2 127.0.0.1; do
    if timeout 3 bash -c "</dev/tcp/$h/15432" 2>/dev/null; then echo "$h open"; else echo "$h closed"; fi
  done' | while read -r h v; do echo "RESULT B.other_slot_port.$h $v"; done
echo "RESULT done"
