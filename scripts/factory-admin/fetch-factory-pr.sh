#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/: autopilot sessions may not run it). Fetches one pull request of profitbuild/factory
# as files, so this repository's review panel can review it (backlog #0-270): `/review factory#<n> <digits>` runs it in
# its step 3, in place of the Maven gate.
#
#   scripts/factory-admin/fetch-factory-pr.sh <pr number> [--previous <head sha of the last round>]
#
# Why files and not a clone: the reviewers' guard (readonly-bash.sh) refuses `git -C <dir>` on purpose (git runs programs
# that the target repository's configuration names), and nothing of the change may run on the owner's Mac (#0-270 AC1).
# So this reads GitHub's API only, as data: nothing it fetches is run, sourced or evaluated, and it runs no git.
#
# It writes one directory per head, .ai/runs/manual/factory-pr<n>-<head, 12 hex>/ (a new push, a new directory; an
# existing one is refused, never overwritten or deleted):
#   factory.diff       the pull request's diff, base...head, pinned to the head (`gh pr diff` follows the current one)
#   delta.diff         with --previous: what changed since that head (the delta a round >= 2 reviews); when that head
#                      is no ancestor of this one (a force-push), the gate says so (`previousRewritten`): the delta
#                      then runs from their common ancestor and does not show a commit the push dropped
#   commits.txt        every commit's full message, from the commits API (`gh pr view`'s headline is cut at 72 chars)
#   pr-body.md         the description
#   files/<path>.pr    every regular file the pull request adds or modifies, as it is at the head, with `.pr` appended:
#                      so no file of the pull request is taken for this session's own (a CLAUDE.md, a skill, an agent
#                      definition Claude Code would load as instructions; a gate-r*.json or dependency-tree-r*.txt the
#                      verifier's read hook would take for a gate) (review round 1 of #0-270)
#   gate-r1.json       head, base, author, draft, commits, files, every CI check, the Test job's counts, whether the
#                      pull request changes anything under `.github/` (its workflows, the actions and scripts they run:
#                      then its CI is its own writing, not to be trusted as its gate), and a status: "pass" (every
#                      check passed or skipped) or "fixable"
# The gate's name matches the verifier's read hook (gate-r*.json under .ai/runs/).
#
# It refuses, writing nothing: a pull request that is not open; CI still running, or a push while it fetches (exit 3:
# wait, then run again); a path from the pull request that is absolute, has a `..` component, a control character
# or a character outside ASCII; two paths that differ only in case (the owner's APFS would write them to one file);
# fewer files or commits listed than the pull request has, or a diff of fewer files (an API's cap); a tree GitHub returns truncated; a directory
# that exists. A path that is a symlink or a submodule at the head (its
# mode in the tree, not the contents API, which serves a symlink to a file as that file) is listed and not written.
# Needs gh (logged in) and jq. Tests: .github/scripts/test-fetch-factory-pr.sh.
# ============================================================
set -euo pipefail

REPO=profitbuild/factory
OUT_ROOT=${FETCH_FACTORY_PR_OUT_ROOT:-.ai/runs/manual}

die() { echo "fetch-factory-pr: $1" >&2; exit "${2:-1}"; }
usage() { die "usage: $0 <pr number> [--previous <40-hex sha>]" 2; }

