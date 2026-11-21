#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory/seed-branch.sh, seed-check.sh (backlog #0-173), seed-fold.sh and seed-record.sh (#0-177),
# in a temporary repository with an origin: the seed branch starts from main (so the evaluator stays main's), its base
# reverts the change's code and its head brings it back, Markdown is not replayed, a rename is a deletion and an
# addition, a merge commit is its whole pull request, and every refusal leaves the tree on a clean main without the
# branch, and the run is recorded in .ai/runs/SEED until return-to-main.sh (#0-172); seed-check.sh confirms the
# seeder's uncommitted edit on that branch, in the change's files, and refuses anything else (a commit of its own
# included, #0-172); seed-fold.sh makes the change and the edit one commit; nothing on the branch names the run (#0-177);
# seed-compile.sh compiles the modules the edit reaches, offline, and fails the run on a plant that does not build (#0-181); and
# seed-record.sh appends a run's row to the gitignored .ai/runs/benchmark/results.md, which leaves main clean.
# Run: .github/scripts/test-seed-branch.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

R=$WORK/repo
git init -q --bare -b main "$WORK/origin.git"
git init -q -b main "$R"
cd "$R" || exit 1
git config user.email t@t && git config user.name t
mkdir -p scripts/factory .ai/rules svc .claude
cp "$SRC"/scripts/factory/_common.sh "$SRC"/scripts/factory/_protected.sh "$SRC"/scripts/factory/seed-branch.sh \
   "$SRC"/scripts/factory/seed-check.sh "$SRC"/scripts/factory/seed-fold.sh "$SRC"/scripts/factory/seed-record.sh \
   "$SRC"/scripts/factory/return-to-main.sh scripts/factory/
cp "$SRC"/.ai/rules/protected-paths.md .ai/rules/
printf '.ai/runs/\n' > .gitignore
printf 'v1\n' > svc/A.java && printf 'backlog 1\n' > BACKLOG.md && printf 'x\n' > .claude/x
# The patterns seed-check.sh holds the seeder's rule and dimension to, read from origin/main (#0-180's rule scope).
mkdir -p .ai/audit/benchmark && printf '%s\n' '| Id | Dimension | Rule | Defect to plant |' '|---|---|---|---|' \
    '| P-10 | performance | PERF-01 | a query in a loop |' '| C-01 | architecture | ARC-23 | a per-replica gauge |' \
    '| P-77 | general | GEN-01 | twice |' '| P-77 | general | GEN-01 | twice |' > .ai/audit/benchmark/patterns.md
# A tracked symlink and a directory: places seed-check.sh refuses (only a regular file has lines to score, #0-181).
ln -s ../BACKLOG.md svc/link
printf 'b\n' > svc/B.java && printf 'd\n' > svc/D.java && printf 'e\n' > svc/E.java && printf 'm1\n' > svc/M.java
git add -A && git commit -qm base
printf 'v2\n' > svc/A.java && printf 'backlog 2\n' > BACKLOG.md
git add -A && git commit -qm "fix(svc): the change under test"
change=$(git rev-parse HEAD)
printf 'y\n' > .claude/x && git add -A && git commit -qm "chore: touches the evaluator"
evaluator_change=$(git rev-parse HEAD)
printf 'backlog 3\n' > BACKLOG.md && git add -A && git commit -qm "docs: backlog moved on"
md_only=$(git rev-parse HEAD)
git mv svc/B.java svc/C.java && git rm -q svc/D.java && git commit -qm "refactor(svc): B becomes C, D goes"
rename_change=$(git rev-parse HEAD)
git rm -q svc/E.java && git commit -qm "chore(svc): drop E"
delete_change=$(git rev-parse HEAD)
git switch -q -c feat && printf 'm2\n' > svc/M.java && git add -A && git commit -qm "feat(svc): the merged change"
git switch -q main && git merge -q --no-ff -m "Merge pull request #1 from feat" feat && git branch -q -D feat
merge_change=$(git rev-parse HEAD)
git remote add origin "$WORK/origin.git" && git push -q origin main 2>/dev/null && git fetch -q origin

SB=scripts/factory/seed-branch.sh
SC=scripts/factory/seed-check.sh
SF=scripts/factory/seed-fold.sh
SR=scripts/factory/seed-record.sh
# Branch names as seed-bugs.js derives them (FNV-1a of "<pattern>\n<run id>"); the scripts take them as given.
B1=review/0684d0a2 B2=review/0584cf0f B3=review/11111111 B4=review/22222222 B9=review/99999999
on_clean_main() { [ "$(git rev-parse --abbrev-ref HEAD)" = main ] && [ -z "$(git status --porcelain)" ]; }
# refused <name> <reason regex> <args...>: ok false with that reason, and the tree left on a clean main, no seed branch.
refused() {
    local name=$1 re=$2 out; shift 2
    out=$("$SB" "$@")
    if jq -e --arg re "$re" '.ok == false and (.reason | test($re))' <<<"$out" >/dev/null && on_clean_main \
       && [ -z "$(git branch --list 'review/*')" ]; then ok "$name"
    else fail "$name: $out (on $(git rev-parse --abbrev-ref HEAD), branches: $(git branch --list 'review/*' | tr '\n' ' '))"; fi
}

# reason <name> <reason regex> <args...>: ok false with that reason (for the cases set up off a clean main).
reason() {
    local name=$1 re=$2 out; shift 2
    out=$("$SB" "$@")
    if jq -e --arg re "$re" '.ok == false and (.reason | test($re))' <<<"$out" >/dev/null; then ok "$name"; else fail "$name: $out"; fi
}

echo "seed-branch.sh: what it refuses"
for name in seed/P-10-r1 review/0684d0a review/0684d0a2x 'review/0684d0a2;x' review/ABCDEF12 review/../x; do
    refused "a branch name that is not review/<8 hex>: $name" "not a seed branch name" "$name" "$change"
