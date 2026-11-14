#!/bin/bash
# ============================================================
# The build VM's contents (backlog #0-238, ADR-0056; #0-116 and #0-240, ADR-0057): what the VM holds beyond Ubuntu's
# cloud image, in one file.
#
# One script, two readers, nothing in it that knows which one runs it (criterion S2):
#   - Lima runs it as a `mode: system` provision (factory-build.yaml), as root, on every boot;
#   - a cloud VM (stage C of ADR-0055) takes the same file as its cloud-init user-data: a user-data that starts with
#     `#!` is run as a script, once, as root.
# So it is idempotent (Lima's every-boot run must change nothing the second time), every step guarded by what it
# installs, and uses nothing of either tool: no Lima variable, no cloud metadata, no file of the repository (a cloud
# VM runs it before any clone exists, so the pins are here, not read from elsewhere).
#
# The boundary (ADR-0057). Code an agent runs (a test) reaches Docker, and Docker is root over whatever its daemon
# runs as. So the daemon is rootless: it runs as the user `factory`, and root in any container is `factory` in the VM,
# which cannot change the VM's firewall, read root's files or write the VM's /etc. Everything `factory` sends - its
# daemon, slirp4netns and so every container, the devcontainer included - goes through one chain of root's,
# FACTORY-EGRESS (factory-egress.sh below): DNS, an allow-list, nothing on the VM's own network or the gateway (the
# Mac's loopback services through Lima's host.lima.internal, #0-240; a cloud VM's metadata at 169.254.169.254), and
# nothing else. The chain is in place before `factory`'s session starts, and rejects everything until its allow-list
# is loaded: it fails closed. Not covered: what `factory` itself holds, the devcontainer's volumes with the bot's
# token and Claude Code's login (stage 4 of ADR-0055, a task container without a token); and DNS as a channel.
#
# Where each comes from, and what checks it:
#   - Ubuntu's packages: its archive, signed, checked by apt.
#   - Docker CE and its rootless extras: Docker's apt repository, signed by the key pinned below by fingerprint
#     (DOCKER_KEY_FPR), refused if the key served has another; Ubuntu's docker.io ships no rootless scripts.
#   - Node: nodejs.org's tarball, checked against the sha256 pinned below. Not Ubuntu's `nodejs`: noble ships 18,
#     and the devcontainer CLI needs 20 or later (its `engines`; npm only warns). The version is .node-version's,
#     the one CI runs (ADR-0043); create.sh refuses a mismatch.
#   - The devcontainer CLI: npm's tarball, checked against the sha512 pinned below (npm's `dist.integrity` of that
#     version, in hex) and installed from the file, so npm fetches nothing: the package has no dependencies.
# The pins are checked against their publishers by verify-pins.sh, run with every change of a pin. A change here takes
# effect on a new VM: delete.sh, then create.sh.
# ============================================================
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

APT_PACKAGES=(git ca-certificates curl xz-utils gnupg uidmap dbus-user-session slirp4netns iptables ipset jq)
# Docker CE by exact version, as Node and the CLI are pinned: VMs made on different days hold the same Docker (review
# round 3 of #0-116). The versions are the ones of Docker's noble repository for arm64 and amd64, which
# verify-pins.sh checks; apt checks each package against the repository's signed index.
DOCKER_VERSION=5:29.9.3-1~ubuntu.24.04~noble
CONTAINERD_VERSION=2.4.2-4~ubuntu.24.04~noble
DOCKER_PACKAGES=(docker-ce="$DOCKER_VERSION" docker-ce-cli="$DOCKER_VERSION" docker-ce-rootless-extras="$DOCKER_VERSION"
  containerd.io="$CONTAINERD_VERSION")
