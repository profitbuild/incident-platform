#!/usr/bin/env bash
# ============================================================
# Tests for the hooks in .claude/hooks/. Each case feeds a tool call as JSON on stdin and checks the exit
# code: 0 = allowed, 2 = blocked. Runs in a temporary git repository for the path-based hooks.
#
# Run: .claude/hooks/test-hooks.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
# The cases hand the hooks a command's text: `$` and backticks in single quotes are literal on purpose, the
# hooks must see them unexpanded (backlog #0-149).
# shellcheck disable=SC2016
set -uo pipefail

HOOKS=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0

bash_call() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"; }
# run_call <agent_id> <tool_use_id> <command> — a Bash call of a factory-ops run, as its hooks see it (backlog #0-169).
run_call() { jq -cn --arg a "$1" --arg t "$2" --arg c "$3" '{agent_type: "factory-ops", agent_id: $a, tool_use_id: $t, tool_name: "Bash", tool_input: {command: $c}}'; }
file_call() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2"; }

# expect <0|2> <name> <hook and args...> -- <json>
expect() {
    local want=$1 name=$2; shift 2
    local args=()
    while [ "$1" != -- ]; do args+=("$1"); shift; done
    shift
    local json=$1 rc
    (cd "$WORK/repo" && printf '%s' "$json" | "${args[@]}" >/dev/null 2>&1); rc=$?
    if [ "$rc" -eq "$want" ]; then echo "  ok: $name"; else echo "::error::$name: expected exit $want, got $rc"; failures=$((failures+1)); fi
}

# A repository whose main has one migration; the working branch adds a second. In a subshell with -e: this
# script runs without it, and a failed step here (the cd above all) ran the git commands that follow in the
# repository the tests were started from (backlog #0-149).
(
    set -e
    mkdir -p "$WORK/repo/svc/src/main/resources/db/migration"
    cd "$WORK/repo"
    git init -q -b main
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    echo "create table a();" > svc/src/main/resources/db/migration/V1__a.sql
    git add . && git -c user.email=t@t -c user.name=t commit -q -m v1
    git checkout -q -b feat/x
    echo "create table b();" > svc/src/main/resources/db/migration/V2__b.sql
) || { echo "::error::cannot set up the test repository in $WORK/repo"; exit 1; }

M="$HOOKS/guard-migrations.sh"
echo "guard-migrations"
expect 2 "edit a migration that is on main"        "$M" -- "$(file_call Edit svc/src/main/resources/db/migration/V1__a.sql)"
expect 2 "edit it by absolute path"                "$M" -- "$(file_call Edit "$WORK/repo/svc/src/main/resources/db/migration/V1__a.sql")"
ln -s "$WORK/repo" "$WORK/mlink"
expect 2 "edit it through a symlinked path"        "$M" -- "$(file_call Edit "$WORK/mlink/svc/src/main/resources/db/migration/V1__a.sql")"
expect 0 "edit a migration only on this branch"    "$M" -- "$(file_call Edit svc/src/main/resources/db/migration/V2__b.sql)"
expect 0 "write a new migration"                   "$M" -- "$(file_call Write svc/src/main/resources/db/migration/V3__c.sql)"
expect 0 "edit a Java file"                        "$M" -- "$(file_call Edit svc/src/main/java/A.java)"
# A git that fails on a migration's path refuses the edit; a base that does not exist lets it through with a
# warning, the second of the hook's two exceptions to FAC-S04 (security review of #0-162).
expect 2 "git cannot find the repository"          env GIT_DIR="$WORK/no-such-git-dir" "$M" -- "$(file_call Edit "$WORK/repo/svc/src/main/resources/db/migration/V2__b.sql")"
expect 0 "control: no git needed for a Java file"  env GIT_DIR="$WORK/no-such-git-dir" "$M" -- "$(file_call Edit "$WORK/repo/svc/src/main/java/A.java")"
expect 0 "a base that does not exist (warned)"     env FACTORY_BASE_REF=refs/heads/no-such-base "$M" -- "$(file_call Edit svc/src/main/resources/db/migration/V1__a.sql)"
# A git that fails only when it lists the base: a migration that is not on the base would pass if a failure read
# as "not there" (security review round 2 of #0-162).
mkdir -p "$WORK/git-ls-tree-fails"
printf '#!/bin/sh\ncase " $* " in *" ls-tree "*) exit 128 ;; esac\nexec %s "$@"\n' "$(command -v git)" >"$WORK/git-ls-tree-fails/git"
chmod +x "$WORK/git-ls-tree-fails/git"
expect 2 "git fails listing the base"              env PATH="$WORK/git-ls-tree-fails:$PATH" "$M" -- "$(file_call Edit svc/src/main/resources/db/migration/V2__b.sql)"
expect 0 "a name with a glob character, not on the base" "$M" -- "$(file_call Write 'svc/src/main/resources/db/migration/V*__a.sql')"
warn=$(cd "$WORK/repo" && file_call Edit svc/src/main/resources/db/migration/V1__a.sql | FACTORY_BASE_REF=refs/heads/no-such-base "$M" 2>&1 >/dev/null)
case "$warn" in *"base refs/heads/no-such-base not found"*) echo "  ok: the missing base is named" ;;
    *) echo "::error::a base that does not exist: no warning naming it (got '$warn')"; failures=$((failures+1)) ;; esac

T="$HOOKS/guard-tests.sh"
echo "guard-tests"
expect 0 "plain verify"                  "$T" -- "$(bash_call './mvnw -B verify -pl incident-service -am')"
expect 0 "one test class"                "$T" -- "$(bash_call './mvnw test -pl incident-service -Dtest=IncidentFsmTest')"
expect 2 "skipTests"                     "$T" -- "$(bash_call './mvnw verify -DskipTests')"
expect 2 "maven.test.skip"               "$T" -- "$(bash_call './mvnw install -Dmaven.test.skip=true')"
expect 2 "jacoco skip"                   "$T" -- "$(bash_call './mvnw verify -Djacoco.skip=true')"
expect 2 "failure ignore"                "$T" -- "$(bash_call './mvnw test -Dmaven.test.failure.ignore=true')"
expect 2 "fail never"                    "$T" -- "$(bash_call './mvnw verify -fn')"
expect 2 "commit --no-verify"            "$T" -- "$(bash_call 'git commit --no-verify -m x')"
expect 2 "commit -n"                     "$T" -- "$(bash_call 'git commit -n -m x')"
expect 0 "commit with message"           "$T" -- "$(bash_call 'git commit -m "fix(incident-service): x"')"

P="$HOOKS/guard-protected-bash.sh"
echo "guard-protected-bash"
expect 0 "read a rule"                   "$P" -- "$(bash_call 'cat .ai/rules/review/security.md')"
expect 0 "diff a workflow"               "$P" -- "$(bash_call 'git diff main -- .github/workflows/ci.yml')"
expect 2 "sed -i a rule"                 "$P" -- "$(bash_call 'sed -i s/a/b/ .ai/rules/review/security.md')"
expect 2 "redirect into settings"        "$P" -- "$(bash_call 'echo {} > .claude/settings.json')"
expect 2 "copy over an agent"            "$P" -- "$(bash_call 'cp /tmp/x .claude/agents/review-security.md')"
expect 2 "git checkout a workflow"       "$P" -- "$(bash_call 'git checkout HEAD~1 -- .github/workflows/ci.yml')"
expect 2 "python writes AGENTS.md"       "$P" -- "$(bash_call 'python3 -c "open(\"AGENTS.md\",\"w\")"')"
expect 2 "redirect into audit decisions" "$P" -- "$(bash_call 'echo accept >> .ai/audit/decisions.md')"
expect 0 "read audit decisions"          "$P" -- "$(bash_call 'cat .ai/audit/decisions.md')"
expect 0 "unrelated write"               "$P" -- "$(bash_call 'echo x > /tmp/y')"
# Backlog #0-166 (ADR-0040): .ruby-version decides the Ruby every .rb check of CI runs on (build-config list).
expect 2 "redirect into .ruby-version"   "$P" -- "$(bash_call 'echo 3.2.0 > .ruby-version')"
expect 0 "read .ruby-version"            "$P" -- "$(bash_call 'cat .ruby-version')"
# Backlog #0-163 (ADR-0043): .node-version decides the Node of CI's JavaScript tests, likewise.
expect 2 "redirect into .node-version"   "$P" -- "$(bash_call 'echo 22.0.0 > .node-version')"
expect 0 "read .node-version"            "$P" -- "$(bash_call 'cat .node-version')"
# Labels (backlog #0-126): the audits count a `human:*` label as the owner's word, so an autopilot session may
# add or remove only the shipper's own labels, on both commands that set them, in every form gh accepts.
expect 0 "shipper creates a labelled PR"        "$P" -- "$(bash_call 'gh pr create --draft --base main --head fix/0-1-x --label autopilot --label blocked --body-file /tmp/b')"
expect 0 "shipper relabels a PR"                "$P" -- "$(bash_call 'gh pr edit 12 --body-file /tmp/b --remove-label blocked --add-label autopilot,shadow,risk-high')"
expect 0 "edit a PR body only"                  "$P" -- "$(bash_call 'gh pr edit 12 --body-file /tmp/b')"
expect 0 "view a PR"                            "$P" -- "$(bash_call 'gh pr view 12 --json labels')"
expect 0 "a commit message naming the command"  "$P" -- "$(bash_call 'git commit -m "docs: gh pr edit --add-label human:agree is refused"')"
expect 2 "add-label human"                      "$P" -- "$(bash_call 'gh pr edit 12 --add-label human:fp-security')"
expect 2 "add-label= human"                     "$P" -- "$(bash_call 'gh pr edit 12 --add-label=human:agree')"
expect 2 "human in a comma list"                "$P" -- "$(bash_call 'gh pr edit 12 --add-label autopilot,human:agree')"
expect 2 "human quoted and split"               "$P" -- "$(bash_call 'gh pr edit 12 --add-label "hu"man:agree')"
expect 2 "remove an owner label"                "$P" -- "$(bash_call 'gh pr edit 12 --remove-label human:missed-general')"
expect 2 "create with --label human"            "$P" -- "$(bash_call 'gh pr create --base main --label human:introduced-ready --body-file /tmp/b')"
expect 2 "create with --label="                 "$P" -- "$(bash_call 'gh pr create --base main --label=human:agree --body-file /tmp/b')"
expect 2 "create with -l"                       "$P" -- "$(bash_call 'gh pr create --base main -l human:agree --body-file /tmp/b')"
expect 2 "create with -l attached"              "$P" -- "$(bash_call 'gh pr create --base main -lhuman:agree --body-file /tmp/b')"
expect 2 "create with -l in a flag cluster"     "$P" -- "$(bash_call 'gh pr create --base main -dl human:agree --body-file /tmp/b')"
expect 2 "a label from a variable"              "$P" -- "$(bash_call 'gh pr edit 12 --add-label $L')"
expect 2 "a label flag from a variable"         "$P" -- "$(bash_call 'gh pr edit 12 $F human:agree')"
expect 2 "an env prefix before gh"              "$P" -- "$(bash_call 'GH_REPO=o/r gh pr edit 12 --add-label human:agree')"
expect 2 "chained after another command"        "$P" -- "$(bash_call 'true && gh pr edit 12 --add-label human:agree')"
expect 2 "gh issue edit on a PR"                "$P" -- "$(bash_call 'gh issue edit 12 --add-label human:agree')"
expect 2 "an unknown label"                     "$P" -- "$(bash_call 'gh pr edit 12 --add-label needs-owner')"
# Review round 1 (#0-126): gh finds the subcommand behind flags, and gh can be run by path or by another program.
expect 2 "a flag between pr and edit"           "$P" -- "$(bash_call 'gh pr -R o/r edit 12 --add-label human:agree')"
expect 2 "a flag before pr"                     "$P" -- "$(bash_call 'gh --repo o/r pr edit 12 --add-label human:agree')"
expect 2 "gh by its path"                       "$P" -- "$(bash_call '/usr/bin/gh pr edit 12 --add-label human:agree')"
expect 2 "gh inside sh -c"                      "$P" -- "$(bash_call 'sh -c "gh pr edit 12 --add-label human:agree"')"
expect 0 "a title that starts with a dash"      "$P" -- "$(bash_call 'gh pr create --base main --title "- list fixes" --label autopilot --body-file /tmp/b')"
expect 0 "a short title flag with a dash value" "$P" -- "$(bash_call 'gh pr create --base main -t "-all done" -l autopilot --body-file /tmp/b')"
# Review round 2 (#0-126): gh's aliases, labels from a recover file, gh by path behind a prefix, removing labels.
expect 2 "gh pr new is gh pr create"            "$P" -- "$(bash_call 'gh pr new --base main --label human:agree --body-file /tmp/b')"
expect 2 "gh issue new"                         "$P" -- "$(bash_call 'gh issue new --label human:agree')"
expect 2 "labels from a recover file"           "$P" -- "$(bash_call 'gh pr create --recover .ai/work/x/r.json')"
expect 2 "recover= form"                        "$P" -- "$(bash_call 'gh pr create --recover=.ai/work/x/r.json')"
expect 2 "gh by path behind an env prefix"      "$P" -- "$(bash_call 'GH_REPO=o/r /usr/bin/gh pr edit 12 --add-label human:agree')"
expect 2 "remove the autopilot label"           "$P" -- "$(bash_call 'gh pr edit 12 --remove-label autopilot')"
expect 0 "remove the blocked label"             "$P" -- "$(bash_call 'gh pr edit 12 --remove-label blocked')"
# Review round 3 (#0-126, sec-3a9c): bash expands an unquoted glob into file names an agent can create
# (`./--remove-label`, `./human:x`), so a globbed word is refused, not read as text.
expect 2 "a globbed label flag and value"       "$P" -- "$(bash_call 'gh pr edit 12 --add-labe? huma?:agree')"
expect 2 "a globbed removal"                    "$P" -- "$(bash_call 'gh pr edit 12 --remove-labe? huma?:missed-security')"
expect 2 "a globbed short flag"                 "$P" -- "$(bash_call 'gh pr create --base main -? x')"
expect 0 "a quoted glob character in a title"   "$P" -- "$(bash_call 'gh pr create --base main --title "fix: why?" --label autopilot --body-file /tmp/b')"
# Review round 4 (#0-126): a globbed command name (`g? pr edit`) is gh to bash and no word to the text checks.
expect 2 "a globbed command name"               "$P" -- "$(bash_call 'g? pr edit 12 --add-label human:agree')"
expect 2 "a bracket glob in the command name"   "$P" -- "$(bash_call '/opt/homebrew/bin/g[h] pr edit 12 --add-label human:agree')"
expect 0 "a glob in an unrelated command"       "$P" -- "$(bash_call 'ls docs/*.md')"
# The allow-lists are copies of the labels the shipper sets and removes: every label its definition names must be
# allowed, and the preflight must check that each allowed one exists. Read as one line, as a value can wrap.
. "$HOOKS/_lib.sh"
shipper_text=$(tr '\n' ' ' < "$HOOKS/../agents/shipper.md")
shipper_add=$(grep -oE -- '--(add-)?label +[a-z-]+' <<<"$shipper_text" | awk '{print $2}' | sort -u)
shipper_remove=$(grep -oE -- '--remove-label +[a-z-]+' <<<"$shipper_text" | awk '{print $2}' | sort -u)
preflight_labels=$(grep -E '^[[:space:]]*for l in ' "$HOOKS/../../scripts/factory/preflight.sh" | head -1)
missing=""
for l in $shipper_add; do case " $GH_LABELS_ALLOWED " in *" $l "*) ;; *) missing="$missing add:$l" ;; esac; done
for l in $shipper_remove; do case " $GH_LABELS_REMOVABLE " in *" $l "*) ;; *) missing="$missing remove:$l" ;; esac; done
for l in $GH_LABELS_ALLOWED; do case " $preflight_labels " in *" $l "*) ;; *) missing="$missing preflight:$l" ;; esac; done
if [ -n "$shipper_add" ] && [ -n "$shipper_remove" ] && [ -z "$missing" ]; then echo "  ok: the hook's label lists match shipper.md and preflight.sh"
else echo "::error::label lists out of step:${missing:- (no labels found in shipper.md)}"; failures=$((failures+1)); fi

