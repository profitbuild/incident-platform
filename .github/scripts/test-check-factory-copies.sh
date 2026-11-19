#!/usr/bin/env bash
# ============================================================
# Tests .github/scripts/check-factory-copies.rb (backlog #0-268, ADR-0061): one temporary directory per case, holding
# a product tree (this repository's compared files, cut down; the pull request's head), a `base` tree (main as the
# merge commit has it, a copy of the product taken when the case starts) and a `factory` tree whose copies equal
# them; the case then changes the product (a difference the pull request brings) or `factory` (one main has already),
# and the checker runs from the product tree. Every case names the message it must give and the exit status it must
# end with, so a case cannot pass on another finding, and which differences fail is tested on its own: on a pull
# request that changes a compared file, only those it brings.
#
# Run by the lint-workflows job in .github/workflows/ci.yml, before the checker; locally:
#   .github/scripts/test-check-factory-copies.sh            (on the Ruby of .ruby-version; ci-local.sh runs it so)
# ============================================================
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
CHECKER=$HERE/check-factory-copies.rb
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
passed=0
n=0
dir=""
SHA_CHECKOUT=1111111111111111111111111111111111111111
SHA_NODE=2222222222222222222222222222222222222222
SHA_OTHER=3333333333333333333333333333333333333333
MARKER=MarkerThatMustNotReachTheLog

# put <tree> <file> <line...>: writes the lines into the file of the case's product or factory tree.
put() {
    local tree=$1 file=$2; shift 2
    mkdir -p "$(dirname "$dir/$tree/$file")"
    printf '%s\n' "$@" > "$dir/$tree/$file"
}

workflow() { # workflow <tree> [<extra env line>...]
    local tree=$1; shift
    put "$tree" .github/workflows/ci.yml 'name: CI' 'on: push' 'jobs:' '  lint:' '    runs-on: ubuntu-latest' \
        '    env:' \
        '      ACTIONLINT_VERSION: v1.7.12' '      ACTIONLINT_SHA256: aaaa' \
        '      SHELLCHECK_VERSION: v0.11.0' '      SHELLCHECK_SHA256: bbbb' \
        '      ZIZMOR_VERSION: v1.30.1' '      ZIZMOR_SHA256: cccc' \
        '      BETTERLEAKS_VERSION: v1.9.0' '      BETTERLEAKS_SHA256: dddd' \
        "$@" \
        '    steps:' \
        "      - uses: actions/checkout@$SHA_CHECKOUT # v7.0.1" \
        '      - run: echo lint'
}

script_body() { printf '%s\n' '#!/usr/bin/env bash' '# ====' "# $1, the original." '#' '# Body comment.' 'echo ok'; }
notice() { printf '%s\n' "# A copy of profitbuild/incident-platform's .github/scripts/$1 (backlog #0-268 there)." \
    '# Kept equal to it.' '#'; }
# copy <name>: the factory copy of a script: the original with the notice after its first bare `#` line.
copy() { script_body "$1" | awk -v notice="$(notice "$1")" '{ print } !done && /^#$/ { print notice; done = 1 }'; }

PRODUCT_DENIES='{"permissions":{"deny":["Bash(git push --force *)","Bash(gh pr review *)","Bash(*repository-settings.rb plan*)","Read(./docker/.env)"]}}'

# fresh: a new case whose trees match; `base` is a copy of the product.
fresh() {
    n=$((n+1)); dir="$WORK/case$n"
    mkdir -p "$dir/product/.github/scripts" "$dir/factory/.github/scripts"
    workflow product
    workflow factory
    put product .github/actions/setup-node/action.yml '# The original setup-node.' 'name: Set up Node' 'runs:' \
        '  using: composite' '  steps:' "    - uses: actions/setup-node@$SHA_NODE # v6" 'description: x'
    put factory .github/actions/setup-node/action.yml '# The copy of setup-node, other words.' 'name: Set up Node' \
        'runs:' '  using: composite' '  steps:' "    - uses: actions/setup-node@$SHA_NODE # v6" 'description: x'
    put product .github/zizmor.yml '# The original config.' 'rules:' '  self-repository:' '    disable: true'
    put factory .github/zizmor.yml '# The copy, other words.' 'rules:' '  self-repository:' '    # why, here' \
        '    disable: true'
    for s in install-pinned-tool.sh secret-scan.sh test-secret-scan.sh; do
        script_body "$s" > "$dir/product/.github/scripts/$s"
        copy "$s" > "$dir/factory/.github/scripts/$s"
    done
    put product .node-version 24.22.1
    put factory .node-version 24.22.1
    put product .claude/settings.json "$PRODUCT_DENIES"
    put factory .claude/settings.json '{"permissions":{"deny":["Bash(git push --force *)","Bash(gh pr review *)"]}}'
    cp -R "$dir/product" "$dir/base"
}

