#!/usr/bin/env bash
# ============================================================
# Tests for .devcontainer/install-claude-code.sh (backlog #0-249, #0-283, ADR-0065): Claude Code installed, or its pin
# checked, only from a manifest the pinned key signed, with the pin's version and checksums, and a binary whose
# SHA-256 is the pin's. A release is served from a temporary directory (CLAUDE_CODE_RELEASES_URL, file://), signed by
# keys generated here with the real gpg. Needs gpg, jq, curl: CI's runner has them; elsewhere without gpg the cases are
# reported as skipped, and in CI (CI=true) a missing gpg fails.
# Run: .github/scripts/test-install-claude-code.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT="$SRC/.devcontainer/install-claude-code.sh"
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

if ! command -v gpg >/dev/null 2>&1; then
    if [ "${CI:-}" = true ]; then echo "::error::gpg is not installed: the install script's tests need it"; exit 1; fi
    echo "test-install-claude-code.sh: skipped, gpg is not installed (CI runs these cases)"
    exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
G="$WORK/gnupg"; mkdir -m 700 "$G"
gen() { gpg --homedir "$G" --batch --quiet --passphrase '' --quick-gen-key "$1" ed25519 sign never 2>/dev/null
        gpg --homedir "$G" --batch --with-colons --fingerprint "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'; }
A=$(gen "Release A <a@example.test>")
B=$(gen "Other B <b@example.test>")
[ ${#A} -eq 40 ] && [ ${#B} -eq 40 ] || { echo "::error::could not generate the test keys"; exit 1; }

V=2.1.400
REL="$WORK/rel"
export CLAUDE_CODE_RELEASES_URL="file://$REL"
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

# release [<signing fingerprint>] [<manifest version>] — a release of $V: two binaries, a manifest listing their
# checksums, signed (detached) by the key given (A by default).
release() {
    local signer=${1:-$A} mv=${2:-$V} p
    rm -rf "$REL"; mkdir -p "$REL/$V/linux-x64" "$REL/$V/linux-arm64"
    for p in linux-x64 linux-arm64; do printf '#!/bin/sh\necho "%s (%s)"\n' "$V" "$p" > "$REL/$V/$p/claude"; done
    jq -n --arg v "$mv" --arg x "$(sha "$REL/$V/linux-x64/claude")" --arg a "$(sha "$REL/$V/linux-arm64/claude")" \
        '{version: $v, platforms: {"linux-x64": {checksum: $x}, "linux-arm64": {checksum: $a}, "darwin-arm64": {checksum: ("0" * 64)}}}' \
        > "$REL/$V/manifest.json"
    gpg --homedir "$G" --batch --quiet --yes --local-user "$signer" --detach-sign --output "$REL/$V/manifest.json.sig" "$REL/$V/manifest.json"
}
# pin [<field>=<value> ...] — writes $WORK/pin from the current release, with the fields given replaced.
pin() {
    local version=$V key=$A x a kv
    x=$(sha "$REL/$V/linux-x64/claude"); a=$(sha "$REL/$V/linux-arm64/claude")
    for kv in "$@"; do
        case "$kv" in version=*) version=${kv#*=} ;; key=*) key=${kv#*=} ;; x64=*) x=${kv#*=} ;; arm64=*) a=${kv#*=} ;; esac
    done
    # The key's line carries the allow comment the repository's pin does (ADR-0036).
    printf '# test pin\nCLAUDE_CODE_VERSION=%s\nCLAUDE_CODE_KEY=%s  # gitleaks:allow: a fingerprint\nCLAUDE_CODE_SHA256_LINUX_X64=%s\nCLAUDE_CODE_SHA256_LINUX_ARM64=%s\n' \
        "$version" "$key" "$x" "$a" > "$WORK/pin"
}
KEYS="$WORK/keys"
keys() { rm -rf "$KEYS"; mkdir -p "$KEYS"; }
keys; gpg --homedir "$G" --armor --export "$A" > "$KEYS/$A.asc"

# run <name> <expected exit> <text the output contains> <arguments...>
run() {
    local name=$1 want=$2 text=$3 out rc; shift 3
    out=$("$SCRIPT" "$@" 2>&1); rc=$?
    if [ "$rc" = "$want" ] && [[ "$out" == *"$text"* ]]; then ok "$name"
    else fail "$name: exit $rc (want $want), output: $(printf '%s' "$out" | head -c 400)"; fi
}
INTO="$WORK/into"
fresh_into() { rm -rf "$INTO"; mkdir -p "$INTO"; }
empty_into() { if [ -z "$(ls -A "$INTO")" ]; then ok "... and nothing was left in the target"; else fail "files left in the target: $(ls -A "$INTO")"; fi; }
case "$(uname -m)" in x86_64|amd64) MINE=linux-x64 ;; aarch64|arm64) MINE=linux-arm64 ;; *) MINE=unknown ;; esac