R="$HOOKS/readonly-bash.sh"
echo "readonly-bash"
expect 0 "git diff range"                "$R" -- "$(bash_call 'git diff main...HEAD')"
expect 0 "git log"                       "$R" -- "$(bash_call 'git log --oneline -5')"
expect 0 "git branch list"               "$R" -- "$(bash_call 'git branch')"
expect 2 "git branch delete"             "$R" -- "$(bash_call 'git branch -D feat/x')"
expect 2 "git diff --output"             "$R" -- "$(bash_call 'git diff --output=/tmp/x')"
expect 2 "pipe"                          "$R" -- "$(bash_call 'git diff | head')"
expect 2 "chaining"                      "$R" -- "$(bash_call 'git log && rm -rf x')"
expect 2 "maven"                         "$R" -- "$(bash_call './mvnw test')"
# Backlog #0-182: no reviewer runs kubectl. The k8s reviewer's render read files git does not track (a root or a base
# above k8s/, a `!!binary` path, an upper-case KUSTOMIZATION.YML printed docker/.env), ran a program (--helm-command)
# and fetched remote bases; a guard of its forms kept missing one, so the mode is gone and CI renders.
expect 2 "kubectl kustomize is refused"  "$R" -- "$(bash_call 'kubectl kustomize k8s/overlays/dev')"
expect 2 "kubeconform is refused"        "$R" -- "$(bash_call 'kubeconform -strict -summary -')"
expect 2 "the old --k8s mode is refused (unknown mode)" "$R" --k8s -- "$(bash_call 'git diff HEAD')"
expect 2 "an unknown mode is refused"    "$R" --no-such-mode -- "$(bash_call 'git log --oneline -1')"
expect 0 "a known mode still runs"       "$R" --gh-read -- "$(bash_call 'git log --oneline -1')"
expect 2 "gh without --gh-read"          "$R" -- "$(bash_call 'gh pr list --label autopilot')"
expect 0 "gh pr list with --gh-read"     "$R" --gh-read -- "$(bash_call 'gh pr list --label autopilot --state merged')"
expect 2 "gh api is not allowed"         "$R" --gh-read -- "$(bash_call 'gh api repos/o/r/pulls')"
expect 2 "gh pr merge"                   "$R" --gh-read -- "$(bash_call 'gh pr merge 1')"
# Backlog #0-215: the picker reads only. Its listed forms pass (picker.md), every git write is refused, `git switch` of
# any branch included (the workflow switches on resume, resume-item.sh), and gh and ls only in the one form it needs.
expect 0 "picker: git grep on the base commit" "$R" --picker -- "$(bash_call "git grep -n -A12 '^### 0-25\\.' 0123456789abcdef0123456789abcdef01234567 -- BACKLOG.md")"
expect 0 "picker: git branch --list"     "$R" --picker -- "$(bash_call "git branch --list '*/0-25-*'")"
expect 0 "picker: gh pr list --json"     "$R" --picker -- "$(bash_call 'gh pr list --state open --json number,title,headRefName,isDraft --limit 300')"
expect 0 "picker: ls of a work dir"      "$R" --picker -- "$(bash_call 'ls .ai/work/0-25')"
expect 2 "picker: git switch of a branch" "$R" --picker -- "$(bash_call 'git switch fix/0-25-queue-version')"
expect 2 "picker: git switch -c"         "$R" --picker -- "$(bash_call 'git switch -c fix/0-25-queue-version')"
expect 2 "picker: git checkout -b"       "$R" --picker -- "$(bash_call 'git checkout -b fix/0-25-queue-version')"
expect 2 "picker: git commit"            "$R" --picker -- "$(bash_call 'git commit -m x')"
expect 2 "picker: git push"              "$R" --picker -- "$(bash_call 'git push -u origin fix/0-25-queue-version')"
expect 2 "picker: git branch create"     "$R" --picker -- "$(bash_call 'git branch -c fix/0-25-x')"
expect 2 "picker: gh pr create"          "$R" --picker -- "$(bash_call 'gh pr create --title x --body y')"
expect 2 "picker: gh pr view"            "$R" --picker -- "$(bash_call 'gh pr view 1')"
expect 2 "picker: gh pr list --web"      "$R" --picker -- "$(bash_call 'gh pr list --web')"
expect 2 "picker: gh pr list -w"         "$R" --picker -- "$(bash_call 'gh pr list -w')"
# Review round 1 of #0-215: the one form only, matched whole; a work directory that is a symlink is refused.
expect 2 "picker: gh pr list -w=true"    "$R" --picker -- "$(bash_call 'gh pr list -w=true')"
expect 2 "picker: gh pr list -ws open"   "$R" --picker -- "$(bash_call 'gh pr list -ws open')"
expect 2 "picker: gh pr list -R another host" "$R" --picker -- "$(bash_call 'gh pr list -R evil.example/o/r --state open --json number,title,headRefName,isDraft --limit 300')"
expect 2 "picker: gh pr list --search"   "$R" --picker -- "$(bash_call 'gh pr list --state open --json number,title,headRefName,isDraft --limit 300 --search x')"
expect 2 "picker: gh pr list, another form" "$R" --picker -- "$(bash_call 'gh pr list --json number')"
mkdir -p "$WORK/repo/.ai/work" && ln -s /etc "$WORK/repo/.ai/work/0-77"
expect 2 "picker: ls of a work dir that is a symlink" "$R" --picker -- "$(bash_call 'ls .ai/work/0-77')"
rm "$WORK/repo/.ai/work/0-77"
# Review round 2 of #0-215: a link in any component, not only the last; and a hook run outside the root refuses.
mkdir -p "$WORK/outside/work/0-78"
mv "$WORK/repo/.ai/work" "$WORK/repo/.ai/work.real" && ln -s "$WORK/outside/work" "$WORK/repo/.ai/work"
expect 2 "picker: ls through a symlinked .ai/work" "$R" --picker -- "$(bash_call 'ls .ai/work/0-78')"
rm "$WORK/repo/.ai/work" && mv "$WORK/repo/.ai/work.real" "$WORK/repo/.ai/work"
mkdir -p "$WORK/repo/.ai/work/0-79" "$WORK/repo/sub/.ai/work/0-79"
expect 0 "picker: ls of a real work dir"  "$R" --picker -- "$(bash_call 'ls .ai/work/0-79')"
rc=0; (cd "$WORK/repo/sub" && printf '%s' "$(bash_call 'ls .ai/work/0-79')" | "$R" --picker >/dev/null 2>&1) || rc=$?
if [ "$rc" -eq 2 ]; then echo "  ok: picker: ls from a hook outside the root refuses"
else echo "::error::picker: ls from a hook outside the root: expected exit 2, got $rc"; failures=$((failures+1)); fi
rm -rf "$WORK/repo/.ai/work/0-79" "$WORK/repo/sub" "$WORK/outside"
expect 2 "picker: ls of .ai/work"        "$R" --picker -- "$(bash_call 'ls .ai/work')"
expect 2 "picker: ls of a ~ path"        "$R" --picker -- "$(bash_call 'ls ~/.ai/work/0-25')"
expect 2 "picker: ls with an option"     "$R" --picker -- "$(bash_call 'ls -la .ai/work/0-25')"
expect 2 "picker: ls of two paths"       "$R" --picker -- "$(bash_call 'ls .ai/work/0-25 .ai/runs')"
expect 2 "picker: ls through .."         "$R" --picker -- "$(bash_call 'ls .ai/work/0-25/../../docker')"
expect 2 "picker: mkdir"                 "$R" --picker -- "$(bash_call 'mkdir -p .ai/work/0-25')"
expect 2 "picker: maven"                 "$R" --picker -- "$(bash_call './mvnw test')"
expect 2 "ls without --picker"           "$R" -- "$(bash_call 'ls .ai/work/0-25')"
expect 2 "gh pr list without a mode"     "$R" -- "$(bash_call 'gh pr list --json number')"
# Backlog #0-123: what reviewers actually tried in a manual /review. The working forms pass, and every
# refusal carries the hint (Read for files, git grep -e for search, one git command).
expect 0 "git diff HEAD (manual review)"  "$R" -- "$(bash_call 'git diff HEAD')"
expect 0 "git status --short (new files)" "$R" -- "$(bash_call 'git status --short')"
expect 0 "git grep with several -e"       "$R" -- "$(bash_call 'git grep -n -i -e mailpit -e MAIL_HOST -- docker')"
expect_hint() {   # expect_hint <name> <command> [mode] [extra text] — refused (exit 2), message names the alternatives
    local name=$1 command=$2 mode=${3:-} extra=${4:-} err rc
    err=$(cd "$WORK/repo" && printf '%s' "$(bash_call "$command")" | "$R" ${mode:+"$mode"} 2>&1 >/dev/null); rc=$?
    if [ "$rc" -eq 2 ] && grep -q "Read tool" <<<"$err" && grep -qF -- "git grep -n -e" <<<"$err" \
       && ! grep -q "Grep or Glob" <<<"$err" && { [ -z "$extra" ] || grep -qF -- "$extra" <<<"$err"; }; then echo "  ok: $name"
    else echo "::error::$name: expected a refusal with the Read / git grep hint${extra:+ and '$extra'}, got exit $rc: $err"; failures=$((failures+1)); fi
}
expect_hint "cat a rule file: hint"            'cat .ai/rules/review/_common.md'
expect_hint "git diff chained with cat: hint"  'git diff HEAD; cat k8s/overlays/dev/mailpit.yml'
expect_hint "git -C: hint"                     'git -C /repo diff HEAD'
expect_hint "alternation with a pipe: hint"    'git grep -n -E "mailpit|MAIL_HOST" -- docker'
expect_hint "git diff --output: hint"          'git diff --output=/tmp/x'
expect_hint "unsafe git grep option: hint"     'git grep --untracked secret'
expect_hint "git branch delete: hint"          'git branch -D feat/x'
expect_hint "gh-read mode names gh reads"      'cat x' --gh-read 'gh pr list/view/diff'
expect_hint "architect mode names git add"     'cat x' --architect 'git add of .ai/decisions/'

W="$HOOKS/write-scope.sh"
echo "write-scope"
expect 0 "audit report"                  "$W" .ai/audit/ -- "$(file_call Write .ai/audit/2026-11-03.md)"
expect 2 "rules from an auditor"         "$W" .ai/audit/ -- "$(file_call Edit .ai/rules/review/security.md)"
expect 2 "dot-dot escape"                "$W" .ai/audit/ -- "$(file_call Write .ai/audit/../rules/x.md)"
expect 0 "architect ADR"                 "$W" .ai/decisions/ .ai/work/ -- "$(file_call Write .ai/decisions/0023-x.md)"
expect 0 "architect progress"            "$W" .ai/decisions/ .ai/work/ -- "$(file_call Edit "$WORK/repo/.ai/work/0-58/progress.md")"
# The repository reached through a symlink (macOS: /var -> /private/var; a project under a linked folder).
ln -s "$WORK/repo" "$WORK/link"
expect 0 "architect progress via a symlink"  "$W" .ai/decisions/ .ai/work/ -- "$(file_call Edit "$WORK/link/.ai/work/0-58/progress.md")"
expect 2 "architect code via a symlink"      "$W" .ai/decisions/ .ai/work/ -- "$(file_call Edit "$WORK/link/svc/src/main/java/A.java")"
expect 2 "outside the repository"            "$W" .ai/decisions/ .ai/work/ -- "$(file_call Write "/tmp/.ai/work/x.md")"
expect 2 "architect code"                "$W" .ai/decisions/ .ai/work/ -- "$(file_call Edit svc/src/main/java/A.java)"

O="$HOOKS/factory-ops-bash.sh"
mkdir -p "$WORK/repo/scripts/factory" && printf '#!/bin/sh\n' > "$WORK/repo/scripts/factory/preflight.sh"
echo "factory-ops-bash"
expect 2 "an untracked factory script"   "$O" -- "$(bash_call 'scripts/factory/preflight.sh --json')"
expect 2 "a missing factory script"      "$O" -- "$(bash_call 'scripts/factory/nope.sh')"
expect 2 "anything else"                 "$O" -- "$(bash_call 'git push origin main')"
expect 2 "chained"                       "$O" -- "$(bash_call 'scripts/factory/preflight.sh; rm -rf /')"

