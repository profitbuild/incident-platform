#!/usr/bin/env bash
# ============================================================
# Tests for the limits of `factory`'s user slice on the build VM (backlog #0-315): provision.sh's factory_slice_limits,
# read from the file the way create.sh reads it, derives MemoryMax (MemTotal less max(1.5 GiB, 12 %)), MemoryHigh (95 %
# of it) and TasksMax (16384) from the VM's memory, and refuses a MemTotal that is not a number or a VM that would leave
# factory less than 4 GiB; and provision.sh writes the result into a drop-in of user-<factory's uid>.slice under /etc,
# before the reload and before factory's lingering session starts.
# Run: .github/scripts/test-factory-slice-limits.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
PROVISION=$SRC/scripts/factory-admin/build-vm/provision.sh
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

echo "factory_slice_limits (provision.sh)"
# The function as create.sh reads it: from its first line to the first line that is `}`.
body=$(sed -n '/^factory_slice_limits() {/,/^}$/p' "$PROVISION")
[ "$(grep -c '^factory_slice_limits() {' "$PROVISION")" = 1 ] || { echo "::error::provision.sh defines factory_slice_limits not exactly once"; exit 1; }
[ "$(tail -n 1 <<<"$body")" = "}" ] || { echo "::error::no closing line of factory_slice_limits in provision.sh"; exit 1; }
eval "$body"

# expect <name> <MemTotal kB> <MemoryHigh kB> <MemoryMax kB>
expect() {
    local out rc want
    out=$(factory_slice_limits "$2" 2>&1); rc=$?
    want=$(printf '[Slice]\nMemoryHigh=%sK\nMemoryMax=%sK\nTasksMax=16384' "$3" "$4")
    if [ "$rc" -ne 0 ]; then fail "$1: exit $rc ($out)"
    elif [ "$out" != "$want" ]; then fail "$1: got $(tr '\n' ' ' <<<"$out"), wanted $(tr '\n' ' ' <<<"$want")"
    else ok "$1"; fi
}
# refused <name> <MemTotal> <text the error must hold>
refused() {
    local out rc
    out=$(factory_slice_limits "$2" 2>&1); rc=$?
    if [ "$rc" -eq 0 ]; then fail "$1: accepted ($out)"
    elif ! grep -qF -- "$3" <<<"$out"; then fail "$1: error lacks '$3' ($out)"
    else ok "$1"; fi
}

# The build VM as it is (factory-build.yaml's 12 GiB, MemTotal read there on 2026-11-22): 12 % is below 1.5 GiB.
expect "a 12 GiB VM keeps the 1.5 GiB reserve"           12221396 10116105 10648532
# A 16 GiB VM (M5's two slots): 12 % is above 1.5 GiB and takes over.
expect "a 16 GiB VM keeps a 12 % reserve"                16777216 14025753 14763951
expect "a VM that leaves factory exactly 4 GiB passes"    5767168  3984588  4194304
refused "a VM that leaves factory 1 kB under 4 GiB fails" 5767167 "below the 4 GiB a gate needs"
refused "a 4 GiB VM fails"                                4194304 "below the 4 GiB a gate needs"
refused "a VM smaller than the reserve fails"             1048576 "below the 4 GiB a gate needs"
refused "an empty MemTotal fails"                         ""      "is not a number of kB"
refused "a MemTotal with a unit fails"                    "12221396 kB" "is not a number of kB"
refused "a negative MemTotal fails"                       "-12221396" "is not a number of kB"

echo "provision.sh writes it"
# Each line as provision.sh has it, then its order: the drop-in written before the reload that applies it, and both
# before factory's session starts (enable-linger), so its daemon starts inside the limits on a new VM.
line_of() { grep -nF -- "$1" "$PROVISION" | head -1 | cut -d: -f1; }
# shellcheck disable=SC2016 # provision.sh's own lines, matched as text: their $… are that file's, never this shell's
{
    read_mem=$(line_of 'limits=$(factory_slice_limits "$(awk '"'"'$1 == "MemTotal:" { print $2 }'"'"' /proc/meminfo)") || exit 1')
    written=$(line_of '> "/etc/systemd/system/user-$factory_uid.slice.d/50-factory-limits.conf"')
    owned=$(line_of 'chown root:root "/etc/systemd/system/user-$factory_uid.slice.d/50-factory-limits.conf"')
    moded=$(line_of 'chmod 0644 "/etc/systemd/system/user-$factory_uid.slice.d/50-factory-limits.conf"')
    linger=$(line_of 'loginctl enable-linger "$FACTORY_USER"')
}
reload=$(awk -v w="${written:-0}" 'NR > w && /^systemctl daemon-reload$/ { print NR; exit }' "$PROVISION")
if [ -z "$read_mem" ]; then fail "provision.sh does not derive the limits from /proc/meminfo's MemTotal"; else ok "the limits come from MemTotal"; fi
if [ -z "$written" ] || [ -z "$owned" ] || [ -z "$moded" ]; then
    fail "provision.sh does not write a root-owned 0644 drop-in of user-\$factory_uid.slice"
else ok "a root-owned 0644 drop-in of factory's slice"; fi
if [ -n "$read_mem" ] && [ -n "$written" ] && [ -n "$reload" ] && [ -n "$linger" ] \
    && [ "$read_mem" -lt "$written" ] && [ "$written" -lt "$reload" ] && [ "$reload" -lt "$linger" ]; then
    ok "derived, written, reloaded, then factory's session"
else
    fail "the order is not MemTotal ($read_mem) < drop-in ($written) < daemon-reload ($reload) < enable-linger ($linger)"
fi

if [ "$failures" -gt 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "all passed"