done
refused "bad commit" "not a commit" "$B1" HEAD
refused "unknown commit" "no such commit" "$B1" deadbeef
refused "a change that touches the evaluator" "touches the evaluator \\(\\.claude/x" "$B1" "$evaluator_change"
refused "a change to Markdown only" "no code to replay" "$B1" "$md_only"
refused "a change that only deletes code" "nothing to plant in" "$B1" "$delete_change"
git switch -q -c other && reason "not on main" "not on main" "$B1" "$change"; git switch -q main && git branch -q -D other
printf 'dirt\n' > svc/A.java; out=$("$SB" "$B1" "$change")
if jq -e '.ok == false and (.reason | test("not clean"))' <<<"$out" >/dev/null; then ok "a dirty tree"; else fail "a dirty tree: $out"; fi
git checkout -q -- svc/A.java
# The tracked results.md is changed only by a series' pull request now (#0-177): changed by hand, it is dirt like any other.
mkdir -p .ai/audit/benchmark && printf '| row |\n' > .ai/audit/benchmark/results.md
reason "an uncommitted results.md is not clean" "^the working tree is not clean$" "$B1" "$change"
rm -f .ai/audit/benchmark/results.md
mkdir -p .ai/runs && echo "R1 $(git rev-parse HEAD)" > .ai/runs/LOCK
refused "an autopilot run holds the lock" "holds the lock" "$B1" "$change"
rm -f .ai/runs/LOCK
printf 'local\n' > svc/C.java && git add svc/C.java && git commit -qm local
refused "main ahead of origin/main" "not at origin/main" "$B1" "$change"
git reset -q --hard origin/main
# A protected-paths.md whose Owner-only list cannot be read (its markers gone) refuses, even with build-config intact.
sed -i.bak -e '/protected:start/d' -e '/protected:end/d' .ai/rules/protected-paths.md && rm -f .ai/rules/protected-paths.md.bak
git commit -qam "chore: markers lost" && git update-ref refs/remotes/origin/main HEAD
refused "an Owner-only list that cannot be read" "cannot read the protected paths .*: protected" "$B1" "$evaluator_change"
git reset -q --hard HEAD~1 && git update-ref refs/remotes/origin/main HEAD

echo "seed-branch.sh: the branch"
# The last run's row, in the gitignored .ai/runs/benchmark/ (seed-record.sh): main stays clean, the next run starts.
mkdir -p .ai/runs/benchmark && printf '| r0 | P-09 | ARC-02 | architecture | yes | yes | — | — |\n' > .ai/runs/benchmark/results.md
reflog_before=$(git reflog show --format='%H %gs' HEAD)   # the owner's HEAD reflog, which the fold must keep
out=$("$SB" "$B1" "$change")
if jq -e --arg b "$B1" '.ok == true and .branch == $b and .files == ["svc/A.java"]' <<<"$out" >/dev/null; then ok "made, with the change's code files only, a row in .ai/runs/ or not"
else fail "made: $out"; fi
base=$(jq -r .base <<<"$out"); head=$(jq -r .head <<<"$out")
if [ "$(git rev-parse --abbrev-ref HEAD)" = "$B1" ]; then ok "checked out"; else fail "not checked out"; fi
if ! git ls-tree -r --name-only HEAD | grep -q '^\.ai/runs/'; then ok "the row in .ai/runs/ is not on the branch"; else fail "a row rode onto the branch"; fi
if [ "$(git rev-parse "$base^")" = "$(git rev-parse main)" ]; then ok "starts from main"; else fail "does not start from main"; fi
if [ "$(git show "$base:svc/A.java")" = v1 ]; then ok "the base has the change's code reverted"; else fail "base A.java: $(git show "$base:svc/A.java")"; fi
if [ "$(git show "$head:svc/A.java")" = v2 ]; then ok "the head has it back"; else fail "head A.java"; fi
if [ "$(git show "$head:BACKLOG.md")" = "backlog 3" ]; then ok "Markdown is main's, not replayed"; else fail "BACKLOG.md was replayed"; fi
if [ "$(git show "$head:.claude/x")" = "$(git show main:.claude/x)" ]; then ok "the evaluator is main's"; else fail ".claude changed"; fi
if [ "$(git log -1 --format=%s "$head")" = "fix(svc): the change under test" ]; then ok "the head carries the change's subject"; else fail "subject: $(git log -1 --format=%s "$head")"; fi
if [ "$(git log -1 --format=%B "$base")" = 'Revert "fix(svc): the change under test"' ]; then ok "the base says what git revert says, and no more"
else fail "base message: $(git log -1 --format=%B "$base")"; fi

echo "seed-branch.sh: the seed record (backlog #0-172)"
if [ "$(cat .ai/runs/SEED 2>/dev/null)" = "$B1 $base $head" ]; then ok "the run is recorded in .ai/runs/SEED: branch, base, head"
else fail "seed record: $(cat .ai/runs/SEED 2>/dev/null)"; fi
if [ -z "$(git status --porcelain)" ]; then ok "the record leaves the branch clean (.ai/runs/ is gitignored)"; else fail "the record dirties the tree"; fi

