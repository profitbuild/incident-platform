#!/usr/bin/env bash
# ============================================================
# The paths no agent writes, read from their one definition, .ai/rules/protected-paths.md. Sourced, not
# run; no side effects. Used by changed-paths.sh (a diff touching them needs the owner) and by next-item.sh
# and check-queue.sh (an item whose Touches names one is not autopilot work). Portable: awk + sed.
#
#   protected_paths <protected|build-config|runtime> [ref]   the entries of one list, one per line, from the
#                                                    commit <ref> (the base), or the working tree without one;
#                                                    `runtime` (the autopilot's state, backlog #0-168) is read
#                                                    only by .github/scripts/check-protected-paths.sh
#   paths_regex <anchored|free>   < paths            an ERE for those paths: anchored matches a repository
#                                                    path (a directory: what is under it; a file: itself),
#                                                    free matches them anywhere in a text, a directory
#                                                    also without its slash (".github", "scripts/factory");
#                                                    a bare alternation, so jq's scan returns the match
# Every ERE metacharacter of an entry is escaped, so an entry is always a literal path.
#
# Fixed (backlog #0-122): the list was copied into each script and agent and had drifted apart.
# ============================================================

# Read relative to the clone, from the given commit's tree (git show <ref>:<file>) or, with no ref, the working
# tree. In the dispatcher's task container the clone and its objects are the agent's side, so this input is not the
# base's as the scripts beside _common.sh are (FACTORY_SCRIPTS_DIR): changed-paths.sh, its reader there, is advisory,
# and no refusal of the dispatcher rests on it; the dispatcher reads the list itself (#0-305, M3.1). Until then a
# branch can narrow what run-tests.sh builds there (it takes its modules from changed-paths.sh); the PR's CI builds
# from the committed tree and is the check. Backlog #0-278.
PROTECTED_PATHS_FILE=.ai/rules/protected-paths.md

# Fails (status 1, nothing printed) when the file, the list or its markers are missing: callers fail closed.
protected_paths() {
    local section=$1 ref=${2:-} text out
    if [ -n "$ref" ]; then
        text=$(git show "$ref:$PROTECTED_PATHS_FILE" 2>/dev/null) || return 1
    else
        text=$(cat "$PROTECTED_PATHS_FILE" 2>/dev/null) || return 1
    fi
    out=$(printf '%s\n' "$text" | LC_ALL=C awk -v s="$section" '
        index($0, "<!-- " s ":start -->") { on = 1; next }
        index($0, "<!-- " s ":end -->")   { on = 0; next }
        on && /^- `[^`]+`/ { p = $0; sub(/^- `/, "", p); sub(/`.*/, "", p); print p }')
    [ -n "$out" ] || return 1
    printf '%s\n' "$out"
}

paths_regex() {
    LC_ALL=C sed -e '/^$/d' -e 's/[][\\.*^$+?(){}|]/\\&/g' | LC_ALL=C awk -v m="$1" '
        { r = $0
          if (m == "anchored") { if (r !~ /\/$/) r = r "$" } else sub(/\/$/, "", r)
          out = (NR == 1) ? r : out "|" r }
        END { if (NR == 0) exit 1; printf (m == "anchored" ? "^(%s)" : "%s"), out }'
}
