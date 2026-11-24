#!/usr/bin/env bash
# ============================================================
# The build VM's copy of the devcontainer's allow-list (backlog #0-116, ADR-0057; review rounds 1 and 2, FAC-A01).
#
# .devcontainer/init-firewall.sh's ALLOWED_DOMAINS and OPTIONAL_DOMAINS bind the agents' commands; factory-egress.sh
# in provision.sh binds everything the VM's rootless Docker sends, so it carries a copy of both, as DOMAINS and
# OPTIONAL_DOMAINS, and keeps what only the VM needs (image registries, the image build's sources) apart, in
# VM_ONLY_DOMAINS. This holds the copy equal both ways, required to required and optional to optional - a host added
# to the devcontainer's list alone is one the VM rejects, and a host removed from it alone is one the VM still lets a
# test reach - and VM_ONLY_DOMAINS apart from both. The GitHub ranges are part of the list too: both files take them
# from api.github.com/meta with `jq -r '(<keys>)[]`, and the keys (.web, .api, .git) must be the same set, or narrowing
# the devcontainer's would leave the VM's wider (review round 4 of #0-116). Equal entries, not equal meaning: the
# devcontainer resolves each as an exact host, the VM's resolver allows it with its subdomains (backlog #0-247, ADR-0057),
# so a host added here opens its whole domain in the VM. Run by create.sh before a VM is made and by
# Factory guards on every pull request, as its own step and as its test's last case, so a drift fails CI, not the
# running VM.
# What it reads is the array literals `NAME=( ... )` and the jq key selection; a host appended elsewhere (`NAME+=(...)`)
# is not seen: init-firewall.sh appends the hosts of the image's /etc/factory-firewall/extra-hosts, below, and, in an
# image that chose them, its own ANTHROPIC_DOMAINS and ANTHROPIC_OPTIONAL_DOMAINS, which are checked as their own lists.
# That file's host (the owner's FACTORY_NTFY_SERVER, written at the image's build since backlog #0-283; no file in a
# task container) is in neither list: docs/ai-factory.md "Build VM" says to add one by hand;
# ntfy.sh is a publishing service, so it is not allowed for the VM by default.
#
#   check-allowlists.sh [<repository root>]     exit 0 and one line when the lists agree, 1 naming each difference
# Since backlog #0-313 (AC7, the proxy), also:
#   - Anthropic's hosts are out of every list `factory` reaches: init-firewall.sh's ANTHROPIC_DOMAINS and
#     ANTHROPIC_OPTIONAL_DOMAINS (opened only in an image that chose them, the owner's container) are in none of
#     ALLOWED_DOMAINS, OPTIONAL_DOMAINS, the VM's DOMAINS, OPTIONAL_DOMAINS or VM_ONLY_DOMAINS; the VM's
#     DISPATCHER_DOMAINS (its proxy's upstream, `dispatcher`'s uid alone) is not empty, holds only Anthropic's hosts,
#     and none of the lists `factory` reaches;
#   - no list `factory` reaches holds a parent of an Anthropic host either (`anthropic.com` would open
#     `api.anthropic.com`: the VM's resolver allows each name with its subdomains);
#   - the choice is the owner's: task.json does not name FACTORY_ANTHROPIC, and the Dockerfile's
#     `ARG FACTORY_ANTHROPIC` defaults to empty (an image built without the argument chooses none);
#   - .devcontainer/factory-proxy, the address and port the task's image lets its container reach, is provision.sh's
#     PROXY_ADDR and the first of its PROXY_PORTS.
# Tested by .github/scripts/test-check-allowlists.sh.
# ============================================================
set -euo pipefail

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
vm_file=$root/scripts/factory-admin/build-vm/provision.sh
ct_file=$root/.devcontainer/init-firewall.sh
proxy_file=$root/.devcontainer/factory-proxy
task_file=$root/.devcontainer/task.json
docker_file=$root/.devcontainer/Dockerfile

