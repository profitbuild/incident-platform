#!/usr/bin/env bash
# ============================================================
# Tests .github/scripts/ci-local-steps.rb and the arguments of .github/scripts/ci-local.sh (backlog #0-166 PR 2),
# without Docker: the step runner on workflows written per case, the wrapper with CI_LOCAL_DRY_RUN=1 (it stops
# after reading its arguments). Every case names the output it must give, so a case cannot pass on another rule.
# Run by .github/workflows/factory-guards.yml; locally: .github/scripts/test-ci-local.sh
# ============================================================
# The cases write workflows and step scripts as literal text: `$` in single quotes is meant.
# shellcheck disable=SC2016
set -uo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
STEPS=${STEPS:-$HERE/ci-local-steps.rb}
WRAPPER=${WRAPPER:-$HERE/ci-local.sh}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
n=0
W=$WORK/w.yml

ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures + 1)); }

# workflow <line...>: the case's workflow, a job `j` whose steps are the given lines (from `steps:` on).
workflow() {
    { printf '%s\n' 'name: W' 'on: push' 'jobs:' '  j:' '    runs-on: ubuntu-latest' '    env:' '      JOB_VAR: from-the-job' '    steps:'
      printf '%s\n' "$@"; } > "$W"
}

# expect <exit> <name> <regex the output must match> [args...] — runs the step runner on $W, job j, in $WORK.
expect() {
    local want=$1 name=$2 re=$3 out rc; shift 3
    n=$((n + 1))
    out=$(cd "$WORK" && ruby "$STEPS" "$W" j "$@" 2>&1); rc=$?
    if [ "$rc" -eq "$want" ] && grep -qE -- "$re" <<<"$out"; then ok "$name"
    else fail "$name: expected exit $want and /$re/, got $rc: $out"; fi
}
# expect_not <name> <regex the output must not match> [args...]
expect_not() {
    local name=$1 re=$2 out; shift 2
    n=$((n + 1))
    out=$(cd "$WORK" && ruby "$STEPS" "$W" j "$@" 2>&1)
    if grep -qE -- "$re" <<<"$out"; then fail "$name: /$re/ found in: $out"; else ok "$name"; fi
}

echo "ci-local-steps: what runs, in order, with what"
workflow '      - name: Write' '        env:' '          STEP_VAR: from-the-step' \
         '        run: echo "$JOB_VAR $STEP_VAR" > "$RUNNER_TEMP/note"' \
         '      - name: Read' '        run: test "$(cat "$RUNNER_TEMP/note")" = "from-the-job from-the-step"' \
         '      - name: In a directory' '        working-directory: sub' '        run: test -f here.txt'
mkdir -p "$WORK/sub" && touch "$WORK/sub/here.txt"
expect 0 "job and step env, RUNNER_TEMP kept across steps, working-directory" '^\[0\] Read '
expect 0 "every step ran" 'j: 3 step\(s\) run, 0 failed, 0 skipped\.'
expect_not "a step's env does not leak into the next" 'STEP_VAR'

