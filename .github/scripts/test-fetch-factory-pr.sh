#!/usr/bin/env bash
# ============================================================
# Tests scripts/factory-admin/fetch-factory-pr.sh (backlog #0-270): a fake `gh` on PATH serves one pull request from
# files (its view, checks, files, commits, tree, contents, the compare diffs and the Test job's log), each case changes
# one of them, and the script runs into a temporary output root. Every case names the message or the file it must
# give, and a refusing case checks that nothing was written.
#
# Run by Factory guards (.github/workflows/factory-guards.yml); locally: .github/scripts/test-fetch-factory-pr.sh
# ============================================================
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=$HERE/../../scripts/factory-admin/fetch-factory-pr.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
passed=0
n=0
HEAD=1111111111111111111111111111111111111111
BASE=9999999999999999999999999999999999999999
PREV=2222222222222222222222222222222222222222
C1=3333333333333333333333333333333333333333

# The fake gh: dispatches on its arguments, serves $FAKE/<file>; --jq is applied with jq, as gh does. The second and
# later `pr view --json headRefOid` read view-after.json when the case wrote one (a push during the fetch).
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE/calls.log"
jqexpr=""; args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --jq) jqexpr=$2; shift 2 ;;
        -H) args+=("H:$2"); shift 2 ;;
        *) args+=("$1"); shift ;;
    esac
done
set -- "${args[@]}"
out() { if [ -n "$jqexpr" ]; then jq -r "$jqexpr" "$1"; else cat "$1"; fi; }
case "$1 $2" in
    "pr view")
        case "$*" in
            *body*) out "$FAKE/body.json" ;;
            *"--json headRefOid"*) if [ -e "$FAKE/view-after.json" ]; then out "$FAKE/view-after.json"; else out "$FAKE/view.json"; fi ;;
            *) out "$FAKE/view.json" ;;
        esac ;;
    "pr checks") cat "$FAKE/checks.json"; exit "$(cat "$FAKE/checks.rc")" ;;
    "run view") cat "$FAKE/test.log" ;;
    *)
        accept=""; path=""
        for a in "$@"; do case "$a" in H:*) accept=${a#H:}; accept=${accept#Accept: } ;; repos/*) path=$a ;; esac; done
        case "$path" in
            */pulls/*/files) out "$FAKE/files.json" ;;
            */pulls/*/commits) out "$FAKE/commits.json" ;;
            */pulls/[0-9]*)
                # The pull request's own counts: from the lists unless a case wrote pull.json.
                if [ ! -e "$FAKE/pull.json" ]; then
                    jq -n --slurpfile f "$FAKE/files.json" --slurpfile c "$FAKE/commits.json" \
                        '{changed_files: ($f[0] | length), commits: ($c[0] | length)}' > "$FAKE/pull.auto.json"
                    out "$FAKE/pull.auto.json"
                else out "$FAKE/pull.json"; fi ;;
            */commits/*) out "$FAKE/commit-${path##*/}.json" ;;
            */compare/*)
                # The diff with the diff Accept, else the comparison's JSON (its status: ahead unless a case says).
                range=${path##*/compare/}
                if [ "$accept" = "application/vnd.github.diff" ]; then cat "$FAKE/compare-$range.diff"
                elif [ -e "$FAKE/compare-$range.json" ]; then out "$FAKE/compare-$range.json"
                else echo '{"status": "ahead"}' > "$FAKE/compare.auto.json"; out "$FAKE/compare.auto.json"; fi ;;
            */git/trees/*) out "$FAKE/tree.json" ;;
            */contents/*)
                rel=${path#*/contents/}; rel=${rel%%\?*}; rel=$(printf '%b' "${rel//%/\\x}")
                [ "$accept" = "application/vnd.github.raw" ] || { echo "fake gh: contents without the raw Accept" >&2; exit 98; }
                cat "$FAKE/raw/$rel" ;;
            *) echo "fake gh: unexpected call: $*" >&2; exit 99 ;;
        esac ;;
esac
EOF
chmod +x "$WORK/bin/gh"