# Docker's release key for its deb repositories; confirmed 2026-11-14 on download.docker.com (the key it serves),
# keyserver.ubuntu.com and Docker's install documentation (ADR-0033's three places).
DOCKER_KEY_FPR=9DC858229FC7DD38854AE2D88D81803C0EBFCD88  # gitleaks:allow: a public key fingerprint (Docker's apt key), no secret
NODE_VERSION=24.22.1
NODE_SHA256_ARM64=dbabf7a1cbf947e6059ffad2c27b80041db97dea1e553b62afdee7f13fca336e
NODE_SHA256_X64=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6
DEVCONTAINER_CLI_VERSION=0.89.0
DEVCONTAINER_CLI_SHA512=2f36a8386290fd9aa5e8fb226788552185596a0cd6903eb9686ff5a2ee7f2a5cb96353ed8cb835ca7eeabbe2d90b3568025e83659fe96f3f2a38ee112cd96a32
FACTORY_USER=factory

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Every package checked, not one stand-in for all: a package added to the list reaches a VM that already has the rest.
if ! dpkg -s "${APT_PACKAGES[@]}" >/dev/null 2>&1; then
  apt-get update
  apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
fi

# --- The user, and the egress chain, before anything of `factory` runs ------------------------------------------
if ! id -u "$FACTORY_USER" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "$FACTORY_USER"
fi
factory_uid=$(id -u "$FACTORY_USER")
# Rootless Docker maps a container's users onto factory's subordinate range; useradd gives one, check it is there.
if ! grep -q "^$FACTORY_USER:" /etc/subuid || ! grep -q "^$FACTORY_USER:" /etc/subgid; then
  echo "provision.sh: no subordinate uid/gid range for $FACTORY_USER" >&2; exit 1
fi
# Every subordinate range of factory's must lie above every account's uid and inside what the egress chain below
# filters (uids 1000 to 4294967294): a subordinate uid under 1000 would send unfiltered (review round 4 of #0-116), and
# one at or under UID_MAX could be a real account's - a cloud image's `ubuntu` is uid 1000 - whose files a container
# would then own (review round 5). useradd starts them at SUB_UID_MIN, 100000 by default, above UID_MAX (60000).
uid_max=$(awk '$1 == "UID_MAX" { print $2 }' /etc/login.defs)
uid_max=${uid_max:-60000}
bad=$(awk -F: -v u="$FACTORY_USER" -v max="$uid_max" '
  $1 == u && ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $2 + 0 <= max + 0 || $2 + $3 - 1 > 4294967294) { print FILENAME ": " $0 }
' /etc/subuid /etc/subgid)
if [ -n "$bad" ]; then
  echo "provision.sh: a subordinate range of $FACTORY_USER is not above UID_MAX ($uid_max) and inside the filtered uids: $bad" >&2
  exit 1
fi
# No group gives `factory` a root daemon: the docker group of a rootful install, if one was ever there, is left.
gpasswd -d "$FACTORY_USER" docker >/dev/null 2>&1 || true

# The VM forwards nothing: a forwarded packet carries no socket owner, so the egress chain below, matched on uids, would
# not see it. Ubuntu's default, set here so the boundary does not rest on a default (review round 3 of #0-116).
printf 'net.ipv4.ip_forward = 0\nnet.ipv6.conf.all.forwarding = 0\n' > /etc/sysctl.d/90-factory-build.conf
sysctl -q -p /etc/sysctl.d/90-factory-build.conf