GP="$HOOKS/guard-git-push.sh"
echo "guard-git-push"
# Backlog #0-131: only the branch the workflow recorded in the lock (state.sh branch).
expect 2 "no lock: no push"               "$GP" -- "$(bash_call 'git push -u origin fix/0-25-notification-version')"
(cd "$WORK/repo" && mkdir -p .ai/runs && echo "R1 $(git rev-parse HEAD)" > .ai/runs/LOCK)
expect 2 "lock without a branch: no push" "$GP" -- "$(bash_call 'git push -u origin fix/0-25-notification-version')"
(cd "$WORK/repo" && echo "R1 $(git rev-parse HEAD) fix/0-25-notification-version" > .ai/runs/LOCK)
expect 0 "push the run's own branch"      "$GP" -- "$(bash_call 'git push -u origin fix/0-25-notification-version')"
expect 2 "another item's branch"          "$GP" -- "$(bash_call 'git push -u origin fix/0-26-other-item')"
expect 2 "the owner's branch"             "$GP" -- "$(bash_call 'git push -u origin feat/0-131-owners-work')"
expect 2 "a prefix of the run's branch"   "$GP" -- "$(bash_call 'git push -u origin fix/0-25-notification')"
expect 2 "the run's branch, longer"       "$GP" -- "$(bash_call 'git push -u origin fix/0-25-notification-version2')"
(cd "$WORK/repo" && echo "R1 $(git rev-parse HEAD) fix/0-25-maintain-x" > .ai/runs/LOCK)
expect 0 "branch name containing main"    "$GP" -- "$(bash_call 'git push -u origin fix/0-25-maintain-x')"
(cd "$WORK/repo" && chmod 000 .ai/runs/LOCK)
[ -r "$WORK/repo/.ai/runs/LOCK" ] || expect 2 "an unreadable lock: no push" "$GP" -- "$(bash_call 'git push -u origin fix/0-25-maintain-x')"
(cd "$WORK/repo" && chmod 644 .ai/runs/LOCK)
expect 2 "bare git push"                  "$GP" -- "$(bash_call 'git push')"
expect 2 "push main"                      "$GP" -- "$(bash_call 'git push -u origin main')"
expect 2 "refspec to main"                "$GP" -- "$(bash_call 'git push -u origin fix/x:main')"
expect 2 "refspec to refs/heads/main"     "$GP" -- "$(bash_call 'git push -u origin HEAD:refs/heads/main')"
expect 2 "force after branch"             "$GP" -- "$(bash_call 'git push -u origin fix/x --force')"
expect 2 "plus refspec"                   "$GP" -- "$(bash_call 'git push -u origin +fix/x')"
expect 2 "other remote"                   "$GP" -- "$(bash_call 'git push -u evil fix/x')"
expect 0 "not a push"                     "$GP" -- "$(bash_call 'git status')"
expect 0 "fetch origin main"              "$GP" -- "$(bash_call 'git fetch origin main')"
expect 2 "fetch moving origin/main"       "$GP" -- "$(bash_call 'git fetch . HEAD:refs/remotes/origin/main')"
expect 2 "fetch from another remote"      "$GP" -- "$(bash_call 'git fetch evil main')"
(cd "$WORK/repo" && rm -f .ai/runs/LOCK)
expect 2 "write the lock"                 "$P" -- "$(bash_call 'echo x > .ai/runs/LOCK')"
# Backlog #0-131 (review round 3): git's writing options into a protected path are writes too.
expect 2 "git log --output into the lock" "$P" -- "$(bash_call 'git log -1 --output=.ai/runs/LOCK')"
expect 2 "git show --output into scripts/factory" "$P" -- "$(bash_call 'git show HEAD:README.md --output=scripts/factory/state.sh')"
expect 0 "git log without --output"      "$P" -- "$(bash_call 'git log -1 -- .ai/rules/')"
# Backlog #0-168: the alternatives of the flattened `protected=` regex, one by one where nothing else probes them.
expect 2 "write the run state"            "$P" -- "$(bash_call 'echo {} > .ai/runs/state.json')"
expect 2 "write into .git"               "$P" -- "$(bash_call 'echo x > .git/hooks/pre-commit')"
expect 0 "another file in .ai/runs"      "$P" -- "$(bash_call 'echo x > .ai/runs/notes.txt')"
# Backlog #0-233: the marks of factory-ops runs (#0-169) — deleting one would give a running factory-ops a second
# call, and a directory or a file at a mark's name refuses that run's call. The implementer's own run directory passes.
expect 2 "delete a factory-ops mark"      "$P" -- "$(bash_call 'rm .ai/runs/ops-calls/a1')"
expect 2 "delete the marks' directory"    "$P" -- "$(bash_call 'rm -rf .ai/runs/ops-calls')"
expect 2 "repoint a factory-ops mark"     "$P" -- "$(bash_call 'ln -sfn tu9 .ai/runs/ops-calls/a1')"
expect 2 "a directory at a mark's name"   "$P" -- "$(bash_call 'mkdir -p .ai/runs/ops-calls/a1')"
expect 0 "the implementer's run directory" "$P" -- "$(bash_call 'mkdir -p .ai/runs/0-25')"
# Backlog #0-252: the isolation records — an agent that made or replaced one would choose the agent type the
# isolation check reads.
expect 2 "make an isolation record"       "$P" -- "$(bash_call 'ln -sn review-general .ai/runs/isolation/R1')"
expect 2 "delete the isolation records"   "$P" -- "$(bash_call 'rm -rf .ai/runs/isolation')"
# Backlog #0-235 (sec-4a1d): git's own way to the ignored runtime state, without naming a protected path. `git add -f`
# stages ignored files (then `git rm -r -f` deletes them); `git mv` of a tracked ancestor moves them with it.
expect 2 "git add -f of the run state"     "$P" -- "$(bash_call 'git add -f .ai/runs')"
expect 2 "git add -f in a cluster"         "$P" -- "$(bash_call 'git add -vf incident-service')"
expect 2 "git add --force, abbreviated"    "$P" -- "$(bash_call 'git add --forc .ai/runs')"
expect 2 "git add -f after git's -c"       "$P" -- "$(bash_call 'git -c core.quotepath=off add -f .')"
expect 2 "git add -f after a separator"    "$P" -- "$(bash_call 'git status && git add -f .')"
expect 0 "git add of tracked paths"        "$P" -- "$(bash_call 'git add -A incident-service')"
expect 0 "git add -n (no -f)"              "$P" -- "$(bash_call 'git add -n BACKLOG.md')"
expect 0 "a path named -f after --"        "$P" -- "$(bash_call 'git add -- -f')"
expect 0 "a commit message that says it"   "$P" -- "$(bash_call "git commit -m 'git add -f is refused'")"
expect 2 "git mv of .ai"                   "$P" -- "$(bash_call 'git mv .ai elsewhere')"
expect 2 "git mv of ./.ai/"                "$P" -- "$(bash_call 'git mv ./.ai/ elsewhere')"
expect 2 "git mv of .ai/runs"              "$P" -- "$(bash_call 'git mv .ai/runs elsewhere')"
expect 2 "git mv with a glob"              "$P" -- "$(bash_call 'git mv .a? elsewhere')"
expect 0 "git mv of a tracked file"        "$P" -- "$(bash_call 'git mv incident-service/A.java incident-service/B.java')"
expect 2 "git rm of the state, named"      "$P" -- "$(bash_call 'git rm -r -f .ai/runs')"
# Review round 2 of #0-235: paths resolved as git resolves them, a quoted subcommand in a compound command.
expect 2 "git mv of .//.ai"                "$P" -- "$(bash_call 'git mv .//.ai elsewhere')"
expect 2 "git mv of x/../.ai"              "$P" -- "$(bash_call 'git mv incident-service/../.ai elsewhere')"
expect 2 "git mv -f onto the lock (//)"    "$P" -- "$(bash_call 'git mv -f notes.txt .ai/runs//LOCK')"
expect 2 "git add of .ai/./runs"           "$P" -- "$(bash_call 'git add .ai/./runs')"
expect 2 "git rm of a mark"                "$P" -- "$(bash_call 'git rm -r .ai/runs/ops-calls')"
expect 2 "git mv out of the repository"    "$P" -- "$(bash_call 'git mv ../outside.txt incident-service')"
expect 2 "git add of a dot glob"           "$P" -- "$(bash_call 'git add .a*')"
expect 2 "a quoted subcommand across a ;"  "$P" -- "$(bash_call "git 'add' -f .ai/runs ':(exclude)a;b' && git status")"
expect 0 "git add of the root"             "$P" -- "$(bash_call 'git add .')"
# Review round 3 of #0-235: the protected match after `//` and `/./`; the text fallback with no separator; a glob
# quoted in the command stays a word (it is not expanded against the hook's directory).
expect 2 "git log --output into the lock (//)"  "$P" -- "$(bash_call 'git log -1 --format=x --output=.ai/runs//LOCK')"
expect 2 "git log --output into the lock (/./)" "$P" -- "$(bash_call 'git log -1 --format=x --output=.ai/runs/./LOCK')"
expect 2 "a directory at a mark's name (//)"    "$P" -- "$(bash_call 'mkdir -p .ai/runs//ops-calls/a1')"
expect 0 "the implementer's run directory (//)" "$P" -- "$(bash_call 'mkdir -p .ai/runs//0-25')"
expect 2 "git add -f, unterminated quote, no separator" "$P" -- "$(bash_call "git add -f 'x")"
expect 2 "git rm of a quoted glob under the state" "$P" -- "$(bash_call "git rm -r '.ai/runs/*'")"
expect 0 "git rm of a tracked file"        "$P" -- "$(bash_call 'git rm BACKLOG.md')"
expect 2 "rewrite the queue"              "$P" -- "$(bash_call 'sed -i s/A/B/ .ai/plan/queue.md')"
expect 2 "delete STOP"                    "$P" -- "$(bash_call 'rm .ai/STOP')"

FS="$HOOKS/guard-factory-scripts.sh"
# ops_call <agent_type or ""> <command> — a Bash call as the session-level hook sees it; "" = the main session.
ops_call() {
    if [ -z "$1" ]; then bash_call "$2"
    else jq -cn --arg a "$1" --arg c "$2" '{agent_type: $a, tool_name: "Bash", tool_input: {command: $c}}'; fi
}
echo "guard-factory-scripts"
(cd "$WORK/repo" && mkdir -p scripts/factory && printf '#!/bin/sh\necho ok\n' > scripts/factory/preflight.sh && git add -A && git -c user.email=t@t -c user.name=t commit -q -m factory && git branch -f main HEAD)
expect 0 "intact factory script"          "$FS" -- "$(ops_call factory-ops 'scripts/factory/preflight.sh')"
expect 0 "unrelated command"              "$FS" -- "$(bash_call 'git status')"
(cd "$WORK/repo" && echo "echo pass" >> scripts/factory/preflight.sh)
expect 2 "modified factory script"        "$FS" -- "$(ops_call factory-ops 'scripts/factory/preflight.sh')"
expect 2 "factory-ops on modified script" "$HOOKS/factory-ops-bash.sh" -- "$(bash_call 'scripts/factory/preflight.sh')"
(cd "$WORK/repo" && git checkout -q -- scripts/factory/preflight.sh && printf '#!/bin/sh\n' > scripts/factory/evil.sh)
expect 2 "untracked factory script"       "$FS" -- "$(ops_call factory-ops 'scripts/factory/evil.sh')"
(cd "$WORK/repo" && rm scripts/factory/evil.sh)
# The base is the sha in .ai/runs/LOCK, whatever the refs say.
# LOCK pins a commit before the script existed; refs still point at the commit that has it.
(cd "$WORK/repo" && mkdir -p .ai/runs && echo "R1 $(git rev-parse HEAD~1)" > .ai/runs/LOCK)
expect 2 "base from LOCK older than the script" "$FS" -- "$(ops_call factory-ops 'scripts/factory/preflight.sh')"
# LOCK pins the current commit; moving main elsewhere does not matter.
(cd "$WORK/repo" && echo "R1 $(git rev-parse HEAD)" > .ai/runs/LOCK && git branch -f main HEAD~1)
expect 0 "base from LOCK, main moved back"  "$FS" -- "$(ops_call factory-ops 'scripts/factory/preflight.sh')"
(cd "$WORK/repo" && git branch -f main feat/x && rm .ai/runs/LOCK)
# Backlog #0-131: only factory-ops runs them; the lock (and the run's branch in it) moves through these scripts.
for who in implementer implementer-light shipper picker review-general ''; do
    for run in "scripts/factory/state.sh branch feat/0-131-owners-work" "./scripts/factory/state.sh unlock" "scripts/factory/preflight.sh" \
               "git status && scripts/factory/state.sh record shipped 0-1"; do
        expect 2 "${who:-the main session} runs: $run" "$FS" -- "$(ops_call "$who" "$run")"
    done
done
expect 0 "factory-ops runs a factory script"           "$FS" -- "$(ops_call factory-ops 'scripts/factory/state.sh get')"
expect 0 "a reviewer names one as a path, runs none"   "$FS" -- "$(ops_call review-general 'git grep -n -e lock -- scripts/factory/')"
expect 0 "an implementer diffs one, runs none"         "$FS" -- "$(ops_call implementer 'git diff HEAD -- scripts/factory/state.sh')"
# Review round 2: anything else that names the path is refused to them, whatever shape the command takes.
expect 2 "an implementer cats one"                     "$FS" -- "$(ops_call implementer 'cat scripts/factory/state.sh')"
expect 2 "a git read chained to a run"                 "$FS" -- "$(ops_call implementer 'git log -1 && scripts/factory/state.sh unlock')"
expect 2 "a quoted command word"                       "$FS" -- "$(ops_call shipper '"scripts/factory/state.sh" unlock')"
expect 2 "a git read that writes with --output"        "$FS" -- "$(ops_call implementer 'git diff HEAD --output=x.txt -- scripts/factory/state.sh')"
expect 2 "a git read over two lines"                   "$FS" -- "$(ops_call implementer $'git log -1\nscripts/factory/state.sh unlock')"
expect 0 "factory-ops with quoted args"   "$HOOKS/factory-ops-bash.sh" -- "$(run_call q1 t1 "scripts/factory/preflight.sh '0-25' 'origin/main'")"
expect 2 "factory-ops with a comment"     "$HOOKS/factory-ops-bash.sh" -- "$(run_call q2 t1 'scripts/factory/preflight.sh #0-25')"

