#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory/check-queue.sh and scripts/factory/next-item.sh, in a temporary repository
# with a small backlog. `gh` is replaced by a stub that prints the branches of open PRs from a file.
# Run: .github/scripts/test-queue.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

# expect_jq <name> <json> <jq expression that must be true>
expect_jq() {
    if printf '%s' "$2" | jq -e "$3" >/dev/null 2>&1; then ok "$1"; else fail "$1: '$3' is false for: $(printf '%s' "$2" | head -c 600)"; fi
}

mkdir -p "$WORK/repo/scripts/factory" "$WORK/repo/.ai/plan" "$WORK/repo/.ai/rules" "$WORK/bin"
cp "$SRC"/scripts/factory/_common.sh "$SRC"/scripts/factory/_backlog.sh "$SRC"/scripts/factory/_protected.sh "$SRC"/scripts/factory/check-queue.sh "$SRC"/scripts/factory/next-item.sh "$WORK/repo/scripts/factory/"
cp "$SRC"/.ai/rules/protected-paths.md "$WORK/repo/.ai/rules/"
printf '#!/bin/sh\ncat "%s/open-prs" 2>/dev/null; [ ! -f "%s/gh-fails" ]\n' "$WORK" "$WORK" > "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
: > "$WORK/open-prs"
export PATH="$WORK/bin:$PATH"

cd "$WORK/repo" || exit 1
git init -q -b main
printf '.ai/runs/\n' > .gitignore

