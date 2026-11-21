#!/usr/bin/env bash
# ============================================================
# Parsing of BACKLOG.md, BACKLOG-DONE.md and .ai/plan/queue.md for the factory scripts. Sourced, not run.
# Text in, JSON out (jq). Portable: awk + jq, no bash 4 features, so the owner can run the checks on macOS.
#
#   backlog_json <protected-re> < BACKLOG.md
#                                      → [{id, title, type, branchPrefix, priority, status, autopilot, risk,
#                                           complexity, dependsOn:[ids], followUpOf, touches, modules:[...],
#                                           protected:[paths], order}]
#     branchPrefix: the prefix of the item's branch, from its **Type:** (BRANCH_PREFIX_OF below), or null for a type
#     that has none (design, a misspelt one): next-item.sh does not choose such an item.
#     protected: the paths of .ai/rules/protected-paths.md that the item's **Touches:** names
#     (<protected-re> from _protected.sh: paths_regex free). Touches is what the change writes; a criterion
#     may name a protected path only to refer to it (an existing check), so the criteria are not read.
#     A bare `ci` (no parentheses) counts too: `ci` is .github/ and scripts/, and everything tracked under
#     both is protected today — a Touches line must name the path for the gate to judge it.
#   done_json      < BACKLOG-DONE.md   → ["0-1", "0-18", …]
#   readied_items <before> <after>     → ["0-50", …]: the items whose section the change from <before> to <after>
#                                        (two BACKLOG.md files) made or changed, and that are `ready` or `human-only`
#                                        after it: the items a /ready PR readied (backlog #0-220, audit-data.sh)
#   queue_json     < queue.md          → {markers: bool, rows: [{index, pos, item, why}]}
#
# Ids are bare ("0-25"), without "#". The order of an item is its row in the open-items table.
# ============================================================

# Values allowed in **Touches:** (and in the architect's planned modules) — the Maven modules of the root
# POM, plus areas outside them. scripts/factory/changed-paths.sh maps a diff onto the same vocabulary, so
# the three can be compared (.ai/rules/planning.md, "Touches"):
#   root   files at the repository root (pom.xml, README.md, CLAUDE.md, Makefile), .ai/context/,
#          architecture-tests/
#   docs   docs/          k8s   k8s/          docker   docker/          ci   .github/, scripts/
# Read by the scripts that source this file (check-queue.sh), not here (backlog #0-149).
# shellcheck disable=SC2034
# The prefix of an item's branch, by its **Type:** (backlog #0-195): the one table. next-item.sh hands it to the
# workflow, which names the branch `<prefix>/<item>-<slug>` with the picker's slug, and start-item.sh refuses a branch
# with another prefix. Fixed: the picker chose the prefix from a table in its own definition, and four runs gave a
# `security` item `feat/` (one shipped as PR #587, one ended the run when the picker tried to rename the branch).
# `design` has none on purpose: next-item.sh never chooses a design item. A type not listed has none either, so a
# misspelt one stops the item before it starts instead of getting a guessed prefix.
BRANCH_PREFIX_OF='{"bug":"fix","security":"fix","tech-debt":"refactor","ci":"ci","docs":"docs","performance":"perf"}'

# The lock of an item by a branch's name (backlog #0-278 AC11, ADR-0060 D8 as amended): item 0-N is held by a branch
# whose name contains /0-N- (a slash, the item, a dash), and by no other. A jq definition, put in front of next-item.sh's
# program; its cases are .github/scripts/fixtures/item-lock-branches.tsv, which test-queue.sh runs through this very
# definition and profitbuild/factory's dispatcher (src/github/item-lock.mjs) through a copy of the file, held equal to
# it by check-factory-copies.rb (ADR-0061): one rule, two implementations, the same cases. Fixed: the rule lived only
# inside next-item.sh's program, and the dispatcher's copy of it was checked against nothing of the product's.
# shellcheck disable=SC2016 # $locks and $id are jq's variables, not the shell's
LOCKED_BY_JQ='def lockedBy($id): [$locks[] | select(contains("/" + $id + "-"))] | first // null;'

KNOWN_MODULES='["shared","service-parent","auth-service","ingestion-service","incident-service","notification-service","escalation-service","postmortem-service","oncall-service","root","docs","k8s","docker","ci"]'

