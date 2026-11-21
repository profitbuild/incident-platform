#!/usr/bin/env bash
# ============================================================
# What the current branch changes relative to its merge base with the base branch, as JSON. The
# autopilot uses it to pick the reviewers to run and to stop on changes only the owner may make, and two
# more things:
#   areas      the modules and areas the diff reaches, in the vocabulary of **Touches:**
#              (scripts/factory/_backlog.sh) — compared with the item's Touches and the architect's plan;
#   ruleFiles  the rule files of .ai/rules/review/ that apply to this diff: general, architecture and
#              security always, the others when the diff reaches their area — the implementer self-checks
#              against those its plan did not list, before the panel sees the change.
#   changed-paths.sh [base-ref] [since-sha]
# With since-sha, "delta" lists what changed since that commit (for review rounds 2+).
# ============================================================
set -uo pipefail
. "$(dirname "$0")/_common.sh"
# Beside this script: _common.sh resolved FACTORY_SCRIPTS_DIR before its cd into the clone (#0-278).
. "$FACTORY_SCRIPTS_DIR/_protected.sh"

base=${1:-$(base_ref)}
since=${2:-}
mb=$(git merge-base "$base" HEAD 2>/dev/null) || { jq -n --arg b "$base" '{error:("no merge base with " + $b)}'; exit 1; }
files=$(git diff --no-renames --name-only "$mb"...HEAD)
delta='[]'
if [ -n "$since" ]; then
    delta=$(git diff --no-renames --name-only "$since"..HEAD | jq -R . | jq -s .)
fi

json_list() { printf '%s\n' "$1" | sed '/^$/d' | jq -R . | jq -s .; }
match() { printf '%s\n' "$files" | grep -E "$1" || true; }

# The protected paths come from their one definition, as it is on the base (.ai/rules/protected-paths.md).
{ protected_re=$(protected_paths protected "$base" | paths_regex anchored) \
    && build_re=$(protected_paths build-config "$base" | paths_regex anchored); } \
    || { jq -n --arg b "$base" '{error:("cannot read the lists of .ai/rules/protected-paths.md on " + $b)}'; exit 1; }