# Backlog #0-169: one allowed call per factory-ops run (agent_id), the first; a refused call does not use it up, and
# the second copy of the same call (frontmatter hook and session twin, tool_use_id) passes.
echo "factory-ops: one call per run"
OPS="$HOOKS/factory-ops-bash.sh"
expect 0 "the run's first call"                          "$OPS" -- "$(run_call a1 tu1 'scripts/factory/preflight.sh')"
expect 0 "the same call, the hook's second copy"         "$OPS" -- "$(run_call a1 tu1 'scripts/factory/preflight.sh')"
expect 0 "the same call, through the session twin"       "$OPS" --agent factory-ops -- "$(run_call a1 tu1 'scripts/factory/preflight.sh')"
expect 2 "a second call of the run"                      "$OPS" -- "$(run_call a1 tu2 'scripts/factory/preflight.sh')"
expect 2 "a second call of the run, through the twin"    "$OPS" --agent factory-ops -- "$(run_call a1 tu3 'scripts/factory/preflight.sh')"
expect 0 "another run's first call"                      "$OPS" -- "$(run_call a2 tu4 'scripts/factory/preflight.sh')"
expect 2 "a refused form first (chained)"                "$OPS" -- "$(run_call a3 tu5 'scripts/factory/preflight.sh; rm -rf x')"
expect 2 "a refused form first (an absolute path)"       "$OPS" -- "$(run_call a3 tu6 "$WORK/repo/scripts/factory/preflight.sh")"
expect 0 "then the run's first allowed call"             "$OPS" -- "$(run_call a3 tu7 'scripts/factory/preflight.sh')"
expect 2 "and nothing after it"                          "$OPS" -- "$(run_call a3 tu8 'scripts/factory/preflight.sh')"
expect 2 "no agent_id"                                   "$OPS" -- "$(jq -cn '{agent_type: "factory-ops", tool_use_id: "tu9", tool_name: "Bash", tool_input: {command: "scripts/factory/preflight.sh"}}')"
expect 2 "no tool_use_id"                                "$OPS" -- "$(jq -cn '{agent_type: "factory-ops", agent_id: "a4", tool_name: "Bash", tool_input: {command: "scripts/factory/preflight.sh"}}')"
expect 2 "an agent_id that is a path"                    "$OPS" -- "$(run_call '../a5' tu10 'scripts/factory/preflight.sh')"
expect 2 "a tool_use_id that is a path"                  "$OPS" -- "$(run_call a6 '../../x' 'scripts/factory/preflight.sh')"
expect 0 "the shipper is not counted (twin)"             "$OPS" --agent factory-ops -- "$(jq -cn '{agent_type: "shipper", tool_name: "Bash", tool_input: {command: "git status"}}')"
# A day-old mark is pruned: it refuses nothing a new run asks, and its own id is free again.
(cd "$WORK/repo" && ln -s tu-old .ai/runs/ops-calls/a7 && touch -h -t 202001010000 .ai/runs/ops-calls/a7)
expect 0 "a day-old mark is pruned"                      "$OPS" -- "$(run_call a7 tu11 'scripts/factory/preflight.sh')"
# Review round 1: a mark that is a directory, or a link to one, is not entered; a tool_use_id starting with `-` is
# not an option of ln.
(cd "$WORK/repo" && mkdir -p .ai/runs/ops-calls/a8 .ai/runs/ops-calls-elsewhere && ln -s "$WORK/repo/.ai/runs/ops-calls-elsewhere" .ai/runs/ops-calls/a9)
expect 2 "a mark that is a directory"                    "$OPS" -- "$(run_call a8 tu12 'scripts/factory/preflight.sh')"
expect 2 "a mark that is a directory, again"             "$OPS" -- "$(run_call a8 tu13 'scripts/factory/preflight.sh')"
expect 2 "a mark that links to a directory"              "$OPS" -- "$(run_call a9 tu14 'scripts/factory/preflight.sh')"
if [ -z "$(ls -A "$WORK/repo/.ai/runs/ops-calls/a8")" ] && [ -z "$(ls -A "$WORK/repo/.ai/runs/ops-calls-elsewhere")" ]; then
    echo "  ok: nothing was linked inside them"
else echo "::error::a link was created inside a directory mark"; failures=$((failures+1)); fi
expect 0 "a tool_use_id starting with -"                 "$OPS" -- "$(run_call a10 -tu15 'scripts/factory/preflight.sh')"
expect 0 "the same call, the hook's second copy (-)"     "$OPS" -- "$(run_call a10 -tu15 'scripts/factory/preflight.sh')"
expect 2 "and a second call of that run"                 "$OPS" -- "$(run_call a10 -tu16 'scripts/factory/preflight.sh')"
# Two copies of one call at once both pass; two different calls of one run at once: exactly one passes.
race() {
    local id=$1 t1=$2 t2=$3 r1 r2
    (cd "$WORK/repo" && run_call "$id" "$t1" 'scripts/factory/preflight.sh' | "$OPS" >/dev/null 2>&1; echo $? > "$WORK/race1") &
    (cd "$WORK/repo" && run_call "$id" "$t2" 'scripts/factory/preflight.sh' | "$OPS" >/dev/null 2>&1; echo $? > "$WORK/race2") &
    wait; r1=$(cat "$WORK/race1"); r2=$(cat "$WORK/race2"); echo "$r1$r2"
}
for i in 1 2 3 4 5; do
    got=$(race "s$i" "tus$i" "tus$i")
    if [ "$got" = 00 ]; then echo "  ok: two copies of one call at once ($i)"
    else echo "::error::two copies of one call at once ($i): got $got"; failures=$((failures+1)); fi
    got=$(race "d$i" "tud$i-1" "tud$i-2")
    case "$got" in 02|20) echo "  ok: two calls of one run at once, one passes ($i)" ;;
        *) echo "::error::two calls of one run at once ($i): got $got, want exactly one 0"; failures=$((failures+1)) ;; esac
done

echo "more guards"
expect 2 "mvnw exec plugin"               "$T" -- "$(bash_call './mvnw -q exec:exec -Dexec.executable=sh')"
expect 2 "mvnw other settings.xml"        "$T" -- "$(bash_call './mvnw -s /tmp/settings.xml verify')"
expect 2 "read a secret"                  "$P" -- "$(bash_call 'cat docker/.env')"
expect 2 "git diff --no-index"            "$P" -- "$(bash_call 'git diff --no-index /dev/null docker/secrets/x')"
expect 2 "write the maven wrapper"        "$P" -- "$(bash_call 'cp /tmp/x ./mvnw')"
expect 0 "run the maven wrapper"          "$P" -- "$(bash_call './mvnw -B verify -pl shared')"
expect 2 "write a factory script"         "$P" -- "$(bash_call 'sed -i s/x/y/ scripts/factory/run-tests.sh')"
expect 2 "reviewer --no-index"            "$R" -- "$(bash_call 'git diff --no-index a b')"
expect 0 "architect stages an ADR"        "$R" --architect -- "$(bash_call 'git add .ai/decisions/0023-x.md .ai/work/0-25/progress.md')"
expect 2 "architect stages code"          "$R" --architect -- "$(bash_call 'git add svc/src/main/java/A.java')"
expect 0 "architect commits"              "$R" --architect -- "$(bash_call 'git commit -m "docs(factory): plan backlog 0-25"')"
expect 2 "architect amends"               "$R" --architect -- "$(bash_call 'git commit --amend -m x')"
# backlog #0-203: the architect's commit carries the attribution trailer in one exact form, nothing else passes.
TRAILER='--trailer "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"'
expect 0 "architect commits with the trailer"      "$R" --architect -- "$(bash_call "git commit -m \"docs(factory): plan backlog 0-25\" $TRAILER")"
expect 2 "architect commit -F (any file into a message)" "$R" --architect -- "$(bash_call 'git commit -F docker/.env')"
expect 2 "architect commit --file"                 "$R" --architect -- "$(bash_call 'git commit --file=.ai/work/0-25/msg')"
expect 2 "architect commit -F from .ai/work"       "$R" --architect -- "$(bash_call 'git commit -F .ai/work/0-25/progress.md')"
expect 2 "architect commit -C (another message)"   "$R" --architect -- "$(bash_call 'git commit -C HEAD~3')"
expect 2 "architect commit -a"                     "$R" --architect -- "$(bash_call 'git commit -a -m "docs(factory): plan backlog 0-25"')"
expect 2 "architect commit --no-verify"            "$R" --architect -- "$(bash_call 'git commit --no-verify -m "x"')"
expect 2 "architect commit, then a redirect"       "$R" --architect -- "$(bash_call "git commit -m \"x\" $TRAILER > /tmp/out")"
expect 2 "architect commit, then a chain"          "$R" --architect -- "$(bash_call "git commit -m \"x\" $TRAILER && git push")"
expect 2 "architect commit, a redirect in the trailer" "$R" --architect -- "$(bash_call 'git commit -m "x" --trailer "Co-Authored-By: a > /tmp/x <noreply@anthropic.com>"')"
expect 2 "architect commit, another address"       "$R" --architect -- "$(bash_call 'git commit -m "x" --trailer "Co-Authored-By: Claude <me@example.com>"')"
expect 2 "architect commit, another trailer key"   "$R" --architect -- "$(bash_call 'git commit -m "x" --trailer "Signed-off-by: Claude <noreply@anthropic.com>"')"
expect 2 "architect commit, a substitution in the subject" "$R" --architect -- "$(bash_call 'git commit -m "$(cat docker/.env)"')"
expect 2 "architect commit, a quote ends the subject early" "$R" --architect -- "$(bash_call 'git commit -m "x" -F docker/.env -m "y"')"
expect 2 "architect commit, a newline"             "$R" --architect -- "$(bash_call "git commit -m \"x\"
git push")"
expect 2 "architect commit-tree"                   "$R" --architect -- "$(bash_call 'git commit-tree HEAD^{tree} -m x')"
expect 2 "reviewer cannot commit with the trailer" "$R" -- "$(bash_call "git commit -m \"x\" $TRAILER")"
expect_hint "architect commit refusal names the form" 'git commit -F x' --architect 'git commit -m'
expect 2 "reviewer cannot commit"         "$R" -- "$(bash_call 'git commit -m x')"
expect 0 "auditor gh pr diff"             "$R" --gh-read -- "$(bash_call 'gh pr diff 12')"

echo "git grep (the agents' only search: no Grep/Glob tool, plain grep -r would read gitignored secrets)"
expect 0 "reviewer git grep"              "$R" -- "$(bash_call 'git grep -n TenantContext -- *.java')"
expect 0 "reviewer git grep in a revision" "$R" -- "$(bash_call 'git grep -n -e foo HEAD~1 -- shared')"
expect 0 "reviewer git grep fixed string" "$R" -- "$(bash_call 'git grep -F -n x.y')"
expect 2 "reviewer git grep -O"           "$R" -- "$(bash_call 'git grep -Osh foo')"
expect 2 "reviewer git grep bundled -nO"  "$R" -- "$(bash_call 'git grep -nOvim foo')"
expect 2 "reviewer git grep pager"        "$R" -- "$(bash_call 'git grep --open-files-in-pager=sh foo')"
expect 2 "reviewer git grep --no-index"   "$R" -- "$(bash_call 'git grep --no-index foo')"
expect 2 "reviewer git grep ignored files" "$R" -- "$(bash_call 'git grep --untracked --no-exclude-standard PASSWORD')"
expect 2 "reviewer git grep -f"           "$R" -- "$(bash_call 'git grep -f docker/x foo')"
expect 2 "reviewer git grep bundled -nf"  "$R" -- "$(bash_call 'git grep -nf patterns.txt')"
expect 2 "reviewer git grep --file="      "$R" -- "$(bash_call 'git grep --file=patterns.txt')"
expect 2 "reviewer git grep piped"        "$R" -- "$(bash_call 'git grep foo | head')"
expect 0 "implementer git grep"           "$P" -- "$(bash_call 'git grep -n TenantContext -- *.java')"
expect 0 "implementer git grep a rule"    "$P" -- "$(bash_call 'git grep -n SEC-03 -- .ai/rules')"
expect 2 "implementer git grep -O"        "$P" -- "$(bash_call 'git grep -O foo')"
expect 2 "implementer git grep untracked" "$P" -- "$(bash_call 'git grep --untracked --no-exclude-standard secret')"
expect 0 "plain grep is not git grep"     "$P" -- "$(bash_call 'cat README.md')"

echo "git grep: allow-list, bash word splitting (review of the factory hardening, sec-4c1e)"
expect 2 "abbreviated --untracked"        "$R" -- "$(bash_call 'git grep --untr --no-exclude-st -h -i secret')"
expect 2 "abbreviated --no-index"         "$R" -- "$(bash_call 'git grep --no-ind foo')"
expect 2 "abbreviated pager"              "$R" -- "$(bash_call 'git grep --open=sh -l x -- f')"
expect 2 "abbreviated --count too"        "$R" -- "$(bash_call 'git grep --cou foo')"
expect 2 "quoted -O"                      "$R" -- "$(bash_call "git grep '-Osh' foo")"
expect 2 "double-quoted --untracked"      "$R" -- "$(bash_call 'git grep "--untracked" foo')"
expect 2 "option split by quotes"         "$R" -- "$(bash_call "git grep -''-untracked foo")"
expect 2 "option behind a backslash"      "$R" -- "$(bash_call 'git grep \--untracked foo')"
expect 2 "variable"                       "$R" -- "$(bash_call 'git grep $OPT foo')"
expect 2 "variable in double quotes"      "$R" -- "$(bash_call 'git grep "$OPT" foo')"
expect 2 "ANSI-C quoting"                 "$R" -- "$(bash_call "git grep \$'\\x2d-untracked' foo")"
expect 2 "brace expansion"                "$R" -- "$(bash_call 'git grep {--untracked,x} foo')"
expect 2 "unquoted glob before --"        "$R" -- "$(bash_call 'git grep -n foo *.java')"
expect 2 "unterminated quote"             "$R" -- "$(bash_call "git grep 'foo")"
expect 0 "glob after --"                  "$R" -- "$(bash_call 'git grep -n foo -- *.java')"
expect 0 "quoted glob pattern"            "$R" -- "$(bash_call "git grep -n -E 'Tenant.*Id' -- shared")"
expect 0 "pattern starting with a dash"   "$R" -- "$(bash_call 'git grep -n -e -foo')"
expect 0 "context options"                "$R" -- "$(bash_call 'git grep -n -A3 -B 2 --context=4 foo')"
expect 0 "long safe options"              "$R" -- "$(bash_call 'git grep --count --ignore-case --fixed-strings foo')"
expect 0 "bundled safe short options"     "$R" -- "$(bash_call 'git grep -niw foo')"
expect 0 "git log --grep is not git grep" "$R" -- "$(bash_call 'git log --oneline --grep=backlog')"
expect 2 "implementer abbreviated option" "$P" -- "$(bash_call 'git grep --untr --no-exclude-st secret')"
expect 2 "implementer quoted option"      "$P" -- "$(bash_call 'git grep "--no-index" foo')"
expect 0 "implementer plain search"       "$P" -- "$(bash_call "git grep -n 'TenantContext.set' -- shared")"