echo "seed-check.sh: the tree the panel runs on"
check() {   # check <name> <reason regex | ok> <args...>
    local name=$1 re=$2 out; shift 2
    out=$("$SC" "$@")
    if [ "$re" = ok ]; then
        if jq -e '.ok == true and .files == ["svc/A.java"] and (has("commit") | not)' <<<"$out" >/dev/null; then ok "$name"; else fail "$name: $out"; fi
    elif jq -e --arg re "$re" '.ok == false and (.reason | test($re))' <<<"$out" >/dev/null; then ok "$name"
    else fail "$name: $out"; fi
}
T=(P-10 PERF-01 performance)   # the seeder's truth: its pattern, rule and dimension
check "no edit yet" "changed nothing" "$B1" "$base" "$head" "${T[@]}"
printf 'v2 planted\n' > svc/A.java
check "the seeder's edit, uncommitted, in the change's file" ok "$B1" "$base" "$head" "${T[@]}"
git add svc/A.java
check "the same edit, staged" ok "$B1" "$base" "$head" "${T[@]}"
git reset -q
# The edit's hunks, the run's ground truth (backlog #0-181): `git diff -U0 HEAD`, line numbers of the tree as the panel
# reads it. hunks <name> <expected hunks JSON> <args...>
hunks() {
    local name=$1 want=$2 out; shift 2
    out=$("$SC" "$@")
    if jq -e --argjson w "$want" '.ok == true and .hunks == $w' <<<"$out" >/dev/null; then ok "$name"; else fail "$name: $out"; fi
}
hunks "a one-line edit: its line" '[{"file":"svc/A.java","start":1,"end":1}]' "$B1" "$base" "$head" "${T[@]}"
printf 'v2\nadded one\nadded two\n' > svc/A.java
hunks "lines added below: the added lines" '[{"file":"svc/A.java","start":2,"end":3}]' "$B1" "$base" "$head" "${T[@]}"
printf 'top\nv2\nadded one\nmid\nadded two\n' > svc/A.java
hunks "two hunks in one file" '[{"file":"svc/A.java","start":1,"end":1},{"file":"svc/A.java","start":3,"end":5}]' "$B1" "$base" "$head" "${T[@]}"
# An added line whose text starts `++ ` shows as `+++ b/…` in the diff: never a file header (review round 1).
printf 'top\n++ b/BACKLOG.md\nv2\nmid\n' > svc/A.java
hunks "a line that reads like a diff header" '[{"file":"svc/A.java","start":1,"end":2},{"file":"svc/A.java","start":4,"end":4}]' "$B1" "$base" "$head" "${T[@]}"
: > svc/A.java
hunks "a line removed: where it was" '[{"file":"svc/A.java","start":1,"end":1}]' "$B1" "$base" "$head" "${T[@]}"
git checkout -q -- svc/A.java && chmod +x svc/A.java
check "a mode change only: no hunk to score" "no hunk to score" "$B1" "$base" "$head" "${T[@]}"
chmod -x svc/A.java && rm svc/A.java
check "a file deleted: no line to score" "deleted a file" "$B1" "$base" "$head" "${T[@]}"
git checkout -q -- svc/A.java && printf 'v2 planted\n' > svc/A.java
# The places the seeder left unedited: tracked, with the line, plain paths, at most two.
check "a place the branch tracks, at a line it has" ok "$B1" "$base" "$head" "${T[@]}" BACKLOG.md:1 svc/A.java:1
check "a place past the file's end" "BACKLOG\\.md has no line 2 \\(it has 1\\)" "$B1" "$base" "$head" "${T[@]}" BACKLOG.md:2
check "a place git does not track" "nope\\.md is not a file the branch tracks" "$B1" "$base" "$head" "${T[@]}" nope.md:1
check "a gitignored place" "is not a file the branch tracks" "$B1" "$base" "$head" "${T[@]}" .ai/runs/SEED:1
check "a symlink: its target is outside the tree's count" "svc/link is not a regular file \\(mode 120000\\)" "$B1" "$base" "$head" "${T[@]}" svc/link:1
check "a directory" "svc is not a regular file \\(mode 040000\\)" "$B1" "$base" "$head" "${T[@]}" svc:1
for place in ../x:1 a/../BACKLOG.md:1 /etc/passwd:1 BACKLOG.md:0 BACKLOG.md BACKLOG.md:1x "BACKLOG.md:1 x"; do
    check "not a plain <file>:<line>: '$place'" "not a <file>:<line>" "$B1" "$base" "$head" "${T[@]}" "$place"
done
check "three places" "usage" "$B1" "$base" "$head" "${T[@]}" BACKLOG.md:1 BACKLOG.md:1 BACKLOG.md:1
check "a clean pattern's truth" ok "$B1" "$base" "$head" C-01 ARC-23 architecture
check "a rule that is not the pattern's" "truth \\(performance, PERF-02\\) is not P-10's \\(performance, PERF-01\\)" "$B1" "$base" "$head" P-10 PERF-02 performance
check "a dimension that is not the pattern's" "is not C-01's \\(architecture, ARC-23\\)" "$B1" "$base" "$head" C-01 ARC-23 general
check "a pattern with no row" "P-99 is not one row of" "$B1" "$base" "$head" P-99 PERF-01 performance
check "a pattern with two rows" "P-77 is not one row of" "$B1" "$base" "$head" P-77 GEN-01 general
check "a pattern id that is a prefix of another's" "P-1 is not one row of" "$B1" "$base" "$head" P-1 PERF-01 performance
check "a bad pattern id" "not a pattern id" "$B1" "$base" "$head" 'P-.*' PERF-01 performance
check "a bad rule id" "not a rule id" "$B1" "$base" "$head" P-10 'PERF-01 x' performance
check "a bad dimension" "not a dimension" "$B1" "$base" "$head" P-10 PERF-01 'performance;x'
check "the old three arguments" "usage" "$B1" "$base" "$head"
git show refs/remotes/origin/main:.ai/audit/benchmark/patterns.md > "$WORK/patterns.md"
printf '| P-10 | performance | PERF-02 | the branch says otherwise |\n' > .ai/audit/benchmark/patterns.md
check "the patterns of origin/main, not of the tree" "is not P-10's \\(performance, PERF-01\\)" "$B1" "$base" "$head" P-10 PERF-02 performance
cp "$WORK/patterns.md" .ai/audit/benchmark/patterns.md
# And not of HEAD: origin/main moved on to a P-10 of another rule, the branch still has the old one.
main_was=$(git rev-parse refs/remotes/origin/main)
blob=$(sed 's/| PERF-01 |/| PERF-02 |/' "$WORK/patterns.md" | git hash-object -w --stdin)
GIT_INDEX_FILE=$WORK/index git read-tree "$main_was" \
    && GIT_INDEX_FILE=$WORK/index git update-index --cacheinfo "100644,$blob,.ai/audit/benchmark/patterns.md"
