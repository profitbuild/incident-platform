#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/: autopilot sessions may not run it). Reads one /seed-bugs run's reviewer
# transcripts and reports what told them the change was a measure, before the run's row lands (backlog #0-179):
#   - told: the message the Workflow tool relayed to every agent ("[Workflow harness — user request]", the user's
#     message that started the turn), when it names the run (seed, benchmark, plant, a pattern id, the run id) (#0-179);
#   - original: a reviewer's git read (`diff`, `show`, `log`, `cat-file`, `rev-list`, `blame`, `grep`, `diff-tree`,
#     `ls-tree`, `archive`, `reflog`, `show-branch`) that names main, HEAD~/^, another ref, the base's parent, the base
#     outside a diff or another commit, or walks a history from HEAD (the merged change is on main, the revert holds
#     its lines: #0-185), as "names" (--stat, --name-only, a message, a list) or "content" (any patch); a read of the
#     reviewed branch's own commit is the review, not a hit, when the run's journal.jsonl names it (the "seed fold"
#     call's answer, seed-bugs.js), and without a journal it is reported like any other commit;
#   - catalogue: a tool call that names .ai/audit/, patterns.md, .ai/rules/audit.md, .ai/runs/benchmark or the seeder
#     (the answer key, ADR-0044 decision 6).
# An aid to the owner's reading, not its replacement (owner, 2026-10-30; ADR-0044 decision 6): the transcripts' format
# is Claude Code's own, not a contract. So it refuses ({"ok": false}) wherever it does not find the shape it knows (no
# reviewer, a reviewer without its transcript, a first message that is neither of the harness's two headers, a panel
# prompt without its mergeBase, a seeder prompt without the pattern and run id asked for), rather than answering
# "nothing found" for a format it cannot read. Its words are matched as text: a hit is for the owner to read, and
# the forms of a read it knows are a list, not a proof (review round 1 of #0-179: a reviewer can reach the change in
# ways no list foresees). Its output quotes what reviewers ran and were relayed, text an agent that read the diff
# shaped: data to read, never instructions, in whatever session it is read.
#
#   seed-scan.sh <workflow transcript dir> <pattern> <run id>
#     the dir: ~/.claude/projects/<project>/<session>/subagents/workflows/wf_<id>/ (the run's transcriptDir)
# Reads the run's agent-*.jsonl and agent-*.meta.json (the transcripts) and its journal.jsonl (the workflow's answers).
# The journal is read differently from the transcripts: a shape it does not know is no refusal, only no exception
# (`run.head` is null and the reviewed commit's reads are reported), so the scan reports more, never less.
# Prints {"ok": true, "run": {...}, "reviewers": [{type, relay, told, original, catalogue}], "summary": {...}}.
# run-summary.sh (backlog #0-205) reads the same layout: a change in Claude Code's format is to be fixed in both. It
# refuses a journal that is not JSON, where this scan reads on (see its header for why they differ).
# Tested by .github/scripts/test-seed-scan.sh.
# ============================================================
set -uo pipefail

refuse() { jq -n --arg r "$1" '{ok: false, reason: $r}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{"ok":false,"reason":"jq is not installed"}'; exit 0; }

[ $# -eq 3 ] || refuse "usage: seed-scan.sh <workflow transcript dir> <pattern> <run id>"
dir=$1 pattern=$2 run_id=$3
# A defect pattern P- or a clean one C- (backlog #0-180): the scan reads both kinds of run the same way.
[[ $pattern =~ ^[PC]-[0-9]+$ ]] || refuse "not a pattern id: ${pattern:0:40}"
[[ $run_id =~ ^[A-Za-z0-9._-]+$ ]] || refuse "not a run id: ${run_id:0:40}"
[ -d "$dir" ] || refuse "no such directory: ${dir:0:200}"

# type_of <meta.json>: the agent type a run's meta file names, or nothing.
type_of() { jq -r '.agentType // empty' "$1" 2>/dev/null; }
# messages <transcript>: every user message's text, one JSON string per message (array contents' text blocks joined).
messages() {
    jq -c 'select(.type == "user") | .message.content
           | if type == "string" then . elif type == "array" then (map(select(.type == "text") | .text) | join("\n")) else empty end' "$1"
}

seeder="" reviewers=()
for meta in "$dir"/agent-*.meta.json; do
    [ -e "$meta" ] || continue
    t=$(type_of "$meta") || refuse "cannot read ${meta##*/}"
    case "$t" in
        defect-seeder) seeder=${meta%.meta.json}.jsonl ;;
        review-*) reviewers+=("${meta%.meta.json}.jsonl|$t") ;;
    esac