echo "git grep: only a git grep command is checked, and it must be one (review round 2)"
expect 0 "commit message mentioning git grep"      "$P" -- "$(bash_call 'git commit -m "docs: use git grep here"')"
expect 0 "commit message ending in git grep"       "$P" -- "$(bash_call 'git commit -m "docs: search with git grep"')"
expect 0 "git log --grep"                          "$P" -- "$(bash_call 'git log --oneline --grep=backlog')"
expect 2 "git grep after &&"                       "$P" -- "$(bash_call 'ls && git grep --untr --no-exclude-st secret')"
expect 2 "git grep after ;"                        "$P" -- "$(bash_call 'ls; git grep --no-ind secret')"
expect 2 "grep behind a backslash"                 "$P" -- "$(bash_call 'git gr\ep --untr secret')"
expect 2 "grep in quotes"                          "$P" -- "$(bash_call 'git "grep" --untr secret')"
expect 2 "git options before grep"                 "$P" -- "$(bash_call 'git -C . grep --untr secret')"
expect 2 "git grep through env"                    "$P" -- "$(bash_call 'env git grep --untracked -e PASSWORD')"
expect 2 "git grep through command"                "$P" -- "$(bash_call 'command git grep --untracked -e PASSWORD')"
expect 2 "git grep through sh -c"                  "$P" -- "$(bash_call 'sh -c "git grep --untracked -e PASSWORD"')"
expect 2 "git grep behind an assignment"           "$P" -- "$(bash_call 'GIT_DIR=.git git grep --untracked -e PASSWORD')"
expect 2 "git grep by a path"                      "$P" -- "$(bash_call '/usr/bin/git grep --untracked -e PASSWORD')"
expect 2 "git grep by a glob"                      "$P" -- "$(bash_call '/usr/bin/gi[t] grep --untracked -e PASSWORD')"
expect 0 "git grep with a quoted glob pattern"     "$P" -- "$(bash_call 'git grep -n "foo*" -- "*.java"')"
expect 0 "a glob without grep"                     "$P" -- "$(bash_call 'ls *.md')"
# A glob where the subcommand goes may become grep (a file named grep in the working directory; review round 4).
expect 2 "git gr?p"                                "$P" -- "$(bash_call 'git gr?p --untracked -e PASSWORD')"
expect 2 "git g[r]ep"                              "$P" -- "$(bash_call 'git g[r]ep --untracked -e PASSWORD')"
expect 2 "git * as the subcommand"                 "$P" -- "$(bash_call 'git * --untracked -e PASSWORD')"
expect 2 "git options before gr?p"                 "$P" -- "$(bash_call 'git -C . gr?p --untracked -e PASSWORD')"
expect 2 "reviewer: git gr?p"                      "$R" -- "$(bash_call 'git gr?p --untracked -e PASSWORD')"
expect 0 "git add with a glob"                     "$P" -- "$(bash_call 'git add src/*.java')"
expect 0 "git add with a glob of grep letters"     "$P" -- "$(bash_call 'git add g*')"
expect 0 "git add with a glob, then commit"        "$P" -- "$(bash_call 'git add src/*.java && git commit -m x')"
# The refusal names what it saw: a glob with grep and no git is not "git grep" (review round 3 of #0-130).
refusal_says() {
    local name=$1 want=$2 err
    err=$(cd "$WORK/repo" && printf '%s' "$(bash_call "$3")" | "$P" 2>&1 >/dev/null)
    case "$err" in *"$want"*) echo "  ok: $name" ;; *) echo "::error::$name: refusal '$err' does not say '$want'"; failures=$((failures+1)) ;; esac
}
refusal_says "a glob and grep, no git: not called git grep" "a command with grep and a glob:" "./mvnw test -Dtest='Foo*' | grep FAIL"
refusal_says "git grep with a pipe: called git grep"       "git grep:" 'git grep foo | head'
# backlog #0-207: a command that is not git grep is named as it is, so the agent rewrites the command it ran.
refusal_says "git show piped to grep: called git show"     "BLOCKED by guard-protected-bash.sh: git show: a command separator" 'git show abc:BACKLOG.md | grep x'
refusal_says "git ls-files piped to grep: git ls-files"    "git ls-files: a command separator" 'git ls-files | grep Foo'
refusal_says "grep chained to git branch: the command grep" "the command grep: a command separator" 'grep x BACKLOG.md ; git branch'
refusal_says "git grep chained: still git grep"            "git grep: a command separator" 'git grep -n x ; git branch'
expect 2 "reviewer: git options before grep"       "$R" -- "$(bash_call 'git -c core.quotepath=off grep foo')"

echo "line continuation (review round 2, sec-b7d2)"
expect 2 "grep split by a continuation"            "$P" -- "$(bash_call $'git gr\\\nep --untr secret')"
expect 2 "git split by a continuation"             "$P" -- "$(bash_call $'g\\\nit grep --untr secret')"
expect 2 "a secret split by a continuation"        "$P" -- "$(bash_call $'cat docker/.e\\\nnv')"
expect 2 "continuation inside double quotes"       "$P" -- "$(bash_call $'git grep "--untr\\\nacked" secret')"
expect 0 "multi-line commit message in quotes"     "$P" -- "$(bash_call $'git commit -m "fix: x\n\nbody line"')"
# The same, one layer down: git_grep_unsafe alone, without guard-protected-bash's own continuation check.
lib_refuses() {
    local name=$1 out
    out=$(bash -c '. "$1"/_lib.sh; git_grep_unsafe "$2"' _ "$HOOKS" "$2")
    if [ -n "$out" ]; then echo "  ok: $name"; else echo "::error::$name: git_grep_unsafe let it through"; failures=$((failures+1)); fi
}
lib_refuses "git_grep_unsafe: grep split by a continuation" $'git gr\\\nep --untr secret'
lib_refuses "git_grep_unsafe: git split by a continuation"  $'g\\\nit grep --untr secret'

echo "a check that fails refuses the command (backlog #0-130)"
# The commands below pass with the real hooks (the first three cases); every other case breaks one thing.
GG='git grep -n foo -- .'
GL='gh pr edit 12 --add-label shadow'
expect 0 "control: git grep passes"                 "$P" -- "$(bash_call "$GG")"
expect 0 "control: an allowed label passes"         "$P" -- "$(bash_call "$GL")"
expect 0 "control: reviewer git grep passes"        "$R" -- "$(bash_call "$GG")"
# A check that aborts (an unset variable under set -u) prints nothing and exits non-zero. One copy per check:
# with both broken, either caller's refusal would hide the other's.
for fn in git_grep_unsafe gh_label_unsafe; do
    mkdir -p "$WORK/abort-$fn"
    cp "$HOOKS/_lib.sh" "$HOOKS/guard-protected-bash.sh" "$HOOKS/readonly-bash.sh" "$WORK/abort-$fn/"
    printf '%s() { local x=$no_such_variable_0_130; }\n' "$fn" >>"$WORK/abort-$fn/_lib.sh"
done
expect 2 "git grep check aborts"                    "$WORK/abort-git_grep_unsafe/guard-protected-bash.sh" -- "$(bash_call "$GG")"
expect 2 "gh label check aborts"                    "$WORK/abort-gh_label_unsafe/guard-protected-bash.sh" -- "$(bash_call "$GL")"
expect 2 "reviewer: git grep check aborts"          "$WORK/abort-git_grep_unsafe/readonly-bash.sh" -- "$(bash_call "$GG")"
# A tool inside a check fails without aborting it: before #0-130 its empty output read as "nothing to refuse".
# The sed stub fails only when its arguments start with $FAIL_SED (empty: every call), so each sed call of a check
# is broken alone below; tr is called once per check.
STUBS="$WORK/stubs"
mkdir -p "$STUBS/tr" "$STUBS/sed"
printf '#!/bin/sh\nexit 1\n' >"$STUBS/tr/tr"
printf '#!/bin/sh\ncase "$*" in "${FAIL_SED:-}"*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v sed)" >"$STUBS/sed/sed"
chmod +x "$STUBS/tr/tr" "$STUBS/sed/sed"
expect 2 "tr fails in the git grep check"           env PATH="$STUBS/tr:$PATH" "$P" -- "$(bash_call "$GG")"
expect 2 "sed fails in the git grep check"          env PATH="$STUBS/sed:$PATH" "$P" -- "$(bash_call "$GG")"
# (tr failing in the gh label check is shown one layer down: at this level git_grep_unsafe's own tr refuses first.)
expect 2 "sed fails in the gh label check"          env PATH="$STUBS/sed:$PATH" "$P" -- "$(bash_call "$GL")"
expect 2 "reviewer: sed fails in the git grep check" env PATH="$STUBS/sed:$PATH" "$R" -- "$(bash_call "$GG")"
# One layer down, each failing step alone: the check itself must exit non-zero (a reason printed would hide it).
# lib_fails <name> <check> <command> <setup run before it, in the same shell>
lib_fails() {
    local name=$1 fn=$2 out rc
    out=$(bash -c 'set -uo pipefail; . "$1"/_lib.sh; eval "$4"; "$2" "$3"' _ "$HOOKS" "$fn" "$3" "$4"); rc=$?
    if [ "$rc" -ne 0 ]; then echo "  ok: $name"; else echo "::error::$name: $fn exited 0 (output: '$out')"; failures=$((failures+1)); fi
}
lib_fails "git_grep_unsafe: tr fails"           git_grep_unsafe "$GG" "PATH=$STUBS/tr:\$PATH"
lib_fails "gh_label_unsafe: tr fails"           gh_label_unsafe "$GL" "PATH=$STUBS/tr:\$PATH"
for args in '-n 1p' '-n 2p' '1,2d'; do
    lib_fails "git_grep_unsafe: sed $args fails" git_grep_unsafe "$GG" "PATH=$STUBS/sed:\$PATH; export FAIL_SED='$args'"
done
for args in '-E' '-n 1p' '-n 2p' '-n 3p' '1,3d'; do
    lib_fails "gh_label_unsafe: sed $args fails" gh_label_unsafe "$GL" "PATH=$STUBS/sed:\$PATH; export FAIL_SED='$args'"
done
# shell_words exits non-zero without a reason: it failed, it did not refuse.
lib_fails "git_grep_unsafe: shell_words fails" git_grep_unsafe "$GG" 'shell_words() { return 1; }'
lib_fails "gh_label_unsafe: shell_words fails" gh_label_unsafe "$GL" 'shell_words() { return 1; }'
# matches: an invalid expression is 2, not "no match"; a byte that is not valid UTF-8 still matches (C locale, sec-9c27).
# The UTF-8 case needs a UTF-8 locale in which bash's own match fails on that byte (it does on macOS); without one it
# would pass while showing nothing, so it reports a skip instead (review round 2 of #0-130).
UTF8=""
for loc in C.UTF-8 en_US.UTF-8; do
    if ! LC_ALL=$loc bash -c 're="(^|[[:space:]])git[[:space:]]"; [[ $(printf "\xff git grep") =~ $re ]]' 2>/dev/null; then UTF8=$loc; break; fi
done
m_rc() { LC_ALL=${UTF8:-C} bash -c '. "$1"/_lib.sh; matches "$2" "$3"' _ "$HOOKS" "$1" "$2"; echo $?; }
if [ "$(m_rc x '(a')" = 2 ]; then echo "  ok: matches: invalid expression is 2"; else echo "::error::matches: invalid expression is not 2"; failures=$((failures+1)); fi
if [ -n "$UTF8" ]; then
    if [ "$(m_rc "$(printf '\xff git grep')" '(^|[[:space:]])git[[:space:]]')" = 0 ]; then echo "  ok: matches: invalid UTF-8 still matches ($UTF8)"
    else echo "::error::matches: invalid UTF-8 read as no match"; failures=$((failures+1)); fi
else
    echo "  skip: matches: invalid UTF-8 (no UTF-8 locale here in which bash fails that match)"
fi

echo "the guards' own checks without grep (backlog #0-132)"
# The checks match with bash's own regex (finds in _lib.sh): a grep that fails or is missing changes nothing.
mkdir -p "$STUBS/grep"
printf '#!/bin/sh\nexit 2\n' >"$STUBS/grep/grep"
chmod +x "$STUBS/grep/grep"
expect 2 "no grep: a write into a protected path"     env PATH="$STUBS/grep:$PATH" "$P" -- "$(bash_call 'echo x > .ai/rules/x.md')"
expect 2 "no grep: a secret file"                     env PATH="$STUBS/grep:$PATH" "$P" -- "$(bash_call 'cat docker/.env')"
expect 2 "no grep: a write to mvnw"                   env PATH="$STUBS/grep:$PATH" "$P" -- "$(bash_call 'cp x mvnw')"
expect 2 "no grep: a skipped test"                    env PATH="$STUBS/grep:$PATH" "$HOOKS/guard-tests.sh" -- "$(bash_call './mvnw verify -DskipTests')"
expect 2 "no grep: a push with no lock"               env PATH="$STUBS/grep:$PATH" "$HOOKS/guard-git-push.sh" -- "$(bash_call 'git push -u origin fix/0-1-x')"
expect 2 "no grep: a factory script run by another agent" env PATH="$STUBS/grep:$PATH" "$FS" -- "$(ops_call implementer 'scripts/factory/state.sh unlock')"
expect 0 "no grep: a git read naming a factory script" env PATH="$STUBS/grep:$PATH" "$FS" -- "$(ops_call implementer 'git diff HEAD -- scripts/factory/state.sh')"
expect 0 "no grep: a harmless command"                env PATH="$STUBS/grep:$PATH" "$P" -- "$(bash_call 'git status')"
# The whole command, not its first line: an allow pattern anchored with ^...$ matched the first line alone under grep.
expect 2 "an allowed fetch with a push on its next line" "$HOOKS/guard-git-push.sh" -- "$(bash_call $'git fetch origin main\ngit push -u origin main')"
# finds: an invalid expression refuses instead of reading as "no match".
out=$(bash -c '. "$1"/_lib.sh; finds x "(a"; echo "went on"' _ "$HOOKS" 2>&1); rc=$?
if [ "$rc" -eq 2 ] && ! grep -q 'went on' <<<"$out"; then echo "  ok: finds: an invalid expression refuses"
else echo "::error::finds: an invalid expression did not refuse (exit $rc): $out"; failures=$((failures+1)); fi

