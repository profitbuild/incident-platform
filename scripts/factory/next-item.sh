#!/usr/bin/env bash
# ============================================================
# Which backlog item the autopilot takes next — decided here, in code, not by an agent.
#   next-item.sh <base-sha>             choose
#   next-item.sh <base-sha> <0-N>       check one item the owner named (args.item)
#
# Everything is read from the run's base commit (the sha in .ai/runs/LOCK), never from the working copy.
# An item can start when, on the base: it is in BACKLOG.md with `**Autopilot:** ready` and a status that starts with
# Open (the condition start-item.sh starts it on: one that passes here and is refused there would be chosen again on
# every run, backlog #0-209), it is not of type
# design, its type has a branch prefix (BRANCH_PREFIX_OF, _backlog.sh; backlog #0-195), its **Touches:** names no path of .ai/rules/protected-paths.md (such an item could only end
# BLOCKED at the implementer, as #0-42 did; backlog #0-122), every `**Depends on:**` is in BACKLOG-DONE.md, and no open PR or local branch holds it (a branch
# name containing "/<id>-" is a lock; a BLOCKED item keeps its draft PR open).
#
# Order of choice:
#   1. follow-up: a ready item with `**Follow-up of:** #P` whose parent P is done — work that a finished
#      item showed was needed runs right after it (.ai/rules/planning.md, "Follow-ups");
#   2. queue: when .ai/plan/queue.md exists on the base, its first row that is not done — strictly in
#      order: when that row cannot start (not ready, a dependency open, waiting for the owner's merge),
#      nothing starts. The queue must pass check-queue.sh, or nothing starts. An exhausted queue means
#      "run /plan-backlog", not a fallback: the owner approved that order and no other;
#   3. priority (no queue file): ready items by priority (High, Medium, Low), then table order.
#
# Output: {"ok", "reasons", "item": "#0-N"|null, "source", "eligible", "reason", "touches", "modules",
#          "followUpOf", "position", "risk", "complexity", "type", "branchPrefix", "skipped": [{"item", "why"}]}
# risk and complexity are read here from the base commit, so the workflow does not depend on the picker's
# copy of them for the merge decision and the choice of implementer; type and branchPrefix likewise, for the name of
# the item's branch (backlog #0-195: the workflow puts the prefix in front of the picker's slug).
# ============================================================
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/_common.sh"
. "$HERE/_backlog.sh"
. "$HERE/_protected.sh"

fail() { jq -n --arg r "$1" '{ok:false, reasons:[$r], item:null}'; exit 1; }

base=${1:-}
want=${2:-}
case "$base" in *[!0-9a-f]*|'') fail "next-item.sh needs the base commit sha" ;; esac
[ "${#base}" -eq 40 ] || fail "next-item.sh needs the full 40-character base commit sha"
git cat-file -e "$base^{commit}" 2>/dev/null || fail "unknown base commit $base"
if [ -n "$want" ]; then
    case "$want" in 0-[0-9]*) ;; *) fail "item must look like 0-25" ;; esac
    case "${want#0-}" in *[!0-9]*) fail "item must look like 0-25" ;; esac
fi

item_re=$({ protected_paths protected "$base" && protected_paths build-config "$base"; } | paths_regex free) \
    || fail "cannot read the lists of .ai/rules/protected-paths.md on the base commit"
backlog=$(git show "$base:BACKLOG.md" | backlog_json "$item_re") || fail "cannot read BACKLOG.md on the base commit"
done_ids=$(git show "$base:BACKLOG-DONE.md" 2>/dev/null | done_json) || done_ids='[]'

check=$("$HERE/check-queue.sh" --ref "$base")
if ! printf '%s' "$check" | jq -e '.valid' >/dev/null 2>&1; then
    fail "the queue on main is invalid: $(printf '%s' "$check" | jq -r '(.errors // ["no result"]) | join("; ")' 2>/dev/null)"
fi
present=$(printf '%s' "$check" | jq -r '.present')
queue='{"markers":true,"rows":[]}'
[ "$present" = true ] && queue=$(git show "$base:.ai/plan/queue.md" | queue_json)

