#!/usr/bin/env bash
# Shared helpers for scripts/factory/*.sh. Sourced, not run.
# Requires: bash (3.2 is enough), git, jq. Some scripts also need gh (authenticated) and docker.

# The directory this file was sourced from, resolved before the cd below: in the dispatcher's task container that is a
# fresh directory holding the base's blobs of trustedPaths (.factory/adapter.json, backlog #0-278), while the working
# directory is the agent's clone. A file the gate reads beside its scripts is read through it, so it is the base's copy;
# one read by a path relative to the clone would be the copy the agent's branch can change.
FACTORY_SCRIPTS_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd) || { echo '{"ok":false,"reasons":["cannot resolve the directory of scripts/factory"]}'; exit 1; }
FACTORY_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo '{"ok":false,"reasons":["not inside the repository"]}'; exit 1; }
cd "$FACTORY_ROOT" || exit 1
RUNS_DIR=".ai/runs"
STATE_FILE="$RUNS_DIR/state.json"
mkdir -p "$RUNS_DIR"

command -v jq >/dev/null 2>&1 || { echo '{"ok":false,"reasons":["jq is not installed"]}'; exit 1; }

# The branch a /seed-bugs run plants its defect on: a name that says nothing of the run (backlog #0-177). The workflow
# derives it from the pattern and the run id (seed-bugs.js, seedBranchOf); seed-branch.sh, seed-check.sh and
# seed-fold.sh take it as given and accept nothing else.
# shellcheck disable=SC2034 # read by the seed-*.sh scripts that source this file, not here
SEED_BRANCH_RE='^review/[0-9a-f]{8}$'

# The branch of a backlog item, `<type>/0-<n>-<slug>`, with the item as the first group (backlog #0-216): start-item.sh
# compares the group with the item it starts, resume-item.sh reads the item from it. The workflow holds the same rule as
# ITEM_BRANCH (backlog-autopilot.js), since it cannot read this file; test-autopilot-workflow.mjs fails when the two
# differ. Fixed: the rule was written four times (twice in the workflow, once in each script) with nothing comparing
# them, so a drift showed up only as a stopped run whose reason named the one copy that refused.
# shellcheck disable=SC2034 # read by start-item.sh and resume-item.sh, which source this file, not here
ITEM_BRANCH_RE='^[a-z]+/(0-[0-9]+)-[A-Za-z0-9._-]+$'

# Same rule as .claude/hooks/_lib.sh: during a run, the commit recorded in .ai/runs/LOCK.
base_ref() {
    local sha
    if [ -f "$RUNS_DIR/LOCK" ]; then
        sha=$(awk '{print $2}' "$RUNS_DIR/LOCK" 2>/dev/null)
        case "$sha" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) echo "$sha"; return ;; esac
    fi
    if [ -n "${FACTORY_BASE_REF:-}" ]; then echo "$FACTORY_BASE_REF"; return; fi
    if git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then echo refs/remotes/origin/main; else echo refs/heads/main; fi
}

state_init() {
    # A missing or unreadable state file is recreated with a breaker that has tripped, not reset to zero:
    # losing the state must not silently re-arm the autopilot.
    if [ ! -s "$STATE_FILE" ] || ! jq -e '(.consecutiveBlocked|type)=="number" and (.shippedSinceAudit|type)=="number"' "$STATE_FILE" >/dev/null 2>&1; then
        if [ -e "$STATE_FILE" ]; then
            echo '{"consecutiveBlocked":99,"shippedSinceAudit":0,"lastAudit":null,"history":[],"note":"state file was unreadable"}' > "$STATE_FILE"
        else
            echo '{"consecutiveBlocked":0,"shippedSinceAudit":0,"lastAudit":null,"history":[]}' > "$STATE_FILE"
        fi
    fi
}

# The Maven modules a list of files reaches (one path per line), and whether it reaches all of them. One
# rule for both gates — changed-paths.sh on the branch's commits, run-tests.sh --working-tree also on the
# uncommitted files — so the manual /review and the autopilot build the same modules for the same change.
# modules_of <files> — the modules, one per line, by top-level directory
modules_of() { printf '%s\n' "$1" | cut -d/ -f1 | sort -u | grep -E '^(shared|service-parent|[a-z]+-service)$' || true; }
# needs_all_modules <files> — true when they change what every module builds: the root POM, shared or
# service-parent (CLAUDE.md: changing shared changes all 7 services). A here-string, not a pipe into
# `grep -q`: under pipefail an early match would SIGPIPE the printf and read as false.
needs_all_modules() { grep -qE '^(pom\.xml|(shared|service-parent)/.*)$' <<<"$1"; }

