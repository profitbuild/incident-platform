#!/usr/bin/env bash
# ============================================================
# Two measurements on the build VM, as root, while no dispatcher run is live:
#   A. #0-313 measurement 2: which address a container of `factory`'s rootless daemon reaches the dispatcher's proxy
#      at, and whether FACTORY-EGRESS lets it (127.0.0.1 through slirp, the VM's address inside and outside the
#      ephemeral range that the chain accepts on lo, a dedicated dummy address with and without a rule of its own, a
#      unix socket).
#   B. #0-285 (ADR-0063 R1): the time of one slot's wipe and its images' reload, on a temporary user `factory-t`
#      with its own rootless daemon (as provision.sh makes `factory`'s), three times; and a pull from the network.
#      With it, two facts the review of ADR-0063's amendment asked for: whether a container of `factory` reaches a
#      port `factory-t`'s container publishes (two slots' tasks), and whether `user@<uid>` comes back by itself after
#      `loginctl terminate-user` and a stop while linger is on (the wipe's order).
#
#   limactl shell factory-build sudo bash -s < measure-0285-0313.sh 2>&1 | tee measure-0285-0313.log
#
# It leaves nothing: the listeners, the dummy interface, the temporary egress rule, the user factory-t (its home, its
# daemon's data, its linger) and the image tarball are removed on exit, on any exit. It changes nothing of `factory`
# but pulling postgres:16-alpine and apache/kafka:3.9.2 into its daemon (the images a task's Testcontainers use).
# Results are lines `RESULT <key> <value>`, for the record in m2.md (A) and #0-285 (B).
# ============================================================
set -uo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
if pgrep -u dispatcher -f 'cli.mjs run' >/dev/null; then echo "a dispatcher run is live: run this later" >&2; exit 1; fi

F=factory; T=factory-t; D=dispatcher
W=/var/tmp/m0285; S=/run/m0285
fuid=$(id -u "$F")
vm_ip=$(ip -4 -o addr show "$(ip -4 route show default | awk '{print $5; exit}')" | awk '{print $4; exit}' | cut -d/ -f1)
read -r eph_lo eph_hi < /proc/sys/net/ipv4/ip_local_port_range
P_OUT=18080; P_EPH=$((eph_lo + 1000)); DUMMY=10.203.0.1
IMAGES=(postgres:16-alpine apache/kafka:3.9.2)
pids=(); rule_added=no

as_f() { runuser -u "$F" -- env XDG_RUNTIME_DIR="/run/user/$fuid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$fuid/bus" \
  DOCKER_HOST="unix:///run/user/$fuid/docker.sock" "$@"; }
tuid() { id -u "$T"; }
as_t() { local u; u=$(tuid); runuser -u "$T" -- env XDG_RUNTIME_DIR="/run/user/$u" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$u/bus" \
  DOCKER_HOST="unix:///run/user/$u/docker.sock" "$@"; }
now() { date +%s.%N; }
dt() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }

cleanup() {
  for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
  [ "$rule_added" = yes ] && iptables -D FACTORY-EGRESS -d "$DUMMY/32" -p tcp --dport "$P_OUT" -j ACCEPT 2>/dev/null
  ip link del m0285 2>/dev/null
  if id "$T" >/dev/null 2>&1; then
    loginctl terminate-user "$T" 2>/dev/null; loginctl disable-linger "$T" 2>/dev/null
    systemctl stop "user@$(tuid).service" 2>/dev/null
    userdel -r "$T" 2>/dev/null
  fi
  rm -rf "$W" "$S" /root/m0285-skel
}
trap cleanup EXIT

echo "RESULT vm_ip $vm_ip"
echo "RESULT ephemeral_range $eph_lo-$eph_hi"
echo "RESULT rootless_env $(as_f systemctl --user show docker -p Environment --value 2>/dev/null | tr ' ' '\n' | grep -E 'ROOTLESSKIT|SLIRP' | tr '\n' ' ')"
helper=$(as_f docker images --format '{{.Repository}}:{{.Tag}}' | awk '/^buildpack-deps:/ {print; exit}')
[ -n "$helper" ] || { echo "no buildpack-deps image in factory's daemon (provision.sh pulls it)" >&2; exit 1; }

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

