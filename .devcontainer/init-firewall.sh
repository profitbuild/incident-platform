#!/usr/bin/env bash
# ============================================================
# Outbound firewall of the factory's devcontainer: default deny, then an allow-list. Modelled on the
# reference devcontainer of Claude Code (github.com/anthropics/claude-code, .devcontainer/), adapted to
# this project. Run as root at container start (postStartCommand). Needs NET_ADMIN and NET_RAW. The dispatcher's task
# container runs it too (task.json, backlog #0-282). `dev` may run it through sudo, without arguments only (the
# Dockerfile's sudoers line), and it takes none: run again, it builds the same list anew.
#
# Fixed (backlog #0-283): it added every argument to its allow-list, and the sudoers line allowed any arguments, so
# code in a container opened any host by `sudo init-firewall.sh <host>` (FAC-S02; on the VM only within its egress
# list). The one extra host, the owner's ntfy server, is read from /etc/factory-firewall/extra-hosts, which the image
# writes at build time (root's; absent in a task container). Not an argument checked by sudo instead: a server changed
# on the host without a rebuild would then make sudo refuse, the script would never start, and the container would
# run with no firewall at all, as nothing would set this script's fail-closed trap.
#
# IPv4 only: every allowed service is reached over IPv4, so IPv6 allows loopback and nothing else (without
# this, a container with an IPv6 route would bypass the whole allow-list). If the container has IPv6 and
# ip6tables cannot be set, the script fails rather than leave IPv6 open.
# Allowed: DNS to the container's own resolver only (no direct queries to outside resolvers); GitHub (its published
# IP ranges); Maven Central; the advisory hosts the verifier agent may fetch from (OSV, Tomcat's and Spring's security
# pages: backlog #0-160, ADR-0037); the Docker host (Testcontainers' mapped ports, and Ollama on the host for the
# optional local model); the hosts of /etc/factory-firewall/extra-hosts (the ntfy server, when the image was built with
# one); the Anthropic API and login only when the image chose them (/etc/factory-firewall/anthropic, the owner's
# container); and the one address and port of /etc/factory-firewall/proxy, the dispatcher's credential proxy on the
# build VM. Everything else from this container is rejected.
#
# Anthropic (backlog #0-313 AC7): a task's container reaches the model through the dispatcher's proxy alone, so it
# opens no Anthropic host; kept, a task's code could still send there around the proxy (telemetry, a key of its own).
# The choice is a file the image writes from devcontainer.json's build argument FACTORY_ANTHROPIC, root's: never an
# argument, a variable or a file `dev` can write, since `dev` may run this script again through sudo. No file, or any
# content but `yes`, means none (fail closed: a missing choice gives a task nothing more).
# The proxy (backlog #0-313): its address and port are copied into every image, the owner's too, from
# .devcontainer/factory-proxy (check-allowlists.sh holds it equal to provision.sh's). In the owner's container on the
# Mac the rule is dead as long as nothing listens at that address: Docker Desktop sends it to whatever network the Mac
# routes 10.0.0.0/8 to, so on a LAN or a VPN that holds it the rule opens that one address and port there (review
# round 1, security). That is accepted on purpose: it opens one address and one port, and the other way, a build
# argument of task.json only, would need the dispatcher's closed table of task.json's keys (ADR-0062 point 4) opened
# for `build.args`.
# The advisory hosts are open to every process in the container, not only to the verifier (whose WebFetch a hook
# narrows to a path prefix), and by IP: a CDN or Google's front end serves other sites from the same addresses,
# reachable by their own name (SNI/Host) once the IP is open. That is why its allow-list is short. .github/scripts/check-web-access.sh fails when
# a host of that list (.claude/hooks/webfetch-allowlist.sh) is missing here.
#
# Not covered, by design of this setup: the host's Docker daemon is reachable (Testcontainers), and a
# container it starts has the host's network, not this firewall. Data can also leave through DNS queries
# the resolver forwards, and through the allowed hosts themselves (a push to GitHub, a PR body). The
# firewall narrows exfiltration; it does not make it impossible (docs/ai-factory.md, "What isolates what").
# Domains are resolved once, at start: a CDN that moves IPs needs a container restart.
#
# Usage: init-firewall.sh   (no arguments; one given fails closed, below)
# ============================================================
set -euo pipefail