# trim() and field(<line>, <name>): the value of `**<name>:**` on a line, up to the next ` · `, without backticks.
# Defined once, and put in front of every awk program below that reads a field (review round 2 of #0-220: backlog_json
# and readied_items held two copies of it, which could drift).
AWK_FIELDS='
        function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function field(line, name,    key, i, rest, j) {
            key = "**" name ":**"; i = index(line, key); if (!i) return ""
            rest = substr(line, i + length(key)); j = index(rest, " \302\267 "); if (j) rest = substr(rest, 1, j - 1)
            gsub(/`/, "", rest); return trim(rest)
        }
'

backlog_json() {
    local protected_re=${1:?backlog_json needs the protected-path regex (_protected.sh)}
    LC_ALL=C awk "$AWK_FIELDS"'
        function flush() {
            if (id != "") printf "I\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", id, title, type, prio, status, auto, risk, cx, deps, fup, touches
            id = ""
        }
        /^\| *\[0-[0-9]+\]/ {
            split($0, c, "|"); tid = c[2]; sub(/^ *\[/, "", tid); sub(/\].*/, "", tid)
            printf "T\t%s\t%s\n", tid, trim(c[5]); next
        }
        /^### 0-[0-9]+\./ {
            flush(); id = $2; sub(/\.$/, "", id); title = $0; sub(/^### 0-[0-9]+\. */, "", title)
            type = prio = status = auto = risk = cx = deps = fup = touches = ""; next
        }
        /^## / { flush(); next }
        id != "" && /^\*\*Type:\*\*/ && type == "" { type = field($0, "Type"); prio = field($0, "Priority"); status = field($0, "Status") }
        id != "" && /^\*\*Autopilot:\*\*/ && auto == "" {
            auto = field($0, "Autopilot"); risk = field($0, "Risk"); cx = field($0, "Complexity")
            deps = field($0, "Depends on"); fup = field($0, "Follow-up of")
        }
        id != "" && /^\*\*Touches:\*\*/ && touches == "" { touches = field($0, "Touches") }
        END { flush() }
    ' | jq -R -s --arg protected "$protected_re" --argjson prefixOf "$BRANCH_PREFIX_OF" '
        split("\n") | map(select(length > 0) | split("\t")) as $rows
        | ($rows | map(select(.[0] == "T")) | to_entries
            | map({key: .value[1], value: {order: .key, priority: .value[2]}}) | from_entries) as $table
        | $rows | map(select(.[0] == "I") | {
            id: .[1], title: .[2], type: (.[3] | ascii_downcase), branchPrefix: ($prefixOf[.[3] | ascii_downcase] // null),
            priority: .[4], status: .[5],
            autopilot: (.[6] | ascii_downcase), risk: (.[7] | ascii_downcase), complexity: (.[8] | ascii_downcase),
            dependsOn: [.[9] | scan("0-[0-9]+")],
            followUpOf: ([.[10] | scan("0-[0-9]+")] | first // null),
            touches: .[11],
            modules: (.[11] | gsub("\\([^)]*\\)"; "") | split(",") | map(gsub("^\\s+|\\s+$"; ""))
                      | map(select(length > 0 and . != "—" and . != "-")) | unique),
            protected: ([.[11] | scan($protected)]
                        + (if (.[11] | test("(^|,)\\s*ci\\s*(,|$)")) then ["ci (no path given)"] else [] end)
                        | unique)
          } | . + {order: ($table[.id].order // 9999),
                   priority: (if .priority == "" then ($table[.id].priority // "") else .priority end)})'
}

# The sections end where backlog_json's do (the next `### 0-N.` or `## ` heading), so both read the same item. An
# item counts when its section differs at all, not only its **Autopilot:** line: a /ready PR that corrects the criteria
# of an item already ready (#582 for #0-199) readied it again. An item the change only adds as not-ready, or splits off
# (#568 added #0-193, not-ready), does not count: its title may name it, but it was not readied.
readied_items() {
    LC_ALL=C awk "$AWK_FIELDS"'
        { f = (FILENAME == ARGV[1]) ? 1 : 2 }
        /^### 0-[0-9]+\./ { id = $2; sub(/\.$/, "", id); seen[f, id] = 1 }
        /^## / { id = ""; next }
        FNR == 1 && !/^### 0-[0-9]+\./ { id = "" }
        id != "" { body[f, id] = body[f, id] $0 "\n" }
        id != "" && /^\*\*Autopilot:\*\*/ && !((f, id) in auto) {
            auto[f, id] = tolower(field($0, "Autopilot"))
        }
        END {
            for (k in seen) {
                split(k, p, SUBSEP); if (p[1] != 2) continue
                i = p[2]; if ((auto[2, i] == "ready" || auto[2, i] == "human-only") && body[1, i] != body[2, i]) print i
            }
        }
    ' "$1" "$2" | jq -R . | jq -s 'unique'
}

# Only the table above `## Details`: below it are finished items' whole sections (moved there from BACKLOG.md), free
# text that may one day hold a table of its own, and a `| 0-N |` row of an open item there would make it "done" and let
# a `**Depends on:**` through. The picker's own `git grep` re-check
# (.claude/agents/picker.md) still reads the whole file: it only repeats what next-item.sh decided from this.
done_json() {
    # awk reads to the end and stops printing, not `exit`: an early exit closes the pipe on the writer (`git show`,
    # `cat` of a 3000-line file), which then dies of SIGPIPE, and under pipefail the caller's `|| done_ids='[]'` would
    # read no item as done (seen in check-queue.sh on the real file, not on the test's small one).
    LC_ALL=C awk '/^## Details/ { stop = 1 } !stop' | LC_ALL=C grep -oE '^\| *0-[0-9]+ *\|' | grep -oE '0-[0-9]+' \
        | jq -R . | jq -s 'unique'
}

queue_json() {
    LC_ALL=C awk "$AWK_FIELDS"'
        /<!-- queue:start -->/ { on = 1; seen++; next }
        /<!-- queue:end -->/   { on = 0; seen++; next }
        on && /^\|/ {
            n = split($0, c, "|"); item = trim(c[3]); pos = trim(c[2])
            if (item == "Item" || $0 ~ /^[|: -]+$/) next
            id = ""; if (match(item, /0-[0-9]+/)) id = substr(item, RSTART, RLENGTH)
            printf "Q\t%s\t%s\t%s\n", pos, id, trim(c[4])
        }
        END { printf "M\t%d\n", seen }
    ' | jq -R -s '
        split("\n") | map(select(length > 0) | split("\t")) as $rows
        | { markers: (($rows | map(select(.[0] == "M")) | first | .[1] | tonumber) == 2),
            rows: ($rows | map(select(.[0] == "Q")) | to_entries
                   | map({index: .key, pos: .value[1], item: .value[2], why: (.value[3] // "")})) }'
}