# No guard goes back to grep for a check (review round 1 of #0-132): every check of .claude/hooks/*.sh matches with
# finds/matches. Comment lines aside, and `git grep` (the agents' search, named in hints and checked by
# git_grep_unsafe); this file runs grep for its own tests.
offenders=""
for f in "$HOOKS"/*.sh; do
    case "${f##*/}" in test-hooks.sh) continue ;; esac
    hits=$(sed -e 's/^[[:space:]]*#.*//' "$f" | awk -v f="${f##*/}" '{ l = $0; gsub(/git[[:space:]]+grep/, "", l) } l ~ /(^|[^[:alnum:]_-])e?grep[[:space:]]+-/ {print f": "$0}')
    [ -z "$hits" ] || offenders="$offenders$hits"$'\n'
done
if [ -z "$offenders" ]; then echo "  ok: no guard calls grep"; else echo "::error::a guard calls grep (use finds): $offenders"; failures=$((failures+1)); fi

echo "shell_words: three answers by its exit status (backlog #0-132)"
sw() { bash -c '. "$1"/_lib.sh; shell_words "$2"; echo "rc=$?"' _ "$HOOKS" "$1"; }
out=$(sw 'git grep -e x')
if [ "$out" = $'git\ngrep\n-e\nx\nrc=0' ]; then echo "  ok: words, status 0"; else echo "::error::shell_words words: $out"; failures=$((failures+1)); fi
out=$(sw 'git status; rm x'); case "$out" in "a command separator or redirect: run it as a command of its own"$'\n'"rc=3") echo "  ok: a refusal: the reason alone, status 3" ;; *) echo "::error::shell_words refusal: $out"; failures=$((failures+1)) ;; esac
lib_refusal_is_reason() {   # lib_refusal_is_reason <name> <check> <command> — shell_words refusing (status 3) is a refusal of the check, not a failure
    local out rc
    out=$(bash -c 'set -uo pipefail; . "$1"/_lib.sh; shell_words() { echo "stub reason"; return 3; }; "$2" "$3"' _ "$HOOKS" "$2" "$3"); rc=$?
    if [ "$rc" -eq 0 ] && grep -q 'stub reason' <<<"$out"; then echo "  ok: $1"; else echo "::error::$1: exit $rc, output '$out'"; failures=$((failures+1)); fi
}
lib_refusal_is_reason "git_grep_unsafe: a shell_words refusal is its reason" git_grep_unsafe "$GG"
lib_refusal_is_reason "gh_label_unsafe: a shell_words refusal is its reason" gh_label_unsafe "$GL"

echo "a newline inside a quoted word (review of #0-130, sec-4e1a)"
expect 2 "git grep: newline makes a fake --"         "$P" -- "$(bash_call $'git grep \'x\n--\' --untracked --no-exclude-standard -e PASSWORD')"
expect 2 "gh: newline makes a fake --title"          "$P" -- "$(bash_call $'gh pr edit 1 \'a\n--title\' --add-label human:x')"
expect 2 "gh: a multi-line --body"                   "$P" -- "$(bash_call $'gh pr create --title t --body "line one\nline two"')"
expect 0 "multi-line commit message naming git grep" "$P" -- "$(bash_call $'git commit -m "docs: x\n\nsearch with git grep"')"
expect 0 "multi-line commit message naming gh pr edit" "$P" -- "$(bash_call $'git commit -m "docs: x\n\ngh pr edit adds labels"')"

echo "write guards: one helper (review of the factory hardening, arc-5e1d)"
expect 2 "migration via nonexistent dir and .." "$M" -- "$(file_call Edit nosuchdir/../svc/src/main/resources/db/migration/V1__a.sql)"
expect 2 "write-scope: .. through a nonexistent dir" "$W" .ai/audit/ -- "$(file_call Write .ai/audit/nosuch/../../rules/x.md)"
expect 2 "write-scope: notebook outside its scope" "$W" .ai/audit/ -- '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"svc/n.ipynb"}}'
(cd "$WORK/repo" && ln -s "$HOME/.mavenrc" link-to-mavenrc)

WR="$HOOKS/guard-write-in-repo.sh"
expect 2 ".. through a nonexistent directory" "$WR" -- "$(file_call Write nosuchdir/../../outside.txt)"
expect 2 "deep .. to the home directory"  "$WR" -- "$(file_call Write nosuchdir/../../../../../../../../.claude/settings.json)"
expect 2 "a symlink pointing outside"     "$WR" -- "$(file_call Write link-to-mavenrc)"
echo "guard-write-in-repo"
expect 0 "write a source file"            "$WR" -- "$(file_call Write svc/src/main/java/A.java)"
expect 0 "edit by absolute path"          "$WR" -- "$(file_call Edit "$WORK/repo/svc/src/main/java/A.java")"
expect 0 "edit through a symlinked path"  "$WR" -- "$(file_call Edit "$WORK/link/svc/src/main/java/A.java")"
expect 0 "a new file in a new directory"  "$WR" -- "$(file_call Write .ai/work/0-25/handoff.md)"
expect 2 "user settings of Claude Code"   "$WR" -- "$(file_call Write "$HOME/.claude/settings.json")"
expect 2 "maven settings"                 "$WR" -- "$(file_call Write "$HOME/.m2/settings.xml")"
expect 2 "mavenrc"                        "$WR" -- "$(file_call Edit "$HOME/.mavenrc")"
expect 2 "tmp"                            "$WR" -- "$(file_call Write /tmp/x)"
expect 2 "dot-dot out of the repository"  "$WR" -- "$(file_call Write ../outside.txt)"
expect 2 "notebook outside"               "$WR" -- '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/tmp/n.ipynb"}}'
expect 2 "no path"                        "$WR" -- '{"tool_name":"Write","tool_input":{}}'

F="$HOOKS/webfetch-allowlist.sh"
# fetch_call <agent_type or ""> <url> — a WebFetch call as a session-level hook sees it; "" = the session itself (no key).
fetch_call() {
    if [ -n "$1" ]; then
        jq -cn --arg a "$1" --arg u "$2" '{agent_type: $a, tool_name: "WebFetch", tool_input: {url: $u, prompt: "p"}}'
    else
        jq -cn --arg u "$2" '{tool_name: "WebFetch", tool_input: {url: $u, prompt: "p"}}'
    fi
}
echo "webfetch-allowlist (backlog #0-160, AC4)"
expect 0 "verifier: an OSV advisory"                 "$F" -- "$(fetch_call verifier https://osv.dev/vulnerability/GHSA-abcd-efgh-ijkl)"
expect 0 "verifier: the OSV API"                     "$F" -- "$(fetch_call verifier https://api.osv.dev/v1/vulns/CVE-2026-1234)"
expect 0 "verifier: Maven Central metadata"          "$F" -- "$(fetch_call verifier https://repo1.maven.org/maven2/org/apache/tomcat/embed/tomcat-embed-core/maven-metadata.xml)"
expect 0 "verifier: a GitHub advisory"               "$F" -- "$(fetch_call verifier https://github.com/advisories/GHSA-abcd-efgh-ijkl)"
expect 0 "verifier: Tomcat's security page"          "$F" -- "$(fetch_call verifier https://tomcat.apache.org/security-10.html)"
expect 0 "verifier: Spring's advisories"             "$F" -- "$(fetch_call verifier https://spring.io/security/cve-2026-1234)"
expect 2 "verifier: another host"                    "$F" -- "$(fetch_call verifier https://example.com/vulnerability/x)"
expect 2 "verifier: allowed host, other path"        "$F" -- "$(fetch_call verifier https://github.com/search/x)"
expect 2 "verifier: a query string"                  "$F" -- "$(fetch_call verifier 'https://osv.dev/vulnerability/x?q=secret')"
expect 2 "verifier: a fragment"                      "$F" -- "$(fetch_call verifier 'https://osv.dev/vulnerability/x#secret')"
expect 2 "verifier: http"                            "$F" -- "$(fetch_call verifier http://osv.dev/vulnerability/x)"
expect 2 "verifier: user info before the host"       "$F" -- "$(fetch_call verifier https://osv.dev@example.com/vulnerability/x)"
expect 2 "verifier: a port"                          "$F" -- "$(fetch_call verifier https://osv.dev:8443/vulnerability/x)"
expect 2 "verifier: a host that only starts allowed" "$F" -- "$(fetch_call verifier https://osv.dev.example.com/vulnerability/x)"
expect 2 "verifier: an uppercase host"               "$F" -- "$(fetch_call verifier https://OSV.dev/vulnerability/x)"
expect 2 "verifier: .. out of the prefix"            "$F" -- "$(fetch_call verifier https://github.com/advisories/../search)"
expect 2 "verifier: %-encoded .."                    "$F" -- "$(fetch_call verifier https://github.com/advisories/%2e%2e/search)"
expect 2 "verifier: // in the path"                  "$F" -- "$(fetch_call verifier https://github.com/advisories//x)"
expect 2 "verifier: a backslash"                     "$F" -- "$(fetch_call verifier 'https://github.com/advisories/\..\search')"
expect 2 "verifier: a space in the path"             "$F" -- "$(fetch_call verifier 'https://osv.dev/vulnerability/a b')"
expect 2 "verifier: no path"                         "$F" -- "$(fetch_call verifier https://osv.dev)"
expect 2 "verifier: no url"                          "$F" -- '{"agent_type":"verifier","tool_name":"WebFetch","tool_input":{"prompt":"p"}}'
expect 2 "a reviewer, allowed URL"                   "$F" -- "$(fetch_call review-security https://osv.dev/vulnerability/x)"
expect 2 "a name that only contains verifier"        "$F" -- "$(fetch_call not-verifier https://osv.dev/vulnerability/x)"
expect 2 "the session itself (no agent_type)"        "$F" -- "$(fetch_call '' https://osv.dev/vulnerability/x)"
expect 2 "an unknown option"                         "$F" --strict -- "$(fetch_call verifier https://osv.dev/vulnerability/x)"
expect 0 "interactive: the owner's session"          "$F" --interactive -- "$(fetch_call '' https://example.com/x)"
expect 0 "interactive: another agent"                "$F" --interactive -- "$(fetch_call Explore https://example.com/x?q=1)"
expect 2 "interactive: the verifier is still checked" "$F" --interactive -- "$(fetch_call verifier https://example.com/x)"
expect 0 "interactive: the verifier, allowed URL"    "$F" --interactive -- "$(fetch_call verifier https://osv.dev/vulnerability/x)"
if [ "$("$F" --list | grep -c .)" -ge 1 ]; then echo "  ok: --list prints the allow-list"; else echo "::error::--list printed nothing"; failures=$((failures+1)); fi

# Without its helper a hook would end in "command not found", which Claude Code does not treat as a block.
mkdir -p "$WORK/nolib"; cp "$F" "$HOOKS/read-scope.sh" "$WORK/nolib/"
expect 2 "webfetch-allowlist without _lib.sh"  "$WORK/nolib/webfetch-allowlist.sh" -- "$(fetch_call verifier https://osv.dev/vulnerability/x)"
expect 2 "read-scope without _lib.sh"          "$WORK/nolib/read-scope.sh" .ai/runs/ -- "$(file_call Read .ai/runs/x.json)"

RS="$HOOKS/read-scope.sh"
echo "read-scope"
expect 0 "read the gate's artifact"              "$RS" .ai/runs/ -- "$(file_call Read .ai/runs/0-25/gate-r1-0.json)"
expect 0 "read it by absolute path"              "$RS" .ai/runs/ -- "$(file_call Read "$WORK/repo/.ai/runs/0-25/gate-r1-0.json")"
expect 2 "read a source file"                    "$RS" .ai/runs/ -- "$(file_call Read svc/src/main/java/A.java)"
expect 2 "read outside the repository"           "$RS" .ai/runs/ -- "$(file_call Read "$HOME/.ssh/id_ed25519")"
expect 2 "read through .."                       "$RS" .ai/runs/ -- "$(file_call Read .ai/runs/../../docker/.env)"
expect 2 "read with no path"                     "$RS" .ai/runs/ -- '{"tool_name":"Read","tool_input":{}}'
expect 2 "no prefix given"                       "$RS" -- "$(file_call Read .ai/runs/x.json)"
# read_call <agent_type or ""> <path> — a Read as a session-level hook sees it.
read_call() {
    if [ -n "$1" ]; then jq -cn --arg a "$1" --arg f "$2" '{agent_type: $a, tool_name: "Read", tool_input: {file_path: $f}}'
    else jq -cn --arg f "$2" '{tool_name: "Read", tool_input: {file_path: $f}}'; fi
}
echo "read-scope --agent (session-level, review round 2 of #0-160)"
expect 0 "the verifier reads the gate's artifact" "$RS" --agent verifier .ai/runs/ -- "$(read_call verifier .ai/runs/0-25/gate-r1-0.json)"
expect 2 "the verifier reads a source file"       "$RS" --agent verifier .ai/runs/ -- "$(read_call verifier svc/src/main/java/A.java)"
expect 2 "the verifier reads outside the repo"    "$RS" --agent verifier .ai/runs/ -- "$(read_call verifier "$HOME/.ssh/id_ed25519")"
expect 0 "another agent reads a source file"      "$RS" --agent verifier .ai/runs/ -- "$(read_call review-security svc/src/main/java/A.java)"
expect 0 "the session reads a source file"        "$RS" --agent verifier .ai/runs/ -- "$(read_call '' svc/src/main/java/A.java)"
expect 2 "a name that only contains verifier"     "$RS" --agent not-verifier .ai/runs/ -- "$(read_call not-verifier svc/x)"
expect 2 "--agent without a name"                 "$RS" --agent -- "$(read_call verifier .ai/runs/x.json)"
expect 2 "--agent without a prefix"               "$RS" --agent verifier -- "$(read_call verifier .ai/runs/x.json)"

# The verifier's own scope: only the files the gate writes, and no second name of another file (review round 3).
echo "read-scope --name, hard links (review round 3 of #0-160)"
GATE=(--name 'gate-r*.json' --name 'dependency-tree-r*.txt' .ai/runs/)
(cd "$WORK/repo" && mkdir -p .ai/runs/0-25 docker && echo '{}' > .ai/runs/0-25/gate-r1-0.json \
    && echo tree > .ai/runs/0-25/dependency-tree-r1-0.txt && echo log > .ai/runs/0-25/tests-r1-0.log \
    && echo 'DB_PASSWORD=x' > docker/.env && ln docker/.env .ai/runs/0-25/gate-r9-0.json)