# Fail closed: if anything below fails, the container ends with every policy DROP (no network at all,
# which is noticed at once) instead of the default ACCEPT. Before this trap, a domain that did not resolve
# (statsig.anthropic.com, 2026-10-09) ended the script before the DROP policies, and the container ran
# with an open network while only the missing "Firewall up" line said so.
# Limits: a trap does not run when the script is killed with SIGKILL (the policies stay ACCEPT, and
# "Firewall up" is missing, as above); IPv6 is closed when the container has it at start, and an interface
# that gains IPv6 later is not covered until the container restarts.
complete=no
fail_closed() {
    [ "$complete" = yes ] && return
    # set +e: under the script's errexit, the first failing command would end this trap, and on a host
    # without ip6tables that left IPv4 flushed and ACCEPT (review round 3). IPv4 DROP policies first, then
    # the flush (a failure after the allow rules are in, a failed self-test, would otherwise keep them), and
    # IPv6 last, where a failure changes nothing.
    set +e
    iptables -P OUTPUT DROP; iptables -P INPUT DROP; iptables -P FORWARD DROP
    iptables -F
    ip6tables -P OUTPUT DROP 2>/dev/null; ip6tables -P INPUT DROP 2>/dev/null; ip6tables -P FORWARD DROP 2>/dev/null
    ip6tables -F 2>/dev/null
    if [ "$(iptables -S 2>/dev/null | grep -c -- '-P [A-Z]* DROP')" -eq 3 ]; then
        echo "FIREWALL SETUP FAILED: all traffic is blocked. Fix the cause above and restart the container." >&2
    else
        echo "FIREWALL SETUP FAILED and the DROP policies could not be set: THE NETWORK MAY BE OPEN. Stop this container." >&2
    fi
}
trap fail_closed EXIT

# After the trap, so a call with arguments (an old devcontainer.json, or root by hand) ends with every policy DROP, not
# with the policies it found.
[ $# -eq 0 ] || { echo "init-firewall.sh takes no arguments (backlog #0-283): extra hosts come from /etc/factory-firewall/extra-hosts" >&2; exit 1; }

# Required: the run cannot work without them, so one that does not resolve stops the setup (fail closed).
# The build VM filters everything its rootless Docker sends with a copy of this list and a list of its own
# (factory-egress.sh in scripts/factory-admin/build-vm/provision.sh, ADR-0057): a domain added here or removed from here
# changes that copy too, which Factory guards checks (check-allowlists.sh). Both resolve each name to its IPv4
# addresses, with different tools (dig here, getent there): two scripts, as provision.sh reads no repository file.
ALLOWED_DOMAINS=(
    repo.maven.apache.org repo1.maven.org
    api.osv.dev osv.dev tomcat.apache.org spring.io
)
# Optional: allowed when they resolve, skipped with a warning when not.
OPTIONAL_DOMAINS=()
# Anthropic's hosts, added to the two lists above only when the image chose them (the owner's container; above). The VM
# allows `dispatcher`'s uid the API alone and `factory`'s none (provision.sh's DISPATCHER_DOMAINS; check-allowlists.sh).
ANTHROPIC_DOMAINS=(api.anthropic.com claude.ai platform.claude.com console.anthropic.com)
# Optional (telemetry), as OPTIONAL_DOMAINS.
ANTHROPIC_OPTIONAL_DOMAINS=(statsig.anthropic.com)
ANTHROPIC_FILE=/etc/factory-firewall/anthropic
anthropic=no
if [ -f "$ANTHROPIC_FILE" ] && [ ! -L "$ANTHROPIC_FILE" ] && [ "$(stat -c %u "$ANTHROPIC_FILE")" = 0 ] \
    && [ "$(cat "$ANTHROPIC_FILE")" = yes ]; then
    anthropic=yes
    ALLOWED_DOMAINS+=("${ANTHROPIC_DOMAINS[@]}")
    OPTIONAL_DOMAINS+=("${ANTHROPIC_OPTIONAL_DOMAINS[@]}")
fi
# The proxy's address and port, one line `<IPv4>:<port>`, root's. A file that is there but not of that form, or not
# root's, fails the setup (closed): an image built from a broken file is noticed at once. No file: no rule.
PROXY_FILE=/etc/factory-firewall/proxy
proxy=
if [ -e "$PROXY_FILE" ] || [ -L "$PROXY_FILE" ]; then
    { [ -f "$PROXY_FILE" ] && [ ! -L "$PROXY_FILE" ] && [ "$(stat -c %u "$PROXY_FILE")" = 0 ]; } \
        || { echo "$PROXY_FILE is not a regular file of root's" >&2; exit 1; }
    proxy=$(cat "$PROXY_FILE")
    octet='(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])'
    [[ $proxy =~ ^$octet\.$octet\.$octet\.$octet:([1-9][0-9]{0,4})$ ]] && [ "${BASH_REMATCH[5]}" -le 65535 ] \
        || { echo "$PROXY_FILE does not hold one <IPv4>:<port>" >&2; exit 1; }
fi
# The image's extra hosts, one per line (the Dockerfile writes at most one, the ntfy server's); required like the
# rest once listed. A line that is not a plain host name is ignored, as an argument was, and so is one starting with a
# hyphen, which `dig` would read as an option.
EXTRA_HOSTS_FILE=/etc/factory-firewall/extra-hosts
if [ -f "$EXTRA_HOSTS_FILE" ]; then
    while IFS= read -r extra || [ -n "$extra" ]; do
        case "$extra" in
            '') ;;
            *[!A-Za-z0-9.-]*|-*) echo "ignored extra host: $extra" >&2 ;;
            *) ALLOWED_DOMAINS+=("$extra") ;;
        esac
    done < "$EXTRA_HOSTS_FILE"
