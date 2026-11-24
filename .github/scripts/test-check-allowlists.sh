#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory-admin/build-vm/check-allowlists.sh (backlog #0-116, ADR-0057): on fixture repositories, the
# VM's copy of the devcontainer's allow-list must equal it both ways, required to required and optional to optional,
# and VM_ONLY_DOMAINS must stay apart from it; the api.github.com/meta keys of both must be the same set (review round 4
# of #0-116); each difference fails and is named; a list or key selection it cannot find fails (no silent pass); a
# comment on a list line is no domain; and the repository's own lists pass.
# Run: .github/scripts/test-check-allowlists.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
CHECK=$SRC/scripts/factory-admin/build-vm/check-allowlists.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

# repo <vm DOMAINS> <vm OPTIONAL> <vm VM_ONLY> <ct ALLOWED> <ct OPTIONAL> [<vm meta keys> [<ct meta keys>]] — a new
# fixture root, printed (meta keys default to `.web + .api + .git`). Each in a
# directory of its own (mktemp, not a counter: this runs in a command substitution, whose variables do not return).
repo() {
    local r
    r=$(mktemp -d "$WORK/r.XXXXXX")
    mkdir -p "$r/scripts/factory-admin/build-vm" "$r/.devcontainer"
    # shellcheck disable=SC2016 # the fixture's own text: its "$meta" is a line of the written file, not this shell's
    printf '#!/bin/bash\ncat <<EOF\nDOMAINS=(\n  %s  # a comment (with parens)\n)\nOPTIONAL_DOMAINS=(%s)\nVM_ONLY_DOMAINS=(\n  %s  # the VM alone\n)\njq -r '"'"'(%s)[] | select(test(":") | not)'"'"' <<<"$meta"\nEOF\n' \
        "$1" "$2" "$3" "${6:-.web + .api + .git}" > "$r/scripts/factory-admin/build-vm/provision.sh"
    # shellcheck disable=SC2016 # the fixture's own text: its ${ALLOWED_DOMAINS[@]} is a line the check must not read
    printf 'ALLOWED_DOMAINS=(\n    %s\n)\nOPTIONAL_DOMAINS=(%s)\nfor d in "${ALLOWED_DOMAINS[@]}"; do :; done\nprintf x | jq -r '"'"'(%s)[] | select(test(":") | not)'"'"'\n' "$4" "$5" "${7:-.web + .api + .git}" \
        > "$r/.devcontainer/init-firewall.sh"
    # The lists and files of backlog #0-313 (AC7, the proxy), each overridable by a variable of the caller.
    printf 'DISPATCHER_DOMAINS=(%s)\nPROXY_ADDR=%s  # the proxy\nPROXY_PORTS=%s\n' \
        "${DISP-api.x.com}" "${PADDR-10.9.0.1}" "${PPORTS-8770}" >> "$r/scripts/factory-admin/build-vm/provision.sh"
    printf 'ANTHROPIC_DOMAINS=(%s)\nANTHROPIC_OPTIONAL_DOMAINS=(%s)\n' "${ANTH-api.x.com y.x.com}" "${ANTH_OPT-t.x.com}" \
        >> "$r/.devcontainer/init-firewall.sh"
    printf '%s\n' "${PFILE-10.9.0.1:8770}" > "$r/.devcontainer/factory-proxy"
    # task.json: valid JSON either way, the caller's when TASKJSON is set (a default inside ${...} would end at its
    # first closing brace: review round 1, general).
    local task_default='{ "build": { "dockerfile": "Dockerfile" } }'
    printf '%s\n' "${DOCKERARG-ARG FACTORY_ANTHROPIC=\"\"}" > "$r/.devcontainer/Dockerfile"
    printf '%s\n' "${TASKJSON-$task_default}" > "$r/.devcontainer/task.json"
    echo "$r"
}
# expect <name> <exit> <text the output must hold> <root>
expect() {
    local out rc
    out=$("$CHECK" "$4" 2>&1); rc=$?
    if [ "$rc" -ne "$2" ]; then fail "$1: exit $rc, wanted $2 ($out)"
    elif ! grep -qF -- "$3" <<<"$out"; then fail "$1: output lacks '$3' ($out)"
    else ok "$1"; fi
}