git update-ref refs/remotes/origin/main "$(git commit-tree -p "$main_was" -m "docs: P-10 moved" "$(GIT_INDEX_FILE=$WORK/index git write-tree)")"
check "the patterns of origin/main, not of HEAD" ok "$B1" "$base" "$head" P-10 PERF-02 performance
git update-ref refs/remotes/origin/main "$main_was"
check "bad base" "not a base commit" "$B1" abc "$head" "${T[@]}"
check "a bad branch name" "not a seed branch name" seed/P-10-r1 "$base" "$head" "${T[@]}"
check "a base that is not under the head" "is not the commit on top of" "$B1" "$(git rev-parse main)" "$head" "${T[@]}"
check "another run's branch" "not on $B9" "$B9" "$base" "$head" "${T[@]}"
git commit -qam "refactor(svc): simplify"
check "a seeder that committed" "the seeder committed" "$B1" "$base" "$head" "${T[@]}"
git reset -q --hard "$head" && printf 'z\n' > svc/Z.java
check "a file git does not track" "files git does not track: svc/Z.java" "$B1" "$base" "$head" "${T[@]}"
rm -f svc/Z.java && printf 'v2 planted\n' > svc/A.java && printf 'w\n' > .claude/x
check "the evaluator, outside the change" "outside the change: \\.claude/x" "$B1" "$base" "$head" "${T[@]}"
git checkout -q -- .claude/x && printf 'n\n' > svc/M.java
check "a file outside the change" "outside the change: svc/M.java" "$B1" "$base" "$head" "${T[@]}"
git reset -q --hard "$head"

echo "seed-fold.sh: the change and the defect as one commit"
# The cases above ran git on the branch (a commit, resets), as a seeder no longer can (#0-172): their HEAD reflog
# entries go, so the fold sees the run as seed-branch.sh left it, its two commits above the switch.
as_made() {   # as_made <branch>
    local n
    n=$(git reflog show --format=%gs HEAD | awk -v s="checkout: moving from main to $1" '$0 == s { print NR - 1; exit }')
    while [ "${n:-0}" -gt 2 ]; do git reflog delete "HEAD@{0}"; n=$((n - 1)); done
}
as_made "$B1"
fold() {   # fold <name> <reason regex> <args...>: ok false with that reason, the branch where it was
    local name=$1 re=$2 out before; shift 2
    before=$(git rev-parse "$B1")
    out=$("$SF" "$@")
    if jq -e --arg re "$re" '.ok == false and (.reason | test($re))' <<<"$out" >/dev/null && [ "$(git rev-parse "$B1")" = "$before" ]; then ok "$name"
    else fail "$name: $out"; fi
}
fold "nothing to fold" "changed nothing" "$B1" "$base" "$head"
printf 'v2 planted\n' > svc/A.java
fold "a bad branch name" "not a seed branch name" seed/P-10-r1 "$base" "$head"
fold "a bad commit" "not a commit" "$B1" "$base" HEAD
fold "the wrong number of arguments (the old <seeded> too)" "usage" "$B1" "$base" "$head" "$head"
fold "a head not on the base" "is not the commit on top of" "$B1" "$head" "$head"
fold "not the change's commit" "HEAD is not the change's commit" "$B1" "$base" "$base"
printf 'z\n' > svc/Z.java
fold "a file git does not track" "files git does not track" "$B1" "$base" "$head"
rm -f svc/Z.java
fold "not on the branch" "on $B1, not on $B9" "$B9" "$base" "$head"
# Staged or not, the fold takes the working tree: a part staged and a part not both land.
printf 'v2 planted\n' > svc/A.java && git add svc/A.java && printf 'v2 planted\nmore\n' > svc/A.java
planted_blob=$(git hash-object svc/A.java)
out=$("$SF" "$B1" "$base" "$head")
folded=$(jq -r .head <<<"$out")
if jq -e '.ok == true' <<<"$out" >/dev/null && [ "$(git rev-parse HEAD)" = "$folded" ] && [ "$(git rev-parse --abbrev-ref HEAD)" = "$B1" ]; then
    ok "folded, the branch at the new commit"; else fail "fold: $out"; fi
if [ "$(git rev-parse "$folded^")" = "$base" ] && [ "$(git rev-list --count "$base..HEAD")" = 1 ]; then ok "one commit on the base"
else fail "commits on the base: $(git rev-list --count "$base..HEAD")"; fi
if [ "$(git rev-parse "$folded:svc/A.java")" = "$planted_blob" ] && [ -z "$(git status --porcelain)" ]; then
    ok "the working tree's edit, staged or not, and a clean working tree"; else fail "tree or status after the fold: $(git status --porcelain)"; fi
if [ "$(git log -1 --format=%B "$folded")" = "fix(svc): the change under test" ]; then ok "under the change's subject only"
else fail "folded message: $(git log -1 --format=%B "$folded")"; fi
# What a reviewer reads of the branch: its name and every message from main on. None names the run or the planting.
told="$B1 $(git log --format=%B "$(git rev-parse main)..HEAD")"
if ! grep -qiE 'seed|plant|benchmark|P-[0-9]|simplify' <<<"$told"; then ok "nothing on the branch names the run (#0-177)"; else fail "a tell: $told"; fi
# Nor its reflogs (review round 1 of #0-177): `git log -g` and `HEAD@{n}` showed the change without the defect.
branch_log=$(git reflog show --format=%H "$B1" 2>/dev/null)
head_log=$(git reflog show --format=%H HEAD)
if ! grep -qxF -e "$head" <<<"$branch_log$head_log"; then ok "no reflog names the change without the defect"
else fail "a reflog still names it: branch [$branch_log] HEAD [$head_log]"; fi
if [ "$(git reflog show --format='%H %gs' HEAD | tail -n +2)" = "$reflog_before" ] \
   && [ "$(git reflog show --format=%gs -n 1 HEAD)" = "checkout: moving from main to $B1" ]; then
    ok "the owner's HEAD reflog is kept, below the run's switch"