fail() { echo "check-allowlists.sh: $*" >&2; exit 1; }
[ -r "$vm_file" ] && [ -r "$ct_file" ] && [ -r "$proxy_file" ] && [ -r "$task_file" ] && [ -r "$docker_file" ] \
    || fail "cannot read $vm_file, $ct_file, $proxy_file, $task_file or $docker_file"

# The words of a bash array literal `NAME=( ... )` at the start of a line (indent allowed), one per line; a `#` ends
# the words of its line.
domains_of() {
    awk -v n="$2" '
        $0 ~ "^ *" n "=\\(" { f = 1; sub(/^[^(]*\(/, "") }
        f { line = $0; sub(/#.*/, "", line); done = sub(/\).*/, "", line); print line; if (done) f = 0 }
    ' "$1" | tr -s ' \t' '\n' | grep -v '^$' || true
}

# The keys of the api.github.com/meta selection `jq -r '(<keys>)[]`, one per line, sorted.
gh_keys_of() {
    { grep -o "jq -r '([^)]*)\[\]" "$1" || true; } | sed "s/^jq -r '(//; s/)\[\]\$//" | tr '+' '\n' | tr -d ' \t' | grep -v '^$' | sort -u || true
}

vm_req=$(domains_of "$vm_file" DOMAINS | sort -u)
vm_opt=$(domains_of "$vm_file" OPTIONAL_DOMAINS | sort -u)
vm_only=$(domains_of "$vm_file" VM_ONLY_DOMAINS | sort -u)
ct_req=$(domains_of "$ct_file" ALLOWED_DOMAINS | sort -u)
ct_opt=$(domains_of "$ct_file" OPTIONAL_DOMAINS | sort -u)
ct_anth=$(domains_of "$ct_file" ANTHROPIC_DOMAINS | sort -u)
ct_anth_opt=$(domains_of "$ct_file" ANTHROPIC_OPTIONAL_DOMAINS | sort -u)
vm_disp=$(domains_of "$vm_file" DISPATCHER_DOMAINS | sort -u)
[ -n "$ct_anth" ] || fail "no ANTHROPIC_DOMAINS list found in $ct_file"
[ -n "$vm_disp" ] || fail "no DISPATCHER_DOMAINS list found in $vm_file"
# The proxy's constants: `NAME=value` at the start of a line, digits, dots and commas, a trailing `# comment` allowed;
# create.sh reads them in the same form (review round 1, FAC-A01).
const_of() { sed -n "s/^$2=\([0-9.,]*\)\( *#.*\)\{0,1\}\$/\1/p" "$1" | head -1; }
proxy_addr=$(const_of "$vm_file" PROXY_ADDR)
proxy_port=$(const_of "$vm_file" PROXY_PORTS); proxy_port=${proxy_port%%,*}
[ -n "$proxy_addr" ] && [ -n "$proxy_port" ] || fail "no PROXY_ADDR or PROXY_PORTS found in $vm_file"
[ -n "$vm_req" ] || fail "no DOMAINS list found in $vm_file"
[ -n "$ct_req" ] || fail "no ALLOWED_DOMAINS list found in $ct_file"
vm_gh=$(gh_keys_of "$vm_file")
ct_gh=$(gh_keys_of "$ct_file")
[ -n "$vm_gh" ] || fail "no api.github.com/meta key selection found in $vm_file"
[ -n "$ct_gh" ] || fail "no api.github.com/meta key selection found in $ct_file"
# only_in <a> <b>: the lines of a that b lacks, on one line.
only_in() { comm -23 <(printf '%s\n' "$1" | grep -v '^$') <(printf '%s\n' "$2" | grep -v '^$') | tr '\n' ' '; }
problems=()
d=$(only_in "$ct_req" "$vm_req"); [ -z "$d" ] || problems+=("required by the devcontainer, not by the VM's copy (DOMAINS): $d")
d=$(only_in "$vm_req" "$ct_req"); [ -z "$d" ] || problems+=("in the VM's copy (DOMAINS), no longer required by the devcontainer: $d")
d=$(only_in "$ct_opt" "$vm_opt"); [ -z "$d" ] || problems+=("optional for the devcontainer, not in the VM's OPTIONAL_DOMAINS: $d")
d=$(only_in "$vm_opt" "$ct_opt"); [ -z "$d" ] || problems+=("in the VM's OPTIONAL_DOMAINS, not optional for the devcontainer: $d")
both=$(printf '%s\n%s\n' "$ct_req" "$ct_opt" | grep -v '^$' | sort -u)
d=$(comm -12 <(printf '%s\n' "$vm_only" | grep -v '^$') <(printf '%s\n' "$both") | tr '\n' ' ')
[ -z "$d" ] || problems+=("in VM_ONLY_DOMAINS but also the devcontainer's, so not the VM's alone: $d")
anth=$(printf '%s\n%s\n' "$ct_anth" "$ct_anth_opt" | grep -v '^$' | sort -u)
reached=$(printf '%s\n%s\n%s\n%s\n%s\n' "$ct_req" "$ct_opt" "$vm_req" "$vm_opt" "$vm_only" | grep -v '^$' | sort -u)
d=$(comm -12 <(printf '%s\n' "$anth") <(printf '%s\n' "$reached") | tr '\n' ' ')
[ -z "$d" ] || problems+=("Anthropic's hosts in a list factory reaches (only the owner's image may choose them, #0-313 AC7): $d")
d=$(only_in "$vm_disp" "$anth"); [ -z "$d" ] || problems+=("in the VM's DISPATCHER_DOMAINS, not one of init-firewall.sh's Anthropic hosts: $d")
d=$(comm -12 <(printf '%s\n' "$vm_disp") <(printf '%s\n' "$reached") | tr '\n' ' ')
[ -z "$d" ] || problems+=("in the VM's DISPATCHER_DOMAINS and also in a list factory reaches: $d")
# A parent of an Anthropic host in a list factory reaches: `anthropic.com` for `api.anthropic.com`.
parents=$(while IFS= read -r h; do
    while IFS= read -r p; do
        if [ -n "$p" ] && [ "$h" != "$p" ] && [[ $h == *".$p" ]]; then echo "$p (for $h)"; fi
    done <<<"$reached"
done <<<"$anth" | sort -u | tr '\n' ' ' || true)
[ -z "$parents" ] || problems+=("a parent of an Anthropic host in a list factory reaches (the resolver allows its subdomains): $parents")
grep -qx 'ARG FACTORY_ANTHROPIC=""' "$docker_file" \
    || problems+=("the Dockerfile's ARG FACTORY_ANTHROPIC does not default to empty: an image built without the argument would choose Anthropic")
if grep -q FACTORY_ANTHROPIC "$task_file"; then problems+=("task.json names FACTORY_ANTHROPIC: Anthropic's hosts are the owner's container's choice alone"); fi
proxy_line=$(cat "$proxy_file")
[ "$proxy_line" = "$proxy_addr:$proxy_port" ] \
    || problems+=("the task image's proxy ($proxy_file: $proxy_line) is not provision.sh's PROXY_ADDR:first PROXY_PORTS ($proxy_addr:$proxy_port)")
[ "$vm_gh" = "$ct_gh" ] || problems+=("GitHub meta keys differ: the devcontainer's $(tr '\n' ' ' <<<"$ct_gh")and the VM's $(tr '\n' ' ' <<<"$vm_gh")")
if [ "${#problems[@]}" -gt 0 ]; then
    for p in "${problems[@]}"; do echo "check-allowlists.sh: $p" >&2; done
    fail "the build VM's copy of the devcontainer's allow-list differs: fix factory-egress.sh in provision.sh"
fi
echo "allow-lists: the VM's copy equals the devcontainer's ($(grep -c . <<<"$ct_req") required, $(grep -c . <<<"$ct_opt" || true) optional, GitHub meta $(tr '\n' ' ' <<<"$ct_gh" | sed 's/ $//')); $(grep -c . <<<"$vm_only") VM-only; Anthropic only for the owner's image and the dispatcher ($(tr '\n' ' ' <<<"$vm_disp" | sed 's/ $//')); proxy $proxy_line"
