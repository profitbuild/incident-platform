#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/: autopilot sessions may not run it). Summarises one workflow run from its Claude Code
# transcripts, per agent call and for the run, for the baseline of ADR-0055 stage 3 (backlog #0-205): what each call
# cost (turns, tokens by kind, model), how long it took, which tools it used, which paths it read and wrote, which
# programs it ran, and every refusal, with the hook that gave it.
#
# Derived from the transcripts, not recorded beside them (#0-205: a PostToolUse logger would record again what the
# transcripts hold, sit on every call and stop a run when it fails). The transcripts' format is Claude Code's own, not a
# contract, so, as seed-scan.sh does (ADR-0044 decision 6), it refuses ({"ok": false}) a shape it does not know rather
# than report numbers it cannot stand behind: a directory with no agent, a meta file without `agentType`, an agent
# without its transcript, a line that is not JSON, an assistant message without its id, model, usage or timestamp.
# The workflow's journal.jsonl only adds each call's label and whether it answered; without it, both are null.
#
# What it never copies (#0-205 AC2): a file's content, a tool's output, a message's text, or a command's arguments
# beyond one word: a command is reduced to its program, and to its first subcommand only for a program known to take one (`git diff`,
# `./mvnw verify`, `scripts/factory/state.sh record`): any other program's first word may be a value (`echo <secret>`,
# `mysql -p <secret>`, review round 1 of #0-205, SEC-31), so it is kept bare. Every path and program that still looks
# like a credential (a GitHub, Anthropic, AWS or Slack token, a JWT) is replaced by "[redacted]". The one word is the
# first that is not an option, so an option's value before the subcommand takes its place (`git -C repo status` gives
# `git repo`): which options take a value differs by program, and the word is lower-case letters and hyphens only, at
# most 24 long (review round 2 of #0-205, SEC-31).
#
# The second reader of this format, next to seed-scan.sh (review round 1 of #0-205, ARC-02): a change in Claude Code's
# layout is to be fixed in both until stage 4's dispatcher replaces them. They differ on purpose on a journal.jsonl that
# is not JSON: seed-scan.sh reads on (its journal only narrows what it reports, so it reports more, never less), this
# script refuses (its journal gives a label and `answered` to every call, and a guessed `answered` would be a number it
# cannot stand behind).
#
#   run-summary.sh <workflow transcript dir>
#     the dir: ~/.claude/projects/<project>/<session>/subagents/workflows/wf_<id>/, or its copy in the owner's archive
# Prints {"ok": true, "run": {...}, "calls": [...]}. Tested by .github/scripts/test-run-summary.sh.
# ============================================================
set -uo pipefail

refuse() { jq -n --arg r "$1" '{ok: false, reason: $r}'; exit 0; }
command -v jq >/dev/null 2>&1 || { echo '{"ok":false,"reason":"jq is not installed"}'; exit 0; }

