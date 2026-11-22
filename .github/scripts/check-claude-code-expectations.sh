#!/usr/bin/env bash
# ============================================================
# The Claude Code version the pinned factory expects equals the one this repository's images install (backlog #0-301
# AC6, ADR-0061 as amended 2026-11-22, ADR-0065).
#
#   .github/scripts/check-claude-code-expectations.sh <factory checkout> [<pin file>]
#
# `factory`'s claude-code/expectations.json holds claudeCodeVersion, the version every agent call's init event must
# show (the dispatcher stops a call on any other, ADR-0064 point 3); .devcontainer/claude-code.pin (the default pin
# file) holds CLAUDE_CODE_VERSION, the version the devcontainer image, and so every task container, installs. Both are
# this repository's choice: the second directly, the first through .factory/adapter.json's factoryVersion. So the
# checkout is `factory` at that version, the tag CI's step "The adapter keeps its factory version's schema" fetched and
# held to provision.sh's FACTORY_COMMIT, the code the build VM runs, never factory@main; and a difference always fails,
# as the gate contract's does (#0-280), since only a pull request here makes one: a Claude Code bump without a factory
# version that expects it, or a factory version moved to one that expects another. Without this the difference
# shows only at the first call on the VM, as a stopped task.
#
# The checkout is outside input, and what this prints goes to a public CI log (SEC-31): a symlink on the way to the file
# is refused before it is read, a file that does not parse is reported by jq's exit alone, and only the two versions,
# the subject of a finding, are printed. Fails closed: a missing file, a missing or malformed version, on either side,
# is an error. Exit 0 equal; 1 a finding (a difference, or a pinned version whose expectations are missing or malformed);
# 2 usage; 3 not checked: no checkout, or one with no tree of factory's (#0-278's step refused the tag before checking it
# out), told apart from a finding as check-gate-answers.mjs does (#0-280), so a red step names the step that failed
# first and never blames factory for a check that was not made. The pin is parsed as install-claude-code.sh's
# pin_value parses it; the tests run that function on the same pins, so the two cannot read different versions.
# Tests: test-check-claude-code-expectations.sh.
# ============================================================
set -euo pipefail

die() { echo "::error::$1 (backlog #0-301)"; exit 1; }
not_checked() { echo "::error::the Claude Code expectations were not checked: $1 (backlog #0-301)"; exit 3; }
[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: $0 <factory checkout> [<pin file>]" >&2; exit 2; }
checkout=$1
pin=${2:-.devcontainer/claude-code.pin}

# The pin file, read as install-claude-code.sh reads it: exactly one KEY= line, a trailing ` # comment` dropped.
[ -f "$pin" ] && [ ! -L "$pin" ] || die "$pin is not a regular file"
n=$(grep -c '^CLAUDE_CODE_VERSION=' "$pin" || true)
[ "$n" = 1 ] || die "$pin must have exactly one CLAUDE_CODE_VERSION= line (found $n)"
ours=$(sed -n 's/^CLAUDE_CODE_VERSION=//p' "$pin" | sed -E 's/[[:space:]]+#.*$//')
[[ "$ours" =~ ^[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}$ ]] || die "$pin's CLAUDE_CODE_VERSION is not x.y.z"

[ ! -L "$checkout" ] || die "$checkout is a symlink: refused, it could point outside the checkout"
[ -d "$checkout" ] || not_checked "$checkout is no checkout of factory at the pinned version (see the adapter's step)"
rel=claude-code/expectations.json
for p in dispatcher claude-code "$rel"; do
    [ ! -L "$checkout/$p" ] || die "factory's $p is a symlink: refused, it could point outside the checkout"
done
[ -d "$checkout/dispatcher" ] || not_checked "$checkout holds no tree of factory's (see the adapter's step)"
[ -f "$checkout/$rel" ] || die "factory at the pinned version has no $rel"
theirs=$(jq -er '.claudeCodeVersion | select(type == "string" and test("\\A[0-9]{1,6}\\.[0-9]{1,6}\\.[0-9]{1,6}\\z"))' \
    "$checkout/$rel" 2>/dev/null) \
    || die "factory's $rel does not parse, or its claudeCodeVersion is not x.y.z"

[ "$ours" = "$theirs" ] \
    || die "factory at the pinned version expects Claude Code $theirs, $pin installs $ours: move both in one pull request (a factory version that expects $ours, or the pin to $theirs)"
echo "factory at the pinned version expects Claude Code $theirs, the version $pin installs"