# run_checker <changed file>...: runs the checker from the product tree; with changed files, as a pull request that
# changes them, `base` its main. Sets out and rc.
run_checker() {
    local args=("$dir/factory")
    if [ $# -gt 0 ]; then
        printf '%s\n' "$@" > "$dir/changed.txt"
        args+=(--changed "$dir/changed.txt" --baseline "$dir/base")
    fi
    rc=0
    out=$(cd "$dir/product" && ruby "$CHECKER" "${args[@]}" 2>&1) || rc=$?
}
# expect <name> <exit status> <text the output must contain> [<changed file>...]
expect() {
    local name=$1 want=$2 text=$3; shift 3
    run_checker "$@"
    if [ "$rc" -ne "$want" ]; then echo "::error::$name: exit $rc, not $want: $out"; failures=$((failures+1)); return; fi
    case "$out" in
        *"$text"*) echo "  ok: $name"; passed=$((passed+1)) ;;
        *) echo "::error::$name: the output does not contain '$text': $out"; failures=$((failures+1)) ;;
    esac
}
replace() { # replace <tree> <file> <from> <to>
    local f="$dir/$1/$2" tmp
    tmp=$(mktemp)
    sed "s|$3|$4|" "$f" > "$tmp" && mv "$tmp" "$f"
}

echo "check-factory-copies.rb: matching copies"
fresh; expect "two trees that match, a push" 0 "factory's copies match this repository's"
fresh; expect "two trees that match, a PR that changes ci.yml" 0 "factory's copies match" .github/workflows/ci.yml
fresh; expect "check-shell.rb not given a shellcheck is a warning" 0 "::warning::factory: check-shell.rb not run"
fresh; expect "optional denies are not required in factory" 0 "factory's copies match" .claude/settings.json
fresh; put factory .claude/settings.json '{"permissions":{"deny":["Bash(git push --force *)","Bash(gh pr review *)","Read(./docker/.env)"]}}'
expect "an optional deny factory adds is no finding" 0 "factory's copies match" .claude/settings.json
fresh; { notice action.yml; cat "$dir/factory/.github/actions/setup-node/action.yml"; } > "$dir/x" && mv "$dir/x" "$dir/factory/.github/actions/setup-node/action.yml"
expect "a notice on a comment-compared copy is no unlisted copy" 0 "factory's copies match" .github/workflows/ci.yml

