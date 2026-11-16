#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/). Creates and starts the build VM from nothing (backlog #0-238, ADR-0056,
# criterion S1): Lima instance `factory-build` from factory-build.yaml, its contents from provision.sh, then the
# repository cloned inside it from GitHub (REPO_URL), owned by the VM's `factory` user (#0-202: a clone of its own, no mount of
# the owner's checkout, no gitignored file of the owner's).
#
#   create.sh            the instance must not exist (delete.sh first): an existing one is refused, not reused, so
#                        "created from nothing" stays true of every VM this script reports
#
# It checks what the ADR and README state as properties rather than trusting the template to give them (review
# round 1 of #0-238): Lima merges ~/.lima/_config/default.yaml and override.yaml into every instance, so a mount or
# SSH agent forwarding set there would reach this VM too. After the start it refuses, and deletes the VM, if Lima
# reports a mount, agent or X11 forwarding, a port forward, an extra network or proxy propagation, or the guest shows
# a host file system or an agent socket. Any failure from `limactl create` until the clone is done deletes the VM
# (review round 3): a half-made VM was never checked, and would only block the next run.
# And the boundary of ADR-0057 (#0-116, #0-240), the same way, on the started VM: no rootful Docker daemon, `factory`
# in no docker group, its daemon rootless, its egress chain in place, the VM's gateway (under Lima, the Mac's loopback
# services) rejected for it, a host outside the allow-list unreachable and one inside it reachable, and its DNS sent to
# the VM's resolver, which adds what it answers for the allow-list (#0-247), checked from a container. Before the VM, the
# VM's copy of the devcontainer's allow-list must equal it both ways (check-allowlists.sh).
# The clone is owned by the subordinate uid the devcontainer's `dev` (uid 1000) maps to under rootless Docker, so
# `dev` can write its workspace.
#
# What it does not do: the logins. The bot's `gh` token and Claude Code's login are entered by the owner once, inside
# the devcontainer in the VM (docs/ai-factory.md "Build VM"). The clone is anonymous, which holds while the
# repository is public (ADR-0055 stage 9 makes it private: then the clone needs a credential, ADR-0056).
# Needs limactl (Lima 2.x, `brew install lima`) on the Mac; the image is downloaded by Lima and checked against the
# digest in factory-build.yaml.
# ============================================================
set -euo pipefail

NAME=factory-build
# This product's repository, named here: the factory is to build other products too (ADR-0055), so in stage 4, when
# these scripts move to the `factory` repository, the URL becomes the product adapter's setting.
REPO_URL=https://github.com/profitbuild/incident-platform.git
CLONE=/home/factory/incident-platform
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../.." && pwd)

fail() { echo "create.sh: $*" >&2; exit 1; }
command -v limactl >/dev/null || fail "limactl not found (brew install lima)"

# The list into a variable first: `limactl list | grep -q` under pipefail can fail when grep exits before limactl
# has written everything (SIGPIPE), and a failure here would read as "no such instance" (review round 1).
instances=$(limactl list --quiet)
if grep -qx "$NAME" <<<"$instances"; then
  fail "instance $NAME exists; run delete.sh first (this script only creates from nothing)"
fi

# provision.sh cannot read .node-version (a cloud VM runs it before any clone), so its copy is checked here.
node_pin=$(sed -n 's/^NODE_VERSION=//p' "$here/provision.sh")
[ "$node_pin" = "$(tr -d '[:space:]' < "$root/.node-version")" ] \
  || fail "provision.sh pins Node $node_pin, .node-version says $(cat "$root/.node-version"): change both (and verify-pins.sh)"

# The VM's copy of the devcontainer's allow-list equal to it both ways (check-allowlists.sh, which Factory guards runs too).
"$here/check-allowlists.sh" "$root" || fail "the allow-lists do not fit: see above"