echo "install-claude-code.sh: a release the pinned key signed"
release; pin
run "--check passes on the signed manifest" 0 "Claude Code $V, linux-x64 and linux-arm64, as signed by $A" --pin "$WORK/pin" --keys "$KEYS" --check
if [ "$MINE" != unknown ]; then
    fresh_into
    run "--into installs this machine's binary" 0 "Installed Claude Code $V ($MINE" --pin "$WORK/pin" --keys "$KEYS" --into "$INTO"
    if cmp -s "$INTO/claude" "$REL/$V/$MINE/claude" && [ -x "$INTO/claude" ] && [ "$(ls -A "$INTO")" = claude ]; then
        ok "... as <dir>/claude, executable, the release's own bytes, nothing else"
    else fail "the installed binary is not the release's $MINE binary: $(ls -la "$INTO")"; fi
fi

echo "install-claude-code.sh: what does not come from the signed manifest"
pin x64="$(printf 'a%.0s' {1..64})"
fresh_into
run "a pinned linux-x64 hash the manifest does not list fails" 1 "the pin's linux-x64 SHA-256 is" --pin "$WORK/pin" --keys "$KEYS" --into "$INTO"
empty_into
pin arm64="$(printf 'b%.0s' {1..64})"
run "a pinned linux-arm64 hash the manifest does not list fails, in --check too" 1 "the pin's linux-arm64 SHA-256 is" --pin "$WORK/pin" --keys "$KEYS" --check
release; pin; printf ' ' >> "$REL/$V/manifest.json"
run "a manifest changed after it was signed fails" 1 "does not verify with $A" --pin "$WORK/pin" --keys "$KEYS" --check
release "$B"; pin
run "a manifest signed by another key fails" 1 "does not verify with $A" --pin "$WORK/pin" --keys "$KEYS" --check
release "$A" 2.1.399; pin
run "a signed manifest of another version fails" 1 "is the manifest of '2.1.399', not $V" --pin "$WORK/pin" --keys "$KEYS" --check
release; pin; rm "$REL/$V/manifest.json.sig"
run "a release without a signature fails" 1 "cannot fetch" --pin "$WORK/pin" --keys "$KEYS" --check
release; pin; printf 'not signed\n' > "$REL/$V/manifest.json.sig"
run "a signature file that is no signature fails" 1 "does not verify with $A" --pin "$WORK/pin" --keys "$KEYS" --check
if [ "$MINE" != unknown ]; then
    release; pin; printf 'replaced\n' > "$REL/$V/$MINE/claude"
    fresh_into
    run "a served binary that is not the pinned one fails" 1 "the downloaded $MINE binary's SHA-256 is" --pin "$WORK/pin" --keys "$KEYS" --into "$INTO"
    empty_into
fi