echo "check-factory-copies.rb: this repository leads (a difference the pull request brings)"
fresh; replace product .github/workflows/ci.yml 'BETTERLEAKS_VERSION: v1.9.0' 'BETTERLEAKS_VERSION: v1.10.0'
expect "a bump here, factory behind, fails the PR" 1 "::error::factory's BETTERLEAKS_VERSION is v1.9.0, this repository's v1.10.0" .github/workflows/ci.yml
expect "the failing summary names the file the PR changed" 1 "it changes .github/workflows/ci.yml" .github/workflows/ci.yml
expect "the same difference on a PR that changes no compared file only warns" 0 "::warning::factory's BETTERLEAKS_VERSION is v1.9.0" README.md
expect "the same difference on a push only warns" 0 "reported as warnings: this run changes none of the compared files"
fresh; replace product .github/workflows/ci.yml "checkout@$SHA_CHECKOUT" "checkout@$SHA_OTHER"
expect "an action bumped here, factory behind" 1 "::error::factory uses actions/checkout@$SHA_CHECKOUT, this repository $SHA_OTHER" .github/workflows/ci.yml
fresh; printf 'echo changed\n' >> "$dir/product/.github/scripts/secret-scan.sh"
expect "a script changed here, its copy behind" 1 "::error::factory's .github/scripts/secret-scan.sh differs from this repository's (sha256 " .github/scripts/secret-scan.sh
fresh; printf 'echo factory only\n' >> "$dir/factory/.github/scripts/secret-scan.sh"
expect "a copy that differs on main already only warns" 0 "::warning::factory's .github/scripts/secret-scan.sh differs" .github/scripts/secret-scan.sh
printf 'echo changed here too\n' >> "$dir/product/.github/scripts/secret-scan.sh"
expect "a further change here cannot hide behind that drift" 1 "::error::factory's .github/scripts/secret-scan.sh differs" .github/scripts/secret-scan.sh
fresh; replace product .github/actions/setup-node/action.yml 'description: x' 'description: y'
expect "setup-node changed here beyond its comments" 1 "::error::factory's .github/actions/setup-node/action.yml differs from this repository's (sha256 " .github/actions/setup-node/action.yml
fresh; put product .github/zizmor.yml 'rules:' '  self-repository:' '    disable: false'
expect "zizmor.yml changed here beyond its comments" 1 "::error::factory's .github/zizmor.yml differs from this repository's (sha256 " .github/zizmor.yml
fresh; put product .node-version 24.22.2
expect ".node-version bumped here" 1 "::error::factory's .node-version is 24.22.1, this repository's 24.22.2" .node-version
fresh; put product .claude/settings.json '{"permissions":{"deny":["Bash(git push --force *)","Bash(gh pr review *)","Read(./.env)"]}}'
expect "a generic .env deny here is required in factory" 1 "::error::factory's .claude/settings.json does not deny Read(./.env)" .claude/settings.json
fresh; put product .claude/settings.json '{"permissions":{"deny":["Bash(git push --force *)","Bash(gh pr review *)","Bash(rm *)"]}}'
expect "a deny added here, factory without it" 1 "::error::factory's .claude/settings.json does not deny Bash(rm *)" .claude/settings.json
fresh; put product .claude/settings.json '{"permissions":{"deny":["Bash(git push --force *)"]}}'
expect "a deny removed here, factory still with it" 1 "::error::factory's .claude/settings.json denies Bash(gh pr review *), which this repository does not" .claude/settings.json

echo "check-factory-copies.rb: drift factory started is main's, not the pull request's"
fresh; replace factory .github/workflows/ci.yml 'BETTERLEAKS_VERSION: v1.9.0' 'BETTERLEAKS_VERSION: v1.8.0'
expect "factory ahead or behind on its own: a PR that changes ci.yml only warns" 0 "::warning::factory's BETTERLEAKS_VERSION is v1.8.0" .github/workflows/ci.yml
expect "and says so in its summary" 0 "all of them are on main already" .github/workflows/ci.yml
replace product .github/workflows/ci.yml 'ZIZMOR_VERSION: v1.30.1' 'ZIZMOR_VERSION: v1.31.0'
expect "a difference the PR brings still fails beside one main has" 1 "::error::factory's ZIZMOR_VERSION is v1.30.1, this repository's v1.31.0" .github/workflows/ci.yml
expect "the summary counts the one main has" 1 "1 more already on main" .github/workflows/ci.yml

echo "check-factory-copies.rb: what only factory can start (found as warnings on a push)"
fresh; replace factory .github/workflows/ci.yml '      ZIZMOR_SHA256: cccc' '      OTHER: x'
expect "a required pin missing in factory" 0 "::warning::factory's CI has no ZIZMOR_SHA256"
fresh; workflow factory '      FOO_VERSION: v1'
expect "a pin factory has and this repository does not" 0 "factory pins FOO_VERSION (v1), which this repository does not pin"
fresh; replace factory .github/workflows/ci.yml "actions/checkout@$SHA_CHECKOUT" "actions/cache@$SHA_OTHER"
expect "an action this repository does not use" 0 "factory uses actions/cache, which this repository does not"
fresh; script_body secret-scan.sh > "$dir/factory/.github/scripts/secret-scan.sh"
expect "a copy without its notice" 0 "factory's .github/scripts/secret-scan.sh has no copy notice"
fresh; { notice secret-scan.sh | head -2; echo 'echo no bare line ends it'; } > "$dir/factory/.github/scripts/secret-scan.sh"
expect "a notice with no bare # line after it" 0 "factory's .github/scripts/secret-scan.sh has no copy notice"
fresh; rm "$dir/factory/.github/scripts/test-secret-scan.sh"
expect "a copy missing in factory" 0 "factory has no .github/scripts/test-secret-scan.sh"
fresh; copy other.sh > "$dir/factory/.github/scripts/other.sh"
expect "a file with the notice that COPIES does not list" 0 "factory's .github/scripts/other.sh says it is a copy of this repository's, but check-factory-copies.rb does not list it in COPIES"
fresh; put factory .claude/settings.json '{"permissions":{"deny":["Bash(git push --force *)","Bash(gh pr review *)","Bash(rm *)"]}}'
expect "a deny only factory has" 0 "factory's .claude/settings.json denies Bash(rm *), which this repository does not"