expect 0 "the gate's artifact"                    "$RS" "${GATE[@]}" -- "$(file_call Read .ai/runs/0-25/gate-r1-0.json)"
expect 0 "the gate's dependency tree"             "$RS" "${GATE[@]}" -- "$(file_call Read .ai/runs/0-25/dependency-tree-r1-0.txt)"
expect 0 "the manual review's artifact"           "$RS" "${GATE[@]}" -- "$(file_call Read .ai/runs/manual/gate-r1.json)"
expect 2 "the gate's test log"                    "$RS" "${GATE[@]}" -- "$(file_call Read .ai/runs/0-25/tests-r1-0.log)"
expect 2 "the run's LOCK"                         "$RS" "${GATE[@]}" -- "$(file_call Read .ai/runs/LOCK)"
expect 2 "an artifact's name outside .ai/runs/"   "$RS" "${GATE[@]}" -- "$(file_call Read svc/gate-r1.json)"
expect 2 "a name with a matching directory"       "$RS" "${GATE[@]}" -- "$(file_call Read .ai/runs/gate-r1.json/x.log)"
expect 2 "an artifact hard-linked to docker/.env" "$RS" "${GATE[@]}" -- "$(file_call Read .ai/runs/0-25/gate-r9-0.json)"
expect 2 "--name without a pattern"               "$RS" --name -- "$(file_call Read .ai/runs/0-25/gate-r1-0.json)"
expect 0 "session-level: the verifier, the artifact" "$RS" --agent verifier "${GATE[@]}" -- "$(read_call verifier .ai/runs/0-25/gate-r1-0.json)"
expect 2 "session-level: the verifier, the test log" "$RS" --agent verifier "${GATE[@]}" -- "$(read_call verifier .ai/runs/0-25/tests-r1-0.log)"
expect 0 "session-level: another agent, the test log" "$RS" --agent verifier "${GATE[@]}" -- "$(read_call review-general .ai/runs/0-25/tests-r1-0.log)"

echo "foreground-bash (backlog #0-206): the implementers run no command in the background"
FG="$HOOKS/foreground-bash.sh"
# bg_call <agent_type or ""> <command> <run_in_background: true|false|absent>
bg_call() {
    local bg=${3:-absent}
    if [ "$bg" = absent ]; then jq -cn --arg a "$1" --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}} + (if $a == "" then {} else {agent_type: $a} end)'
    else jq -cn --arg a "$1" --arg c "$2" --argjson b "$bg" '{tool_name: "Bash", tool_input: {command: $c, run_in_background: $b}} + (if $a == "" then {} else {agent_type: $a} end)'; fi
}
expect 0 "a test in the foreground"                      "$FG" -- "$(bg_call '' './mvnw test -pl shared')"
expect 0 "run_in_background false"                       "$FG" -- "$(bg_call '' './mvnw test -pl shared' false)"
expect 2 "a test in the background"                      "$FG" -- "$(bg_call '' './mvnw verify' true)"
expect 2 "run_in_background as a string"                 "$FG" -- '{"tool_name":"Bash","tool_input":{"command":"x","run_in_background":"yes"}}'
expect 2 "an argument but --agent is refused"            "$FG" --architect -- "$(bg_call '' 'x')"
expect 2 "twin: the implementer in the background"       "$FG" --agent implementer,implementer-light -- "$(bg_call implementer './mvnw verify' true)"
expect 2 "twin: implementer-light in the background"     "$FG" --agent implementer,implementer-light -- "$(bg_call implementer-light './mvnw verify' true)"
expect 0 "twin: the implementer in the foreground"       "$FG" --agent implementer,implementer-light -- "$(bg_call implementer './mvnw verify' false)"
expect 0 "twin: another agent is not its business"       "$FG" --agent implementer,implementer-light -- "$(bg_call shipper 'x' true)"
expect 0 "twin: the main session is not its business"    "$FG" --agent implementer,implementer-light -- "$(bg_call '' 'x' true)"
expect 2 "twin: --agent without names"                   "$FG" --agent -- "$(bg_call implementer 'x' true)"
err=$(printf '%s' "$(bg_call '' './mvnw verify' true)" | "$FG" 2>&1 >/dev/null)
if grep -qF -- "foreground" <<<"$err" && grep -qF -- "timeout" <<<"$err"; then echo "  ok: the refusal names the alternative"
else echo "::error::foreground-bash refusal should name the foreground and the timeout: $err"; failures=$((failures+1)); fi

echo "session-level twins: --agent (backlog #0-164)"
# agent_call <agent> <tool> <field> <value> — a call as a session-level hook sees it: with agent_type, or (agent
# empty) without it, as the main session's calls are.
agent_call() {
    if [ -n "$1" ]; then jq -cn --arg a "$1" --arg t "$2" --arg f "$3" --arg v "$4" '{agent_type: $a, tool_name: $t, tool_input: {($f): $v}}'
    else jq -cn --arg t "$2" --arg f "$3" --arg v "$4" '{tool_name: $t, tool_input: {($f): $v}}'; fi
}
expect 0 "readonly twin: the reviewer runs git status"      "$R" --agent review-general,review-docs -- "$(agent_call review-docs Bash command 'git status')"
expect 2 "readonly twin: the reviewer is refused rm"        "$R" --agent review-general,review-docs -- "$(agent_call review-docs Bash command 'rm -rf x')"
expect 2 "readonly twin: the first name of the list too"    "$R" --agent review-general,review-docs -- "$(agent_call review-general Bash command 'rm -rf x')"
expect 0 "readonly twin: another agent passes"              "$R" --agent review-general,review-docs -- "$(agent_call implementer Bash command 'rm -rf x')"
expect 0 "readonly twin: the main session passes"           "$R" --agent review-general,review-docs -- "$(agent_call '' Bash command 'rm -rf x')"
expect 0 "readonly twin: review, a part of a listed name, is another agent" "$R" --agent review-general,review-docs -- "$(agent_call review Bash command 'rm x')"
expect 0 "readonly twin: review-general-2 is another agent"    "$R" --agent review-general -- "$(agent_call review-general-2 Bash command 'rm x')"
expect 2 "readonly twin with a mode: audit-pipeline is refused rm" "$R" --agent audit-pipeline,audit-reviewers --gh-read -- "$(agent_call audit-pipeline Bash command 'rm x')"
expect 0 "readonly twin with a mode: its own extra command" "$R" --agent audit-pipeline,audit-reviewers --gh-read -- "$(agent_call audit-pipeline Bash command 'gh pr list --label autopilot')"
expect 2 "readonly twin: review-k8s may not run kubectl" "$R" --agent acceptance-reviewer,review-k8s -- "$(agent_call review-k8s Bash command 'kubectl kustomize k8s/base')"
expect 2 "readonly twin --picker: the picker may not switch (#0-215)" "$R" --agent picker --picker -- "$(agent_call picker Bash command 'git switch fix/0-25-queue-version')"
expect 0 "readonly twin --picker: its own ls"                "$R" --agent picker --picker -- "$(agent_call picker Bash command 'ls .ai/work/0-25')"
expect 0 "readonly twin --picker: the shipper is not bound by it" "$R" --agent picker --picker -- "$(agent_call shipper Bash command 'git push -u origin fix/0-25-x')"
expect 2 "write twin: the planner writes outside its scope" "$W" --agent planner .ai/plan/ BACKLOG.md -- "$(agent_call planner Write file_path svc/src/main/java/A.java)"
expect 0 "write twin: the planner writes the queue"         "$W" --agent planner .ai/plan/ BACKLOG.md -- "$(agent_call planner Write file_path .ai/plan/queue.md)"
expect 0 "write twin: the implementer is not its business"  "$W" --agent planner .ai/plan/ BACKLOG.md -- "$(agent_call implementer Write file_path svc/src/main/java/A.java)"
expect 2 "factory-ops twin: factory-ops runs git push"      "$O" --agent factory-ops -- "$(agent_call factory-ops Bash command 'git push')"
expect 0 "factory-ops twin: factory-ops runs a gate"        "$O" --agent factory-ops -- "$(run_call tw1 tw1 'scripts/factory/preflight.sh')"
expect 0 "factory-ops twin: the shipper is not its business" "$O" --agent factory-ops -- "$(agent_call shipper Bash command 'git push')"
expect 2 "factory-ops: an argument but --agent is refused"  "$O" --gh-read -- "$(agent_call factory-ops Bash command 'scripts/factory/preflight.sh')"
expect 2 "--agent with an empty name in the list"           "$R" --agent review-general,,review-docs -- "$(agent_call implementer Bash command 'git status')"
expect 2 "--agent with a trailing comma"                    "$R" --agent review-general, -- "$(agent_call implementer Bash command 'git status')"
expect 2 "--agent with a name that is not one"              "$R" --agent 'review general' -- "$(agent_call implementer Bash command 'git status')"
expect 2 "--agent with no names"                            "$W" --agent -- "$(agent_call planner Write file_path .ai/plan/q.md)"
expect 2 "--agent with an empty name (readonly)"            "$R" --agent '' -- "$(agent_call '' Bash command 'git status')"
expect 2 "--agent with an empty name (write)"               "$W" --agent '' .ai/plan/ -- "$(agent_call '' Write file_path .ai/plan/q.md)"
expect 2 "--agent with an empty name (factory-ops)"         "$O" --agent '' -- "$(agent_call '' Bash command 'scripts/factory/preflight.sh')"
expect 2 "an agent_type that does not parse"                "$R" --agent review-general -- '{"agent_type": '

echo "the defect-seeder: a seed run's scope (backlog #0-172)"
# A merged change that added a migration and a class, on `seedmain` (standing in for main: every migration of a
# merged change is on it); its seed branch as seed-branch.sh makes it: the change reverted as the base, then back.
SEED_BR=review/0684d0a2
MIG=svc/src/main/resources/db/migration
(
    set -e
    cd "$WORK/repo"
    g() { git -c user.email=t@t -c user.name=t "$@"; }
    git switch -q -c seedmain
    mkdir -p svc/src/main/java
    echo "create table s();" > "$MIG/V3__s.sql" && echo "class S {}" > svc/src/main/java/S.java
    git add "$MIG/V3__s.sql" svc/src/main/java/S.java && g commit -q -m "feat(svc): the merged change"
    git switch -q -c "$SEED_BR"
    git rm -q "$MIG/V3__s.sql" svc/src/main/java/S.java && g commit -q -m 'Revert "feat(svc): the merged change"'
    base=$(git rev-parse HEAD)
    git checkout -q seedmain -- "$MIG/V3__s.sql" svc/src/main/java/S.java && g commit -q -m "feat(svc): the merged change"
    mkdir -p .ai/runs && echo "$SEED_BR $base $(git rev-parse HEAD)" > .ai/runs/SEED
) || { echo "::error::cannot set up the seed branch in $WORK/repo"; exit 1; }
seeder() { agent_call defect-seeder "$1" file_path "$2"; }
expect 0 "seeder edits the change's class"            "$W" --seed -- "$(seeder Edit svc/src/main/java/S.java)"
expect 0 "seeder edits the change's migration"        "$W" --seed -- "$(seeder Edit "$MIG/V3__s.sql")"
expect 0 "seeder, by absolute path"                   "$W" --seed -- "$(seeder Edit "$WORK/repo/svc/src/main/java/S.java")"
expect 2 "seeder edits a file the change did not touch" "$W" --seed -- "$(seeder Edit "$MIG/V1__a.sql")"
expect 2 "seeder writes a new file"                   "$W" --seed -- "$(seeder Write svc/src/main/java/New.java)"
expect 2 "seeder writes the seed record"              "$W" --seed -- "$(seeder Write .ai/runs/SEED)"
expect 2 "seeder writes a run's row"                  "$W" --seed -- "$(seeder Write .ai/runs/benchmark/results.md)"
expect 2 "seeder edits a hook"                        "$W" --seed -- "$(seeder Edit .claude/hooks/write-scope.sh)"
expect 2 "seeder: .. out of the change's file"        "$W" --seed -- "$(seeder Edit svc/src/main/java/../../../../.ai/runs/SEED)"
expect 2 "seeder writes outside the repository"       "$W" --seed -- "$(seeder Write "$HOME/.claude/settings.json")"
expect 2 "--seed takes no prefix"                     "$W" --seed svc/ -- "$(seeder Edit svc/src/main/java/S.java)"
expect 0 "twin: the seeder, the change's class"       "$W" --agent defect-seeder --seed -- "$(seeder Edit svc/src/main/java/S.java)"
expect 2 "twin: the seeder, outside the change"       "$W" --agent defect-seeder --seed -- "$(seeder Edit "$MIG/V1__a.sql")"
expect 0 "twin: another agent is not its business"    "$W" --agent defect-seeder --seed -- "$(agent_call implementer Edit file_path "$MIG/V1__a.sql")"
# The migration guard compares with the run's base on its branch: the change's migration is new there.
expect 0 "migration: the change's, on the seed base"  env FACTORY_BASE_REF=refs/heads/seedmain "$M" -- "$(seeder Edit "$MIG/V3__s.sql")"
expect 2 "migration: one on the seed base too"        env FACTORY_BASE_REF=refs/heads/seedmain "$M" -- "$(seeder Edit "$MIG/V1__a.sql")"
(cd "$WORK/repo" && echo "R1 $(git rev-parse seedmain)" > .ai/runs/LOCK)
expect 2 "migration: an autopilot lock comes first"   "$M" -- "$(seeder Edit "$MIG/V3__s.sql")"
(cd "$WORK/repo" && rm -f .ai/runs/LOCK)
# The seed base is the migration guard's alone (architecture review round 1): base_ref, which the factory scripts'
# integrity check reads, stays main's on the run's branch.
got=$(cd "$WORK/repo" && FACTORY_BASE_REF=refs/heads/seedmain "$BASH" -c '. "$1"/_lib.sh; base_ref' _ "$HOOKS")
if [ "$got" = refs/heads/seedmain ]; then echo "  ok: base_ref is not the seed base"
else echo "::error::base_ref on the seed branch answered $got, not refs/heads/seedmain"; failures=$((failures+1)); fi
# A record naming commits this repository does not hold (security review round 1): no write, and main's base, not the
# migration guard's "base not found" exception.
(cd "$WORK/repo" && cp .ai/runs/SEED "$WORK/seed.good" && echo "$SEED_BR $(printf 'a%.0s' $(seq 40)) $(printf 'b%.0s' $(seq 40))" > .ai/runs/SEED)
expect 2 "a record of commits that do not exist: the seeder writes nothing" "$W" --seed -- "$(seeder Edit svc/src/main/java/S.java)"
expect 2 "a record of commits that do not exist: main's base" env FACTORY_BASE_REF=refs/heads/seedmain "$M" -- "$(seeder Edit "$MIG/V3__s.sql")"
(cd "$WORK/repo" && cp "$WORK/seed.good" .ai/runs/SEED)
# The seeder's Bash is read-only (readonly-bash.sh): no branch, no commit, no redirect into a migration.
for c in 'git switch main' 'git checkout -b other' 'git checkout seedmain' 'git branch other' 'git commit -qam x' \
         "git add $MIG/V3__s.sql" "printf 'x' >> $MIG/V1__a.sql" 'git stash' 'git reset --hard'; do
    expect 2 "seeder's Bash: $c" "$R" --agent defect-seeder -- "$(agent_call defect-seeder Bash command "$c")"