# Locks: open PRs (draft or not) and local branches. Fail closed: no answer from GitHub, no start.
prs=$(gh pr list --state open --json headRefName --limit 300 --jq '.[].headRefName' 2>/dev/null) || fail "gh pr list failed: cannot check locks"
local_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/)
locks=$(printf '%s\n%s\n' "$prs" "$local_branches" | sed '/^$/d' | jq -R . | jq -s .)

# 'done' quoted: bare, shellcheck reads jq's variable name as the shell keyword (SC1010, backlog #0-149).
jq -n --argjson items "$backlog" --argjson 'done' "$done_ids" --argjson q "$queue" --argjson locks "$locks" \
      --arg want "$want" --argjson present "$present" --argjson prefixOf "$BRANCH_PREFIX_OF" '
  ($items | map({key: .id, value: .}) | from_entries) as $byId
  | def isDone($id): ($done | index($id)) != null;
    '"$LOCKED_BY_JQ"'
    def why($id):
      ($byId[$id]) as $it
      | if $it == null then (if isDone($id) then "done" else "not in BACKLOG.md on main" end)
        elif $it.autopilot != "ready" then "not ready (Autopilot: \(if $it.autopilot == "" then "none" else $it.autopilot end))"
        elif ($it.status | startswith("Open") | not)
          then "its status is not Open (Status: \(if $it.status == "" then "none" else $it.status[0:60] end)): start-item.sh starts only an Open item"
        elif $it.type == "design" then "a design item"
        elif $it.branchPrefix == null
          then "its type (Type: \(if $it.type == "" then "none" else $it.type[0:40] end)) has no branch prefix: one of \($prefixOf | keys | join(", ")) (_backlog.sh, BRANCH_PREFIX_OF)"
        elif ($it.protected | length) > 0
          then "Touches names \($it.protected | join(", ")), a path the autopilot may not write (.ai/rules/protected-paths.md): make it human-only or split it"
        elif ([$it.dependsOn[] | select(isDone(.) | not)] | length) > 0
          then "waits for \([$it.dependsOn[] | select(isDone(.) | not) | "#" + .] | join(", "))"
        elif lockedBy($id) != null then "in progress or blocked (branch \(lockedBy($id)))"
        else null end;
    def pick($id; $source; $position):
      ($byId[$id]) as $it
      | {ok: true, reasons: [], item: ("#" + $id), source: $source, eligible: true, reason: null,
         touches: $it.touches, modules: $it.modules, followUpOf: $it.followUpOf, position: $position,
         risk: $it.risk, complexity: $it.complexity, type: $it.type, branchPrefix: $it.branchPrefix};
    def rank: {"high": 0, "medium": 1, "low": 2}[ascii_downcase] // 3;

  if $want != "" then
    (why($want)) as $w
    | if $w == null then pick($want; "manual"; null) + {skipped: []}
      else {ok: true, reasons: [], item: null, source: "manual", eligible: false,
            reason: "#\($want) cannot start: \($w)", skipped: [{item: ("#" + $want), why: $w}]} end
  else
    ([$items[] | select(.followUpOf != null and isDone(.followUpOf) and why(.id) == null)] | sort_by(.order) | first) as $fu
    | if $fu != null then pick($fu.id; "follow-up"; null) + {skipped: []}
      elif $present then
        ($q.rows | map(select(.item != "" and (isDone(.item) | not))) | first) as $head
        | if $head == null then
            {ok: true, reasons: [], item: null, source: "queue", eligible: false,
             reason: "the approved queue is done: run /plan-backlog for the next one", skipped: []}
          elif why($head.item) == null then pick($head.item; "queue"; ($head.index + 1)) + {skipped: []}
          else
            {ok: true, reasons: [], item: null, source: "queue", eligible: false,
             reason: "the next queue row, #\($head.item) (row \($head.index + 1)), cannot start: \(why($head.item))",
             skipped: [{item: ("#" + $head.item), why: why($head.item)}]}
          end
      else
        ([$items[] | select(why(.id) == null)] | sort_by([(.priority | rank), .order]) | first) as $p
        | if $p != null then pick($p.id; "priority"; null) + {skipped: []}
          else {ok: true, reasons: [], item: null, source: "priority", eligible: false,
                reason: "no item is ready on main with its dependencies done and no lock", skipped: []} end
      end
  end'
