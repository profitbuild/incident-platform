#!/usr/bin/env bash
# ============================================================
# Tests .github/scripts/check-claude-code-expectations.sh (backlog #0-301 AC6): one temporary directory per case,
# holding a pin file and a `factory` checkout cut down to claude-code/expectations.json. Every case names the exit
# status and the text the output must contain, so a case cannot pass on another finding.
#
# Run by the lint-workflows job in .github/workflows/ci.yml, before the check; locally:
#   .github/scripts/test-check-claude-code-expectations.sh
# ============================================================
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECKER=$HERE/check-claude-code-expectations.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
passed=0
n=0
dir=""
MARKER=MarkerThatMustNotReachTheLog

# fresh: a new case whose pin and expectations agree on 2.1.328, the pin with its real file's comment shape.
fresh() {
    n=$((n+1)); dir="$WORK/case$n"
    mkdir -p "$dir/factory/claude-code" "$dir/factory/dispatcher"
    printf '%s\n' '# The pin.' 'CLAUDE_CODE_VERSION=2.1.328' \
        'CLAUDE_CODE_KEY=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE  # gitleaks:allow: a public fingerprint, no secret' \
        > "$dir/claude-code.pin"
    expectations '"2.1.328"'
}
expectations() { printf '{ "claudeCodeVersion": %s, "builtinPlugins": [] }\n' "$1" > "$dir/factory/claude-code/expectations.json"; }

# expect <name> <exit status> <text the output must contain> [<args>...]: args default to the case's checkout and pin.
expect() {
    local name=$1 want=$2 text=$3 rc=0 out; shift 3
    [ $# -gt 0 ] || set -- "$dir/factory" "$dir/claude-code.pin"
    out=$("$CHECKER" "$@" 2>&1) || rc=$?
    if [ "$rc" -ne "$want" ]; then echo "::error::$name: exit $rc, not $want: $out"; failures=$((failures+1)); return; fi
    case "$out" in
        *"$MARKER"*) echo "::error::$name: the output carries the file's text: $out"; failures=$((failures+1)) ;;
        *"$text"*) echo "  ok: $name"; passed=$((passed+1)) ;;
        *) echo "::error::$name: the output does not contain '$text': $out"; failures=$((failures+1)) ;;
    esac
}

echo "check-claude-code-expectations.sh: equal"
fresh; expect "the pin and the expectations agree" 0 "expects Claude Code 2.1.328, the version"

echo "check-claude-code-expectations.sh: a difference always fails"
fresh; expectations '"2.1.330"'
expect "factory expects a newer version than the pin" 1 \
    "::error::factory at the pinned version expects Claude Code 2.1.330, $dir/claude-code.pin installs 2.1.328"
fresh; sed 's/^CLAUDE_CODE_VERSION=.*/CLAUDE_CODE_VERSION=2.1.340/' "$dir/claude-code.pin" > "$dir/p" && mv "$dir/p" "$dir/claude-code.pin"
expect "the pin bumped, factory behind" 1 "expects Claude Code 2.1.328, $dir/claude-code.pin installs 2.1.340"
fresh; expectations '"v2.1.328"'
expect "a version with a v is malformed, not equal" 1 "its claudeCodeVersion is not x.y.z"

echo "check-claude-code-expectations.sh: fails closed"
fresh; rm "$dir/factory/claude-code/expectations.json"
expect "a factory version with no expectations" 1 "factory at the pinned version has no claude-code/expectations.json"
fresh; printf '{ "builtinPlugins": [] }\n' > "$dir/factory/claude-code/expectations.json"
expect "expectations without claudeCodeVersion" 1 "its claudeCodeVersion is not x.y.z"
fresh; expectations 2.1
expect "a number, not a string" 1 "its claudeCodeVersion is not x.y.z"
fresh; printf '{ "claudeCodeVersion": %s\n' "$MARKER" > "$dir/factory/claude-code/expectations.json"
expect "expectations that do not parse, quoted nowhere" 1 "does not parse"
fresh; printf '%s\n' "$MARKER" > "$dir/outside.json"; rm "$dir/factory/claude-code/expectations.json"
ln -s "$dir/outside.json" "$dir/factory/claude-code/expectations.json"
expect "a symlinked expectations file is refused before it is read" 1 "claude-code/expectations.json is a symlink"
fresh; mv "$dir/factory/claude-code" "$dir/elsewhere"; ln -s "$dir/elsewhere" "$dir/factory/claude-code"
expect "a symlinked claude-code directory is refused" 1 "factory's claude-code is a symlink"
echo "check-claude-code-expectations.sh: a check not made is not a finding (exit 3, as #0-280's)"
fresh; expect "no checkout" 3 "were not checked: $dir/none is no checkout" "$dir/none" "$dir/claude-code.pin"
fresh; mkdir -p "$dir/init-only/.git"
expect "a checkout the adapter's step refused before checking out (git init alone)" 3 "holds no tree of factory's" \
    "$dir/init-only" "$dir/claude-code.pin"