# The provision file's path is the Mac's, read by limactl at create time, so it is written into a copy of the template
# (a `--set` applies too late: "locator is empty"). A path holding a character special to sed or YAML is refused
# rather than escaped; the repository's own path holds none.
case "$here" in *[\"\\\|\&]*) fail "unsupported path: $here" ;; esac
template=$(mktemp -d)/factory-build.yaml
created=false ready=false
cleanup() {
  local rc=$?
  rm -rf "${template%/*}"
  if $created && ! $ready; then
    echo "create.sh: the VM is not ready (exit $rc); deleting $NAME" >&2
    limactl delete --force "$NAME" >&2 || echo "create.sh: could not delete $NAME: run delete.sh" >&2
  fi
  exit "$rc"
}
trap cleanup EXIT
sed "s|@PROVISION_SH@|$here/provision.sh|" "$here/factory-build.yaml" > "$template"
if grep -q '@PROVISION_SH@' "$template"; then fail "the template's placeholder was not filled"; fi
created=true
limactl create --tty=false --name="$NAME" "$template"
limactl start --tty=false "$NAME"

# The EXIT trap deletes the VM: every failure below leaves `ready` false.
isolation_fail() { echo "create.sh: $*" >&2; exit 1; }
# Each check fails closed: a command that cannot answer deletes the VM like a check that finds something (review
# round 2 of #0-238: a failed `limactl list` or `limactl shell` used to stop the script and leave the VM running).
mounts=$(limactl list "$NAME" --format '{{json .Config.Mounts}}') || isolation_fail "cannot read the VM's mounts"
[ "$mounts" = "[]" ] || [ "$mounts" = "null" ] \
  || isolation_fail "Lima mounts host directories into the VM ($mounts): check ~/.lima/_config/default.yaml and override.yaml"
agent=$(limactl list "$NAME" --format '{{.Config.SSH.ForwardAgent}}') || isolation_fail "cannot read the VM's agent forwarding"
[ "$agent" = "false" ] || isolation_fail "Lima forwards the SSH agent (forwardAgent=$agent)"
# Every port rule must be an `ignore` one: a rule merged in ahead of the template's (override.yaml) would forward.
forwarding=$(limactl list "$NAME" --format '{{range .Config.PortForwards}}{{if not .Ignore}}{{.GuestPortRange}} {{end}}{{end}}') \
  || isolation_fail "cannot read the VM's port forwards"
[ -z "$forwarding" ] || isolation_fail "Lima forwards VM ports to the Mac (guest ports $forwarding): check ~/.lima/_config/override.yaml"
# The other keys ~/.lima/_config/ could merge in that widen what the VM reaches or receives (review round 3):
# a network (vzNAT, bridged: the VM on the LAN), X11 forwarding, the Mac's proxy variables.
extra=$(limactl list "$NAME" --format 'networks={{json .Config.Networks}} x11={{.Config.SSH.ForwardX11}} proxy={{.Config.PropagateProxyEnv}}') \
  || isolation_fail "cannot read the VM's networks and forwarding"
case "$extra" in
  "networks=[] x11=false proxy=false" | "networks=null x11=false proxy=false") ;;
  *) isolation_fail "Lima adds a network, X11 forwarding or proxy variables ($extra): check ~/.lima/_config/" ;;
esac
# And what could copy files out of the VM onto the Mac (copyToHost), attach a disk, or run another script or probe
# than provision.sh (review round 4).
more=$(limactl list "$NAME" --format 'copy={{len .Config.CopyToHost}} disks={{len .Config.AdditionalDisks}} provision={{len .Config.Provision}} probes={{len .Config.Probes}}') \
  || isolation_fail "cannot read the VM's copies, disks, provisions and probes"
[ "$more" = "copy=0 disks=0 provision=1 probes=0" ] \
  || isolation_fail "Lima adds a copy to the Mac, a disk, a provision or a probe ($more): check ~/.lima/_config/"
# findmnt exits 1 when it finds nothing; any other status (the shell failed) is no answer.
rc=0
host_fs=$(limactl shell "$NAME" findmnt -rn -o TARGET,FSTYPE -t virtiofs,9p,fuse.sshfs,sshfs) || rc=$?
case $rc in
  0) isolation_fail "the guest has host file systems mounted: $host_fs" ;;
  1) ;;
  *) isolation_fail "cannot list the guest's file systems (exit $rc)" ;;
esac
# shellcheck disable=SC2016 # expanded in the guest, not here
sock=$(limactl shell "$NAME" sh -c 'echo "${SSH_AUTH_SOCK:-}"') || isolation_fail "cannot read the guest's environment"
[ -z "$sock" ] || isolation_fail "the guest has an SSH agent socket ($sock)"

# Lima reports the VM started once its provisions ran; check that this one did, rather than trusting the order.
limactl shell "$NAME" cat /etc/factory-build-provisioned