install -m 0755 /dev/stdin /usr/local/sbin/factory-egress.sh <<'EGRESS'
#!/bin/bash
# The build VM's egress filter (backlog #0-116, #0-240, ADR-0057), written by provision.sh.
#   factory-egress.sh          (boot, factory-egress.service) the chain, rejecting all, then the allow-list
#   factory-egress.sh refresh  (factory-egress.timer) the allow-list only, resolved again: CDNs change addresses
# The chain is root's and takes every socket of a uid from 1000 up: `factory`, whose rootless Docker's packets all
# carry its uid (slirp4netns runs as factory), and every uid factory could become, its subordinate range among them
# (100000 up: `rootlesskit -- setpriv --reuid=1 curl` reached example.com when only factory's own uid was matched,
# review round 2 of #0-116), and any user added later. System accounts (below 1000: root, systemd-resolve, _apt, and
# Lima's user, who takes the Mac's uid) are not filtered; factory can become none of them. It fails closed: built
# before its allow-list, swapped in whole, never flushed in place.
set -euo pipefail
FILTERED=1000-4294967294
# The devcontainer's own allow-list, copied: .devcontainer/init-firewall.sh's ALLOWED_DOMAINS and OPTIONAL_DOMAINS,
# entry for entry (check-allowlists.sh holds the copies equal both ways, in create.sh and Factory guards). Both
# scripts resolve each name to its IPv4 addresses, with different tools (dig there, getent here), and this one again
# every 30 minutes.
DOMAINS=(
  api.anthropic.com claude.ai platform.claude.com console.anthropic.com
  repo.maven.apache.org repo1.maven.org
  api.osv.dev osv.dev tomcat.apache.org spring.io
)
OPTIONAL_DOMAINS=(statsig.anthropic.com)
# What only the VM needs, as its rootless Docker builds the devcontainer's image and pulls images: none of these may
# be in the devcontainer's list (check-allowlists.sh).
VM_ONLY_DOMAINS=(
  registry-1.docker.io auth.docker.io production.cloudflare.docker.com production.cloudfront.docker.com  # Docker Hub
  download.docker.com  # the docker-outside-of-docker feature's Docker CLI
  ghcr.io pkg-containers.githubusercontent.com  # the devcontainer's features
  ports.ubuntu.com archive.ubuntu.com security.ubuntu.com cli.github.com  # the image build's apt
  downloads.claude.ai  # the image build's Claude Code install
)