else fail "HEAD reflog: $(git reflog show --format=%gs HEAD | head -5 | tr '\n' '|')"; fi
git reset -q --hard "$head"
git switch -q main
check "not on the seed branch" "on main, not on $B1" "$B1" "$base" "$head" "${T[@]}"
reason "the branch exists already" "exists already" "$B1" "$change"
if [ "$(git rev-parse "$B1")" = "$head" ] && on_clean_main; then ok "an existing branch is left as it was"; else fail "an existing branch was touched"; fi
git branch -D -q "$B1"

echo "seed-branch.sh: renames, deletions and merge commits"
out=$("$SB" "$B3" "$rename_change")
if jq -e '.ok == true and .files == ["svc/C.java"]' <<<"$out" >/dev/null; then ok "a rename: only the file that is left to plant in"
else fail "rename: $out"; fi
base=$(jq -r .base <<<"$out"); head=$(jq -r .head <<<"$out")
if git cat-file -e "$base:svc/B.java" && git cat-file -e "$base:svc/D.java" && ! git cat-file -e "$base:svc/C.java" 2>/dev/null \
   && ! git cat-file -e "$head:svc/B.java" 2>/dev/null && ! git cat-file -e "$head:svc/D.java" 2>/dev/null; then
    ok "the base has B and D back, the head moves B to C and drops D"
else fail "rename base/head trees"; fi
printf 'b again\n' > svc/B.java && git add svc/B.java
check "a file the change deleted, brought back" "outside the change: svc/B.java" "$B3" "$base" "$head" "${T[@]}"
git reset -q --hard "$head"
# Git that ran on the branch since seed-branch.sh (a switch away and back, the edit carried along): the newest switch
# is not the run's, an entry sits above seed-branch.sh's two commits. Refused, the branch where it was.
printf 'c planted\n' > svc/C.java
git switch -q main && git switch -q "$B3"
out=$("$SF" "$B3" "$base" "$head")
if jq -e '.ok == false and (.reason | test("does not show the switch|git ran on the branch"))' <<<"$out" >/dev/null \
   && [ "$(git rev-parse "$B3")" = "$head" ]; then ok "git that ran on the branch since: refused"
else fail "switched away and back: $out"; fi
# A HEAD reflog without the run's switch (expired, or off): refused before anything moves.
git reflog expire --expire=now HEAD
out=$("$SF" "$B3" "$base" "$head")
if jq -e '.ok == false and (.reason | test("does not show the switch"))' <<<"$out" >/dev/null && [ "$(git rev-parse "$B3")" = "$head" ]; then
    ok "no switch in the HEAD reflog: refused, the branch where it was"; else fail "no switch: $out"; fi
git reset -q --hard "$head"
git switch -q main && git branch -D -q "$B3"
out=$("$SB" "$B4" "$merge_change")
if jq -e '.ok == true and .files == ["svc/M.java"]' <<<"$out" >/dev/null; then ok "a merge commit: its pull request's files"; else fail "merge: $out"; fi
base=$(jq -r .base <<<"$out"); head=$(jq -r .head <<<"$out")
if [ "$(git show "$base:svc/M.java")" = m1 ] && [ "$(git show "$head:svc/M.java")" = m2 ]; then ok "the merge's change reverted, then back"
else fail "merge base/head"; fi
if [ "$(git log -1 --format=%s "$head")" = "feat(svc): the merged change" ]; then ok "under its pull request's subject"
else fail "merge subject: $(git log -1 --format=%s "$head")"; fi
if [ "$(cat .ai/runs/SEED)" = "$B4 $base $head" ]; then ok "a new run's record replaces the last one's"; else fail "record: $(cat .ai/runs/SEED)"; fi
# The run over, back on main: the record goes with it (#0-172). Left on the branch (a dirty tree), it stays.
printf 'dirt\n' > svc/M.java
out=$(scripts/factory/return-to-main.sh)
if jq -e '.onMain == false' <<<"$out" >/dev/null && [ -f .ai/runs/SEED ]; then ok "left on the branch: the record stays"; else fail "dirty return: $out"; fi
git checkout -q -- svc/M.java
out=$(scripts/factory/return-to-main.sh)
if jq -e '.onMain == true' <<<"$out" >/dev/null && [ ! -e .ai/runs/SEED ]; then ok "back on main: the record is gone"; else fail "return: $out"; fi
git branch -D -q "$B4"

echo "seed-branch.sh: a change that no longer applies"
printf 'v3\n' > svc/A.java && git add -A && git commit -qm "fix(svc): later" && git push -q origin main 2>/dev/null && git fetch -q origin
printf '%s %s %s\n' "$B9" "$change" "$change" > .ai/runs/SEED
refused "the change's code changed since" "no longer applies" "$B2" "$change"
if [ ! -e .ai/runs/SEED ]; then ok "a refusal after the branch was made leaves no record"; else fail "a record after a refusal: $(cat .ai/runs/SEED)"; fi

