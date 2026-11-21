#!/usr/bin/env bash
# ============================================================
# Deterministic test gate of the autopilot, run before the review panel (a reviewer never judges code
# that does not build). Prints JSON:
#   {"status":"pass|fixable|stop", "exitCode", "modules", "log", "head", "artifact", "summary": [last relevant lines]}
#   pass    — ./mvnw verify succeeded for the affected modules (tests + JaCoCo check)
#   fixable — the build or a test failed: the implementer gets the summary and fixes it
#   stop    — the environment failed (no Docker, a dependency could not be downloaded): a human looks
# Usage: run-tests.sh [--working-tree] <item-id> <round> [base-ref]
# Affected modules: every top-level module the branch touches; all of them when shared, service-parent
# or the root POM changed (CLAUDE.md: changing shared changes all 7 services). `-am` builds what they
# depend on. Never add -DskipTests here: this script is the gate.
#
# The gate's artifact (backlog #0-160): on a pass, .ai/runs/<item>/gate-r<round>.json (<round> as given: the
# autopilot passes <round>-<attempt>, so gate-r1-0.json; the manual /review passes 1) says what the gate
# tested and what it produced — the HEAD, the modules asked for (`modules`) and those the numbers come
# from (`built`: with `-am` also what they depend on, shared), per module the tests run, failed, errored
# and skipped (the <testcase> elements of surefire's TEST-*.xml) and the JaCoCo line coverage (jacoco.csv),
# only from files this run wrote — and names dependency-tree-r<round>.txt (`dependency:tree` of the same modules). The reviewers
# are read-only (no Maven), so before #0-160 they were told only "the gate passed", and every claim about
# a test, the coverage or the resolved version of a library went to their `unverified` list. A report that
# cannot be read stops the gate: an artifact with missing numbers would read as zero tests.
#
# --working-tree: for the manual /review only, which reviews uncommitted changes. The gate then tests the
# working tree instead of refusing it, records `dirty: true`, and checks that the build left the tree as it
# found it. Refused while an autopilot run holds the lock: the autopilot tests commits.
# ============================================================
set -uo pipefail
. "$(dirname "$0")/_common.sh"

working_tree=false
if [ "${1:-}" = --working-tree ]; then working_tree=true; shift; fi
item=${1:?item id}; round=${2:?round}; base=${3:-$(base_ref)}
safe_item=$(printf '%s' "$item" | tr -c 'A-Za-z0-9._-' '-')
# The round names files the gate removes and writes (rm -f below): letters, digits and dashes only.
case "$round" in ''|*[!A-Za-z0-9-]*)
    jq -n --arg r "$round" '{status:"stop", exitCode:-1, modules:"", log:"", head:"", artifact:null, summary:["invalid round: " + $r]}'
    exit 0 ;;
esac
dir="$RUNS_DIR/$safe_item"; mkdir -p "$dir"
log="$dir/tests-r$round.log"
artifact="$dir/gate-r$round.json"
tree="$dir/dependency-tree-r$round.txt"
rm -f "$artifact" "$tree"

# stop <head> <reason> — the gate refuses or the environment failed
stop() {
    jq -n --arg log "$log" --arg h "$1" --arg r "$2" '{status:"stop", exitCode:-1, modules:"", log:$log, head:$h, artifact:null, summary:[$r]}'
    exit 0
}

# The state of the working tree outside .ai/runs: the status, the diff against HEAD and every untracked
# file's content. Equal before and after the build means the build changed nothing a reviewer reads.
tree_state() {
    git status --porcelain --untracked-files=normal -- . ':!.ai/runs'
    git diff HEAD --binary | git hash-object --stdin
    git ls-files -o --exclude-standard -- . ':!.ai/runs' | git hash-object --stdin-paths
}

if [ "$working_tree" = true ]; then
    [ -f "$RUNS_DIR/LOCK" ] && stop "" "--working-tree is for the manual /review only; an autopilot run (it holds $RUNS_DIR/LOCK) tests commits"
else
    # The gate tests a commit, not a working tree: uncommitted changes would be tested but never reviewed.
    [ -n "$(git status --porcelain --untracked-files=normal -- . ':!.ai/runs')" ] && \
        stop "" "the working tree is not clean: commit or remove the changes, the gate tests HEAD only"
fi
head=$(git rev-parse HEAD)
state_before=$(tree_state)
dirty=false
[ -n "$(git status --porcelain --untracked-files=normal -- . ':!.ai/runs')" ] && dirty=true