# add_file <path> <status> [<mode>] [<content>]: a file of the pull request, its tree entry and its content.
add_file() {
    local path=$1 st=$2 mode=${3:-100644} content=${4:-content of $1}
    jq --arg p "$path" --arg s "$st" '. + [{filename: $p, status: $s}]' "$FAKE/files.json" > "$FAKE/f" && mv "$FAKE/f" "$FAKE/files.json"
    jq --arg p "$path" --arg m "$mode" '.tree += [{path: $p, mode: $m}]' "$FAKE/tree.json" > "$FAKE/t" && mv "$FAKE/t" "$FAKE/tree.json"
    mkdir -p "$FAKE/raw/$(dirname "$path")"; printf '%s\n' "$content" > "$FAKE/raw/$path"
    printf 'diff --git a/%s b/%s\n+x\n' "$path" "$path" >> "$FAKE/compare-$BASE...$HEAD.diff"
}

# fresh: a new case: an open pull request #7 at $HEAD on $BASE, one commit, two files (one in a subdirectory, with a
# space) and a removed one, CI green.
fresh() {
    n=$((n+1)); export FAKE="$WORK/case$n"; OUT="$WORK/out$n"
    mkdir -p "$FAKE/raw"
    jq -n --arg h "$HEAD" --arg b "$BASE" '{number: 7, state: "OPEN", isDraft: true, headRefOid: $h, baseRefOid: $b,
        headRefName: "docs/x", author: {login: "app/profitbuild-factory-dev"}, title: "docs: x"}' > "$FAKE/view.json"
    printf '%s\n' '{"body": "## Summary\n- x"}' > "$FAKE/body.json"
    jq -n '[{name: "Test", state: "SUCCESS", bucket: "pass", link: "https://github.com/profitbuild/factory/actions/runs/41/job/42"},
            {name: "Secret Scan", state: "SUCCESS", bucket: "pass", link: "https://x/actions/runs/41/job/43"}]' > "$FAKE/checks.json"
    echo 0 > "$FAKE/checks.rc"
    : > "$FAKE/compare-$BASE...$HEAD.diff"
    echo '[]' > "$FAKE/files.json"; echo '{"truncated": false, "tree": []}' > "$FAKE/tree.json"
    add_file README.md modified 100644 '# readme'
    add_file 'docs/new file.md' added 100644 '# new'
    jq '. + [{filename: "old.md", status: "removed"}]' "$FAKE/files.json" > "$FAKE/f" && mv "$FAKE/f" "$FAKE/files.json"
    printf 'diff --git a/old.md b/old.md\n-x\n' >> "$FAKE/compare-$BASE...$HEAD.diff"
    jq -n --arg c "$C1" '[{sha: $c}]' > "$FAKE/commits.json"
    jq -n '{author: {login: "profitbuild-factory-dev[bot]"}, commit: {author: {name: "x"},
        message: "docs(factory): x (incident-platform backlog #0-270)\n\nThe full body, past seventy-two characters of the subject line.\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"}}' > "$FAKE/commit-$C1.json"
    printf 'Test\tThe tests\t2026-11-19T10:00:00Z ℹ tests 32\nTest\tThe tests\t2026-11-19T10:00:00Z ℹ pass 32\nTest\tThe tests\t2026-11-19T10:00:00Z ℹ fail 0\n' > "$FAKE/test.log"
    : > "$FAKE/calls.log"
}
run() { rc=0; out=$(PATH="$WORK/bin:$PATH" FETCH_FACTORY_PR_OUT_ROOT="$OUT" "$SCRIPT" "$@" 2>&1) || rc=$?; }
ok() { echo "  ok: $1"; passed=$((passed+1)); }
bad() { echo "::error::$1"; failures=$((failures+1)); }
dir() { printf '%s/factory-pr7-%s' "$OUT" "${HEAD:0:12}"; }
nothing_written() { [ -z "$(find "$OUT" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; }
# refused <exit> <message part> <name>: the run exited so, said so, and wrote nothing.
refused() {
    if [ "$rc" -eq "$1" ] && case "$out" in *"$2"*) true ;; *) false ;; esac && nothing_written; then ok "$3, nothing written"
    else bad "$3: exit $rc: $out"; fi
}