expect 0 "the versions of Ruby, json and psych come first" '^ruby [0-9]+\.[0-9]+.*; json [0-9]+\.[0-9]+.*, psych [0-9]+\.[0-9]+'
expect 0 "then the version of Node" '^node v[0-9]+\.[0-9]+'
# No node on PATH (an image built without it): the runner stops before any step, instead of a Node step failing later.
n=$((n + 1))
ruby_bin=$(command -v ruby)
mkdir -p "$WORK/no-node"
for tool in uname bash sh; do ln -sf "$(command -v "$tool")" "$WORK/no-node/$tool"; done   # what Ruby itself needs
out=$(cd "$WORK" && PATH="$WORK/no-node" "$ruby_bin" "$STEPS" "$W" j 2>&1); rc=$?
if [ "$rc" -eq 2 ] && grep -q 'no node in this image' <<<"$out" && ! grep -q '^\[' <<<"$out"; then ok "no node: exit 2, no step run"
else fail "no node: expected exit 2, 'no node in this image' and no step, got $rc: $out"; fi
# A node that does not answer with a version (a broken binary): exit 2 too, before any step.
n=$((n + 1))
printf '#!/bin/sh\necho "cannot run" >&2\nexit 1\n' > "$WORK/no-node/node" && chmod +x "$WORK/no-node/node"
out=$(cd "$WORK" && PATH="$WORK/no-node" "$ruby_bin" "$STEPS" "$W" j 2>&1); rc=$?
if [ "$rc" -eq 2 ] && grep -q 'node --version. failed' <<<"$out" && ! grep -q '^\[' <<<"$out"; then ok "a node that fails: exit 2, no step run"
else fail "a node that fails: expected exit 2, 'node --version failed' and no step, got $rc: $out"; fi
rm -f "$WORK/no-node/node"
workflow '      - name: Where' '        run: echo "$RUNNER_TEMP" > "$GITHUB_WORKSPACE_RT"'
n=$((n + 1))
(cd "$WORK" && GITHUB_WORKSPACE_RT=$WORK/rt ruby "$STEPS" "$W" j >/dev/null 2>&1)
if [ -s "$WORK/rt" ] && [ ! -e "$(cat "$WORK/rt")" ]; then ok "RUNNER_TEMP is removed at the end"
else fail "RUNNER_TEMP is removed at the end: $(cat "$WORK/rt" 2>/dev/null) still exists"; fi

echo "ci-local-steps: GitHub's shell (bash -eo pipefail)"
workflow '      - name: Pipe' '        run: false | true' '      - name: Errexit' '        run: |' '          false' '          echo after'
expect 1 "a failing command inside a pipe fails the step (pipefail)" '^\[1\] Pipe '
expect 1 "the first failing command ends the step (-e)" '^\[1\] Errexit '
expect_not "the line after it never runs" 'after'

echo "ci-local-steps: every step runs after a failure, and its output's tail is shown"
workflow '      - name: Fails' '        run: |' '          echo "the reason it failed"' '          exit 3' \
         '      - name: Still runs' '        run: true'
expect 1 "a failure is reported with its exit code" '^\[3\] Fails '
expect 1 "its output is shown under it" '^    the reason it failed'
expect 1 "the next step still runs" '^\[0\] Still runs '
expect 1 "the summary counts it" 'j: 2 step\(s\) run, 1 failed, 0 skipped\.'
workflow '      - name: Long' '        run: |' '          for i in $(seq 1 50); do echo "line-$i"; done' '          exit 1'
expect 1 "the tail of a long output is shown" '^    line-50$'
expect_not "only its last 40 lines" '^    line-10$'

echo "ci-local-steps: what is skipped, and why"
workflow '      - name: Checkout' '        uses: actions/checkout@0000000000000000000000000000000000000000 # v4' \
         '      - name: Ruby' '        uses: ./.github/actions/setup-ruby' \
         '      - name: Other action' '        uses: actions/cache@0000000000000000000000000000000000000000 # v4' \
         '      - name: Conditional' "        if: github.event_name != 'push'" '        run: echo conditional-ran' \
         '      - name: Not cancelled' '        if: ${{ !cancelled() }}' '        run: echo not-cancelled-ran' \
         '      - name: Always' '        if: always()' '        run: echo always-ran' \
         '      - name: Token' '        env:' '          GH_TOKEN: ${{ github.token }}' '        run: echo token-ran' \
         '      - name: Expression' '        run: echo "${{ github.sha }}" expression-ran' \
         '      - name: Pwsh' '        shell: pwsh' '        run: Write-Output pwsh-ran' \
         '      - name: Nothing' \
         '      - name: Bash' '        shell: bash' '        run: echo bash-ran' \
         '      - name: Plain' '        run: echo plain-ran'
