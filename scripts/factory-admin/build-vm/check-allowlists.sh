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
# the devcontainer's would leave the VM's wider (review round 4 of #0-116). Run by create.sh before a VM is made and by
# Factory guards on every pull request, as its own step and as its test's last case, so a drift fails CI, not the
# running VM.
# What it reads is the array literals `NAME=( ... )` and the jq key selection; a host appended elsewhere (`NAME+=(...)`)
# is not seen: init-firewall.sh appends only the hosts passed as arguments, below.
# Hosts passed to init-firewall.sh as arguments (FACTORY_NTFY_SERVER) are in neither file: docs/ai-factory.md
# "Build VM" says to add one by hand; ntfy.sh is a publishing service, so it is not allowed for the VM by default.
#
#   check-allowlists.sh [<repository root>]     exit 0 and one line when the lists agree, 1 naming each difference
# Tested by .github/scripts/test-check-allowlists.sh.
# ============================================================
set -euo pipefail

root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}
vm_file=$root/scripts/factory-admin/build-vm/provision.sh
ct_file=$root/.devcontainer/init-firewall.sh

fail() { echo "check-allowlists.sh: $*" >&2; exit 1; }
[ -r "$vm_file" ] && [ -r "$ct_file" ] || fail "cannot read $vm_file or $ct_file"

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
[ "$vm_gh" = "$ct_gh" ] || problems+=("GitHub meta keys differ: the devcontainer's $(tr '\n' ' ' <<<"$ct_gh")and the VM's $(tr '\n' ' ' <<<"$vm_gh")")
if [ "${#problems[@]}" -gt 0 ]; then
    for p in "${problems[@]}"; do echo "check-allowlists.sh: $p" >&2; done
    fail "the build VM's copy of the devcontainer's allow-list differs: fix factory-egress.sh in provision.sh"
fi
echo "allow-lists: the VM's copy equals the devcontainer's ($(grep -c . <<<"$ct_req") required, $(grep -c . <<<"$ct_opt") optional, GitHub meta $(tr '\n' ' ' <<<"$ct_gh" | sed 's/ $//')); $(grep -c . <<<"$vm_only") VM-only"