echo "install-claude-code.sh: the key"
release; pin
keys; gpg --homedir "$G" --armor --export "$B" > "$KEYS/$A.asc"
run "a key file named by the pin that holds another key fails" 1 "must hold exactly the key $A" --pin "$WORK/pin" --keys "$KEYS" --check
keys; gpg --homedir "$G" --armor --export "$A" "$B" > "$KEYS/$A.asc"
run "a key file that holds a second key besides the pinned one fails" 1 "must hold exactly the key $A" --pin "$WORK/pin" --keys "$KEYS" --check
keys
run "no key file for the pinned key fails" 1 "no key file" --pin "$WORK/pin" --keys "$KEYS" --check
# A revoked key: gpg 2.4 writes a revocation certificate for every key it generates; imported, it revokes A.
keys; R=$(mktemp -d); mkdir -m 700 "$R/g"
gpg --homedir "$G" --armor --export "$A" > "$R/a.asc"
gpg --homedir "$R/g" --batch --quiet --import "$R/a.asc" 2>/dev/null
sed 's/^:-----/-----/' "$G/openpgp-revocs.d/$A.rev" > "$R/a.rev"
gpg --homedir "$R/g" --batch --quiet --import "$R/a.rev" 2>/dev/null
gpg --homedir "$R/g" --armor --export "$A" > "$KEYS/$A.asc"
rm -rf "$R"
run "a manifest signed by a key since revoked fails (gpg exits 0 and reports REVKEYSIG)" 1 "is not good: [GNUPG:] REVKEYSIG" --pin "$WORK/pin" --keys "$KEYS" --check
keys; gpg --homedir "$G" --armor --export "$A" > "$KEYS/$A.asc"

echo "install-claude-code.sh: the pin's form"
release
pin version=latest
run "a version that is not x.y.z fails" 1 "CLAUDE_CODE_VERSION must be x.y.z" --pin "$WORK/pin" --keys "$KEYS" --check
pin key="$(printf '%s' "$A" | tr 'A-F' 'a-f')"
run "a fingerprint not in uppercase fails" 1 "40-character uppercase fingerprint" --pin "$WORK/pin" --keys "$KEYS" --check
pin x64=abc
run "a hash that is not 64 hex fails" 1 "64 lowercase hex" --pin "$WORK/pin" --keys "$KEYS" --check
pin; sed -i.bak '/^CLAUDE_CODE_SHA256_LINUX_ARM64=/d' "$WORK/pin"
run "a missing line fails" 1 "exactly one CLAUDE_CODE_SHA256_LINUX_ARM64= line (found 0)" --pin "$WORK/pin" --keys "$KEYS" --check
pin; printf 'CLAUDE_CODE_VERSION=%s\n' "$V" >> "$WORK/pin"
run "a line given twice fails" 1 "exactly one CLAUDE_CODE_VERSION= line (found 2)" --pin "$WORK/pin" --keys "$KEYS" --check
pin
# The command substitution is meant literally: it must reach the pin file unexpanded, and never run.
# shellcheck disable=SC2016
printf 'CLAUDE_CODE_VERSION=$(touch %s/sourced)\n' "$WORK" > "$WORK/pin.x"
grep -v '^CLAUDE_CODE_VERSION=' "$WORK/pin" >> "$WORK/pin.x"
run "a pin is read, never run" 1 "CLAUDE_CODE_VERSION must be x.y.z" --pin "$WORK/pin.x" --keys "$KEYS" --check
if [ ! -e "$WORK/sourced" ]; then ok "... and nothing in it ran"; else fail "a command in the pin ran"; fi
pin; sed -i.bak 's/^\(CLAUDE_CODE_SHA256_LINUX_X64=[0-9a-f]*\)$/\1 trailing/' "$WORK/pin"
run "text after a value that is not a ' # comment' fails" 1 "64 lowercase hex" --pin "$WORK/pin" --keys "$KEYS" --check
pin; sed -i.bak 's/^\(CLAUDE_CODE_SHA256_LINUX_X64=[0-9a-f]*\)$/\1#nospace/' "$WORK/pin"
run "a '#' with no space before it is part of the value, and fails" 1 "64 lowercase hex" --pin "$WORK/pin" --keys "$KEYS" --check
run "no pin file fails" 1 "cannot read" --pin "$WORK/no-such-pin" --keys "$KEYS" --check

echo "install-claude-code.sh: usage"
pin
run "--check and --into together are refused" 2 "usage" --pin "$WORK/pin" --keys "$KEYS" --check --into "$INTO"
run "neither --check nor --into is refused" 2 "usage" --pin "$WORK/pin" --keys "$KEYS"
run "no --keys is refused" 2 "usage" --pin "$WORK/pin" --check
run "an unknown option is refused" 2 "usage" --pin "$WORK/pin" --keys "$KEYS" --check --force

if [ "$failures" -ne 0 ]; then echo "$failures install-claude-code.sh test(s) failed."; exit 1; fi
echo "All install-claude-code.sh tests passed."
