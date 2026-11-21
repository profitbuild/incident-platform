#!/usr/bin/env bash
# ============================================================
# Installs Claude Code at the version claude-code.pin names, from a manifest Anthropic signed (backlog #0-249, #0-283,
# ADR-0065), or only checks the pin against that manifest.
#
#   install-claude-code.sh --pin <claude-code.pin> --keys <dir> --into <dir>   the image's build (as root)
#   install-claude-code.sh --pin <claude-code.pin> --keys <dir> --check        CI (lint-workflows in ci.yml)
#
# Both: the pin's four lines are read (never sourced) and their forms checked; <dir>/<CLAUDE_CODE_KEY>.asc must hold
# that key as its primary key; <version>/manifest.json and its detached manifest.json.sig are fetched, and the signature
# must be good and made by that key (gpg's VALIDSIG, its primary fingerprint), from a key neither revoked nor expired;
# the manifest's own `version` must be the pin's, and its checksum of linux-x64 and of linux-arm64 the pin's. So a
# hash in the pin that did not come from Anthropic's signed manifest fails, whoever wrote it.
# --into then downloads this machine's binary (linux-x64 or linux-arm64, by `uname -m`), compares its SHA-256 with the
# pin before anything runs it, and installs it as <dir>/claude, mode 0755: run as root, it is root's, and the agent
# user cannot replace it (ADR-0064's residual, the binary's part within one container).
# Not `install.sh | bash`: that script is fetched unpinned at build time and runs `claude install`, which lays the
# binary out under the user's ~/.local, where the agent can write.
#
# CLAUDE_CODE_RELEASES_URL (default https://downloads.claude.ai/claude-code-releases) exists for the tests
# (.github/scripts/test-install-claude-code.sh, file:// URLs); whatever it serves still has to be signed by the key.
# Needs bash, curl, jq, gpg, sha256sum (or shasum), uname. Nothing is left in <dir> on any failure.
# ============================================================
set -euo pipefail

usage() { echo "usage: $0 --pin <file> --keys <dir> (--into <dir> | --check)" >&2; exit 2; }
die() { echo "install-claude-code.sh: $*" >&2; exit 1; }

pin="" keys="" into="" check=no
while [ $# -gt 0 ]; do
    case "$1" in
        --pin) [ $# -ge 2 ] || usage; pin=$2; shift 2 ;;
        --keys) [ $# -ge 2 ] || usage; keys=$2; shift 2 ;;
        --into) [ $# -ge 2 ] || usage; into=$2; shift 2 ;;
        --check) check=yes; shift ;;
        *) usage ;;
    esac
done
[ -n "$pin" ] && [ -n "$keys" ] || usage
{ [ "$check" = yes ] && [ -z "$into" ]; } || { [ "$check" = no ] && [ -n "$into" ]; } || usage
[ -r "$pin" ] || die "cannot read $pin"

# pin_value <KEY> — the value of the one line `KEY=value`, without a trailing ` # comment` (the secret scan's
# gitleaks:allow on CLAUDE_CODE_KEY's line, ADR-0036); none, or more than one, is an error. Anything else after the
# value stays in it, and the value's own check below refuses it.
pin_value() {
    local n
    n=$(grep -c "^$1=" "$pin" || true)
    [ "$n" = 1 ] || die "$pin must have exactly one $1= line (found $n)"
    sed -n "s/^$1=//p" "$pin" | sed -E 's/[[:space:]]+#.*$//'
}
version=$(pin_value CLAUDE_CODE_VERSION)
fpr=$(pin_value CLAUDE_CODE_KEY)
sha_x64=$(pin_value CLAUDE_CODE_SHA256_LINUX_X64)
sha_arm64=$(pin_value CLAUDE_CODE_SHA256_LINUX_ARM64)
[[ "$version" =~ ^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$ ]] || die "CLAUDE_CODE_VERSION must be x.y.z, got '$version'"
[[ "$fpr" =~ ^[0-9A-F]{40}$ ]] || die "CLAUDE_CODE_KEY must be a 40-character uppercase fingerprint, got '$fpr'"
for s in "$sha_x64" "$sha_arm64"; do
    [[ "$s" =~ ^[0-9a-f]{64}$ ]] || die "a CLAUDE_CODE_SHA256_* value must be 64 lowercase hex characters, got '$s'"