backlog() {   # backlog <autopilot of 0-8>
cat > BACKLOG.md <<EOF
# Backlog

## Open items

| # | Title | Type | Priority | Status |
|---|---|---|---|---|
| [0-1](#0-1-a) | One | bug | High | Open |
| [0-2](#0-2-b) | Two | bug | Medium | Open |
| [0-3](#0-3-c) | Three | tech-debt | Low | Open |
| [0-4](#0-4-d) | Four | tech-debt | Medium | Open |
| [0-5](#0-5-e) | Five | ci | High | Open |
| [0-6](#0-6-f) | Six | design | High | Open |
| [0-7](#0-7-g) | Seven | tech-debt | Low | Open |
| [0-8](#0-8-h) | Eight | tech-debt | Low | Open |
| [0-10](#0-10-j) | Ten | tech-debt | Low | Open |
| [0-11](#0-11-k) | Eleven | tech-debt | Low | Open |
| [0-12](#0-12-l) | Twelve | bug | Low | Open |
| [0-13](#0-13-m) | Thirteen | bug | Low | Open |
| [0-14](#0-14-n) | Fourteen | bug | Low | Open |
| [0-15](#0-15-o) | Fifteen | bug | Low | Open |
| [0-16](#0-16-p) | Sixteen | bug | Low | Open |
| [0-17](#0-17-q) | Seventeen | bug | Low | Open |
| [0-18](#0-18-r) | Eighteen | bug | Low | In progress |
| [0-19](#0-19-s) | Nineteen | secruity | Low | Open |

---

### 0-1. One

**Type:** bug · **Priority:** High · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** incident-service (incident.fsm)

### 0-2. Two

**Type:** bug · **Priority:** Medium · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** #0-1
**Touches:** incident-service (incident.api)

### 0-3. Three

**Type:** tech-debt · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** oncall-service

### 0-4. Four

**Type:** tech-debt · **Priority:** Medium · **Status:** Open
**Autopilot:** not-ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** notification-service

### 0-5. Five

**Type:** ci · **Priority:** High · **Status:** Open
**Autopilot:** human-only · **Risk:** high · **Complexity:** low · **Depends on:** —

### 0-6. Six

**Type:** design · **Priority:** High · **Status:** Open
**Autopilot:** ready · **Risk:** high · **Complexity:** low · **Depends on:** —

### 0-7. Seven

**Type:** tech-debt · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** shared (tenant)

### 0-8. Eight

**Type:** tech-debt · **Priority:** Low · **Status:** Open
**Autopilot:** $1 · **Risk:** low · **Complexity:** low · **Depends on:** #0-9 · **Follow-up of:** #0-9
**Touches:** escalation-service

### 0-10. Ten

**Type:** tech-debt · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** frontend

### 0-11. Eleven

**Type:** tech-debt · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —

### 0-12. Twelve

**Type:** bug · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** high · **Complexity:** medium · **Depends on:** —
**Touches:** k8s (overlays/dev), ci (.github/scripts, .github/workflows/ci.yml)

### 0-13. Thirteen

**Type:** bug · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** incident-service (incident.api)

**Acceptance criteria.**
AC1. The endpoint answers 404 for another tenant.
AC2. The existing check .github/scripts/check-tenant-status-config.sh still passes.

### 0-14. Fourteen

**Type:** bug · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** root (CLAUDE.md "Commands")

### 0-15. Fifteen

**Type:** bug · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** root (mvnw, .mvn/wrapper)

### 0-16. Sixteen

**Type:** bug · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** k8s (overlays/dev), ci

### 0-17. Seventeen

**Type:** bug · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** high · **Complexity:** low · **Depends on:** —
**Touches:** root (scripts/factory)

### 0-18. Eighteen

**Type:** bug · **Priority:** Low · **Status:** In progress — autopilot run 20261101-000000. Quotes **Status:** Open.
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** oncall-service

### 0-19. Nineteen

**Type:** secruity · **Priority:** Low · **Status:** Open
**Autopilot:** ready · **Risk:** low · **Complexity:** low · **Depends on:** —
**Touches:** oncall-service
EOF
}
backlog proposed
cat > BACKLOG-DONE.md <<'EOF'
| # | Title | Delivered in |
|---|---|---|
| 0-9 | Nine | PR #1 |
EOF

queue() {     # queue <item> ...   (rows in this order)
    { echo '# Execution queue'; echo; echo '<!-- queue:start -->'
      echo '| # | Item | Why here |'; echo '|---|---|---|'
      n=0; for item in "$@"; do n=$((n+1)); echo "| $n | #$item | because |"; done
      echo '<!-- queue:end -->'; } > .ai/plan/queue.md
}
commit() { git add -A >/dev/null && git -c user.email=t@t -c user.name=t commit -q -m "${1:-x}" --allow-empty && git rev-parse HEAD; }
CQ=scripts/factory/check-queue.sh
NI=scripts/factory/next-item.sh

echo "check-queue"
expect_jq "no queue file is valid"         "$($CQ)" '.valid and (.present | not)'
queue 0-1 0-2 0-3;                         expect_jq "dependency before dependant"   "$($CQ)" '.valid and .openRows == 3'
queue 0-2 0-1;                             expect_jq "dependency queued after"       "$($CQ)" '(.valid | not) and (.errors | any(test("queued after")))'
queue 0-2;                                 expect_jq "dependency missing"            "$($CQ)" '(.valid | not) and (.errors | any(test("neither done nor queued")))'
# A finished item's section under "## Details" that holds a table row of the open 0-1: not a done row.
cp BACKLOG-DONE.md BACKLOG-DONE.bak
printf '\n## Details\n\n### 0-9. Nine\n\n| 0-1 | quoted in a table of its own | PR #2 |\n' >> BACKLOG-DONE.md
queue 0-2;                                 expect_jq "a row under Details is not done" "$($CQ)" '(.valid | not) and (.errors | any(test("neither done nor queued")))'
# Details long enough that a reader which stops at the heading would close the pipe on `cat` (SIGPIPE): the done table
# above it must still be read (0-9 done, so queueing it alone is valid).
for _ in $(seq 20000); do echo "filler line of a long finished section"; done >> BACKLOG-DONE.md
queue 0-9;                                 expect_jq "a long Details still reads the table" "$($CQ)" '.valid and .openRows == 0'
mv BACKLOG-DONE.bak BACKLOG-DONE.md
queue 0-7 0-3;                             expect_jq "shared next to others is fine" "$($CQ)" '.valid'
queue 0-5;                                 expect_jq "human-only queued"             "$($CQ)" '(.valid | not) and (.errors | any(test("human-only")))'
queue 0-6;                                 expect_jq "design item queued"            "$($CQ)" '(.valid | not) and (.errors | any(test("design item")))'
queue 0-19;                                expect_jq "type with no branch prefix queued" "$($CQ)" '(.valid | not) and (.errors | any(test("type \\(Type: secruity\\) has no branch prefix")))'
queue 0-99;                                expect_jq "unknown item"                  "$($CQ)" '(.valid | not) and (.errors | any(test("neither an open item")))'
queue 0-1 0-1;                             expect_jq "item twice"                    "$($CQ)" '(.valid | not) and (.errors | any(test("queued 2 times")))'
queue 0-9 0-3;                             expect_jq "done item stays valid"         "$($CQ)" '.valid and .openRows == 1'
queue 0-10;                                expect_jq "unknown module"                "$($CQ)" '(.valid | not) and (.errors | any(test("unknown module")))'
queue 0-11;                                expect_jq "no Touches is a warning"       "$($CQ)" '.valid and (.warnings | any(test("not be measured")))'
queue 0-12;                                expect_jq "protected path in Touches"     "$($CQ)" '(.valid | not) and (.errors | any(test("#0-12 names \\.github in Touches")))'
queue 0-15;                                expect_jq "build config in Touches"       "$($CQ)" '(.valid | not) and (.errors | any(test("#0-15 names \\.mvn, mvnw ")))'
queue 0-16;                                expect_jq "a bare ci in Touches"          "$($CQ)" '(.valid | not) and (.errors | any(test("#0-16 names ci \\(no path given\\)")))'
queue 0-17;                                expect_jq "a directory without its slash" "$($CQ)" '(.valid | not) and (.errors | any(test("#0-17 names scripts/factory in")))'
queue 0-13 0-14;                           expect_jq "a criterion may refer to .github/; CLAUDE.md blocks are the implementer's" "$($CQ)" '.valid'
queue 0-4;                                 expect_jq "not-ready is a warning"        "$($CQ)" '.valid and (.warnings | any(test("queue stops at it")))'
printf '| 1 | #0-1 | x |\n' > .ai/plan/queue.md; expect_jq "markers missing"     "$($CQ)" '(.valid | not) and (.errors | any(test("queue:start")))'
printf '<!-- queue:start -->\n| # | Item | Why here |\n|---|---|---|\n| 1 | soon | x |\n<!-- queue:end -->\n' > .ai/plan/queue.md
expect_jq "row without an id"              "$($CQ)" '(.valid | not) and (.errors | any(test("no backlog item id")))'
queue 0-1; base=$(commit q1); rm .ai/plan/queue.md
expect_jq "--ref reads the commit, not the tree" "$($CQ --ref "$base")" '.valid and .present and .rows == 1'

echo "next-item"
rm -f .ai/plan/queue.md; base=$(commit noqueue)
expect_jq "no queue: priority order"            "$($NI "$base")" '.ok and .item == "#0-1" and .source == "priority" and .type == "bug" and .branchPrefix == "fix"'
expect_jq "manual item with an open dependency" "$($NI "$base" 0-2)" '.ok and .item == null and (.reason | test("waits for #0-1"))'
expect_jq "manual item that can start"          "$($NI "$base" 0-3)" '.ok and .item == "#0-3" and .source == "manual" and .modules == ["oncall-service"] and .risk == "low" and .complexity == "low" and .type == "tech-debt" and .branchPrefix == "refactor"'
expect_jq "manual item that is human-only"      "$($NI "$base" 0-5)" '.ok and .item == null and (.reason | test("not ready"))'
expect_jq "protected path in Touches: no start" "$($NI "$base" 0-12)" '.ok and .item == null and (.reason | test("Touches names \\.github, a path the autopilot may not write"))'
expect_jq "a criterion naming .github/: starts" "$($NI "$base" 0-13)" '.ok and .item == "#0-13"'
expect_jq "CLAUDE.md agent-editable: starts"    "$($NI "$base" 0-14)" '.ok and .item == "#0-14"'
# start-item.sh starts only an Open item: chosen here and refused there, it would come back on every run (#0-209).
expect_jq "ready but not Open: no start"        "$($NI "$base" 0-18)" '.ok and .item == null and (.reason | test("its status is not Open \\(Status: In progress"))'
# The branch's prefix comes from the type (backlog #0-195): a type with none is not chosen, not given a guessed prefix.
expect_jq "a type with no branch prefix: no start" "$($NI "$base" 0-19)" '.ok and .item == null and (.reason | test("its type \\(Type: secruity\\) has no branch prefix"))'
queue 0-3 0-1; base=$(commit q)
expect_jq "first queue row"                     "$($NI "$base")" '.ok and .item == "#0-3" and .source == "queue" and .position == 1'
queue 0-9 0-3 0-1; base=$(commit q1b)
expect_jq "done rows are skipped"               "$($NI "$base")" '.ok and .item == "#0-3" and .position == 2'
queue 0-4 0-1; base=$(commit q2)
expect_jq "a not-ready row stops the queue"     "$($NI "$base")" '.ok and .item == null and (.reason | test("#0-4")) and (.skipped[0].item == "#0-4")'
queue 0-3 0-1; base=$(commit q2b)
echo "fix/0-3-three" > "$WORK/open-prs"
expect_jq "an open PR stops the queue"          "$($NI "$base")" '.ok and .item == null and (.reason | test("in progress"))'
: > "$WORK/open-prs"
git branch -q refactor/0-3-left-over
expect_jq "a local branch is a lock too"        "$($NI "$base")" '.ok and .item == null'
git branch -q -D refactor/0-3-left-over
queue 0-9; base=$(commit q3)
expect_jq "queue done: no fallback"             "$($NI "$base")" '.ok and .item == null and (.reason | test("plan-backlog"))'
backlog ready; queue 0-3; base=$(commit followup)
expect_jq "a ready follow-up of a done parent goes first" "$($NI "$base")" '.ok and .item == "#0-8" and .source == "follow-up" and .followUpOf == "0-9"'
backlog proposed; queue 0-2; base=$(commit badqueue)
expect_jq "invalid queue on the base: no start" "$($NI "$base")" '(.ok | not) and (.reasons[0] | test("invalid"))'
queue 0-3; base=$(commit q4); touch "$WORK/gh-fails"
expect_jq "gh failure: fail closed"             "$($NI "$base")" '(.ok | not) and (.reasons[0] | test("gh pr list"))'
rm -f "$WORK/gh-fails"
expect_jq "short sha refused"                   "$($NI "${base:0:12}")" '(.ok | not)'
expect_jq "malformed item refused"              "$($NI "$base" '0-3;x')" '(.ok | not)'
echo "#0-3 changed in the working tree" >> BACKLOG.md
expect_jq "the working copy is ignored"         "$($NI "$base")" '.ok and .item == "#0-3"'
git rm -q .ai/rules/protected-paths.md; base=$(commit noprotected)
expect_jq "no protected-path list: fail closed"  "$($NI "$base" 0-3)" '(.ok | not) and (.reasons[0] | test("protected-paths.md"))'
expect_jq "no list: the queue check fails closed" "$($CQ)" '(.valid | not) and (.errors[0] | test("protected-paths.md"))'

echo "the lock rule against its cases (backlog #0-278 AC11)"
# next-item.sh's own definition (_backlog.sh, LOCKED_BY_JQ) run on every case of the fixture that profitbuild/factory's
# dispatcher reads a copy of: the two sides of the rule agree on the same names. A case file read whole or not at all.
LOCK_CASES=$SRC/.github/scripts/fixtures/item-lock-branches.tsv
# shellcheck source=scripts/factory/_backlog.sh
LOCKED_BY_JQ=$(. "$SRC/scripts/factory/_backlog.sh" && printf '%s' "$LOCKED_BY_JQ")
cases=0
while IFS=$'\t' read -r item branch want extra; do
    case "$item" in '#'*|'') continue ;; esac
    cases=$((cases+1))
    if [ -n "${extra:-}" ] || [ -z "$branch" ] || { [ "$want" != held ] && [ "$want" != free ]; }; then
        fail "a malformed case in item-lock-branches.tsv: $item $branch $want"; continue
    fi
    got=$(jq -n --arg id "$item" --arg b "$branch" '[$b] as $locks | '"$LOCKED_BY_JQ"' if lockedBy($id) == null then "free" else "held" end') \
        || { fail "jq could not run the lock rule on $item $branch"; continue; }
    [ "$got" = "\"$want\"" ] || fail "lock: $item by $branch is $got, the case says $want"
done < "$LOCK_CASES"
if [ "$cases" -ge 10 ]; then echo "  ok: the lock rule agrees with all $cases cases of item-lock-branches.tsv"
else fail "item-lock-branches.tsv holds $cases cases, fewer than its 10"; fi

if [ "$failures" -gt 0 ]; then echo "$failures queue test(s) failed"; exit 1; fi
echo "All queue tests passed."
