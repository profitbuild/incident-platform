#!/usr/bin/env bash
# ============================================================
# Tests for .github/scripts/check-protected-paths.sh: it passes on the repository's own files and fails when
# the settings miss a deny rule, when the hook lets a write through, when CODEOWNERS misses an owner-only
# path, or when the list cannot be read; and, the other way (backlog #0-168), when a copy protects a path the
# list lacks, or the hook's line is not one flat alternation. Those cases name the message they must give, so a
# case cannot pass on another rule's refusal.
# Run: .github/scripts/test-protected-paths.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
CHECK="$SRC/.github/scripts/check-protected-paths.sh"

# expect <0|1> <name> <args...>   (run from the repository root, like CI)
expect() {
    local want=$1 name=$2; shift 2
    local rc
    (cd "$SRC" && "$CHECK" "$@" >/dev/null 2>&1); rc=$?
    if [ "$rc" -eq "$want" ]; then echo "  ok: $name"; else echo "::error::$name: expected exit $want, got $rc"; failures=$((failures+1)); fi
}

# expect_msg <name> <regex the output must match> <args...> — exit 1 with that message.
expect_msg() {
    local name=$1 re=$2 out rc; shift 2
    out=$(cd "$SRC" && "$CHECK" "$@" 2>&1); rc=$?
    if [ "$rc" -eq 1 ] && grep -qE -- "$re" <<<"$out"; then echo "  ok: $name"
    else echo "::error::$name: expected exit 1 and /$re/, got $rc: $out"; failures=$((failures+1)); fi
}
HOOK=$SRC/.claude/hooks/guard-protected-bash.sh
SETTINGS=$SRC/.claude/settings.autopilot.json

echo "check-protected-paths"
expect 0 "the repository's own copies cover the list"

jq '.permissions.deny |= map(select(. != "Write(./.github/**)"))' "$SRC/.claude/settings.autopilot.json" > "$WORK/no-write.json"
expect 1 "a missing Write deny fails" "$WORK/no-write.json"

jq '.permissions.deny |= map(select(. != "Edit(./mvnw)"))' "$SRC/.claude/settings.autopilot.json" > "$WORK/no-edit.json"
expect 1 "a missing deny for a build-config file fails" "$WORK/no-edit.json"

printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$WORK/open-hook.sh"
expect 1 "a hook that lets writes through fails" "$SRC/.claude/settings.autopilot.json" "$WORK/open-hook.sh"

# The shadow-mode catch-all (`*`, backlog #0-113) still matches the path, and does not count as its rule.
grep -v '^/.ai/audit/decisions.md' "$SRC/.github/CODEOWNERS" > "$WORK/CODEOWNERS-missing"
expect 1 "a protected path without a CODEOWNERS rule fails" "$SRC/.claude/settings.autopilot.json" "$SRC/.claude/hooks/guard-protected-bash.sh" "$WORK/CODEOWNERS-missing"

printf '/.ai/   @owner\n/.claude/ @owner\n/.github/ @owner\n/architecture-tests/ @owner\n/AGENTS.md @owner\n/scripts/ @owner\n/.devcontainer/ @owner\n/.factory/ @owner\n' > "$WORK/CODEOWNERS-parents"
expect 0 "a rule for a directory above covers it" "$SRC/.claude/settings.autopilot.json" "$SRC/.claude/hooks/guard-protected-bash.sh" "$WORK/CODEOWNERS-parents"

{ cat "$SRC/.github/CODEOWNERS"; echo '/.github/workflows/'; } > "$WORK/CODEOWNERS-unowned"
expect 1 "a later narrower line without an owner fails (last match wins)" "$SRC/.claude/settings.autopilot.json" "$SRC/.claude/hooks/guard-protected-bash.sh" "$WORK/CODEOWNERS-unowned"

{ echo '/.github/workflows/'; cat "$SRC/.github/CODEOWNERS"; } > "$WORK/CODEOWNERS-unowned-first"
expect 0 "an unowned line before the owned one is overridden" "$SRC/.claude/settings.autopilot.json" "$SRC/.claude/hooks/guard-protected-bash.sh" "$WORK/CODEOWNERS-unowned-first"

printf '* @owner\n' > "$WORK/CODEOWNERS-star"
# The shadow-mode catch-all (backlog #0-113) is not a protected path's own rule: removed in phase 3, it would take
# every path with it.
expect 1 "a global * rule alone is no path's own rule" "$SRC/.claude/settings.autopilot.json" "$SRC/.claude/hooks/guard-protected-bash.sh" "$WORK/CODEOWNERS-star"