[ $# -ge 1 ] || usage
pr=$1; shift
[[ $pr =~ ^[1-9][0-9]{0,6}$ ]] || usage
previous=""
while [ $# -gt 0 ]; do
    case "$1" in
        --previous) [ $# -ge 2 ] || usage; previous=$2; shift 2 ;;
        *) usage ;;
    esac
done
[ -z "$previous" ] || [[ $previous =~ ^[0-9a-f]{40}$ ]] || usage
command -v jq >/dev/null || die "jq is required"

view=$(gh pr view "$pr" --repo "$REPO" --json number,state,isDraft,headRefOid,baseRefOid,headRefName,author,title)
[ "$(jq -r .state <<<"$view")" = OPEN ] || die "pull request #$pr of $REPO is $(jq -r .state <<<"$view"), not open"
head=$(jq -r .headRefOid <<<"$view")
base=$(jq -r .baseRefOid <<<"$view")
[[ $head =~ ^[0-9a-f]{40}$ && $base =~ ^[0-9a-f]{40}$ ]] || die "no head or base SHA for pull request #$pr"

# CI first: material for a head whose checks still run would be reviewed against a result nobody has yet.
checks=$(gh pr checks "$pr" --repo "$REPO" --json name,state,bucket,link) || {
    # gh exits non-zero when a check failed or is pending, after printing them: keep what it printed.
    [ -n "${checks:-}" ] || die "could not read the checks of pull request #$pr"
}
jq -e 'type == "array" and length > 0' <<<"$checks" >/dev/null || die "pull request #$pr has no check yet: wait for its CI"
if jq -e 'any(.[]; .bucket == "pending")' <<<"$checks" >/dev/null; then
    die "the CI of pull request #$pr at ${head:0:12} is still running: wait (gh pr checks $pr --repo $REPO --watch), then run again" 3
fi
status=$(jq -r 'if any(.[]; .bucket == "fail" or .bucket == "cancel") then "fixable" else "pass" end' <<<"$checks")

dir=$OUT_ROOT/factory-pr$pr-${head:0:12}
[ ! -e "$dir" ] || die "$dir exists: that head is fetched already (a new push gives a new directory)"

# Every path the pull request touches, with its status; each is checked, in jq on the whole path (a shell loop over
# lines would split a path that holds a newline), before anything is written.
files=$(gh api --paginate "repos/$REPO/pulls/$pr/files" --jq '.[] | {path: .filename, status: .status}' | jq -s .)
if jq -e 'any(.[].path; explode | any(. < 32 or . == 127))' <<<"$files" >/dev/null; then
    die "refused path in pull request #$pr: it holds a control character"
fi
# Outside ASCII, APFS also merges names: another letter's case (Ä, ä) and a Unicode normalisation (é as one code point
# or as e and an accent) are one file there, which no check here could mirror (review round 3 of #0-270, tried on the
# owner's Mac). factory's paths are ASCII; one that is not stops the fetch, so it is decided, not written over.
if jq -e 'any(.[].path; explode | any(. > 126))' <<<"$files" >/dev/null; then
    die "refused path in pull request #$pr: it holds a character outside ASCII"
fi
bad=$(jq -r 'map(.path | select(startswith("/") or (split("/") | any(. == "..")))) | first // empty' <<<"$files")
[ -z "$bad" ] || die "refused path in pull request #$pr: $bad (absolute or with ..)"
# Paths that differ only in case land on one file of a case-insensitive filesystem (APFS, the owner's Mac): files/
# would show one's content under both names (review round 2 of #0-270).
clash=$(jq -r 'map(.path) | group_by(ascii_downcase) | map(select(length > 1)) | first // empty | join(", ")' <<<"$files")
[ -z "$clash" ] || die "refused paths in pull request #$pr: $clash differ only in case"
# Anything under .github/ changes the CI that gates this pull request: its workflows, and the actions and scripts they
# run (review round 2 of #0-270: .github/workflows/ alone missed a composite action).
ci_changed=$(jq '[.[].path | select(startswith(".github/"))] | length > 0' <<<"$files")
listed_files=$(jq length <<<"$files")

# The head's tree gives each path's mode: 120000 a symlink, 160000 a submodule, written as neither.
tree=$(gh api "repos/$REPO/git/trees/$head?recursive=1")
[ "$(jq -r .truncated <<<"$tree")" = false ] || die "GitHub returned the tree of ${head:0:12} truncated: the modes of its files are not all known"
modes=$(jq '[.tree[] | {key: .path, value: .mode}] | from_entries' <<<"$tree")

mkdir -p "$OUT_ROOT"
work=$(mktemp -d "$OUT_ROOT/.factory-pr$pr.XXXXXX")
trap 'rm -rf "$work"' EXIT

gh api -H 'Accept: application/vnd.github.diff' "repos/$REPO/compare/$base...$head" > "$work/factory.diff"
# A diff of fewer files than the pull request's would be cut short somewhere: GitHub's documentation is no source
# this session can check whether compare errs or truncates on a large diff (review round 4 of #0-270), so it is
# counted. A line of a file's own text inside the diff starts with +, - or a space, never with `diff --git `.
diffed=$(grep -c '^diff --git ' "$work/factory.diff" || true)
[ "$diffed" = "$listed_files" ] || die "factory.diff of pull request #$pr holds $diffed files, the pull request $listed_files: not fetched whole"
rewritten=false
if [ -n "$previous" ]; then
    gh api -H 'Accept: application/vnd.github.diff' "repos/$REPO/compare/$previous...$head" > "$work/delta.diff"
    # ahead (or identical): the previous head is an ancestor and the delta is all that changed since. Otherwise a
    # force-push rewrote what the last round reviewed (review round 4 of #0-270).
    case "$(gh api "repos/$REPO/compare/$previous...$head" --jq .status)" in
        ahead|identical) ;;
        *) rewritten=true ;;
    esac
fi

# Every commit, through the paginated commits API (gh pr view caps its list), with its author and co-authors.
commits='[]'
: > "$work/commits.txt"
# Into a variable first: a failure inside `for x in $(...)` would not stop the script, and leave no commit listed.
oids=$(gh api --paginate "repos/$REPO/pulls/$pr/commits" --jq '.[].sha')
[ -n "$oids" ] || die "pull request #$pr lists no commit"
# The lists of files and commits are capped by GitHub (review round 3 of #0-270): fewer than the pull request's own
# counts would be material a reviewer approves without having seen it, so it stops the fetch.
counts=$(gh api "repos/$REPO/pulls/$pr" --jq '{files: .changed_files, commits: .commits}')
listed_commits=$(wc -w <<<"$oids" | tr -d ' ')
[ "$(jq -r .files <<<"$counts")" = "$listed_files" ] && [ "$(jq -r .commits <<<"$counts")" = "$listed_commits" ] \
    || die "pull request #$pr has $(jq -r .files <<<"$counts") files and $(jq -r .commits <<<"$counts") commits, GitHub listed $listed_files and $listed_commits: too large to fetch whole"