expect 0 "checkout: the container is it" '^\[skip\] Checkout: uses actions/checkout: the container is that'
expect 0 "setup-ruby: the container is it" '^\[skip\] Ruby: uses \./\.github/actions/setup-ruby: the container is that'
expect 0 "another action is not run" '^\[skip\] Other action: uses actions/cache@0+: not run locally'
expect 0 "a step with if:" "^\[skip\] Conditional: has \`if: github.event_name != 'push'\`"
expect 0 "if: !cancelled() is run: every step runs here after a failure" '^\[0\] Not cancelled '
expect 0 "if: always() is run too" '^\[0\] Always '
expect 0 "a step whose env needs a token" '^\[skip\] Token: its env GH_TOKEN is \$\{\{ github.token \}\}'
expect 0 "a step whose run holds an expression" '^\[skip\] Expression: its run holds a \$\{\{ \}\} expression'
expect 0 "a step in another shell" '^\[skip\] Pwsh: runs in pwsh'
expect 0 "a step with no run" '^\[skip\] Nothing: no run'
expect 0 "shell: bash is run" '^\[0\] Bash '
expect 0 "the rest runs" 'j: 4 step\(s\) run, 0 failed, 8 skipped\.'
expect_not "no skipped step ran" '(conditional|token|expression|pwsh)-ran'

echo "ci-local-steps: --step"
workflow '      - name: Install the tools' '        run: echo install-pinned-tool.sh would run here' \
         '      - name: Lint the workflows' '        run: echo linted' \
         '      - name: Shellcheck the scripts' '        run: echo shellchecked'
expect 0 "a selected step runs" '^\[0\] Shellcheck the scripts ' --step Shellcheck
expect 0 "a step that installs the pinned tools always runs" '^\[0\] Install the tools ' --step Shellcheck
expect 0 "the others are skipped" '^\[skip\] Lint the workflows: not selected \(--step\)' --step Shellcheck
expect 0 "two --step texts select two steps" 'j: 3 step\(s\) run' --step Shellcheck --step Lint

echo "ci-local-steps: a YAML anchor, as GitHub reads it"
{ printf '%s\n' 'name: W' 'on: push' 'jobs:' '  j:' '    runs-on: ubuntu-latest' '    env:' '      JOB_VAR: from-the-job' \
    '    steps:' '      - &common' '        name: Anchored' '        run: echo anchored' '      - *common'; } > "$W"
expect 0 "an anchored step and its alias both run" 'j: 2 step\(s\) run, 0 failed, 0 skipped\.'

echo "ci-local-steps: usage errors (exit 2)"
workflow '      - name: Plain' '        run: true'
expect 0 "run: true is text, as GitHub reads it (YAML would make it a boolean)" '^\[0\] Plain '
n=$((n + 1))
out=$(ruby "$STEPS" "$W" nope 2>&1); rc=$?
if [ $rc -eq 2 ] && grep -q "has no job nope" <<<"$out"; then ok "a job the workflow does not have"; else fail "unknown job: exit $rc: $out"; fi
n=$((n + 1))
out=$(ruby "$STEPS" "$WORK/missing.yml" j 2>&1); rc=$?
if [ $rc -eq 2 ] && grep -q "cannot read" <<<"$out"; then ok "a workflow that cannot be read"; else fail "missing workflow: exit $rc: $out"; fi
n=$((n + 1))
expect 2 "an unknown option" 'unknown option --nope' --nope
expect 2 "--step without its text" '--step needs a text' --step
{ printf '%s\n' 'name: W' 'on: push' 'jobs:' '  j:' '    runs-on: ubuntu-latest' '    env:' '      TOKEN: ${{ secrets.X }}' '    steps:' '      - run: true'; } > "$W"
expect 2 "a job env with an expression" 'job j: its env TOKEN is \$\{\{ secrets\.X \}\}, not supplied locally'

echo "ci-local.sh: arguments (CI_LOCAL_DRY_RUN=1 stops before Docker)"
wrapper() {   # wrapper <exit> <name> <regex> [args...]
    local want=$1 name=$2 re=$3 out rc; shift 3
    n=$((n + 1))
    out=$(CI_LOCAL_DRY_RUN=1 CI_LOCAL_CONTAINER_MARKER=$WORK/no-marker "$WRAPPER" "$@" 2>&1); rc=$?
    if [ "$rc" -eq "$want" ] && grep -qE -- "$re" <<<"$out"; then ok "$name"; else fail "$name: expected exit $want and /$re/, got $rc: $out"; fi
}
wrapper 0 "both jobs by default" '^jobs: lint-workflows factory-guards; steps: all; rebuild: 0$'
wrapper 0 "one job, two steps, rebuild" '^jobs: factory-guards; steps: --step Hook --step Preflight; rebuild: 1$' \
    --job factory-guards --step Hook --step Preflight --rebuild