echo "fetch-factory-pr.sh: the material"
fresh; run 7; d=$(dir); g=$d/gate-r1.json
if [ "$rc" -eq 0 ] && [ -d "$d" ]; then ok "an open pull request with green CI is fetched into factory-pr7-<head12>"; else bad "fetched: exit $rc: $out"; fi
if cmp -s "$d/factory.diff" "$FAKE/compare-$BASE...$HEAD.diff"; then ok "factory.diff is base...head, pinned to the head (not gh pr diff)"; else bad "factory.diff"; fi
if grep -q 'past seventy-two characters' "$d/commits.txt"; then ok "commits.txt holds each commit's full message"; else bad "commits.txt"; fi
if grep -q '## Summary' "$d/pr-body.md"; then ok "pr-body.md is the description"; else bad "pr-body.md"; fi
if [ "$(cat "$d/files/docs/new file.md.pr")" = "# new" ] && [ "$(cat "$d/files/README.md.pr")" = "# readme" ]; then
    ok "files/ holds each added or modified file at the head as <path>.pr, a path with a space included"; else bad "files/"; fi
if [ -z "$(find "$d/files" -type f ! -name '*.pr')" ]; then ok "no file is written under its own name (nothing a loader or the verifier takes for its own)"; else bad "a file without .pr"; fi
if [ ! -e "$d/files/old.md.pr" ] && [ ! -e "$d/files/old.md" ]; then ok "a removed file is not fetched"; else bad "removed file fetched"; fi
if [ ! -e "$d/delta.diff" ]; then ok "no delta.diff without --previous"; else bad "delta.diff without --previous"; fi
if [ "$(jq -r .status "$g")" = pass ] && [ "$(jq -r .head "$g")" = "$HEAD" ]; then ok "the gate says pass, at the head"; else bad "status/head"; fi
if [ "$(jq -c .tests "$g")" = '{"tests":32,"pass":32,"fail":0}' ]; then ok "the gate carries the Test job's counts from its log"; else bad "tests: $(jq -c .tests "$g")"; fi
if [ "$(jq -r '.commits[0].authors | join(",")' "$g")" = "profitbuild-factory-dev[bot],Claude Opus 5.5" ]; then
    ok "the gate names each commit's author and co-authors"; else bad "authors: $(jq -c .commits "$g")"; fi
if [ "$(jq -r '.files | length' "$g")" = 3 ]; then ok "the gate lists every file with its status"; else bad "files in the gate"; fi
if [ "$(jq -r .ciChanged "$g")" = false ]; then ok "a pull request that leaves .github/ alone has ciChanged false"; else bad "ciChanged"; fi
if grep -q 'check-factory-copies.rb' "$g"; then ok "notRun names the copy check that does not run on the pull request"; else bad "notRun"; fi
case "$out" in *'"status":"pass"'*factory-pr7-*) ok "it prints the status and the directory" ;; *) bad "output: $out" ;; esac
if [ -z "$(find "$OUT" -maxdepth 1 -name '.factory-pr7.*')" ]; then ok "no temporary directory is left"; else bad "temporary directory left"; fi
if [ "$(grep -c -- '--json headRefOid ' "$FAKE/calls.log")" -ge 1 ]; then ok "the head is read again at the end"; else bad "head not re-read"; fi

fresh; printf 'delta\n' > "$FAKE/compare-$PREV...$HEAD.diff"; run 7 --previous "$PREV"; d=$(dir)
if [ "$(jq -r .previousRewritten "$d/gate-r1.json")" = false ]; then ok "a previous head that is an ancestor gives previousRewritten false"; else bad "previousRewritten false: $out"; fi
if [ "$(cat "$d/delta.diff")" = delta ] && [ "$(jq -r .previous "$d/gate-r1.json")" = "$PREV" ]; then
    ok "--previous writes delta.diff, previous...head, and names the previous head"; else bad "--previous: exit $rc: $out"; fi