echo "check-factory-copies.rb: factory's own checks are warnings"
fresh; workflow factory; printf '%s\n' '      - run: curl -fsSL https://example.com/tool | sh' >> "$dir/factory/.github/workflows/ci.yml"
expect "a check-downloads.rb finding in factory warns, even on a PR that changes ci.yml" 0 "::warning::factory: check-downloads.rb: .github/workflows/ci.yml" .github/workflows/ci.yml

echo "check-factory-copies.rb: the checkout is outside input (SEC-31)"
fresh; put factory .claude/settings.json "{\"permissions\": $MARKER }"
expect "a settings file that does not parse fails, on a push too" 1 "factory's .claude/settings.json does not parse (JSON::ParserError)"
case "$out" in *"$MARKER"*) echo "::error::the parse error carries the file's text: $out"; failures=$((failures+1)) ;; *) echo "  ok: the parse error quotes nothing of the file"; passed=$((passed+1)) ;; esac
fresh; printf '%s\n' "$MARKER" > "$dir/outside.txt"; rm "$dir/factory/.claude/settings.json"; ln -s "$dir/outside.txt" "$dir/factory/.claude/settings.json"
expect "a symlinked settings file is refused before it is read" 1 "factory's .claude/settings.json is a symlink"
case "$out" in *"$MARKER"*) echo "::error::the symlink's target reached the output: $out"; failures=$((failures+1)) ;; *) echo "  ok: nothing of the symlink's target is printed"; passed=$((passed+1)) ;; esac
fresh; mv "$dir/factory/.github/scripts" "$dir/elsewhere"; ln -s "$dir/elsewhere" "$dir/factory/.github/scripts"
expect "a symlinked directory on the way to a copy is refused" 1 "factory's .github/scripts is a symlink"
fresh; ln -s "$dir/product/.github/workflows/ci.yml" "$dir/factory/.github/workflows/other.yml"
expect "a symlinked workflow is refused" 1 "factory's .github/workflows/other.yml is a symlink"
fresh; mkdir -p "$dir/factory/dispatcher"; ln -s "$dir/outside.txt" "$dir/factory/dispatcher/run.sh"
expect "a symlink anywhere in the checkout is refused, before the sub-checks read it" 1 "factory's dispatcher/run.sh is a symlink"
fresh; mkdir -p "$dir/elsewhere-git"; ln -s "$dir/elsewhere-git" "$dir/factory/.git"
expect "a .git that is a symlink is refused" 1 "factory's .git is a symlink"

echo "check-factory-copies.rb: fails closed"
fresh; rm -rf "$dir/factory/.github/workflows"
expect "a factory checkout with no workflows, even on a push" 1 "is not a checkout of profitbuild/factory"
fresh
rc=0; out=$(cd "$dir/product" && ruby "$CHECKER" 2>&1) || rc=$?
if [ "$rc" -eq 2 ] && [[ "$out" == *usage:* ]]; then echo "  ok: no argument"; passed=$((passed+1)); else echo "::error::no argument: exit $rc: $out"; failures=$((failures+1)); fi
printf '.node-version\n' > "$dir/changed.txt"
rc=0; out=$(cd "$dir/product" && ruby "$CHECKER" "$dir/factory" --changed "$dir/changed.txt" 2>&1) || rc=$?
if [ "$rc" -eq 2 ] && [[ "$out" == *usage:* ]]; then echo "  ok: --changed without --baseline"; passed=$((passed+1)); else echo "::error::--changed without --baseline: exit $rc: $out"; failures=$((failures+1)); fi

if [ "$failures" -gt 0 ]; then echo "$failures check-factory-copies case(s) failed"; exit 1; fi
echo "All $passed check-factory-copies cases passed."