echo "seed-record.sh: a run's row in .ai/runs/benchmark/results.md"
rows=.ai/runs/benchmark/results.md
rm -rf .ai/runs/benchmark
record() {   # record <name> <reason regex | ok> <args...>
    local name=$1 re=$2 out; shift 2
    out=$("$SR" "$@")
    if [ "$re" = ok ]; then
        if jq -e --arg f "$rows" '.appended == true and .file == $f' <<<"$out" >/dev/null; then ok "$name"; else fail "$name: $out"; fi
    elif jq -e --arg re "$re" '.appended == false and (.reason | test($re))' <<<"$out" >/dev/null; then ok "$name"
    else fail "$name: $out"; fi
}
record "a caught run" ok r1 P-10 PERF-01 performance yes yes performance,general,docs -
record "a missed run, a reviewer without an answer" ok r2 P-11 PERF-23 performance no no - security,docs
expected='| Run | Pattern | Rule | Expected | Caught by expected | Blocking | Also caught by | No answer |
|---|---|---|---|---|---|---|---|
| r1 | P-10 | PERF-01 | performance | yes | yes | general, docs | — |
| r2 | P-11 | PERF-23 | performance | no | no | — | security, docs |'
if [ "$(cat "$rows")" = "$expected" ]; then ok "the table: a header once, one row per run"; else fail "rows: $(cat "$rows")"; fi
if on_clean_main; then ok "main stays clean: the rows are gitignored"; else fail "the rows dirty main: $(git status --porcelain)"; fi
# A run id is matched in the first column only (review round 1): `security` is a dimension in r2's row, not its id.
record "a run id that is also a dimension" ok security P-12 PERF-02 performance yes no - -
record "a run id recorded already" "r1 is in \\.ai/runs/benchmark/results\\.md already" r1 P-10 PERF-01 performance yes yes - -
mkdir -p .ai/audit/benchmark && printf '| r7 | P-12 | PERF-02 | performance | yes | yes | — | — |\n' > .ai/audit/benchmark/results.md
record "a run id landed already" "r7 is in \\.ai/audit/benchmark/results\\.md already" r7 P-12 PERF-02 performance yes yes - -
# A long tracked file, the id in its first row: `cut | grep -q` would stop early, SIGPIPE cut, and pass (round 3).
{ printf '| r8 | P-12 | PERF-02 | performance | yes | yes | — | — |\n'
  for i in $(seq 1 50000); do printf '| x%s | P-01 | SEC-06 | security | yes | yes | — | — |\n' "$i"; done; } > .ai/audit/benchmark/results.md
record "a run id landed already, in a long file" "r8 is in \\.ai/audit/benchmark/results\\.md already" r8 P-12 PERF-02 performance yes yes - -
rm -f .ai/audit/benchmark/results.md
record "a bad run id" "not a run id" "r 1" P-10 PERF-01 performance yes yes - -
record "a bad pattern" "not a pattern id" P-1x r3 PERF-01 performance yes yes - -
record "a bad rule" "not a rule id" r3 P-10 "PERF-01'" performance yes yes - -
record "a rule with two letters after the dash" "not a rule id" r3 P-10 FAC-AB02 architecture yes yes - -
record "an unknown dimension" "not a dimension" r3 P-10 PERF-01 frontend yes yes - -
record "not yes or no" "not yes or no" r3 P-10 PERF-01 performance true yes - -
for list in 'general,frontend' 'general;rm' '*' 'general,' ''; do
    record "a bad list: '$list'" "not a list of dimensions" r3 P-10 PERF-01 performance yes yes "$list" -
    record "a bad no-answer list: '$list'" "not a list of dimensions" r3 P-10 PERF-01 performance yes yes - "$list"
done
record "the wrong number of arguments" "usage" r3 P-10 PERF-01 performance yes yes -
if [ "$(grep -c '^| [rs]' "$rows")" = 3 ]; then ok "a refused row writes nothing"; else fail "rows after refusals: $(cat "$rows")"; fi
# A dimension and a rule id's name may hold a digit (k8s, K8S-08: #0-115's k8s.md): as expected, in "Also caught by" and in "No answer".
record "a k8s run" ok r9 P-20 K8S-08 k8s yes yes k8s,general security,k8s
if [ "$(tail -1 "$rows")" = '| r9 | P-20 | K8S-08 | k8s | yes | yes | general | security, k8s |' ]; then ok "the k8s row"
else fail "k8s row: $(tail -1 "$rows")"; fi
# A factory id has a letter after the dash (FAC-A02: #0-115's F1, #0-185).
record "a factory run" ok r10 P-23 FAC-A02 architecture yes yes architecture,security -
if [ "$(tail -1 "$rows")" = '| r10 | P-23 | FAC-A02 | architecture | yes | yes | security | — |' ]; then ok "the factory row"
else fail "factory row: $(tail -1 "$rows")"; fi

echo "seed-record.sh --clean: a clean run's row in .ai/runs/benchmark/clean.md (backlog #0-180)"
clean_rows=.ai/runs/benchmark/clean.md
crecord() {   # crecord <name> <reason regex | ok> <args...>
    local name=$1 re=$2 out; shift 2
    out=$("$SR" --clean "$@")
    if [ "$re" = ok ]; then
        if jq -e --arg f "$clean_rows" '.appended == true and .file == $f' <<<"$out" >/dev/null; then ok "$name"; else fail "$name: $out"; fi
    elif jq -e --arg re "$re" '.appended == false and (.reason | test($re))' <<<"$out" >/dev/null; then ok "$name"
    else fail "$name: $out"; fi
}
crecord "a clean run no dimension stopped" ok c1 C-01 ARC-23 architecture - architecture general -
crecord "a clean run two dimensions stopped" ok c2 C-02 ARC-29 architecture architecture,general - - docs
expected='| Run | Pattern | Rule | Expected | False alarm by | Raised by | Blocking elsewhere | No answer |
|---|---|---|---|---|---|---|---|
| c1 | C-01 | ARC-23 | architecture | — | architecture | general | — |
| c2 | C-02 | ARC-29 | architecture | architecture, general | — | — | docs |'
if [ "$(cat "$clean_rows")" = "$expected" ]; then ok "the clean table: its own header, one row per run"; else fail "clean rows: $(cat "$clean_rows")"; fi
if ! grep -q '^| c[12] ' "$rows"; then ok "a clean row never reaches the defects' table"; else fail "a clean row in $rows"; fi
crecord "a defect pattern is not a clean one" "not a clean pattern id" c3 P-07 ARC-23 architecture - - - -
crecord "a bad list of false alarms" "not a list of dimensions" c3 C-01 ARC-23 architecture 'general;rm' - - -
crecord "a run id of the defects' table" "r1 is in \\.ai/runs/benchmark/results\\.md already" r1 C-01 ARC-23 architecture - - - -
record "a defect run id of the clean table" "c1 is in \\.ai/runs/benchmark/clean\\.md already" c1 P-07 ARC-23 architecture yes yes - -
mkdir -p .ai/audit/benchmark && printf '| c9 | C-01 | ARC-23 | architecture | — | — | — | — |\n' > .ai/audit/benchmark/clean.md
crecord "a run id landed in the tracked clean table" "c9 is in \\.ai/audit/benchmark/clean\\.md already" c9 C-01 ARC-23 architecture - - - -
rm -f .ai/audit/benchmark/clean.md
crecord "the wrong number of arguments" "usage" c4 C-01 ARC-23 architecture - - -
if on_clean_main; then ok "main stays clean: the clean rows are gitignored"; else fail "the clean rows dirty main: $(git status --porcelain)"; fi