done
key="$keys/$fpr.asc"
[ -r "$key" ] || die "no key file $key for CLAUDE_CODE_KEY"

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
base=${CLAUDE_CODE_RELEASES_URL:-https://downloads.claude.ai/claude-code-releases}
# https only, redirects included (--proto limits only the first request); file:// for the tests' releases.
fetch() { curl -fsSL --proto '=https,file' --proto-redir '=https' --max-time "${2:-60}" -o "$3" "$base/$version/$1" || die "cannot fetch $base/$version/$1"; }
fetch manifest.json 60 "$work/manifest.json"
fetch manifest.json.sig 60 "$work/manifest.json.sig"

g="$work/gnupg"
mkdir -m 700 "$g"
gpg --homedir "$g" --batch --quiet --import "$key" 2>/dev/null </dev/null || die "gpg cannot import $key"
# The key file's primary key is the pinned one: a file named by one fingerprint that holds another is refused, so the
# name in the pin is what verifies.
primaries=$(gpg --homedir "$g" --batch --with-colons --list-keys 2>/dev/null </dev/null |
    awk -F: '$1 == "pub" { p = 1; next } $1 == "fpr" && p { print $10; p = 0 }')
[ "$primaries" = "$fpr" ] || die "$key must hold exactly the key $fpr, holds: $(echo "$primaries" | tr '\n' ' ')"
# A good signature by that key (VALIDSIG's last field, the primary's fingerprint), and nothing gpg reports against it:
# a revoked or expired key, an expired signature, or a bad one anywhere in the file. A non-zero exit refuses too.
status=$(gpg --homedir "$g" --batch --status-fd 1 --verify "$work/manifest.json.sig" "$work/manifest.json" 2>/dev/null </dev/null) \
    || die "the signature of $version/manifest.json does not verify with $fpr"
signer=$(awk '$2 == "VALIDSIG" { print $NF; exit }' <<<"$status")
[ "$signer" = "$fpr" ] || die "$version/manifest.json is not signed by $fpr (signer: ${signer:-none})"
if grep -Eq '^\[GNUPG:\] (BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|KEYREVOKED)( |$)' <<<"$status"; then
    die "the signature of $version/manifest.json is not good: $(grep -E 'BADSIG|ERRSIG|EXPSIG|EXPKEYSIG|REVKEYSIG|KEYREVOKED' <<<"$status" | head -1)"
fi

manifest_version=$(jq -r '.version // empty' "$work/manifest.json") || die "$version/manifest.json is not JSON"
[ "$manifest_version" = "$version" ] || die "$version/manifest.json is the manifest of '$manifest_version', not $version"
for p in linux-x64:"$sha_x64" linux-arm64:"$sha_arm64"; do
    platform=${p%%:*} want=${p#*:}
    got=$(jq -r --arg p "$platform" '.platforms[$p].checksum // empty' "$work/manifest.json")
    [ "$got" = "$want" ] || die "the pin's $platform SHA-256 is $want, the signed manifest's is ${got:-missing}"
done

if [ "$check" = yes ]; then
    echo "claude-code.pin: Claude Code $version, linux-x64 and linux-arm64, as signed by $fpr."
    exit 0
fi

case "$(uname -m)" in
    x86_64|amd64) platform=linux-x64 want=$sha_x64 ;;
    aarch64|arm64) platform=linux-arm64 want=$sha_arm64 ;;
    *) die "no pinned Claude Code for machine $(uname -m)" ;;
esac
# The binary is about 370 MB: a longer limit than the manifest's.
fetch "$platform/claude" 900 "$work/claude"
got=$(sha256 "$work/claude")
[ "$got" = "$want" ] || die "the downloaded $platform binary's SHA-256 is $got, the pin's $want"
[ -d "$into" ] || die "$into is not a directory"
tmp="$into/claude.tmp.$$"
if ! install -m 0755 "$work/claude" "$tmp" || ! mv -f "$tmp" "$into/claude"; then
    rm -f "$tmp"
    die "cannot install into $into"
fi
echo "Installed Claude Code $version ($platform, SHA-256 $want) as $into/claude."