wrapper 2 "an unknown job" "unknown job 'build-and-test'" --job build-and-test
wrapper 2 "an unknown argument" "unknown argument '--with-gh'" --with-gh
wrapper 2 "--step without its text" 'usage:' --step

echo "ci-local.sh: what the container gets (CI_LOCAL_LIST_ONLY=1 stops before Docker)"
R=$WORK/repo
mkdir -p "$R" && (cd "$R" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'secret.env\n' > .gitignore && echo kept > kept.txt && echo gone > gone.txt \
    && git add . && git commit -qm init && rm gone.txt && echo s > secret.env && echo new > new.sh)
export CI_LOCAL_CONTAINER_MARKER=$WORK/no-marker   # the cases below run where /.dockerenv may exist (ci-local itself)
list=$(cd "$R" && CI_LOCAL_LIST_ONLY=1 "$WRAPPER" 2>&1); rc=$?
check() {   # check <name> <grep args...>
    local name=$1; shift
    n=$((n + 1))
    if [ $rc -eq 0 ] && grep -q "$@" <<<"$list"; then ok "$name"; else fail "$name: exit $rc, list: $list"; fi
}
nocheck() { n=$((n + 1)); if grep -q "$2" <<<"$list"; then fail "$1: list: $list"; else ok "$1"; fi; }
n=$((n + 1))
if [ "$(head -1 <<<"$list")" = .git ]; then ok ".git first"; else fail ".git is not first: $list"; fi
check "a tracked file" -x 'kept.txt'
check "an untracked file that is not ignored" -x 'new.sh'
nocheck "no ignored file (the secrets the tree must not hand over)" '^secret\.env$'
nocheck "no tracked file deleted in the working tree" '^gone\.txt$'
(cd "$R" && git worktree add -q "$WORK/wt" -b wt 2>/dev/null)
n=$((n + 1))
out=$(cd "$WORK/wt" && CI_LOCAL_LIST_ONLY=1 "$WRAPPER" 2>&1); rc=$?
if [ $rc -eq 2 ] && grep -q "not a directory (a git worktree?)" <<<"$out"; then ok "a git worktree is refused"
else fail "a git worktree is refused: exit $rc: $out"; fi

refused() {   # refused <name> <regex> <dir> [env...] — the wrapper exits 2 with the message, before Docker
    local name=$1 re=$2 dir=$3 out rc; shift 3
    n=$((n + 1))
    out=$(cd "$dir" && env CI_LOCAL_LIST_ONLY=1 "$@" "$WRAPPER" 2>&1); rc=$?
    if [ $rc -eq 2 ] && grep -qE -- "$re" <<<"$out"; then ok "$name"; else fail "$name: exit $rc: $out"; fi
}
touch "$WORK/marker"
refused "inside a container (the devcontainer)" "inside a container" "$R" CI_LOCAL_CONTAINER_MARKER="$WORK/marker"
(cd "$R" && echo s > stashed.txt && git add stashed.txt && git stash -q)
refused "a stash (its objects can hold ignored files)" "the stash is not empty" "$R"
(cd "$R" && git stash drop -q)
(cd "$R" && git remote add origin https://user:tok3n@example.com/o/r.git)
refused "a remote URL with credentials" "holds credentials \(remote\.origin\.url" "$R"
(cd "$R" && git remote set-url origin https://example.com/o/r.git && git config http.https://example.com/.extraheader "AUTHORIZATION: basic x")
refused "an http extraheader" "holds credentials \(http\." "$R"
(cd "$R" && git config --unset http.https://example.com/.extraheader)
n=$((n + 1))
if (cd "$R" && CI_LOCAL_LIST_ONLY=1 "$WRAPPER" >/dev/null 2>&1); then ok "a remote URL without credentials is fine"; else fail "a clean remote URL was refused"; fi

if [ "$failures" -gt 0 ]; then echo "::error::$failures of $n ci-local case(s) failed (backlog #0-166)"; exit 1; fi
echo "All $n ci-local cases passed."