echo "seed-compile.sh: the plant is compiled before the panel (#0-181)"
# Its own repository: the modules modules_of knows (shared, a *-service) and a stub ./mvnw that records how it was
# called and answers as $MVN_MODE says. A fold is made the way seed-fold.sh makes it: one commit on the change's parent,
# with the change's tree and the seeder's edit, checked out on the branch.
C=$WORK/compile
git init -q -b main "$C"
cd "$C" || exit 1
git config user.email t@t && git config user.name t
mkdir -p scripts/factory shared/src demo-service/src docs
cp "$SRC"/scripts/factory/_common.sh "$SRC"/scripts/factory/seed-compile.sh "$SRC"/scripts/factory/maven-settings.xml scripts/factory/
printf '.ai/runs/\n' > .gitignore
cat > mvnw <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$MVN_CALLS"
printf 'MAVEN_OPTS=%s JAVA_TOOL_OPTIONS=%s MAVEN_SKIP_RC=%s\n' "${MAVEN_OPTS:-}" "${JAVA_TOOL_OPTIONS:-}" "${MAVEN_SKIP_RC:-}" >> "$MVN_CALLS"
case "${MVN_MODE:-ok}" in
    ok) echo "[INFO] BUILD SUCCESS"; exit 0 ;;
    compile) echo "[ERROR] COMPILATION ERROR : "
             echo "[ERROR] $PWD/demo-service/src/A.java:[3,12] non-static variable id cannot be referenced from a static context"
             echo "[ERROR] $PWD/demo-service/src/A.java:[4,1] second"; exit 1 ;;
    env) echo "[ERROR] Failed to execute goal on project demo-service: Could not resolve dependencies: Cannot access central (https://repo) in offline mode"; exit 1 ;;
    other) echo "[ERROR] Failed to execute goal enforcer: rule failed"; exit 1 ;;
    caller) echo "[ERROR] $PWD/demo-service/src/Caller.java:[7,3] cannot find symbol"
            echo "[ERROR] $PWD/demo-service/src/A.java:[3,12] second"; exit 1 ;;
    module) echo "[ERROR] $PWD/shared/src/S.java:[1,7] duplicate class: S"; exit 1 ;;
    dirty) echo changed >> docs/README.md; exit 0 ;;
esac
STUB
chmod +x mvnw
printf 'class A {}\n' > demo-service/src/A.java && printf 'class S {}\n' > shared/src/S.java && printf '<project/>\n' > demo-service/pom.xml
printf 'doc\n' > docs/README.md && printf 'x\n' > Tool.java
git add -A && git commit -qm base
printf 'class A { int id; }\n' > demo-service/src/A.java && git add -A && git commit -qm "feat(demo): the change"
cchange=$(git rev-parse HEAD)
export MVN_CALLS=$WORK/mvn-calls
CB=review/aaaaaaaa
plant() {   # plant <file> <text>: back on main, the branch at a fold of the change and the edit
    git switch -q main 2>/dev/null; git branch -q -D "$CB" 2>/dev/null
    git switch -q -c "$CB" "$cchange" && printf '%s\n' "$2" >> "$1" && git add -A
    cfold=$(git commit-tree "$(git write-tree)" -p "$cchange^1" -m "feat(demo): the change")
    git reset -q --hard "$cfold"
}
SCC=scripts/factory/seed-compile.sh
compiled() {   # compiled <name> <jq test> [MVN_MODE]
    local out; rm -f "$MVN_CALLS"
    out=$(MVN_MODE=${3:-ok} MAVEN_OPTS=-Dskip JAVA_TOOL_OPTIONS=-Dx "$SCC" "$CB" "$cchange" "$cfold")
    if jq -e "$2" <<<"$out" >/dev/null; then ok "$1"; else fail "$1: $out"; fi
}
called() { grep -qE -- "$1" "$MVN_CALLS" 2>/dev/null; }

plant demo-service/src/A.java 'class B { static int f() { return 1; } }'
compiled "a Java plant in a service: compiled" '.ok == true and .compiled == true and .modules == "demo-service"'
cset=$(cd -P scripts/factory && pwd)/maven-settings.xml
if called "^-B -ntp -s $cset -gs $cset -o test-compile -pl demo-service -am\$"; then
    ok "offline test-compile of the module and what it depends on, with the factory's settings"