# write_artifact <modules> <tests JSON> <coverage JSON> <tree path or ""> <note>
write_artifact() {
    jq -n --arg h "$head" --argjson d "$dirty" --arg m "$1" --arg log "$log" --argjson t "$2" --argjson c "$3" \
        --arg tree "$4" --arg note "$5" \
        '{head:$h, dirty:$d, modules:$m, built:(($t + $c) | keys), log:$log, tests:$t, coverage:$c,
          totals:{tests:([$t[].tests]|add // 0), failures:([$t[].failures]|add // 0),
                  errors:([$t[].errors]|add // 0), skipped:([$t[].skipped]|add // 0)},
          dependencyTree:(if $tree == "" then null else $tree end), note:$note}' > "$artifact"
}

ALL="shared,service-parent,auth-service,ingestion-service,incident-service,notification-service,escalation-service,postmortem-service,oncall-service"
# Beside this script (_common.sh resolved it before its cd into the clone), whatever form of path ran it (#0-278).
paths=$(bash "$FACTORY_SCRIPTS_DIR/changed-paths.sh" "$base")
if ! printf '%s' "$paths" | jq -e '(.error == null) and (.modules|type == "array")' >/dev/null 2>&1; then
    stop "$head" "changed-paths failed: $paths"
fi
all=$(printf '%s' "$paths" | jq -r '.allModules')
mods=$(printf '%s' "$paths" | jq -r '.modules | join(",")')
if [ "$working_tree" = true ]; then
    # changed-paths.sh reads commits only; the uncommitted files count too, by the same rule (_common.sh).
    local_files=$( { git diff --name-only HEAD; git ls-files -o --exclude-standard; } | grep -v '^\.ai/runs/' || true)
    local_mods=$(modules_of "$local_files")
    needs_all_modules "$local_files" && all=true
    mods=$(printf '%s\n%s\n' "$(printf '%s' "$mods" | tr ',' '\n')" "$local_mods" | sed '/^$/d' | sort -u | paste -sd, -)
fi
[ "$all" = true ] && mods=$ALL
if [ -z "$mods" ]; then
    write_artifact "" '{}' '{}' "" "no Maven module changed: nothing to build"
    jq -n --arg log "$log" --arg h "$head" --arg a "$artifact" '{status:"pass", exitCode:0, modules:"", log:$log, head:$h, artifact:$a, summary:["no Maven module changed: nothing to build"]}'
    exit 0
fi

# Maven through factory_mvn (_common.sh): the environment's options, ~/.mavenrc and the user's settings stripped.
# Reports older than this marker are from an earlier build (verify does not clean) and are never counted.
marker="$dir/.gate-start-r$round"
rm -f "$marker"; touch "$marker"
sleep 1    # file times have a one-second resolution on some filesystems: a report written in the same second would not be newer
factory_mvn verify -pl "$mods" -am > "$log" 2>&1
rc=$?

if [ "$rc" -eq 0 ]; then
    status=pass
elif grep -Eq "$MAVEN_ENV_ERRORS" "$log"; then
    status=stop
else
    status=fixable
fi

summary=$( { grep -E '^\[ERROR\]|Tests run:.*Fail|FAILURE|BUILD (SUCCESS|FAILURE)|Coverage checks have not been met' "$log" | grep -v 'Re-run Maven\|-> \[Help' | tail -60; } | jq -R . | jq -s .)

# Surefire's counts are read from the elements, not from the <testsuite> attributes: with JUnit 5 @Nested
# classes surefire writes a `tests=` lower than the <testcase> elements it lists (oncall-service, 2026-10-23:
# tests="30" over 37 test cases; Maven's own summary counted 139 where the attributes summed to 125).
# without_cdata <file> — the report without its CDATA sections (captured output may hold any text, a
# "<testcase" too)
without_cdata() {
    awk '{ line = $0; out = ""
           while (1) {
               if (incdata) { i = index(line, "]]>"); if (!i) break; line = substr(line, i + 3); incdata = 0 }
               else { i = index(line, "<![CDATA["); if (!i) { out = out line; break }
                      out = out substr(line, 1, i - 1); line = substr(line, i + 9); incdata = 1 }
           }
           print out }' "$1"
}
# count_elements <element> <xml> — how many <element> start tags the text holds
count_elements() { printf '%s\n' "$2" | grep -oE "<$1([[:space:]/>]|\$)" | wc -l | tr -d ' '; }

# collect — the artifact's per-module numbers, from the reports this run wrote; returns 1 with a reason on stdout
collect() {
    local tests='{}' coverage='{}' m f xml n fl e s csv header sums
    for m in $(printf '%s' "$ALL" | tr ',' ' '); do
        for f in $(find "$m/target/surefire-reports" -maxdepth 1 -name 'TEST-*.xml' -newer "$marker" 2>/dev/null | sort); do
            xml=$(without_cdata "$f")
            if [ "$(count_elements testsuite "$xml")" -lt 1 ]; then echo "cannot read the counts of $f: no <testsuite>"; return 1; fi
            n=$(count_elements testcase "$xml"); fl=$(count_elements failure "$xml")
            e=$(count_elements error "$xml"); s=$(count_elements skipped "$xml")
            tests=$(printf '%s' "$tests" | jq --arg m "$m" --argjson n "$n" --argjson f "$fl" --argjson e "$e" --argjson s "$s" \
                '.[$m] = ((.[$m] // {suites:0, tests:0, failures:0, errors:0, skipped:0})
                          | .suites += 1 | .tests += $n | .failures += $f | .errors += $e | .skipped += $s)')
        done
        csv="$m/target/site/jacoco/jacoco.csv"
        if [ -f "$csv" ] && [ "$csv" -nt "$marker" ]; then
            header=$(head -1 "$csv" | tr -d '\r' | cut -d, -f8,9)
            [ "$header" = "LINE_MISSED,LINE_COVERED" ] || { echo "unexpected columns in $csv: $header"; return 1; }
            sums=$(awk -F, 'NR > 1 { m += $8; c += $9 } END { print m + 0, c + 0 }' "$csv")
            coverage=$(printf '%s' "$coverage" | jq --arg m "$m" --argjson mi "${sums% *}" --argjson co "${sums#* }" \
                '.[$m] = {lineMissed:$mi, lineCovered:$co, ratio:(if ($mi + $co) == 0 then null else (($co * 1000 / ($mi + $co)) | floor) / 1000 end)}')
        fi
    done
    for m in $(printf '%s' "$mods" | tr ',' ' '); do
        # A module with tests whose build wrote no test report did not run them: never read that as "0 tests".
        # Its coverage the same way (every such module binds jacoco:report to verify, root pom.xml): a missing
        # entry would read as "unknown" next to a module that has one.
        [ -d "$m/src/test" ] || continue
        if [ "$(printf '%s' "$tests" | jq --arg m "$m" 'has($m)')" != true ]; then
            echo "no test report from this run for $m"; return 1
        fi
        if [ "$(printf '%s' "$coverage" | jq --arg m "$m" 'has($m)')" != true ]; then
            echo "no jacoco.csv from this run for $m"; return 1
        fi
    done
    printf '%s\n%s\n' "$(printf '%s' "$tests" | jq -c .)" "$(printf '%s' "$coverage" | jq -c .)"
}

if [ "$status" = pass ]; then
    if ! numbers=$(collect); then
        status=stop; summary=$(jq -n --arg r "the gate's artifact could not be written: $numbers" '[$r]')
    elif ! factory_mvn dependency:tree -pl "$mods" -am -DoutputFile="$PWD/$tree" -DappendOutput=true >> "$log" 2>&1 || [ ! -s "$tree" ]; then
        status=stop; summary=$(jq -n --arg l "$log" '["dependency:tree failed after a green verify (see " + $l + ")"]')
    else
        write_artifact "$mods" "$(printf '%s' "$numbers" | sed -n 1p)" "$(printf '%s' "$numbers" | sed -n 2p)" "$tree" ""
    fi
fi
rm -f "$marker"

# The build must not have changed what the reviewers read (a generated file, a plugin rewriting sources):
# a commit's tracked files, or with --working-tree the whole working tree as it was before the build.
if [ "$working_tree" = true ]; then changed=$([ "$(tree_state)" != "$state_before" ] && echo yes)
else changed=$([ -n "$(git status --porcelain --untracked-files=no)" ] && echo yes); fi
if [ "$(git rev-parse HEAD)" != "$head" ] || [ -n "$changed" ]; then
    status=stop; rm -f "$artifact"
    summary=$(jq -n '["the build changed the working tree or HEAD: a reviewer would not read what was tested"]')
fi
art=null; [ "$status" = pass ] && art=$(jq -n --arg a "$artifact" '$a')
jq -n --arg s "$status" --argjson rc "$rc" --arg m "$mods" --arg log "$log" --arg h "$head" --argjson a "$art" --argjson sum "$summary" \
    '{status:$s, exitCode:$rc, modules:$m, log:$log, head:$h, artifact:$a, summary:$sum}'