done
for c in 'git show --stat HEAD' 'git show HEAD' 'git status' 'git grep -n -e class -- svc'; do
    expect 0 "seeder's Bash: $c" "$R" --agent defect-seeder -- "$(agent_call defect-seeder Bash command "$c")"
done
# Off the run's branch, or with a record that is not one, the seeder writes nothing and the base is main's again.
(cd "$WORK/repo" && git switch -q seedmain)
expect 2 "seeder on another branch: nothing"          "$W" --seed -- "$(seeder Edit svc/src/main/java/S.java)"
expect 2 "migration: off the run's branch, main's base" env FACTORY_BASE_REF=refs/heads/seedmain "$M" -- "$(seeder Edit "$MIG/V3__s.sql")"
(cd "$WORK/repo" && git switch -q "$SEED_BR" && echo "$SEED_BR not-a-sha" > .ai/runs/SEED)
expect 2 "a record that is not one: the seeder writes nothing" "$W" --seed -- "$(seeder Edit svc/src/main/java/S.java)"
expect 2 "a record that is not one: main's base"      env FACTORY_BASE_REF=refs/heads/seedmain "$M" -- "$(seeder Edit "$MIG/V3__s.sql")"
(cd "$WORK/repo" && rm -f .ai/runs/SEED)
expect 2 "no record: the seeder writes nothing"       "$W" --seed -- "$(seeder Edit svc/src/main/java/S.java)"
expect 2 "no record: main's base (P-19's refusal)"    env FACTORY_BASE_REF=refs/heads/seedmain "$M" -- "$(seeder Edit "$MIG/V3__s.sql")"
(cd "$WORK/repo" && git switch -q feat/x)

echo "isolation-probe (backlog #0-252)"
IP="$HOOKS/isolation-probe.sh"
# probe_call <agent_type, "" for none> <command> — a Bash call as the session-level hook sees it.
probe_call() {
    if [ -n "$1" ]; then jq -cn --arg a "$1" --arg c "$2" '{agent_type: $a, agent_id: "ag1", tool_use_id: "tu1", tool_name: "Bash", tool_input: {command: $c}}'
    else jq -cn --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}}'; fi
}
PROBE='git rev-parse --verify --quiet isolation-probe-R7'
record() { readlink "$WORK/repo/.ai/runs/isolation/R7" 2>/dev/null || echo "-"; }
# The hook's message, read into a variable: under pipefail a pipe into grep would take the hook's exit 2 as its own.
said() { local out; out=$(cd "$WORK/repo" && printf '%s' "$2" | "$IP" 2>&1 >/dev/null); case "$out" in *"$1"*) return 0 ;; esac; return 1; }
ok() { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }
(cd "$WORK/repo" && mkdir -p .ai/runs && rm -rf .ai/runs/isolation && echo "R7 $(git rev-parse HEAD)" > .ai/runs/LOCK)
expect 0 "another command passes"               "$IP" -- "$(probe_call review-general 'git status')"
expect 0 "a reviewer's git grep for the probe passes" "$IP" -- "$(probe_call review-general 'git grep -n isolation-probe -- .claude/')"
expect 0 "not the exact probe passes, unrecorded" "$IP" -- "$(probe_call review-general "$PROBE; true")"
if [ "$(record)" = "-" ]; then ok "... and records nothing"; else fail "a command that is not the exact probe recorded $(record)"; fi
expect 2 "the probe without agent_type is refused" "$IP" -- "$(probe_call "" "$PROBE")"
if [ "$(record)" = "-" ]; then ok "... and records nothing (the main session)"; else fail "a probe without agent_type recorded $(record)"; fi
expect 2 "a probe naming another run is refused" "$IP" -- "$(probe_call review-general 'git rev-parse --verify --quiet isolation-probe-R6')"
# -L, not -e: a record links to a type name, not a file, so -e follows it to nothing and reads "absent" (a mutation
# that dropped the lock check passed this test with -e).
if [ ! -L "$WORK/repo/.ai/runs/isolation/R6" ]; then ok "... and records nothing for it"; else fail "a probe of a run that holds no lock was recorded"; fi
expect 2 "the probe is refused, so it never runs" "$IP" -- "$(probe_call review-general "$PROBE")"
if [ "$(record)" = review-general ]; then ok "... and records the agent type Claude Code named"; else fail "the probe recorded $(record), not review-general"; fi
if said "recorded (agent type: review-general)" "$(probe_call review-general "$PROBE")"; then ok "... and tells the agent it was recorded"
else fail "the probe's refusal does not say it was recorded"; fi
expect 2 "a second probe of the run is refused"  "$IP" -- "$(probe_call workflow-subagent "$PROBE")"
if [ "$(record)" = review-general ]; then ok "... and does not replace the first record"; else fail "a second probe replaced the record with $(record)"; fi
(cd "$WORK/repo" && rm -rf .ai/runs/isolation)
expect 2 "an agent of another type is recorded as itself" "$IP" -- "$(probe_call workflow-subagent "$PROBE")"
if [ "$(record)" = workflow-subagent ]; then ok "... as workflow-subagent, which the check refuses"; else fail "recorded $(record), not workflow-subagent"; fi
(cd "$WORK/repo" && rm -rf .ai/runs/isolation && mkdir -p .ai/runs/isolation/R7)
expect 2 "a directory at the record's name refuses" "$IP" -- "$(probe_call review-general "$PROBE")"
if [ -z "$(ls -A "$WORK/repo/.ai/runs/isolation/R7")" ]; then ok "... and nothing is linked inside it"; else fail "the probe linked inside a directory at the record's name"; fi
(cd "$WORK/repo" && rm -rf .ai/runs/isolation && mkdir -p "$WORK/iso-elsewhere" && ln -s "$WORK/iso-elsewhere" .ai/runs/isolation)
expect 2 "a symlink at the records' directory refuses" "$IP" -- "$(probe_call review-general "$PROBE")"
if [ -z "$(ls -A "$WORK/iso-elsewhere")" ]; then ok "... and nothing is recorded where it points"; else fail "the probe was recorded through a symlinked directory"; fi
(cd "$WORK/repo" && rm -rf .ai/runs/isolation && printf 'R7' > .ai/runs/LOCK)
expect 2 "a lock without its newline still names the run" "$IP" -- "$(probe_call review-general "$PROBE")"
if [ "$(record)" = review-general ]; then ok "... and the probe is recorded"; else fail "a lock without a newline: recorded $(record)"; fi
(cd "$WORK/repo" && rm -rf .ai/runs/isolation .ai/runs/LOCK)
expect 2 "no lock: the probe is refused"         "$IP" -- "$(probe_call review-general "$PROBE")"
if [ "$(record)" = "-" ]; then ok "... and records nothing"; else fail "a probe without a lock recorded $(record)"; fi
expect 2 "an argument is refused"                "$IP" --agent x -- "$(probe_call review-general 'git status')"
(cd "$WORK/repo" && rm -rf .ai/runs/isolation)

echo "every hook fails closed (backlog #0-162)"
# Claude Code runs the call after any exit status but 2, so each way a hook can fail must end in 2. One row per
# hook in this directory: its arguments and a call it allows, so that a 2 below can only come from the failure.
# A hook without a row fails here, and so in Factory guards: a new hook gets these cases or does not merge.
FAILS_CLOSED=(
    "guard-migrations.sh||$(file_call Edit svc/src/main/java/A.java)"
    "guard-tests.sh||$(bash_call './mvnw test -pl incident-service')"
    "guard-protected-bash.sh||$(bash_call 'git status')"
    "readonly-bash.sh||$(bash_call 'git status')"
    "write-scope.sh|.ai/audit/|$(file_call Write .ai/audit/2026-11-03.md)"
    "factory-ops-bash.sh||$(run_call fc1 fc1 'scripts/factory/preflight.sh')"
    "guard-git-push.sh||$(bash_call 'git status')"
    "guard-factory-scripts.sh||$(bash_call 'git status')"
    "guard-write-in-repo.sh||$(file_call Write svc/src/main/java/A.java)"
    "webfetch-allowlist.sh||$(fetch_call verifier https://osv.dev/vulnerability/x)"
    "read-scope.sh|.ai/runs/|$(file_call Read .ai/runs/x.json)"
    "foreground-bash.sh||$(bash_call './mvnw test -pl shared')"
    "isolation-probe.sh||$(bash_call 'git status')"
)
# Three broken copies of the directory: no helper; a helper that aborts the hook while it loads (an unset variable
# under set -u ends the shell, which `|| exit 2` on the load line cannot see: only the EXIT trap turns it into 2);
# and a jq that fails, on PATH (installed, so json_get does not fall back to python3).
mkdir -p "$WORK/fc-nolib" "$WORK/fc-abort" "$WORK/fc-jq"
for f in "$HOOKS"/*.sh; do
    case "${f##*/}" in _lib.sh|test-hooks.sh) continue ;; esac
    cp "$f" "$WORK/fc-nolib/"; cp "$f" "$WORK/fc-abort/"
done
cp "$HOOKS/_lib.sh" "$WORK/fc-abort/"
printf ': "$no_such_variable_0_162"\n' >>"$WORK/fc-abort/_lib.sh"
printf '#!/bin/sh\nexit 5\n' >"$WORK/fc-jq/jq"; chmod +x "$WORK/fc-jq/jq"
for row in "${FAILS_CLOSED[@]}"; do
    hook=${row%%|*} rest=${row#*|}
    arg=${rest%%|*} json=${rest#*|}
    set -f
    # shellcheck disable=SC2206
    args=($arg)
    set +f
    expect 0 "$hook: control, the call is allowed"   "$HOOKS/$hook" ${args[@]+"${args[@]}"} -- "$json"
    expect 2 "$hook: without _lib.sh"                "$WORK/fc-nolib/$hook" ${args[@]+"${args[@]}"} -- "$json"
    expect 2 "$hook: aborts while loading"           "$WORK/fc-abort/$hook" ${args[@]+"${args[@]}"} -- "$json"
    expect 2 "$hook: jq fails"                       env PATH="$WORK/fc-jq:$PATH" "$HOOKS/$hook" ${args[@]+"${args[@]}"} -- "$json"
done
for f in "$HOOKS"/*.sh; do
    name=${f##*/}
    case "$name" in _lib.sh|test-hooks.sh) continue ;; esac
    found=0
    for row in "${FAILS_CLOSED[@]}"; do [ "${row%%|*}" = "$name" ] && found=1; done
    if [ "$found" = 1 ]; then echo "  ok: $name has fail-closed cases"
    else echo "::error::$name has no row in FAILS_CLOSED (test-hooks.sh): add one, with a call it allows"; failures=$((failures+1)); fi
done
# The guarded load also refuses when the helper is unreadable, not only missing (a trap cannot see that one: `.`
# fails, the hook goes on and ends in exit 0). Skipped as root, who reads the file anyway.
if [ "$(id -u)" != 0 ]; then
    mkdir -p "$WORK/fc-unreadable"; cp "$HOOKS/_lib.sh" "$HOOKS/guard-tests.sh" "$WORK/fc-unreadable/"
    chmod 000 "$WORK/fc-unreadable/_lib.sh"
    expect 2 "guard-tests.sh: _lib.sh unreadable"    "$WORK/fc-unreadable/guard-tests.sh" -- "$(bash_call './mvnw test -pl incident-service')"
    chmod 644 "$WORK/fc-unreadable/_lib.sh"
else
    echo "  skip: _lib.sh unreadable (running as root)"
fi
# One layer down: json_get tells an absent field (empty, 0) from a parser that failed or empty input (4) and from
# no parser at all (3), with jq and with the python3 fallback (a PATH that holds only the python3 given).
JG="$WORK/jg"
mkdir -p "$JG/none" "$JG/py-ok" "$JG/py-fails"
ln -s "$(command -v python3)" "$JG/py-ok/python3"
printf '#!/bin/sh\nexit 1\n' >"$JG/py-fails/python3"; chmod +x "$JG/py-fails/python3"
# jg_rc <PATH or empty for the normal one> <json> <path>
jg_rc() {
    local path=${1:-$PATH}
    env PATH="$path" "$BASH" -c '. "$1"/_lib.sh; json_get "$2" "$3" >/dev/null' _ "$HOOKS" "$2" "$3"; echo $?
}
for case_ in "0||{\"a\":1}|.b|jq: an absent field" "4||not json|.a|jq: input that does not parse" \
             "4|||.a|jq: empty input" "0|$JG/py-ok|{\"a\":1}|.a|python3: a field" \
             "4|$JG/py-ok|not json|.a|python3: input that does not parse" "4|$JG/py-ok||.a|python3: empty input" \
             "4|$JG/py-fails|{\"a\":1}|.a|python3 fails" "3|$JG/none|{\"a\":1}|.a|no parser at all"; do
    want=${case_%%|*} r=${case_#*|}; pth=${r%%|*} r=${r#*|}; in=${r%%|*} r=${r#*|}; path=${r%%|*} name=${r#*|}
    got=$(jg_rc "$pth" "$in" "$path")
    if [ "$got" = "$want" ]; then echo "  ok: json_get: $name"; else echo "::error::json_get: $name: expected $want, got $got"; failures=$((failures+1)); fi
done

if [ "$failures" -gt 0 ]; then echo "$failures hook test(s) failed"; exit 1; fi
echo "All hook tests passed."