[ $# -eq 1 ] || refuse "usage: run-summary.sh <workflow transcript dir>"
dir=${1%/}
[ -d "$dir" ] || refuse "no such directory: ${dir:0:200}"

# The journal: per agent id, the label of its `started` event and whether a `result` followed. Optional.
journal='{}'
if [ -f "$dir/journal.jsonl" ]; then
    journal=$(jq -s 'reduce .[] as $e ({};
            if $e.type == "started" and ($e.agentId | type) == "string" then .[$e.agentId].label = ($e.label // null)
            elif $e.type == "result" and ($e.agentId | type) == "string" then .[$e.agentId].answered = true
            else . end)' "$dir/journal.jsonl" 2>/dev/null) || refuse "journal.jsonl is not JSON lines"
fi

# One call's summary, from its transcript (slurped) and its meta file.
# shellcheck disable=SC2016  # a jq program: its $names are jq's, not the shell's
call_jq='
def secret: test("gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}");
def clean: if secret then "[redacted]" else . end;
# ts: the timestamp of a line in milliseconds (ISO 8601, UTC, with or without a fraction of a second).
def ts: .timestamp as $t
  | ($t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) * 1000
    + ((($t | capture("\\.(?<f>[0-9]+)Z$") | .f) // "0") + "00" | .[0:3] | tonumber);
# program: a shell command reduced to its program, no arguments: leading VAR=value words are skipped. Only a program
# that takes a subcommand (git, gh, docker, kubectl, limactl, npm, mvn, the Maven wrapper, a factory script) keeps its
# first word that is not an option, and only a plain lower-case word of letters and hyphens, at most 24 long (no
# digits: a commit or a run id stays out).
def subcommands: ["git", "gh", "docker", "kubectl", "limactl", "npm", "mvn", "mvnw"];
def program:
  (split("\n")[0] | [splits("[ \t]+")] | map(select(length > 0))
   | until((length == 0) or (.[0] | test("^[A-Za-z_][A-Za-z0-9_]*=") | not); .[1:])) as $w
  | if ($w | length) == 0 then "" else
      ($w[0] | (split("/") | last) as $b | (subcommands | index([$b]) != null)
               or test("(^|/)scripts/factory(-admin)?/[A-Za-z0-9_.-]+\\.sh$")) as $takes
      | ($w[1:] | map(select(startswith("-") | not)) | .[0] // "") as $sub
      | ($w[0] | clean) + (if $takes and ($sub | test("^[a-z]([a-z-]{0,22}[a-z])?$")) then " " + $sub else "" end)
    end;
def text: if type == "string" then . elif type == "array" then (map(.text // "") | join(" ")) else "" end;
def refusal:
  (.content | text) as $t
  | if ($t | test("^(PreToolUse|PostToolUse):[A-Za-z]+ hook error")) then
      {kind: "hook", tool: ($t | capture("^[A-Za-z]+:(?<x>[A-Za-z]+)").x),
       by: (($t | capture("BLOCKED by (?<x>[A-Za-z0-9._-]+\\.sh)").x) // null)}
    elif ($t | test("^Permission to use [A-Za-z]+ has been denied")) then
      {kind: "permission", tool: ($t | capture("^Permission to use (?<x>[A-Za-z]+)").x), by: null}
    else null end;

. as $lines
| ($lines | map(select(.type == "assistant"))) as $asst
| ($asst | map(.message.content // [] | if type == "array" then .[] else empty end | select(.type == "tool_use"))
   | unique_by(.id)) as $uses
| ($lines | map(select(.type == "user") | .message.content | if type == "array" then .[] else empty end
   | select(.type == "tool_result" and .is_error == true))) as $errors
# One entry per API message: Claude Code writes a message as one line per content block, each with the usage of the
# message. Every line of the stage 2 runs carries the same usage (372 messages, 286 of them split); the largest value
# of each field is kept, so a format that wrote partial usage on early lines would still count the final one (review
# round 2 of #0-205, GEN-01).
| ($asst | group_by(.message.id) | map({model: .[0].message.model,
     usage: {input_tokens: (map(.message.usage.input_tokens // 0) | max),
             output_tokens: (map(.message.usage.output_tokens // 0) | max),
             cache_read_input_tokens: (map(.message.usage.cache_read_input_tokens // 0) | max),
             cache_creation_input_tokens: (map(.message.usage.cache_creation_input_tokens // 0) | max)}})) as $msgs
| ($lines | map(select(.timestamp != null) | ts)) as $times
| {agentId: $id, type: $meta.agentType, phase: ($meta.workflowPhase // null),
   label: ($journal[$id].label // null), answered: (if $journal == {} then null else ($journal[$id].answered // false) end),
   models: ($msgs | map(.model) | map(select(. != "<synthetic>")) | unique),
   turns: ($msgs | length),
   tokens: {input: ($msgs | map(.usage.input_tokens // 0) | add // 0),
            output: ($msgs | map(.usage.output_tokens // 0) | add // 0),
            cacheRead: ($msgs | map(.usage.cache_read_input_tokens // 0) | add // 0),
            cacheCreation: ($msgs | map(.usage.cache_creation_input_tokens // 0) | add // 0)},
   startedAt: (if ($times | length) > 0 then ($times | min / 1000 | floor | todate) else null end),
   startedMs: (if ($times | length) > 0 then ($times | min) else null end),
   durationMs: (if ($times | length) > 0 then ($times | max) - ($times | min) else 0 end),
   tools: ($uses | group_by(.name) | map({key: .[0].name, value: length}) | from_entries),
   paths: {read: ($uses | map(select(.name == "Read") | .input.file_path // empty | clean) | unique),
           written: ($uses | map(select(.name == "Edit" or .name == "Write" or .name == "NotebookEdit")
                     | (.input.file_path // .input.notebook_path) // empty | clean) | unique)},
   commands: ($uses | map(select(.name == "Bash") | .input.command // "" | program | select(length > 0))
              | group_by(.) | map({key: .[0], value: length}) | from_entries),
   refusals: ($errors | map(refusal) | map(select(. != null))),
   errors: ($errors | map(select(refusal == null)) | length)}
'

calls='[]' n=0
for meta in "$dir"/agent-*.meta.json; do
    [ -e "$meta" ] || continue
    id=${meta##*/agent-}; id=${id%.meta.json}
    transcript=${meta%.meta.json}.jsonl
    meta_json=$(jq -c . "$meta" 2>/dev/null) || refuse "agent-$id.meta.json is not JSON"
    jq -e '.agentType | type == "string"' <<<"$meta_json" >/dev/null || refuse "agent-$id.meta.json names no agentType"
    [ -f "$transcript" ] || refuse "agent-$id has a meta file and no transcript"
    jq -e . "$transcript" >/dev/null 2>&1 || refuse "agent-$id.jsonl is not JSON lines"
    bad=$(jq -r 'select(.type == "assistant" and ((.message.id | type) != "string" or (.message.model | type) != "string"
                 or (.message.usage | type) != "object" or (.timestamp | type) != "string")) | "x"' "$transcript" | head -1)
    [ -z "$bad" ] || refuse "agent-$id.jsonl has an assistant message without its id, model, usage or timestamp"
    call=$(jq -s --arg id "$id" --argjson meta "$meta_json" --argjson journal "$journal" "$call_jq" "$transcript" 2>/dev/null) \
        || refuse "agent-$id.jsonl could not be summarised"
    calls=$(jq -c --argjson c "$call" '. + [$c]' <<<"$calls")
    n=$((n + 1))
done
[ "$n" -gt 0 ] || refuse "no agent in this directory (agent-*.meta.json)"

# shellcheck disable=SC2016  # a jq program
jq -n --arg run "${dir##*/}" --argjson calls "$calls" '
  def sum(f): map(f) | add // 0;
  def tok: {input: sum(.tokens.input), output: sum(.tokens.output), cacheRead: sum(.tokens.cacheRead),
            cacheCreation: sum(.tokens.cacheCreation)};
  ($calls | sort_by(.startedMs // 0)) as $c
  | ($c | map(select(.startedMs != null))) as $timed
  | {ok: true,
     run: {id: $run, calls: ($c | length), turns: ($c | sum(.turns)), tokens: ($c | tok),
           startedAt: ($timed | first | .startedAt // null),
           wallMs: (if ($timed | length) > 0 then
                      ($timed | map(.startedMs + .durationMs) | max) - ($timed | first | .startedMs)
                    else 0 end),
           byType: ($c | group_by(.type) | map({key: .[0].type, value: {calls: length, turns: sum(.turns),
                     durationMs: sum(.durationMs), tokens: tok}}) | from_entries),
           byModel: ($c | map(. as $x | .models[] | {m: ., x: $x}) | group_by(.m)
                     | map({key: .[0].m, value: {calls: length}}) | from_entries),
           refusals: ($c | map(.refusals[]) | group_by(.kind + ":" + (.by // .tool))
                      | map({key: (.[0].kind + ":" + (.[0].by // .[0].tool)), value: length}) | from_entries),
           unanswered: ($c | map(select(.answered == false) | .agentId))},
     calls: $c}'