fresh; ln -s "$dir/factory" "$dir/linked"
expect "a symlinked checkout is refused, not taken as not checked" 1 "is a symlink" "$dir/linked" "$dir/claude-code.pin"
fresh; mv "$dir/factory/dispatcher" "$dir/elsewhere-d"; ln -s "$dir/elsewhere-d" "$dir/factory/dispatcher"
expect "a symlinked dispatcher directory is refused" 1 "factory's dispatcher is a symlink"
fresh; printf '%s\n' 'CLAUDE_CODE_VERSION=2.1.328' 'CLAUDE_CODE_VERSION=2.1.329' > "$dir/claude-code.pin"
expect "a pin with two version lines" 1 "must have exactly one CLAUDE_CODE_VERSION= line (found 2)"
fresh; printf '%s\n' 'CLAUDE_CODE_KEY=x' > "$dir/claude-code.pin"
expect "a pin with no version line" 1 "must have exactly one CLAUDE_CODE_VERSION= line (found 0)"
fresh; printf '%s\n' 'CLAUDE_CODE_VERSION=latest' > "$dir/claude-code.pin"
expect "a pin whose version is not x.y.z" 1 "CLAUDE_CODE_VERSION is not x.y.z"
fresh; expect "a missing pin file" 1 "is not a regular file" "$dir/factory" "$dir/none.pin"
fresh; expect "three arguments" 2 "usage:" "$dir/factory" "$dir/claude-code.pin" extra
rc=0; out=$("$CHECKER" 2>&1) || rc=$?
if [ "$rc" -eq 2 ] && [[ "$out" == *usage:* ]]; then echo "  ok: no argument at all"; passed=$((passed+1)); else echo "::error::no argument: exit $rc: $out"; failures=$((failures+1)); fi

echo "check-claude-code-expectations.sh: the pin read as install-claude-code.sh reads it"
# The installer's own pin_value, taken from install-claude-code.sh and run on the same pins as the check: if either
# parser changes alone, the version the check compares and the one the image installs part, and this fails. The real
# pin first, then the shapes its header allows (a trailing comment, spaces before it).
INSTALLER=$HERE/../../.devcontainer/install-claude-code.sh
REAL_PIN=$HERE/../../.devcontainer/claude-code.pin
pin_value_src=$(sed -n '/^pin_value() {$/,/^}$/p' "$INSTALLER")
if [ -z "$pin_value_src" ]; then
    echo "::error::install-claude-code.sh has no pin_value() to compare with"; failures=$((failures+1))
else
    for shape in real comment spaces; do
        fresh
        case $shape in
            real) cp "$REAL_PIN" "$dir/claude-code.pin" ;;
            comment) printf '%s\n' 'CLAUDE_CODE_VERSION=2.1.400 # a comment' > "$dir/claude-code.pin" ;;
            spaces) printf '%s\n' 'CLAUDE_CODE_VERSION=2.1.401	   # tab and spaces' > "$dir/claude-code.pin" ;;
        esac
        # shellcheck disable=SC2034,SC2329 # pin and die are read by the installer's pin_value, run by the eval
        installs=$(pin="$dir/claude-code.pin"; die() { echo "die: $*"; }; eval "$pin_value_src"; pin_value CLAUDE_CODE_VERSION)
        expectations "\"$installs\""
        expect "the check reads the version install-claude-code.sh installs ($shape pin: $installs)" 0 \
            "expects Claude Code $installs, the version"
    done
fi

if [ "$failures" -gt 0 ]; then echo "$failures check-claude-code-expectations case(s) failed"; exit 1; fi
echo "All $passed check-claude-code-expectations cases passed."