for oid in $oids; do
    [[ $oid =~ ^[0-9a-f]{40}$ ]] || die "a commit of pull request #$pr has no SHA"
    # Only what is used, through gh's --jq: the whole answer, patches included, as an argument to jq would pass
    # macOS's ARG_MAX on a large commit (review round 4 of #0-270).
    c=$(gh api "repos/$REPO/commits/$oid" --jq '{login: .author.login, name: .commit.author.name, message: .commit.message}')
    { printf '=== %s\n' "$oid"; jq -r .message <<<"$c"; printf '\n'; } >> "$work/commits.txt"
    commits=$(jq -c --arg oid "$oid" --argjson c "$c" '. + [{oid: $oid,
        authors: ([$c.login // $c.name]
                  + [$c.message | split("\n")[] | (capture("^co-authored-by:[ \\t]*(?<n>[^<]*?)[ \\t]*<"; "i") | .n)?])}]' <<<"$commits")
done
gh pr view "$pr" --repo "$REPO" --json body --jq .body > "$work/pr-body.md"

# The files at the head, through the contents API, as `<path>.pr`; NUL-separated, so no character of a path is lost.
skipped='[]'
while IFS= read -r -d '' path; do
    mode=$(jq -r --arg p "$path" '.[$p] // "missing"' <<<"$modes")
    case "$mode" in
        100644|100755) ;;
        *) skipped=$(jq -c --arg p "$path" --arg m "$mode" '. + [{path: $p, mode: $m}]' <<<"$skipped"); continue ;;
    esac
    enc=$(jq -rn --arg p "$path" '$p | split("/") | map(@uri) | join("/")')
    mkdir -p "$work/files/$(dirname "$path")"
    gh api -H 'Accept: application/vnd.github.raw' "repos/$REPO/contents/$enc?ref=$head" > "$work/files/$path.pr"
done < <(jq -j '.[] | select(.status != "removed") | .path, "\u0000"' <<<"$files")

# The Test job's own counts (node --test prints `ℹ tests <n>`, `ℹ pass <n>`, ...), from its log, carriage returns and
# colour codes taken out first.
tests=null
test_link=$(jq -r 'map(select(.name == "Test"))[0].link // empty' <<<"$checks")
if [[ $test_link =~ /actions/runs/([0-9]+)/job/([0-9]+) ]]; then
    log=$(gh run view "${BASH_REMATCH[1]}" --repo "$REPO" --job "${BASH_REMATCH[2]}" --log 2>/dev/null || true)
    log=${log//$'\r'/}
    esc=$(printf '\033')
    # grep -E, not sed's \| (BSD sed on the owner's Mac has no alternation in a basic expression).
    tests=$(printf '%s\n' "$log" | sed -E "s/${esc}\[[0-9;]*m//g" \
        | { grep -oE 'ℹ (tests|pass|fail|skipped|cancelled) [0-9]+$' || true; } \
        | jq -Rn '[inputs | ltrimstr("ℹ ") | split(" ") | {(.[0]): (.[1] | tonumber)}] | add // null')
fi

# A push while this ran would leave material and CI of two heads: refuse it, so the gate's head is the material's.
now=$(gh pr view "$pr" --repo "$REPO" --json headRefOid --jq .headRefOid)
[ "$now" = "$head" ] || die "pull request #$pr moved from ${head:0:12} to ${now:0:12} while it was fetched: run again" 3

jq -n --arg repo "$REPO" --argjson pr "$pr" --argjson view "$view" --argjson files "$files" --argjson skipped "$skipped" \
      --argjson checks "$checks" --argjson tests "$tests" --arg status "$status" --arg previous "$previous" \
      --argjson commits "$commits" --argjson ci_changed "$ci_changed" --argjson rewritten "$rewritten" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    repository: $repo, pullRequest: $pr, status: $status,
    head: $view.headRefOid, base: $view.baseRefOid, branch: $view.headRefName, draft: $view.isDraft,
    author: $view.author.login, title: $view.title,
    previous: (if $previous == "" then null else $previous end), previousRewritten: $rewritten,
    commits: $commits, files: $files, notWritten: $skipped,
    ciChanged: $ci_changed,
    ci: [$checks[] | {name, state, bucket}], tests: $tests,
    fetchedAt: $at,
    notRun: ["nothing of the change ran on this machine: its tests and linters are the pull request'"'"'s own CI on GitHub (Test, Lint Workflows, Secret Scan)",
             "incident-platform'"'"'s check of factory'"'"'s copies (check-factory-copies.rb, ADR-0061) runs after the merge, not on this pull request"]
}' > "$work/gate-r1.json"

mv "$work" "$dir"
trap - EXIT
jq -c --arg dir "$dir" '{status, dir: $dir, head, tests, ciChanged}' "$dir/gate-r1.json"