else fail "the Maven call: $(cat "$MVN_CALLS")"; fi
if called '^MAVEN_OPTS= JAVA_TOOL_OPTIONS= MAVEN_SKIP_RC=true$'; then ok "the environment's Maven options are stripped"
else fail "the environment reached Maven: $(cat "$MVN_CALLS")"; fi
# As the dispatcher runs it (backlog #0-278): the scripts from a directory of their own (the base's blobs of
# trustedPaths), the working directory the clone, whose scripts/factory/maven-settings.xml a branch can rewrite. The
# settings Maven gets are the ones beside the script, never the clone's.
TRUSTED=$WORK/trusted && mkdir -p "$TRUSTED"
cp scripts/factory/_common.sh scripts/factory/seed-compile.sh scripts/factory/maven-settings.xml "$TRUSTED/"
rm -f "$MVN_CALLS"
MVN_MODE=ok "$TRUSTED/seed-compile.sh" "$CB" "$cchange" "$cfold" >/dev/null
tset=$(cd -P "$TRUSTED" && pwd)/maven-settings.xml
if called "^-B -ntp -s $tset -gs $tset "; then ok "run from another directory, Maven reads the settings beside the script, not the clone's"
else fail "the settings Maven read, run from another directory: $(cat "$MVN_CALLS")"; fi
if [ -z "$(ls .ai/runs/seed-compile-* 2>/dev/null)" ]; then ok "a build that passed leaves no log"; else fail "log left: $(ls .ai/runs)"; fi
compiled "a compiler error: the first one, from the repository's root" \
    '.ok == false and .reason == "the plant does not compile (log .ai/runs/seed-compile-aaaaaaaa.log): [ERROR] demo-service/src/A.java:[3,12] non-static variable id cannot be referenced from a static context"' compile
if [ -s .ai/runs/seed-compile-aaaaaaaa.log ]; then ok "a failed build keeps its log"; else fail "no log after a failure"; fi
compiled "a first error in a file the seeder did not edit: not named the plant's" \
    '.ok == false and (.reason | startswith("the build fails outside the seeder'"'"'s edit, in demo-service/src/Caller.java: ")) and (.reason | test("\\[7,3\\] cannot find symbol$"))' caller
compiled "a first error in another module: outside the edit too (review round 2)" \
    '.ok == false and (.reason | startswith("the build fails outside the seeder'"'"'s edit, in shared/src/S.java: "))' module
compiled "an environment that cannot build offline is not the seeder's error" \
    '.ok == false and (.reason | startswith("the build environment failed (log .ai/runs/seed-compile-aaaaaaaa.log): [ERROR] ")) and (.reason | test("in offline mode"))' env
compiled "any other failure: its first [ERROR]" \
    '.ok == false and (.reason | test("^the build failed with exit code 1 .*: \\[ERROR\\] Failed to execute goal enforcer"))' other
compiled "a build that changes a tracked file is refused" '.ok == false and (.reason | test("changed the working tree or HEAD"))' dirty
git checkout -q -- docs/README.md

plant shared/src/S.java 'class T {}'
compiled "a plant in shared: its dependents too" '.ok == true and .compiled == true and .modules == "shared"'
if called '-pl shared -am -amd$'; then ok "-amd for shared"; else fail "shared without -amd: $(cat "$MVN_CALLS")"; fi
plant demo-service/pom.xml '<!-- planted -->'
compiled "a POM in the edit: not compiled" '.ok == true and .compiled == false and (.reason | test("changes a POM"))'
if [ ! -e "$MVN_CALLS" ]; then ok "no Maven for a POM plant"; else fail "Maven ran: $(cat "$MVN_CALLS")"; fi
plant docs/README.md 'planted'
compiled "no Java in the edit: not compiled" '.ok == true and .compiled == false and (.reason | test("no Java file"))'
plant Tool.java 'planted'
compiled "Java outside a module: not compiled" '.ok == true and .compiled == false and (.reason | test("no Java file of the edit is in a Maven module"))'
if [ ! -e "$MVN_CALLS" ]; then ok "no Maven when nothing is in a module"; else fail "Maven ran: $(cat "$MVN_CALLS")"; fi

plant demo-service/src/A.java 'class C {}'
crefused() {   # crefused <name> <reason regex> <args...>
    local name=$1 re=$2 out; shift 2; rm -f "$MVN_CALLS"
    out=$("$SCC" "$@")
    if jq -e --arg re "$re" '.ok == false and (.reason | test($re))' <<<"$out" >/dev/null && [ ! -e "$MVN_CALLS" ]; then ok "$name"
    else fail "$name: $out"; fi
}
crefused "the wrong number of arguments" "usage" "$CB" "$cchange"
crefused "a bad branch name" "not a seed branch name" seed/x "$cchange" "$cfold"
crefused "a bad commit" "not a commit" "$CB" HEAD "$cfold"
crefused "not the folded commit" "HEAD is not the folded commit" "$CB" "$cchange" "$cchange"
git switch -q main
crefused "not on the branch" "on main, not on $CB" "$CB" "$cchange" "$cfold"
git switch -q "$CB"
other=$(git commit-tree "$(git write-tree)" -p "$cchange" -m other) && git reset -q --hard "$other"
crefused "a commit that is not the fold of the change" "is not the fold of" "$CB" "$cchange" "$other"
git reset -q --hard "$cfold"
echo dirty >> docs/README.md
crefused "a tree that is not clean" "not clean" "$CB" "$cchange" "$cfold"
git checkout -q -- docs/README.md
nofold=$(git commit-tree "$cchange^{tree}" -p "$cchange^1" -m same) && git reset -q --hard "$nofold"
crefused "a fold with no edit" "holds no edit" "$CB" "$cchange" "$nofold"
cd "$R" || exit 1

if [ "$failures" -gt 0 ]; then echo "$failures seed-branch/seed-check/seed-fold/seed-compile/seed-record test(s) failed"; exit 1; fi
echo "All seed-branch, seed-check, seed-fold, seed-compile and seed-record tests passed."