# factory_mvn <args...> — Maven as the factory runs it: run-tests.sh's gate and seed-compile.sh's compile of a plant
# (backlog #0-181), one list of what is stripped. Only the repository decides what runs. MAVEN_SKIP_RC: Maven's
# launcher would otherwise source ~/.mavenrc; -s and -gs: the factory's own settings instead of ~/.m2/settings.xml and
# of the global settings in the downloaded distribution (conf/settings.xml under ~/.m2/wrapper); no
# MAVEN_OPTS/MAVEN_ARGS/JAVA_TOOL_OPTIONS from the environment. All of these can be written by code an agent runs (its
# tests), and each can skip tests or swap artifacts. What such code can still change: the local repository and the
# distribution's own launcher (bin/mvn) under ~/.m2, and an ignored file in the workspace that Maven reads — it can add
# .mvn/maven.config, jvm.config or extensions.xml and hide them from a clean-tree check through .git/info/exclude or a
# global gitignore. The PR's CI, on a fresh runner from the committed tree, is the check that none of this can forge.
# The settings file is read beside this script (FACTORY_SCRIPTS_DIR), not as scripts/factory/maven-settings.xml of the
# clone. Fixed (backlog #0-278): in the dispatcher's task container the working directory is the agent's clone, so the
# relative path read the settings the agent's branch had written, and a branch could point Maven at its own mirror.
# What that fix does not reach: ./mvnw and .mvn/wrapper/maven-wrapper.properties (distributionUrl) are still the
# clone's, so a branch can run a Maven of its own that ignores -s and -gs, and the agent's tests can rewrite the
# scripts the dispatcher unpacked (same uid in the container). The dispatcher's gate is the agent's side and can be
# forged by a branch (ADR-0060 D6); the PR's CI, on a fresh runner, is the gate that counts.
factory_mvn() {
    env -u MAVEN_OPTS -u MAVEN_ARGS -u JAVA_TOOL_OPTIONS -u _JAVA_OPTIONS -u JDK_JAVA_OPTIONS MAVEN_SKIP_RC=true \
        ./mvnw -B -ntp -s "$FACTORY_SCRIPTS_DIR/maven-settings.xml" -gs "$FACTORY_SCRIPTS_DIR/maven-settings.xml" "$@"
}
# A Maven log line that says the environment failed, not the code: no Docker, a dependency that could not be fetched
# (or, offline, is not in the local repository), no disk. run-tests.sh stops on it for a human; seed-compile.sh fails
# the run with it, never as the seeder's compile error.
# shellcheck disable=SC2034 # read by run-tests.sh and seed-compile.sh, which source this file
MAVEN_ENV_ERRORS='Could not find a valid Docker environment|Cannot connect to the Docker daemon|Could not transfer artifact|Could not resolve dependencies|Connection refused.*(repo|maven)|No space left on device|in offline mode|has not been downloaded from it before'

# clean_main_at <base sha> — true when the tree is on main, clean (untracked files count) and at <base sha>, the
# commit the preflight recorded; otherwise prints the first reason and returns 1. The one copy of the precondition of
# start-item.sh and resume-item.sh (review round 1 of #0-215): the two moved a run's tree from the same state.
clean_main_at() {
    local dirty
    [ "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" = main ] || { echo "not on main: a run's branch starts from main"; return 1; }
    dirty=$(git status --porcelain --untracked-files=all 2>/dev/null) || { echo "cannot read the working tree's status"; return 1; }
    [ -z "$dirty" ] || { echo "the working tree is not clean"; return 1; }
    [ "$(git rev-parse HEAD 2>/dev/null)" = "$1" ] || { echo "main is not at the base commit $1 the preflight recorded"; return 1; }
}

# is_int <value> — true for a non-negative integer
is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# The runs directory, the lock and STOP are local state and must never be committed.
ensure_ignored() {
    for p in ".ai/runs/" ".ai/STOP"; do
        git check-ignore -q "$p" 2>/dev/null || echo "warning: $p is not gitignored" >&2
    done
}