fresh; printf 'delta\n' > "$FAKE/compare-$PREV...$HEAD.diff"; echo '{"status": "diverged"}' > "$FAKE/compare-$PREV...$HEAD.json"
run 7 --previous "$PREV"
if [ "$(jq -r .previousRewritten "$(dir)/gate-r1.json")" = true ]; then ok "a force-push since the previous head gives previousRewritten true"; else bad "previousRewritten true: $out"; fi
fresh; run 7
if [ "$(jq -r .previousRewritten "$(dir)/gate-r1.json")" = false ]; then ok "without --previous, previousRewritten is false"; else bad "previousRewritten without --previous"; fi
fresh; sed -i.bak '/old.md/d' "$FAKE/compare-$BASE...$HEAD.diff"; run 7
refused 1 "not fetched whole" "a diff of fewer files than the pull request is refused"
fresh; add_file .github/workflows/ci.yml modified; run 7
if [ "$(jq -r .ciChanged "$(dir)/gate-r1.json")" = true ]; then ok "a pull request that changes a workflow has ciChanged true"; else bad "ciChanged, workflow: $out"; fi
fresh; add_file .github/actions/setup-node/action.yml modified; run 7
if [ "$(jq -r .ciChanged "$(dir)/gate-r1.json")" = true ]; then ok "a pull request that changes an action a workflow runs has ciChanged true"; else bad "ciChanged, action: $out"; fi
fresh; add_file readme.md added; run 7
refused 1 "differ only in case" "two paths that differ only in case (README.md, readme.md) are refused"
fresh; echo '[]' > "$FAKE/commits.json"; run 7
refused 1 "lists no commit" "a pull request whose commits cannot be listed is refused"
fresh; echo '{"changed_files": 3001, "commits": 1}' > "$FAKE/pull.json"; run 7
refused 1 "too large to fetch whole" "more files than GitHub listed (its cap) are refused"
fresh; echo '{"changed_files": 3, "commits": 251}' > "$FAKE/pull.json"; run 7
refused 1 "too large to fetch whole" "more commits than GitHub listed (its cap) are refused"
for p in "$(printf 'caf\xc3\xa9.md')" "$(printf '\xc3\x84.md')"; do
    fresh; add_file "$p" added; run 7
    refused 1 "outside ASCII" "a path outside ASCII ($p) is refused"
done
fresh; rm "$FAKE/commits.json"; run 7
if [ "$rc" -ne 0 ] && nothing_written; then ok "a failed commits call stops the run, nothing written (not an empty list)"; else bad "failed commits call: exit $rc: $out"; fi
fresh; add_file 'odd\name.md' added 100644 '# backslash'; run 7
if [ "$(cat "$(dir)/files/odd\\name.md.pr")" = "# backslash" ]; then ok "a path with a backslash is fetched whole (NUL-separated, not @tsv)"; else bad "backslash: exit $rc: $out"; fi
fresh; printf 'Test\tx\t2026-11-19T10:00:00Z \033[32mℹ tests 5\033[0m\r\nTest\tx\t2026-11-19T10:00:00Z ℹ pass 5\r\n' > "$FAKE/test.log"; run 7
if [ "$(jq -c .tests "$(dir)/gate-r1.json")" = '{"tests":5,"pass":5}' ]; then ok "colour codes and carriage returns in the log do not hide the counts"; else bad "ANSI/CR: $out"; fi

echo "fetch-factory-pr.sh: CI decides"
fresh; jq '.[1].bucket = "fail" | .[1].state = "FAILURE"' "$FAKE/checks.json" > "$FAKE/c" && mv "$FAKE/c" "$FAKE/checks.json"; echo 1 > "$FAKE/checks.rc"
run 7
if [ "$rc" -eq 0 ] && [ "$(jq -r .status "$(dir)/gate-r1.json")" = fixable ]; then ok "a failed check gives status fixable (the material is still written)"; else bad "fixable: exit $rc: $out"; fi
fresh; jq '.[0].bucket = "pending"' "$FAKE/checks.json" > "$FAKE/c" && mv "$FAKE/c" "$FAKE/checks.json"; echo 8 > "$FAKE/checks.rc"
run 7
refused 3 "still running" "CI still running: exit 3"
fresh; echo '[]' > "$FAKE/checks.json"; run 7
refused 1 "no check yet" "no check yet: refused"
fresh; jq --arg h "$PREV" '.headRefOid = $h' "$FAKE/view.json" > "$FAKE/view-after.json"; run 7
refused 3 "while it was fetched" "a push while it fetches: exit 3"