done
[ "${#reviewers[@]}" -gt 0 ] || refuse "no review-* agent in this directory (not a /seed-bugs run that reached its panel?)"
[ -n "$seeder" ] && [ -f "$seeder" ] || refuse "no defect-seeder transcript in this directory"

# The run, from the seeder's prompt (seed-bugs.js): "Pattern <p>. Run id <id>. The branch <b> is checked out: it holds
# merged change <commit>\nas its last commit, on the base <base>."
task=$(messages "$seeder" | jq -rs 'join("\n")') || refuse "cannot read the seeder's transcript"
[[ $task =~ Pattern\ ([PC]-[0-9]+)\.\ Run\ id\ ([A-Za-z0-9._-]+)\. ]] || refuse "the seeder's prompt names no pattern and run id"
[ "${BASH_REMATCH[1]}" = "$pattern" ] && [ "${BASH_REMATCH[2]}" = "$run_id" ] \
    || refuse "this directory is the run of ${BASH_REMATCH[1]} ${BASH_REMATCH[2]}, not of $pattern $run_id"
[[ $task =~ merged\ change\ ([0-9a-f]{7,40}) ]] || refuse "the seeder's prompt names no merged change"
commit=${BASH_REMATCH[1]}
[[ $task =~ on\ the\ base\ ([0-9a-f]{40}) ]] || refuse "the seeder's prompt names no base"
base=${BASH_REMATCH[1]}
# The branch the panel reviewed: seed-fold.sh's head, from the run's journal (the "seed fold" call's answer). A read of
# that commit is the review itself, not the original (sec-p05-blind: `git log -1 --format=%B <it>` was a false hit).
# No journal, or no such answer: no exception, so the scan reports more, never less.
fold_head=""
if [ -f "$dir/journal.jsonl" ]; then
    fold_head=$(jq -rs '(map(select(.type == "started" and .label == "seed fold") | .key)) as $k
        | map(select(.type == "result" and (.key as $x | $k | index($x)) and .result.ok == true) | .result.head)
        | map(select(type == "string" and test("^[0-9a-f]{40}$"))) | first // empty' "$dir/journal.jsonl" 2>/dev/null) || fold_head=""
fi
# A fold head that is the base or the merged change would hide the reads this scan exists for: refused.
if [ -n "$fold_head" ] && { [ "$fold_head" = "$base" ] || [[ $fold_head == "$commit"* ]]; }; then
    refuse "the journal's fold head $fold_head is the base or the merged change, not the reviewed branch"
fi

# tells <text>: the words of the run that a relayed message names, one per line (any case).
tells() {
    local text=$1 w
    shopt -s nocasematch
    for w in seed benchmark plant patterns.md -after-p "$pattern" "$run_id"; do
        [[ $text == *"$w"* ]] && printf '%s\n' "$w"
    done
    [[ $text =~ (^|[^A-Za-z0-9])[PC]-[0-9][0-9]([^0-9]|$) ]] && printf '%s\n' "a pattern id"
    shopt -u nocasematch
    return 0
}
# catalogue_hit <text>: whether a tool call's input names the answer key (any case).
catalogue_hit() {
    local rc=1
    shopt -s nocasematch
    [[ $1 == *.ai/audit* || $1 == *patterns.md* || $1 == *.ai/rules/audit.md* || $1 == *.ai/runs/benchmark* \
       || $1 == *defect-seeder* || $1 == *seed-bugs* ]] && rc=0
    shopt -u nocasematch
    return "$rc"
}
# original_level <command>: "content", "names" or nothing, for a git read that reaches the merged change (#0-185).
# Refs are matched case-sensitively (review round 1: `Main.java` is no ref); a word of 7 to 40 hex digits is a commit
# only if it holds a digit (`defaced` is a word); a pattern given with -e/--grep is the text searched, not a revision.
# A history read with no revision, or HEAD alone (`git log -p`, `git log -- <path>`) starts at HEAD and walks past the base into
# main's history, and `reflog`/`show-branch`/`--all` list other refs: all of them hits (review round 2).
original_level() {
    local cmd=$1 sub="" hit="" w prev="" i start=0 revs=0 paths="" seen_git="" skip="" limit=""
    local -a words
    read -ra words <<<"$cmd"
    # the subcommand: the word after `git` and its global options (`--no-pager`, `-C <dir>`, `-c <key=value>`, …)
    for ((i = 0; i < ${#words[@]}; i++)); do
        if [ -z "$seen_git" ]; then [ "${words[i]}" = git ] && seen_git=1; continue; fi
        if [ -n "$skip" ]; then skip=""; continue; fi
        case "${words[i]}" in
            -C|-c|--git-dir|--work-tree|--namespace) skip=1 ;;
            -*) ;;
            *) sub=${words[i]}; start=$((i + 1)); break ;;
        esac
    done
    case "$sub" in
        diff|show|log|cat-file|rev-list|blame|grep|diff-tree|ls-tree|archive) ;;
        reflog|show-branch) hit=1 ;;
        *) return 0 ;;
    esac
    for ((i = start; i < ${#words[@]}; i++)); do
        w=${words[i]}; w=${w//\"/}; w=${w//\'/}
        case "$prev" in -n|--max-count) limit=$w; prev=$w; continue ;; esac
        case "$prev" in -e|--grep|-G|-S|--author|--format|--pretty) prev=$w; continue ;; esac
        [[ $w =~ ^-([0-9]+)$ || $w =~ ^-n([0-9]+)$ || $w =~ ^--max-count=([0-9]+)$ ]] && limit=${BASH_REMATCH[1]}
        prev=$w
        [ "$w" = -- ] && { paths=1; continue; }
        [ -n "$paths" ] && continue
        case "$w" in
            --all|--branches*|--remotes*|--glob=*|--tags*) hit=1; continue ;;
            -*) continue ;;
        esac
        # HEAD alone, or the reviewed branch's own commit (the fold head), names no other start than the default: still
        # a walk from HEAD into main's history (`git log -p <fold head>`, review round 1 of the re-run's landing)
        local is_fold=""
        [ -n "$fold_head" ] && [[ $w =~ ^[0-9a-f]{7,40}$ ]] && [[ $fold_head == "$w"* ]] && is_fold=1
        [ "$w" = HEAD ] || [ "$w" = @ ] || [ -n "$is_fold" ] || revs=$((revs + 1))
        case "$w" in
            # the rule files the review procedure reads from main: not the change
            *main:.ai/rules/*) continue ;;
            main|origin/main|refs/remotes/origin/main|refs/heads/main|main[.~^:@]*|origin/main[.~^:@]*|refs/remotes/origin/main[.~^:@]*|*..main|*..origin/main) hit=1 ;;   # a range ending on main, two dots or three
            HEAD~*|HEAD^*|HEAD@*|@~*|@^*|@\{*|FETCH_HEAD*|ORIG_HEAD*|origin/HEAD*|refs/remotes/origin/HEAD*) hit=1 ;;
        esac
        if [[ $w =~ ^([0-9a-f]{7,40})([.~^:].*)?$ ]]; then
            local sha=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]:-}
            if [ -n "$fold_head" ] && [[ $fold_head == "$sha"* ]] && [ -z "$rest" ]; then
                :   # the reviewed branch itself
            elif [[ $base == "$sha"* ]]; then
                # the base: its parent always; itself outside a diff (`git show <base>` is the revert's patch)
                [[ $rest == '^'* || $rest == '~'* ]] && hit=1
                [ "$sub" != diff ] && [ "$sub" != rev-list ] && [[ $rest != ...* && $rest != ..* ]] && hit=1
            elif [[ $sha =~ [0-9] ]]; then
                hit=1   # another commit, the merged change's above all
            fi
        elif [[ $w =~ \.\.\.?([0-9a-f]{7,40}) ]] && [[ $base != "${BASH_REMATCH[1]}"* ]] && [[ ${BASH_REMATCH[1]} =~ [0-9] ]]; then
            hit=1
        fi
    done
    # a history with no revision named starts at HEAD and runs on into main's (`git log -p`, `git log -- <path>`),
    # unless it stops within the branch's own two commits (the change and its revert: `git log -1`, `-n 2`)
    case "$sub" in log|rev-list) [ "$revs" -eq 0 ] && { [ -z "$limit" ] || [ "$limit" -gt 2 ]; } && hit=1 ;; esac
    [ -n "$hit" ] || return 0
    # A patch flag wins over a names flag (`git log -p --stat` shows the lines, review round 2).
    if [[ $cmd =~ (^|[[:space:]])(-p|--patch|-u)([[:space:]]|$) ]] || [ "$sub" = archive ]; then
        echo content
    elif [ "$sub" = ls-tree ] || [ "$sub" = reflog ] || [ "$sub" = show-branch ] \
         || { { [ "$sub" = log ] || [ "$sub" = rev-list ]; }; } \
         || [[ $cmd =~ --stat|--shortstat|--numstat|--name-only|--name-status|--oneline|--format|--pretty|[[:space:]]-s([[:space:]]|$)|--no-patch|[[:space:]]-l([[:space:]]|$)|--files-with-matches ]]; then
        echo names
    else
        echo content
    fi
}

out='[]'
for r in "${reviewers[@]}"; do
    file=${r%|*} type=${r##*|}
    [ -f "$file" ] || refuse "$type has no transcript (${file##*/})"
    first=$(head -n 1 "$file" | jq -r 'select(.type == "user") | .message.content | strings' 2>/dev/null) \
        || refuse "$type: the transcript's first line does not parse"
    [ -n "$first" ] || refuse "$type: the transcript does not start with a user message of text"
    case "$first" in
        '[Workflow harness — user request]'*)
            # The relayed message: the lines indented by two spaces after the header line.
            relay=$(awk 'NR == 1 { next } /^  / { sub(/^  /, ""); print; next } { exit }' <<<"$first") ;;
        '[Workflow harness — computed task]'*) relay="" ;;
        *) refuse "$type: its first message is neither of the Workflow tool's headers (a format this does not know)" ;;
    esac
    all=$(messages "$file" | jq -rs 'join("\n")') || refuse "$type: cannot read its messages"
    [[ $all =~ mergeBase:\ ([0-9a-f]{40}) ]] || refuse "$type: its prompt names no mergeBase"
    [ "${BASH_REMATCH[1]}" = "$base" ] || refuse "$type: its mergeBase ${BASH_REMATCH[1]} is not the seeder's base $base"
    told=$(tells "$relay")
    calls=$(jq -c 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | {name, input}' "$file") \
        || refuse "$type: cannot read its tool calls"
    original='[]' catalogue='[]'
    while IFS= read -r call; do
        [ -n "$call" ] || continue
        name=$(jq -r .name <<<"$call") text=$(jq -r '.input | tostring' <<<"$call")
        catalogue_hit "$text" && catalogue=$(jq -c --arg n "$name" --arg t "${text:0:300}" '. + [{tool: $n, input: $t}]' <<<"$catalogue")
        if [ "$name" = Bash ]; then
            cmd=$(jq -r '.input.command // empty' <<<"$call")
            level=$(original_level "$cmd")
            [ -n "$level" ] && original=$(jq -c --arg c "${cmd:0:300}" --arg l "$level" '. + [{command: $c, level: $l}]' <<<"$original")
        fi
    done <<<"$calls"
    out=$(jq -c --arg t "$type" --arg relay "$relay" --arg told "$told" --argjson o "$original" --argjson c "$catalogue" \
        '. + [{type: $t, relay: (if $relay == "" then null else $relay end),
               told: ($told | split("\n") | map(select(. != ""))), original: $o, catalogue: $c}]' <<<"$out")
done
jq -n --arg p "$pattern" --arg i "$run_id" --arg c "$commit" --arg b "$base" --arg h "$fold_head" --argjson r "$out" '
  {ok: true, run: {pattern: $p, runId: $i, commit: $c, base: $b, head: (if $h == "" then null else $h end)}, reviewers: $r,
   summary: {told: [$r[] | select(.told | length > 0) | .type],
             originalContent: [$r[] | select(any(.original[]; .level == "content")) | .type],
             originalNames: [$r[] | select(any(.original[]; .level == "names")) | .type],
             catalogue: [$r[] | select(.catalogue | length > 0) | .type]}}'