load_allowed() {
  ipset create factory-allowed hash:net -exist
  ipset create factory-allowed-new hash:net -exist
  ipset flush factory-allowed-new
  local meta cidr d ip
  meta=$(curl -fsS --max-time 15 https://api.github.com/meta)
  # The same keys as init-firewall.sh's (web, api, git): ghcr.io and its content host are VM_ONLY_DOMAINS by name.
  for cidr in $(jq -r '(.web + .api + .git)[] | select(test(":") | not)' <<<"$meta"); do
    ipset add factory-allowed-new "$cidr" -exist
  done
  for d in "${DOMAINS[@]}" "${VM_ONLY_DOMAINS[@]}"; do
    ip=$(getent ahostsv4 "$d" | awk '{print $1}' | sort -u)
    [ -n "$ip" ] || { echo "factory-egress: $d does not resolve" >&2; exit 1; }
    for i in $ip; do ipset add factory-allowed-new "$i" -exist; done
  done
  for d in "${OPTIONAL_DOMAINS[@]}"; do
    for i in $(getent ahostsv4 "$d" | awk '{print $1}' | sort -u); do ipset add factory-allowed-new "$i" -exist; done
  done
  ipset swap factory-allowed-new factory-allowed
  ipset destroy factory-allowed-new
  echo "factory-egress: $(ipset list factory-allowed | grep -c '^[0-9]') allowed networks"
}

if [ "${1:-}" = refresh ]; then load_allowed; exit 0; fi

ipset create factory-allowed hash:net -exist
gw=$(ip -4 route show default | awk '{print $3; exit}')
dev=$(ip -4 route show default | awk '{print $5; exit}')
net=$(ip -4 -o addr show "$dev" | awk '{print $4; exit}')
vm_ip=${net%/*}
dns=$(awk '/^nameserver/ {print $2}' /run/systemd/resolve/resolv.conf 2>/dev/null | grep -E '^[0-9.]+$' || true)
read -r eph_lo eph_hi < /proc/sys/net/ipv4/ip_local_port_range
iptables -N FACTORY-EGRESS-NEW 2>/dev/null || iptables -F FACTORY-EGRESS-NEW
# Loopback: the local resolver, and the VM's own address on the ports Docker publishes a container's on (the kernel's
# ephemeral range: Testcontainers' mapped ports, through host.docker.internal). Nothing else of the VM's own listeners,
# sshd among them, nor one a later change adds (review round 2 of #0-116).
iptables -A FACTORY-EGRESS-NEW -o lo -d 127.0.0.0/8 -p udp --dport 53 -j ACCEPT
iptables -A FACTORY-EGRESS-NEW -o lo -d 127.0.0.0/8 -p tcp --dport 53 -j ACCEPT
[ -z "$vm_ip" ] || iptables -A FACTORY-EGRESS-NEW -o lo -d "$vm_ip" -p tcp --dport "$eph_lo:$eph_hi" -j ACCEPT
iptables -A FACTORY-EGRESS-NEW -o lo -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FACTORY-EGRESS-NEW -o lo -j REJECT
# DNS to the resolvers systemd-resolved uses, and only them: under Lima that is the gateway, in a cloud the provider's
# resolver; a gateway that is no resolver stays rejected below (review round 3 of #0-116). None found: no DNS.
for r in $(printf '%s\n' $dns | sort -u); do
  iptables -A FACTORY-EGRESS-NEW -d "$r" -p udp --dport 53 -j ACCEPT
  iptables -A FACTORY-EGRESS-NEW -d "$r" -p tcp --dport 53 -j ACCEPT
done
# The gateway and the VM's network: under Lima the Mac (its loopback services, #0-240), in a cloud the provider's
# network; and link-local, a cloud VM's metadata service.
[ -z "$gw" ] || iptables -A FACTORY-EGRESS-NEW -d "$gw" -j REJECT
[ -z "$net" ] || iptables -A FACTORY-EGRESS-NEW -d "$net" -j REJECT
iptables -A FACTORY-EGRESS-NEW -d 169.254.0.0/16 -j REJECT
iptables -A FACTORY-EGRESS-NEW -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FACTORY-EGRESS-NEW -m set --match-set factory-allowed dst -j ACCEPT
iptables -A FACTORY-EGRESS-NEW -j REJECT
# Swap in whole: the new chain takes the traffic before the old one goes.
iptables -I OUTPUT 1 -m owner --uid-owner "$FILTERED" -j FACTORY-EGRESS-NEW
while iptables -D OUTPUT -m owner --uid-owner "$FILTERED" -j FACTORY-EGRESS 2>/dev/null; do :; done
if iptables -L FACTORY-EGRESS -n >/dev/null 2>&1; then iptables -F FACTORY-EGRESS; iptables -X FACTORY-EGRESS; fi
iptables -E FACTORY-EGRESS-NEW FACTORY-EGRESS
# IPv6 not at all, loopback included: ::1 reaches the listeners on [::] (sshd) that the IPv4 rules above keep out.
ip6tables -C OUTPUT -m owner --uid-owner "$FILTERED" -j REJECT 2>/dev/null \
  || ip6tables -I OUTPUT 1 -m owner --uid-owner "$FILTERED" -j REJECT
load_allowed
EGRESS

cat > /etc/systemd/system/factory-egress.service <<UNIT
[Unit]
Description=Egress filter of the user $FACTORY_USER (backlog #0-116, #0-240)
Wants=network-online.target
After=network-online.target
Before=user@$factory_uid.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/factory-egress.sh
[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/factory-egress-refresh.service <<UNIT
[Unit]
Description=Resolve the allow-list of $FACTORY_USER's egress again
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/factory-egress.sh refresh
UNIT
# The timer names its service: without Unit= a timer starts the service of its own name, factory-egress.service, a
# oneshot already active, so nothing ran (review round 1 of #0-116, seen with systemctl show factory-egress.timer).
cat > /etc/systemd/system/factory-egress.timer <<UNIT
[Unit]
Description=Resolve the allow-list of $FACTORY_USER's egress every 30 minutes
[Timer]
Unit=factory-egress-refresh.service
OnBootSec=30min
OnUnitActiveSec=30min
[Install]
WantedBy=timers.target
UNIT
# factory's session (its lingering rootless Docker) requires the filter, not only follows it: if factory-egress.sh fails
# before its OUTPUT rule is in, the session does not start, rather than start unfiltered (fail closed at boot, review
# round 1 of #0-116).
install -d "/etc/systemd/system/user@$factory_uid.service.d"
cat > "/etc/systemd/system/user@$factory_uid.service.d/factory-egress.conf" <<UNIT
[Unit]
Requires=factory-egress.service
After=factory-egress.service
UNIT
systemctl daemon-reload
systemctl enable factory-egress.service factory-egress.timer
systemctl start factory-egress.service factory-egress.timer

# --- Docker CE, rootless for `factory`, no rootful daemon --------------------------------------------------------
docker_installed() {  # every package of DOCKER_PACKAGES at its pinned version
  local p
  for p in "${DOCKER_PACKAGES[@]}"; do
    [ "$(dpkg-query -W -f '${Version}' "${p%%=*}" 2>/dev/null)" = "${p#*=}" ] || return 1
  done
}
if ! docker_installed; then
  curl -fsSL -o "$work/docker.asc" https://download.docker.com/linux/ubuntu/gpg
  # Exactly one primary key, the pinned one: the whole file becomes the repository's signed-by keyring, so a second
  # key appended to it would be trusted too (review round 1 of #0-116).
  keys=$(gpg --show-keys --with-colons "$work/docker.asc" 2>/dev/null | grep -c '^pub:' || true)
  fpr=$(gpg --show-keys --with-colons "$work/docker.asc" 2>/dev/null | awk -F: '/^fpr/ {print $10; exit}')
  [ "$keys" = 1 ] && [ "$fpr" = "$DOCKER_KEY_FPR" ] \
    || { echo "provision.sh: Docker's apt key file holds $keys key(s), first $fpr, not only $DOCKER_KEY_FPR" >&2; exit 1; }
  install -m 0755 -d /etc/apt/keyrings
  install -m 0644 "$work/docker.asc" /etc/apt/keyrings/docker.asc
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get remove -y docker.io >/dev/null 2>&1 || true
  apt-get update
  apt-get install -y --no-install-recommends --allow-downgrades "${DOCKER_PACKAGES[@]}"
fi
systemctl mask --now docker.service docker.socket containerd.service
# Again after it: installing Docker CE starts its rootful daemon once, before the mask, and that daemon turns IPv4
# forwarding on (found by create.sh's check on a fresh VM, review round 3 of #0-116).
sysctl -q -p /etc/sysctl.d/90-factory-build.conf
# And what else that daemon left until the next boot: its iptables chains and rules (DOCKER*, docker0's) and the
# docker0 bridge, none of which the rootless daemon uses. Each table restored without them, whole, so the egress chain
# is never without its rules.
for table in filter nat; do
  if iptables-save -t "$table" | grep -q -e DOCKER -e docker0; then
    iptables-save -t "$table" | grep -v -e DOCKER -e docker0 | iptables-restore -T "$table"
  fi
done
if ip link show docker0 >/dev/null 2>&1; then ip link delete docker0; fi

# Ubuntu 24.04 confines unprivileged user namespaces; rootlesskit needs one.
cat > /etc/apparmor.d/usr.bin.rootlesskit <<'PROFILE'
abi <abi/4.0>,
include <tunables/global>
/usr/bin/rootlesskit flags=(unconfined) {
  userns,
  include if exists <local/usr.bin.rootlesskit>
}
PROFILE
apparmor_parser -r /etc/apparmor.d/usr.bin.rootlesskit

# The default socket path is the rootless daemon's, so `docker` and the devcontainer CLI need no DOCKER_HOST, and the
# devcontainer's docker-outside-of-docker feature mounts it unchanged. Made by systemd-tmpfiles early at every boot,
# before factory's session: the rootless daemon sees /run as it was when it started, and a link made later (by this
# script, which Lima runs late in the boot) was missing to it after a reboot, so the feature's mount failed.
# Root's own `docker`, if anything ran one, would reach factory's daemon through it: an untrusted one, as code a test
# runs controls it; nothing in this VM runs `docker` as root.
echo "L+ /run/docker.sock - - - - /run/user/$factory_uid/docker.sock" > /etc/tmpfiles.d/factory-docker-sock.conf
systemd-tmpfiles --create /etc/tmpfiles.d/factory-docker-sock.conf

loginctl enable-linger "$FACTORY_USER"
rundir=/run/user/$factory_uid
for _ in $(seq 60); do [ -S "$rundir/bus" ] && break; sleep 1; done
[ -S "$rundir/bus" ] || { echo "provision.sh: no user session for $FACTORY_USER" >&2; exit 1; }
as_factory() { runuser -u "$FACTORY_USER" -- env XDG_RUNTIME_DIR="$rundir" DBUS_SESSION_BUS_ADDRESS="unix:path=$rundir/bus" "$@"; }

# host.docker.internal is the VM's address, where rootlesskit publishes a container's ports: the bridge's gateway
# does not reach them (Testcontainers' Ryuk failed so in the spike). Written every boot, as the address may change.
vm_ip=$(ip -4 -o addr show "$(ip -4 route show default | awk '{print $5; exit}')" | awk '{print $4; exit}' | cut -d/ -f1)
# Written as factory, never as root: factory's home is factory's, and so is any path a rootless container a test starts
# can bind-mount there. Root writing or chowning through it would follow a link factory planted (daemon.json -> a
# root file), and give factory that file, then root: checked in the VM, a root-owned file under /etc became factory's
# after a reboot (review round 1 of #0-116). As factory, a link only redirects factory's own write, and the rename below
# replaces it.
daemon_json=/home/$FACTORY_USER/.config/docker/daemon.json
want="{ \"host-gateway-ip\": \"$vm_ip\" }"
rc=0
# shellcheck disable=SC2016 # expanded by the shell runuser starts, with the arguments after `_`
# Unchanged only when it is a regular file holding $want; otherwise a new file is renamed over it, which replaces a
# planted link itself instead of writing through it (a write through a link to a root file is refused to factory, and
# in the round 1 re-test that stopped the daemon's start after a reboot).
as_factory sh -c 'd=${1%/*}; mkdir -p -- "$d" || exit 4
  if [ -f "$1" ] && [ ! -L "$1" ] && [ "$(cat -- "$1")" = "$2" ]; then exit 3; fi
  t=$(mktemp -- "$d/.daemon.json.XXXXXX") || exit 4
  printf "%s\n" "$2" > "$t" && mv -f -- "$t" "$1"' \
  _ "$daemon_json" "$want" || rc=$?
case $rc in
  0) changed=yes ;;
  3) changed=no ;;
  *) echo "provision.sh: cannot write $daemon_json as $FACTORY_USER (exit $rc)" >&2; exit 1 ;;
esac
if ! as_factory test -f "/home/$FACTORY_USER/.config/systemd/user/docker.service"; then
  as_factory dockerd-rootless-setuptool.sh install
elif [ "$changed" = yes ]; then
  as_factory systemctl --user restart docker
fi
as_factory systemctl --user is-active --quiet docker

if [ "$(/usr/local/bin/node --version 2>/dev/null)" != "v$NODE_VERSION" ]; then
  case "$(dpkg --print-architecture)" in
    arm64) node_arch=arm64 node_sha=$NODE_SHA256_ARM64 ;;
    amd64) node_arch=x64 node_sha=$NODE_SHA256_X64 ;;
    *) echo "provision.sh: no Node pin for $(dpkg --print-architecture)" >&2; exit 1 ;;
  esac
  node_tar=node-v${NODE_VERSION}-linux-${node_arch}.tar.xz
  curl -fsSL -o "$work/$node_tar" "https://nodejs.org/dist/v${NODE_VERSION}/${node_tar}"
  echo "$node_sha  $work/$node_tar" | sha256sum -c -
  tar -xJf "$work/$node_tar" -C /usr/local --strip-components=1 --no-same-owner \
    --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md
fi

if [ "$(devcontainer --version 2>/dev/null)" != "$DEVCONTAINER_CLI_VERSION" ]; then
  cli_tgz=$work/devcontainers-cli-${DEVCONTAINER_CLI_VERSION}.tgz
  curl -fsSL -o "$cli_tgz" "https://registry.npmjs.org/@devcontainers/cli/-/cli-${DEVCONTAINER_CLI_VERSION}.tgz"
  echo "$DEVCONTAINER_CLI_SHA512  $cli_tgz" | sha512sum -c -
  # --ignore-scripts: no lifecycle script runs as root (0.89.0 has none; a later version cannot add one unseen).
  /usr/local/bin/npm install -g --no-fund --no-audit --ignore-scripts "$cli_tgz"
fi

# The boot it finished in, so create.sh can tell this boot's run from an earlier one.
echo "factory-build provisioned: $(docker --version), rootless for $FACTORY_USER; node $(/usr/local/bin/node --version); devcontainer $(devcontainer --version); boot $(cat /proc/sys/kernel/random/boot_id)" \
  > /etc/factory-build-provisioned