echo "fetch-factory-pr.sh: refusals"
for p in '../escape.md' 'a/../../b.md' '/etc/passwd' 'a/..'; do
    fresh; jq --arg p "$p" '. + [{filename: $p, status: "added"}]' "$FAKE/files.json" > "$FAKE/f" && mv "$FAKE/f" "$FAKE/files.json"
    run 7
    refused 1 "refused path" "a path like $p is refused"
done
fresh; jq '. + [{filename: "a\nb.md", status: "added"}]' "$FAKE/files.json" > "$FAKE/f" && mv "$FAKE/f" "$FAKE/files.json"; run 7
refused 1 "control character" "a path with a newline is refused as a control character"
fresh; jq '(.tree[] | select(.path == "README.md") | .mode) = "120000"' "$FAKE/tree.json" > "$FAKE/t" && mv "$FAKE/t" "$FAKE/tree.json"; run 7
if [ ! -e "$(dir)/files/README.md.pr" ] && [ "$(jq -r '.notWritten[0].mode' "$(dir)/gate-r1.json")" = 120000 ]; then
    ok "a symlink by its tree mode is listed in notWritten, not written, whatever the contents API serves"; else bad "symlink: $out"; fi
fresh; jq '(.tree[] | select(.path == "README.md") | .mode) = "160000"' "$FAKE/tree.json" > "$FAKE/t" && mv "$FAKE/t" "$FAKE/tree.json"; run 7
if [ "$(jq -r '.notWritten[0].mode' "$(dir)/gate-r1.json")" = 160000 ]; then ok "a submodule is listed, not written"; else bad "submodule: $out"; fi
fresh; jq '.truncated = true' "$FAKE/tree.json" > "$FAKE/t" && mv "$FAKE/t" "$FAKE/tree.json"; run 7
refused 1 "truncated" "a truncated tree is refused"
fresh; rm "$FAKE/raw/docs/new file.md"; run 7
if [ "$rc" -ne 0 ]; then ok "a gh failure mid-fetch fails the run"; else bad "mid-fetch failure passed"; fi
if nothing_written; then ok "  and leaves no directory, temporary or final"; else bad "mid-fetch failure left: $(find "$OUT")"; fi
fresh; jq '.state = "MERGED"' "$FAKE/view.json" > "$FAKE/v" && mv "$FAKE/v" "$FAKE/view.json"; run 7
refused 1 "MERGED, not open" "a pull request that is not open is refused"
fresh; mkdir -p "$(dir)"; run 7
if [ "$rc" -eq 1 ] && case "$out" in *"fetched already"*) true ;; *) false ;; esac; then ok "an existing directory is refused, not overwritten"; else bad "existing dir: exit $rc: $out"; fi
fresh
for a in "" "x" "0" "7 --previous abc" "7 --bogus"; do
    # shellcheck disable=SC2086 # the argument list is split on purpose
    run $a
    if [ "$rc" -eq 2 ] && case "$out" in *usage:*) true ;; *) false ;; esac; then ok "arguments '$a' give the usage"; else bad "arguments '$a': exit $rc: $out"; fi
done

calls=$(cat "$WORK"/case*/calls.log)
if printf '%s\n' "$calls" | grep -qvE '^(pr (view|checks) |api |run view )' || printf '%s\n' "$calls" | grep -qE -- '-X|--method|-f |-F |--field|pr diff'; then
    bad "a gh call that is not a read, or gh pr diff: $calls"
else
    ok "gh is only read from: pr view/checks, api GETs, run view, never gh pr diff (across every case)"
fi

if [ "$failures" -gt 0 ]; then echo "$failures fetch-factory-pr case(s) failed"; exit 1; fi
echo "All $passed fetch-factory-pr cases passed."