# The boundary of ADR-0057, each check failing closed as the ones above.
boundary_fail() { echo "create.sh: the build VM's boundary does not hold: $*" >&2; exit 1; }
vm() { limactl shell "$NAME" "$@"; }
# check_boundary <when>: everything the boundary rests on, as the VM is now.
check_boundary() {
  uid=$(vm id -u factory) || boundary_fail "no user factory"
  [ "$uid" -ge 1000 ] || boundary_fail "factory's uid $uid is below 1000, outside the filtered range"
  # Commands as factory without its login shell (`sudo -iu` would run ~/.profile, which code a test can rewrite on a VM
  # agents have used, and make a check pass falsely: review round 4 of #0-116); curl -q skips ~/.curlrc, and DOCKER_HOST
  # names factory's daemon over any context in ~/.docker.
  as_factory=(sudo -u factory -H env "DOCKER_HOST=unix:///run/user/$uid/docker.sock")
  [ "$(vm systemctl is-enabled docker.service 2>/dev/null || true)" = masked ] || boundary_fail "the rootful docker.service is not masked"
  # Each read answers first, then is judged: a `limactl shell` or `sudo` that fails is no pass (review round 1 of #0-116).
  groups=$(vm id -nG factory) || boundary_fail "cannot read factory's groups"
  if [[ " $groups " == *" docker "* ]]; then boundary_fail "factory is in the docker group"; fi
  [ "$(vm sysctl -n net.ipv4.ip_forward)" = 0 ] || boundary_fail "the VM forwards IPv4: packets it forwards carry no owner the chain can match"
  # Nothing of the rootful daemon that ran once at install: its chains and docker0 (review round 3 of #0-116).
  leftovers=$(vm sh -c 'sudo iptables-save | grep -c -e DOCKER -e docker0; ip -o link show docker0 2>/dev/null | wc -l') \
    || boundary_fail "cannot read the VM's iptables and links"
  [ "$(tr -d ' \n' <<<"$leftovers")" = 00 ] || boundary_fail "the rootful Docker daemon left chains or docker0 behind ($leftovers)"
  # The loopback rule lets factory reach the VM's own address on the ephemeral ports, meant for Docker's published
  # ports: no other process may listen there (review round 3 of #0-116). Listeners on loopback addresses are outside
  # that rule; any other one in the range must be factory's.
  range=$(vm cat /proc/sys/net/ipv4/ip_local_port_range) || boundary_fail "cannot read the ephemeral port range"
  listeners=$(vm sudo ss -H -ltne) || boundary_fail "cannot list the VM's listeners"
  strangers=$(awk -v lo="${range%%[[:space:]]*}" -v hi="${range##*[[:space:]]}" -v u="uid:$uid" '
    { addr = $4; port = addr; sub(/.*:/, "", port); sub(/:[0-9]+$/, "", addr)
      if (addr ~ /^(127\.|\[::1\]|\[::ffff:127\.)/) next
      if (port + 0 < lo + 0 || port + 0 > hi + 0) next
      mine = 0; for (i = 5; i <= NF; i++) if ($i == u) mine = 1
      if (!mine) print $4 }' <<<"$listeners")
  [ -z "$strangers" ] || boundary_fail "a process other than factory listens on the ephemeral ports factory may reach: $strangers"
  sec=$(vm "${as_factory[@]}" docker info --format '{{.SecurityOptions}}') || boundary_fail "factory's Docker does not answer"
  [[ $sec == *name=rootless* ]] || boundary_fail "factory's Docker is not rootless ($sec)"
  gw=$(vm sh -c "ip -4 route show default | awk '{print \$3; exit}'") || boundary_fail "cannot read the VM's gateway"
  vm sudo iptables -C OUTPUT -m owner --uid-owner 1000-4294967294 -j FACTORY-EGRESS 2>/dev/null \
    || boundary_fail "the traffic of uids from 1000 up does not go through FACTORY-EGRESS"
  vm sudo ip6tables -C OUTPUT -m owner --uid-owner 1000-4294967294 -j REJECT 2>/dev/null \
    || boundary_fail "IPv6 is not rejected for uids from 1000 up"
  vm sudo iptables -C FACTORY-EGRESS -d "$gw" -j REJECT 2>/dev/null || boundary_fail "the gateway $gw is not rejected for factory"
  # Blocked means refused: the chain's REJECT answers at once, curl's exit 7. A timeout, a DNS failure or a failed shell
  # is no answer about the filter.
  # refused <what> <command…>: the command, run in the VM, must end in curl's exit 7.
  refused() {
    local what=$1 rc=0; shift
    vm "$@" || rc=$?
    case $rc in
      7) ;;
      0) boundary_fail "$what is reached" ;;
      *) boundary_fail "cannot tell whether $what is reached (curl or shell exit $rc)" ;;
    esac
  }
  refused "example.com, outside the allow-list, by factory" \
    "${as_factory[@]}" curl -q -s -m 10 -o /dev/null https://example.com
  # As a subordinate uid of factory's in the VM's own network namespace: reached example.com when only factory's own
  # uid was filtered (review round 2 of #0-116).
  refused "example.com by a subordinate uid of factory's" \
    "${as_factory[@]}" rootlesskit --net=host -- setpriv --reuid=1 --regid=1 --clear-groups curl -q -s -m 10 -o /dev/null https://example.com
  vm_ip=$(vm sh -c "ip -4 -o addr show \$(ip -4 route show default | awk '{print \$5; exit}') | awk '{print \$4; exit}' | cut -d/ -f1") \
    || boundary_fail "cannot read the VM's address"
  refused "the VM's sshd ($vm_ip:22) by factory" \
    "${as_factory[@]}" curl -q -s -m 10 -o /dev/null "http://$vm_ip:22/"
  vm "${as_factory[@]}" curl -q -s -m 10 -o /dev/null https://api.github.com/zen || boundary_fail "factory cannot reach api.github.com: the allow-list is not loaded"
  # The resolver (backlog #0-247): every DNS query of a filtered uid goes to it, and it adds what it answers for a
  # listed name to factory-dns. Checked where a test meets it, from a container: a static set failed the first
  # autopilot run's image pulls, which a check from the VM's own shell, right after the set was loaded, did not show.
  [ "$(vm systemctl is-active factory-dns.service 2>/dev/null || true)" = active ] || boundary_fail "factory's resolver (factory-dns.service) is not active"
  vm sudo iptables -t nat -C OUTPUT -m owner --uid-owner 1000-4294967294 -j FACTORY-DNS 2>/dev/null \
    || boundary_fail "the DNS of uids from 1000 up is not sent to the resolver (nat OUTPUT -> FACTORY-DNS)"
  vm sudo iptables -C FACTORY-EGRESS -m set --match-set factory-dns dst -j ACCEPT 2>/dev/null \
    || boundary_fail "FACTORY-EGRESS does not take the resolver's set factory-dns"
  # Every check pulls its image again: the pull is what goes through the registry and its CDN, which a cached image
  # never shows (backlog #0-247).
  vm "${as_factory[@]}" docker rmi -f alpine >/dev/null 2>&1 || true
  # shellcheck disable=SC2016 # the awk program runs in the container's shell, not here
  answered=$(vm "${as_factory[@]}" docker run --rm alpine sh -c 'nslookup -type=a registry-1.docker.io 2>/dev/null | awk "/^Address: /{print \$2}"' | grep -E '^[0-9.]+$' | head -1) \
    || boundary_fail "a container cannot resolve registry-1.docker.io through the resolver"
  vm sudo ipset test factory-dns "$answered" 2>/dev/null || boundary_fail "the resolver's answer $answered for registry-1.docker.io is not in factory-dns"
  # Outside the list: resolved (the resolver answers every name), never reached. slirp4netns does not pass the REJECT
  # back to the container, so the attempt ends by its own timeout, not curl's exit 7.
  if vm "${as_factory[@]}" docker run --rm alpine wget -q -T 8 -O /dev/null https://example.com 2>/dev/null; then
    boundary_fail "a container reaches example.com, outside the allow-list"
  fi
  # ... and its address does not enter the resolver's set; a query to an outside server (8.8.8.8) is answered by the
  # resolver all the same (its answer lands in the set); the resolver answers no one outside the VM, never runs as
  # root, and the private networks are rejected before either set (review round 1 of #0-247).
  # shellcheck disable=SC2016 # the awk programs run in the container's shell, not here
  outside=$(vm "${as_factory[@]}" docker run --rm alpine sh -c 'nslookup -type=a example.com 2>/dev/null | awk "/^Address: /{print \$2}"' | grep -E '^[0-9.]+$' | head -1) \
    || boundary_fail "a container cannot resolve example.com through the resolver (it answers every name)"
  if vm sudo ipset test factory-dns "$outside" 2>/dev/null; then boundary_fail "example.com's address $outside is in factory-dns"; fi
  # shellcheck disable=SC2016 # as above
  via=$(vm "${as_factory[@]}" docker run --rm alpine sh -c 'nslookup -type=a registry-1.docker.io 8.8.8.8 2>/dev/null | awk "/^Address: /{print \$2}"' | grep -E '^[0-9.]+$' | head -1) \
    || boundary_fail "a container's query to 8.8.8.8 is not answered: it is not sent to the resolver"
  vm sudo ipset test factory-dns "$via" 2>/dev/null || boundary_fail "the answer $via to a query to 8.8.8.8 is not in factory-dns: it did not come from the resolver"
  for p in udp tcp; do
    vm sudo iptables -C INPUT ! -i lo -p "$p" --dport 5300 -j DROP 2>/dev/null || boundary_fail "the resolver answers $p queries from outside the VM"
  done
  # shellcheck disable=SC2016 # expanded in the VM's shell, not here
  [ "$(vm sh -c 'ps -o user= -p "$(systemctl show -p MainPID --value factory-dns.service)"' | tr -d ' ')" = dnsmasq ] \
    || boundary_fail "the resolver does not run as the user dnsmasq"
  for n in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 172.16.0.0/12 192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4; do
    vm sudo iptables -C FACTORY-EGRESS -d "$n" -j REJECT 2>/dev/null || boundary_fail "the network $n is not rejected for factory"
  done
  # And the resolver's own refusals, read from the configuration it runs with (review round 2 of #0-247).
  conf=$(vm cat /run/factory-dns/dnsmasq.conf) || boundary_fail "cannot read the resolver's configuration"
  grep -qx stop-dns-rebind <<<"$conf" || boundary_fail "the resolver does not refuse private answers (stop-dns-rebind)"
  grep -qx 'max-cache-ttl=300' <<<"$conf" || boundary_fail "the resolver caches answers longer than 300 s (max-cache-ttl)"
  # The devcontainer's docker-outside-of-docker feature mounts /var/run/docker.sock: the rootless daemon must see it,
  # in its own mount namespace, which it builds when it starts (a link made later is missing to it).
  vm "${as_factory[@]}" docker run --rm -v /var/run/docker.sock:/s alpine test -S /s \
    || boundary_fail "factory's Docker cannot mount /var/run/docker.sock"
  echo "factory-build: boundary holds $1 (rootless Docker for factory, egress filtered, gateway $gw rejected)"
}
check_boundary "after creation"
# Once more after a reboot: provision.sh runs again, late in the boot, after factory's session and its daemon have
# started; what holds only on a fresh VM fails here (the socket link did, in review round 1 of #0-116).
limactl stop "$NAME" >/dev/null
limactl start --tty=false "$NAME" >/dev/null
marker=$(vm cat /etc/factory-build-provisioned) || boundary_fail "no provisioning marker after a reboot"
boot=$(vm cat /proc/sys/kernel/random/boot_id) || boundary_fail "cannot read the VM's boot id"
[[ $marker == *"boot $boot"* ]] || boundary_fail "provision.sh did not finish in the boot after the reboot"
check_boundary "after a reboot"