# --- B. a slot's wipe and its images' reload ------------------------------------------------------------------------
install -d -m 0755 "$W"
for i in "${IMAGES[@]}"; do as_f docker pull -q "$i" >/dev/null || { echo "pull $i failed" >&2; exit 1; }; done
task_image=$(as_f docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}' | grep -v -E '^(buildpack-deps|postgres|apache/kafka|<none>)' | head -1 | cut -d' ' -f1)
echo "RESULT B.task_image ${task_image:-none}"
save=("${IMAGES[@]}"); [ -n "$task_image" ] && save+=("$task_image")
install -d -m 0777 "$W/out"
as_f docker save -o "$W/out/images.tar" "${save[@]}" || { echo "docker save failed" >&2; exit 1; }
chmod 0644 "$W/out/images.tar"
echo "RESULT B.tarball_bytes $(stat -c %s "$W/out/images.tar")"

useradd --create-home --shell /bin/bash "$T"
loginctl enable-linger "$T"
u=$(tuid); for _ in $(seq 60); do [ -S "/run/user/$u/bus" ] && break; sleep 1; done
as_t dockerd-rootless-setuptool.sh install >/dev/null 2>&1 || { echo "rootless install for $T failed" >&2; exit 1; }
cp -a "/home/$T" /root/m0285-skel

wait_daemon() { for _ in $(seq 120); do as_t docker info >/dev/null 2>&1 && return 0; sleep 0.5; done; return 1; }
for n in 1 2 3; do
  t0=$(now)
  loginctl terminate-user "$T" 2>/dev/null; systemctl stop "user@$u.service"
  t1=$(now)
  if [ "$n" = 1 ]; then
    sleep 5
    echo "RESULT B.user_manager_back_by_itself_with_linger $(systemctl is-active "user@$u.service" 2>/dev/null || true)"
    systemctl stop "user@$u.service" 2>/dev/null
  fi
  rm -rf "/home/${T:?}"; find /tmp /var/tmp /dev/shm -xdev -uid "$u" -delete 2>/dev/null
  t2=$(now)
  cp -a /root/m0285-skel "/home/$T"; systemctl start "user@$u.service"; wait_daemon || { echo "daemon of $T not up" >&2; exit 1; }
  t3=$(now)
  as_t docker load -q -i "$W/out/images.tar" >/dev/null || { echo "docker load failed" >&2; exit 1; }
  t4=$(now)
  echo "RESULT B.run$n.stop_s $(dt "$t0" "$t1")"
  echo "RESULT B.run$n.remove_s $(dt "$t1" "$t2")"
  echo "RESULT B.run$n.recreate_and_daemon_s $(dt "$t2" "$t3")"
  echo "RESULT B.run$n.load_s $(dt "$t3" "$t4")"
  echo "RESULT B.run$n.total_s $(dt "$t0" "$t4")"
  if [ "$n" = 1 ]; then
    # Another slot's published port: factory-t's PostgreSQL on 15432, tried from a container of factory's daemon.
    as_t docker run -d --name m0285-pg -e POSTGRES_PASSWORD=m0285 -p 15432:5432 postgres:16-alpine >/dev/null \
      && sleep 5
    # shellcheck disable=SC2016 # the single-quoted text is the inner shell's or node's, expanded there
    as_f docker run --rm --add-host host.docker.internal:host-gateway "$helper" bash -c '
      for h in '"$vm_ip"' host.docker.internal 10.0.2.2 127.0.0.1; do
        if timeout 3 bash -c "</dev/tcp/$h/15432" 2>/dev/null; then echo "$h open"; else echo "$h closed"; fi
      done' | while read -r h v; do echo "RESULT B.other_slot_port.$h $v"; done
    as_t docker rm -f m0285-pg >/dev/null 2>&1
  fi
done
as_t docker image rm "${IMAGES[@]}" >/dev/null 2>&1
t0=$(now); for i in "${IMAGES[@]}"; do as_t docker pull -q "$i" >/dev/null; done; t1=$(now)
echo "RESULT B.pull_postgres_kafka_from_network_s $(dt "$t0" "$t1")"
echo "RESULT done"