echo "check-allowlists.sh"
expect "an equal copy and a separate VM-only list pass"          0 "the VM's copy equals"           "$(repo 'a.com b.com' 'opt.com' 'reg.io' 'a.com b.com' 'opt.com')"
expect "a domain only the devcontainer requires fails"           1 "not by the VM's copy (DOMAINS): new.example.com" "$(repo 'a.com' '' 'reg.io' 'a.com new.example.com' '')"
expect "a domain the devcontainer dropped, left in the copy, fails" 1 "no longer required by the devcontainer: old.example.com" "$(repo 'a.com old.example.com' '' 'reg.io' 'a.com' '')"
expect "an optional devcontainer domain missing from the VM fails" 1 "not in the VM's OPTIONAL_DOMAINS: opt.com" "$(repo 'a.com' '' '' 'a.com' 'opt.com')"
expect "a required domain kept as optional in the VM fails"      1 "not by the VM's copy (DOMAINS): b.com" "$(repo 'a.com' 'b.com' '' 'a.com b.com' '')"
expect "a devcontainer domain in VM_ONLY_DOMAINS fails"          1 "not the VM's alone: a.com"      "$(repo 'a.com' '' 'a.com reg.io' 'a.com' '')"
expect "an empty VM-only list passes"                            0 "the VM's copy equals"           "$(repo 'a.com' '' '' 'a.com' '')"
r=$(repo 'a.com' '' '' 'a.com' ''); sed -i.bak 's/^DOMAINS=(/LIST=(/' "$r/scripts/factory-admin/build-vm/provision.sh"
expect "no VM list found fails"                                  1 "no DOMAINS list"                "$r"
r=$(repo 'a.com' '' '' 'a.com' ''); sed -i.bak 's/^ALLOWED_DOMAINS=(/X=(/' "$r/.devcontainer/init-firewall.sh"
expect "no devcontainer list found fails"                        1 "no ALLOWED_DOMAINS list"        "$r"
expect "the same GitHub meta keys in another order pass"         0 "the VM's copy equals"           "$(repo 'a.com' '' '' 'a.com' '' '.git + .web + .api')"
expect "GitHub meta keys the devcontainer narrowed fail"        1 "GitHub meta keys differ"        "$(repo 'a.com' '' '' 'a.com' '' '.web + .api + .git' '.api + .git')"
r=$(repo 'a.com' '' '' 'a.com' ''); sed -i.bak '/^jq -r/d' "$r/scripts/factory-admin/build-vm/provision.sh"
expect "no VM meta key selection found fails"                    1 "no api.github.com/meta key selection" "$r"
r=$(repo 'a.com' '' '' 'a.com' ''); sed -i.bak '/jq -r/d' "$r/.devcontainer/init-firewall.sh"
expect "no devcontainer meta key selection found fails"          1 "no api.github.com/meta key selection found in $r/.devcontainer" "$r"
# Backlog #0-313: Anthropic only for the owner's image and the dispatcher, the proxy's address in one place.
expect "Anthropic only in the owner's lists and the dispatcher's passes" 0 "Anthropic only for the owner's image" "$(repo 'a.com' '' '' 'a.com' '')"
expect "an Anthropic host in the task's required list fails"     1 "Anthropic's hosts in a list factory reaches" "$(repo 'a.com y.x.com' '' '' 'a.com y.x.com' '')"
expect "an optional Anthropic host in the VM's list fails"       1 "#0-313 AC7): t.x.com" "$(repo 'a.com' 't.x.com' '' 'a.com' 't.x.com')"
expect "an Anthropic host among the VM's own fails"              1 "#0-313 AC7): y.x.com" "$(repo 'a.com' '' 'y.x.com' 'a.com' '')"
expect "a dispatcher host not Anthropic's fails"                 1 "not one of init-firewall.sh's Anthropic hosts: z.com" "$(DISP='api.x.com z.com' repo 'a.com' '' '' 'a.com' '')"
expect "a dispatcher host factory reaches too fails"             1 "in a list factory reaches: api.x.com" "$(repo 'a.com api.x.com' '' '' 'a.com api.x.com' '')"
expect "no dispatcher list found fails"                          1 "no DISPATCHER_DOMAINS list" "$(DISP='' repo 'a.com' '' '' 'a.com' '')"
expect "no Anthropic list in the devcontainer found fails"       1 "no ANTHROPIC_DOMAINS list" "$(ANTH='' repo 'a.com' '' '' 'a.com' '')"
expect "task.json naming the Anthropic choice fails"             1 "task.json names FACTORY_ANTHROPIC" "$(TASKJSON='{ "build": { "args": { "FACTORY_ANTHROPIC": "1" } } }' repo 'a.com' '' '' 'a.com' '')"
expect "a task image's proxy address other than the VM's fails"  1 "is not provision.sh's PROXY_ADDR" "$(PFILE='10.9.0.2:8770' repo 'a.com' '' '' 'a.com' '')"
expect "a task image's proxy port other than the first fails"    1 "is not provision.sh's PROXY_ADDR" "$(PFILE='10.9.0.1:8771' PPORTS='8770,8771' repo 'a.com' '' '' 'a.com' '')"
expect "the first of several proxy ports passes"                 0 "proxy 10.9.0.1:8770" "$(PPORTS='8770,8771' repo 'a.com' '' '' 'a.com' '')"
expect "a parent of an Anthropic host in the VM's list fails"    1 "a parent of an Anthropic host in a list factory reaches" "$(repo 'a.com x.com' '' '' 'a.com x.com' '')"
expect "a parent of an Anthropic host among the VM's own fails"  1 "x.com (for api.x.com)" "$(repo 'a.com' '' 'x.com' 'a.com' '')"
expect "a Dockerfile choosing Anthropic by default fails"        1 "does not default to empty" "$(DOCKERARG='ARG FACTORY_ANTHROPIC="1"' repo 'a.com' '' '' 'a.com' '')"
expect "a Dockerfile without the argument fails"                 1 "does not default to empty" "$(DOCKERARG='FROM scratch' repo 'a.com' '' '' 'a.com' '')"
expect "a proxy constant with a trailing comment passes"         0 "proxy 10.9.0.1:8770" "$(repo 'a.com' '' '' 'a.com' '')"
expect "no proxy constants found fails"                          1 "no PROXY_ADDR or PROXY_PORTS" "$(PADDR='' repo 'a.com' '' '' 'a.com' '')"
expect "the repository's own lists"                              0 "the VM's copy equals"           "$SRC"

if [ "$failures" -gt 0 ]; then echo "$failures check-allowlists case(s) failed."; exit 1; fi
echo "All check-allowlists cases passed."