limactl shell "$NAME" sudo -u factory -H git clone --quiet "$REPO_URL" "$CLONE"
cloned=$(limactl shell "$NAME" sudo -u factory -H git -C "$CLONE" rev-parse HEAD)
echo "factory-build: cloned $cloned"
# The devcontainer's dev (uid and gid 1000, .devcontainer/Dockerfile) is start + 999 of factory's subordinate ranges,
# /etc/subuid for the uid and /etc/subgid for the gid.
dev_uid=$(vm sh -c "awk -F: '\$1==\"factory\" {print \$2 + 999}' /etc/subuid") || boundary_fail "cannot read factory's subordinate uids"
dev_gid=$(vm sh -c "awk -F: '\$1==\"factory\" {print \$2 + 999}' /etc/subgid") || boundary_fail "cannot read factory's subordinate gids"
[[ $dev_uid =~ ^[0-9]+$ && $dev_gid =~ ^[0-9]+$ ]] || boundary_fail "no subordinate range for factory"
# -h: a symbolic link in the clone is changed itself, never its target (the default of -R, said outright).
vm sudo chown -R -h "$dev_uid:$dev_gid" "$CLONE"
ready=true
# The VM's contents come from this checkout's provision.sh, its code from the default branch of REPO_URL: the two match
# only when this runs from an up-to-date main (review round 4). Not a failure: the VM is fine, the owner decides.
local_head=$(git -C "$root" rev-parse HEAD)
if [ -n "$(git -C "$root" status --porcelain -- scripts/factory-admin/build-vm .node-version)" ]; then
  echo "create.sh: WARNING: provisioned from uncommitted build-vm files of this checkout, cloned $cloned:" \
       "recreate from an up-to-date main once they are merged" >&2
elif [ "$local_head" != "$cloned" ]; then
  echo "create.sh: WARNING: provisioned from this checkout at $local_head, cloned $cloned:" \
       "recreate from an up-to-date main if provision.sh differs between them" >&2
fi
echo "factory-build: ready; next, the manual steps in docs/ai-factory.md \"Build VM\""