protected=$(match "$protected_re")
build_config=$(match "$build_re")
skip_props=$(git diff --no-renames "$mb"...HEAD -- '*pom.xml' | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E 'skipTests|maven\.test\.skip|testFailureIgnore|<skip>[[:space:]]*true|haltOnFailure|jacoco\.skip|<excludes>|<exclude>' | head -3 || true)
[ -n "$skip_props" ] && build_config="$build_config"$'\n'"pom.xml: skip/exclude property added"
# The coverage check itself: a lowered <minimum>, a removed <rule> or `check` goal, a moved <phase>, an
# <include> that narrows what is counted (as an <exclude> does; the same element in another plugin, e.g.
# Surefire's test includes, narrows what runs and is flagged too). An element with attributes counts too:
# `<rules combine.self="override"/>` in a module POM wipes the inherited rule (review round 3). Added
# or removed lines both count (a deletion weakens it as much as an edit). Not the plugin's version, so a
# dependency bump of jacoco-maven-plugin is not flagged. Same patterns as check-factory-guards.sh, rule 6.
coverage_cfg=$(git diff --no-renames "$mb"...HEAD -- '*pom.xml' | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' \
    | grep -E '<(minimum|maximum|counter|value|element|limits?|rules?|phase|includes?)([[:space:]/>])|<goal>[[:space:]]*check[[:space:]]*</goal>' | head -3 || true)
[ -n "$coverage_cfg" ] && build_config="$build_config"$'\n'"pom.xml: coverage check configuration changed"
# CLAUDE.md: only its agent-editable blocks are the implementer's (CLAUDE.md, "Commands").
claude_md=false
if grep -qx 'CLAUDE.md' <<<"$files"; then
    strip() { awk '/<!-- agent-editable:start/{skip=1} !skip{print} /<!-- agent-editable:end/{skip=0}'; }
    markers() { grep -n 'agent-editable:' | sed 's/^[0-9]*://'; }
    if [ "$(git show "$mb:CLAUDE.md" 2>/dev/null | strip)" != "$(git show HEAD:CLAUDE.md | strip)" ] \
       || [ "$(git show "$mb:CLAUDE.md" 2>/dev/null | markers)" != "$(git show HEAD:CLAUDE.md | markers)" ]; then claude_md=true; fi
fi
migrations=$(match '/src/main/resources/db/migration/.*\.(sql|java)$')
edited_applied=""
for f in $migrations; do
    if git cat-file -e "$base:$f" 2>/dev/null && ! git diff --quiet "$mb" HEAD -- "$f"; then edited_applied="$edited_applied$f"$'\n'; fi
done
# a deleted applied migration
for f in $(git diff --no-renames --name-only --diff-filter=D "$mb"...HEAD | grep -E '/src/main/resources/db/migration/' || true); do
    git cat-file -e "$base:$f" 2>/dev/null && edited_applied="$edited_applied$f (deleted)"$'\n'
done
entities=$(git diff "$mb"...HEAD -- '*.java' | grep -E '^\+.*@(Entity|Table|Column|Version)\b' | head -1 || true)
# .dockerignore decides what reaches every image's build context (since backlog #0-141 an allowlist of
# the service jars), so it is the k8s reviewer's, like the Dockerfiles that read it. So is a
# <service>/Dockerfile.dockerignore: BuildKit uses it instead of the root file for that Dockerfile's build.
k8s=$(match '(^k8s/|(^|/)Dockerfile(\.dockerignore)?$|(^|/)pom\.xml$|^\.dockerignore$)')
pom_supply=$(git diff "$mb"...HEAD -- '*pom.xml' | grep -E '^\+.*<(plugin|repository|pluginRepository|dependency)>' | head -5 || true)
deleted_tests=$(git diff --no-renames --name-only --diff-filter=D "$mb"...HEAD | grep -E '/src/test/' || true)
disabled_added=$(git diff "$mb"...HEAD -- '*.java' | grep -cE '^\+.*@Disabled' || true)
docs=$(match '(\.md$|/src/main/resources/application[^/]*\.ya?ml$)')
mods=$(modules_of "$files")
all_modules=false; needs_all_modules "$files" && all_modules=true
# Areas: Maven modules by their directory; the rest by path. Process files (.ai/ except context/, the
# backlog) are not part of an item's reach.
areas=$(printf '%s\n' "$files" | sed '/^$/d' | awk -F/ '
    $1 ~ /^(shared|service-parent|auth-service|ingestion-service|incident-service|notification-service|escalation-service|postmortem-service|oncall-service)$/ { print $1; next }
    $1 == "docs" { print "docs"; next }
    $1 == "k8s" { print "k8s"; next }
    $1 == "docker" { print "docker"; next }
    $1 == ".github" || $1 == "scripts" { print "ci"; next }
    $0 ~ /^\.ai\/context\// || $1 == "architecture-tests" { print "root"; next }
    $1 == ".ai" || $0 ~ /^BACKLOG(-DONE)?\.md$/ { next }
    NF == 1 { print "root"; next }
    { print "root" }' | sort -u)
# Rule files the diff calls for, beyond the core three. Triggers are deliberately broad: a false trigger
# costs one self-check by the implementer, a missed one costs a review round.
added_java=$(git diff "$mb"...HEAD -- '*.java' | grep -E '^\+' | grep -vE '^\+\+\+' || true)
rule_files="general"$'\n'"architecture"$'\n'"security"
{ [ -n "$migrations" ] || [ -n "$entities" ]; } && rule_files="$rule_files"$'\n'"migration"
[ -n "$k8s" ] && rule_files="$rule_files"$'\n'"k8s"
# Here-strings, not `printf | grep -q`: under pipefail an early match would SIGPIPE the printf and the
# pipeline would count as false on a large diff.
grep -qE '@(KafkaListener|Scheduled|Query|Modifying|Async|Cacheable)\b|extends (Jpa|Crud|PagingAndSorting|ListCrud)Repository|findAll\(|Executor|KafkaTemplate|RestClient|WebClient|@Transactional' <<<"$added_java" \
    && rule_files="$rule_files"$'\n'"performance"
# `[ -n "$(… | grep)" ]`, not the `grep -q` shellcheck suggests: the same SIGPIPE as above (backlog #0-149).
# shellcheck disable=SC2143
{ [ -n "$(match '(\.md$|/src/main/resources/application[^/]*\.ya?ml$)' | grep -vE '^(\.ai/(work|decisions)/|BACKLOG(-DONE)?\.md$)')" ] \
  || grep -qE '@(RestController|Controller|(Get|Post|Put|Patch|Delete|Request)Mapping)\b' <<<"$added_java"; } \
    && rule_files="$rule_files"$'\n'"docs"

ready_flag=$(git diff "$mb"...HEAD -- BACKLOG.md | grep -E '^\+' | grep -vE '^\+\+\+' | grep -E '\*\*Autopilot:\*\*[[:space:]]*ready([^a-z-]|$)' | head -1 || true)

jq -n --argjson files "$(json_list "$files")" --argjson protected "$(json_list "$protected")" \
      --argjson migrations "$(json_list "$migrations")" --argjson editedApplied "$(json_list "$edited_applied")" \
      --arg entities "$entities" --argjson k8s "$(json_list "$k8s")" --arg pomSupply "$pom_supply" \
      --argjson deletedTests "$(json_list "$deleted_tests")" --argjson disabledAdded "${disabled_added:-0}" \
      --argjson docs "$(json_list "$docs")" --argjson modules "$(json_list "$mods")" --argjson allModules "$all_modules" --arg readyFlag "$ready_flag" \
      --argjson buildConfig "$(json_list "$build_config")" --argjson claudeMd "$claude_md" \
      --argjson delta "$delta" --arg base "$base" --arg mb "$mb" --arg head "$(git rev-parse HEAD)" \
      --argjson areas "$(json_list "$areas")" --argjson ruleFiles "$(json_list "$rule_files")" '
{ base:$base, mergeBase:$mb, head:$head, files:$files, delta:$delta, modules:$modules,
  areas:$areas, ruleFiles:$ruleFiles,
  protectedTouched:$protected,
  migrationTouched:(($migrations|length)>0 or ($entities|length)>0),
  editedAppliedMigrations:$editedApplied,
  k8sOrBuildTouched:(($k8s|length)>0),
  pomSupplyChainChange:(($pomSupply|length)>0), pomSupplyChainLines:$pomSupply,
  allModules:$allModules,
  deletedTests:$deletedTests, disabledTestsAdded:$disabledAdded,
  docsTouched:(($docs|length)>0), readyFlagAdded:(($readyFlag|length)>0),
  buildConfigChanged:$buildConfig, claudeMdOutsideBlocks:$claudeMd,
  needsHuman:( ($protected|length)>0 or ($editedApplied|length)>0 or ($pomSupply|length)>0
               or ($deletedTests|length)>0 or $disabledAdded>0 or ($readyFlag|length)>0
               or ($buildConfig|length)>0 or $claudeMd ) }'