fi

# Only the filter table is reset. The nat table is left alone: Docker's embedded DNS (127.0.0.11) lives
# there, and flushing it would break name resolution in the container.
iptables -F; iptables -X
ipset destroy allowed 2>/dev/null || true

# DNS to the configured resolver(s) only, and loopback, so the resolution below works.
resolvers=$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | grep -E '^[0-9.]+$' || true)
[ -n "$resolvers" ] || { echo "no IPv4 nameserver in /etc/resolv.conf" >&2; exit 1; }
for r in $resolvers; do
    iptables -A OUTPUT -p udp -d "$r" --dport 53 -j ACCEPT
    iptables -A OUTPUT -p tcp -d "$r" --dport 53 -j ACCEPT
    iptables -A INPUT  -p udp -s "$r" --sport 53 -j ACCEPT
done
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed hash:net

# GitHub publishes its ranges; take web, api and git (IPv4).
gh_meta=$(curl -fsS --max-time 15 https://api.github.com/meta) || { echo "could not fetch GitHub meta" >&2; exit 1; }
printf '%s' "$gh_meta" | jq -r '(.web + .api + .git)[] | select(test(":") | not)' | sort -u | while read -r cidr; do
    ipset add allowed "$cidr" -exist
done

for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips=$(dig +short A "$domain" | grep -E '^[0-9.]+$' || true)
    [ -n "$ips" ] || { echo "could not resolve $domain" >&2; exit 1; }
    for ip in $ips; do ipset add allowed "$ip" -exist; done
done
for domain in "${OPTIONAL_DOMAINS[@]}"; do
    ips=$(dig +short A "$domain" | grep -E '^[0-9.]+$' || true)
    [ -n "$ips" ] || { echo "warning: optional $domain does not resolve, not allowed" >&2; continue; }
    for ip in $ips; do ipset add allowed "$ip" -exist; done
done

# The Docker host: Testcontainers' mapped ports and Ollama.
host_ip=$(getent ahostsv4 host.docker.internal | awk 'NR==1{print $1}' || true)
[ -n "$host_ip" ] && ipset add allowed "$host_ip" -exist
gw=$(ip route | awk '/default/ {print $3; exit}')
[ -n "$gw" ] && ipset add allowed "$gw" -exist

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP
iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed dst -j ACCEPT
[ -z "$proxy" ] || iptables -A OUTPUT -p tcp -d "${proxy%:*}" --dport "${proxy##*:}" -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# IPv6: loopback only. Applied whenever the kernel has IPv6 (/proc/net/if_inet6 lists an address, ::1
# included); a container without IPv6 has nothing to close. Read, not `-s`: procfs files report size 0.
if grep -q . /proc/net/if_inet6 2>/dev/null; then
    { ip6tables -F && ip6tables -X; } || { echo "IPv6 is present but ip6tables cannot be set: refusing to leave it open" >&2; exit 1; }
    ip6tables -A INPUT  -i lo -j ACCEPT
    ip6tables -A OUTPUT -o lo -j ACCEPT
    ip6tables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT DROP
    ip6tables -A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited
    ipv6=closed
else
    ipv6="not present"
fi

# Self-test: one allowed, one denied.
curl -fsS --max-time 5 https://api.github.com/zen >/dev/null || { echo "firewall self-test: GitHub not reachable" >&2; exit 1; }
if curl -fsS --max-time 5 https://example.com >/dev/null 2>&1; then
    echo "firewall self-test: example.com is reachable, the allow-list is not applied" >&2; exit 1
fi
if [ "$ipv6" = closed ] && curl -6 -fsS --max-time 5 https://example.com >/dev/null 2>&1; then
    echo "firewall self-test: example.com is reachable over IPv6" >&2; exit 1
fi
# Without the image's choice, Anthropic's API is refused too (backlog #0-313 AC7): any answer, a 4xx included, means
# the connection was made.
if [ "$anthropic" = no ] && curl -sS --max-time 5 -o /dev/null https://api.anthropic.com/ 2>/dev/null; then
    echo "firewall self-test: api.anthropic.com is reachable without the image's choice" >&2; exit 1
fi
complete=yes
echo "Firewall up: $(ipset list allowed | grep -c '^[0-9]') allowed networks; Anthropic ${anthropic/no/not chosen}; proxy ${proxy:-none}; IPv6 $ipv6."