{ cat "$SRC/.github/CODEOWNERS"; echo '*'; } > "$WORK/CODEOWNERS-star-last"
expect 1 "a last * line without an owner takes every review away" "$SRC/.claude/settings.autopilot.json" "$SRC/.claude/hooks/guard-protected-bash.sh" "$WORK/CODEOWNERS-star-last"

echo "check-protected-paths: the other way, nothing in a copy the list lacks (backlog #0-168)"
jq '.permissions.deny += ["Edit(./.zshrc)", "Write(./.zshrc)"]' "$SETTINGS" > "$WORK/extra-deny.json"
expect_msg "a deny of a path the list lacks fails" 'denies Edit\(\./\.zshrc\), but .* lists no \.zshrc' "$WORK/extra-deny.json"
jq '.permissions.deny += ["Edit(./.node-version/**)"]' "$SETTINGS" > "$WORK/dir-deny.json"
expect_msg "a deny of a file entry as a directory fails" 'lists no \.node-version/' "$WORK/dir-deny.json"
jq '.permissions.deny += ["Edit(**/.zshrc)"]' "$SETTINGS" > "$WORK/odd-deny.json"
expect_msg "a path deny in another spelling than ./ fails" 'denies Edit\(\*\*/\.zshrc\): write a path deny as Edit\(\./' "$WORK/odd-deny.json"
jq '.permissions.deny += ["Bash(rm -rf *)", "Read(./secret.txt)"]' "$SETTINGS" > "$WORK/other-deny.json"
expect 0 "denies of other tools are not paths of the list" "$WORK/other-deny.json"
sed -E "s#^protected='\\(#protected='(\\.zshrc|#" "$HOOK" > "$WORK/extra-hook.sh"
expect_msg "a hook alternative the list lacks fails" 'protects \.zshrc, but .* lists no \.zshrc' "$SETTINGS" "$WORK/extra-hook.sh"
sed -E 's#\\.ai/runs/LOCK\|\\.ai/runs/state\\.json#\\.ai/runs/(LOCK|state\\.json)#' "$HOOK" > "$WORK/group-hook.sh"
grep -q 'runs/(LOCK' "$WORK/group-hook.sh" || { echo "::error::the group case did not change the hook"; failures=$((failures+1)); }
expect_msg "a group inside the hook's alternation fails" 'one flat alternation' "$SETTINGS" "$WORK/group-hook.sh"
grep -v "^protected='" "$HOOK" > "$WORK/no-line-hook.sh"
expect_msg "a hook without its protected= line fails" "expected exactly one line protected=" "$SETTINGS" "$WORK/no-line-hook.sh"

echo '{"permissions":{"deny":[]}}' > "$WORK/empty.json"
expect 1 "settings without deny rules fail" "$WORK/empty.json"

# The list itself unreadable: a copy of the repository without the file.
git clone -q "$SRC" "$WORK/clone" 2>/dev/null || cp -R "$SRC" "$WORK/clone"
cp "$SRC/scripts/factory/_protected.sh" "$WORK/clone/scripts/factory/"
cp "$CHECK" "$WORK/clone/.github/scripts/"
cp "$SRC/.claude/settings.autopilot.json" "$WORK/clone/.claude/"
cp "$SRC/.claude/hooks/guard-protected-bash.sh" "$WORK/clone/.claude/hooks/"
# A runtime path dropped from the list while both copies still protect it (backlog #0-168).
# The backticks are the list's Markdown, matched literally (backlog #0-168).
# shellcheck disable=SC2016
grep -v '^- `\.ai/STOP`' "$SRC/.ai/rules/protected-paths.md" > "$WORK/clone/.ai/rules/protected-paths.md"
out=$(cd "$WORK/clone" && .github/scripts/check-protected-paths.sh 2>&1); rc=$?
if [ "$rc" -eq 1 ] && grep -q 'denies Edit(./.ai/STOP)' <<<"$out" && grep -q 'protects .ai/STOP' <<<"$out"; then echo "  ok: a path dropped from the list, still in both copies, fails"
else echo "::error::a path dropped from the list: expected exit 1 naming both copies, got $rc: $out"; failures=$((failures+1)); fi
rm -f "$WORK/clone/.ai/rules/protected-paths.md"
rc=0; (cd "$WORK/clone" && .github/scripts/check-protected-paths.sh >/dev/null 2>&1) || rc=$?
if [ "$rc" -eq 1 ]; then echo "  ok: no list: fail closed"; else echo "::error::no list: expected exit 1, got $rc"; failures=$((failures+1)); fi

if [ "$failures" -gt 0 ]; then echo "$failures protected-path test(s) failed"; exit 1; fi
echo "All protected-path tests passed."
