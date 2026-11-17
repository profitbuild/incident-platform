#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory-admin/run-summary.sh (backlog #0-205, ADR-0055 stage 3), on fixture transcripts shaped as
# Claude Code writes a Workflow run's (agent-<id>.jsonl + agent-<id>.meta.json + journal.jsonl): per agent call its
# turns and tokens (one API message split over several lines counted once), duration, tools, paths, programs and
# refusals with the hook that gave them; the run's totals; nothing of a file's content, a command's arguments or a
# token-shaped string; and a refusal, rather than numbers, wherever the shape is not the one it knows.
# Run: .github/scripts/test-run-summary.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
SUMMARY="$SRC/scripts/factory-admin/run-summary.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

# A fake token of each shape the summary redacts, built at run time so that no literal sits in this file.
GH_TOKEN_LIKE="ghp_$(printf 'A%.0s' $(seq 36))"
SECRET_CONTENT="db-password-must-not-leak"

# asst <msg id> <ts> <model> <in> <out> <content json>: one line of an assistant message (Claude Code writes one line per
# content block, each with the message's id and usage).
asst() {
    jq -cn --arg id "$1" --arg ts "$2" --arg m "$3" --argjson i "$4" --argjson o "$5" --argjson c "$6" \
        '{type: "assistant", timestamp: $ts, message: {id: $id, model: $m, content: $c,
          usage: {input_tokens: $i, output_tokens: $o, cache_read_input_tokens: 100, cache_creation_input_tokens: 10}}}'
}
use() { jq -cn --arg id "$1" --arg n "$2" --argjson in "$3" '[{type: "tool_use", id: $id, name: $n, input: $in}]'; }
result() {   # result <ts> <tool_use id> <is_error> <text>
    jq -cn --arg ts "$1" --arg id "$2" --argjson e "$3" --arg t "$4" \
        '{type: "user", timestamp: $ts, message: {content: [{type: "tool_result", tool_use_id: $id, is_error: $e, content: $t}]}}'
}
user() { jq -cn --arg ts "$1" --arg t "$2" '{type: "user", timestamp: $ts, message: {content: $t}}'; }
meta() { jq -cn --arg t "$1" --arg p "$2" '{agentType: $t, isBuiltIn: false, workflowPhase: $p}'; }

# The run: an implementer (two messages, the first split over three lines; a Read, an Edit with a secret in its text, a
# Bash with a token as an argument and an env prefix, a hook refusal, a permission refusal, a failed command) and a
# reviewer on another model; the journal says the implementer answered and the reviewer did not.
run=$WORK/wf_test-run
mkdir -p "$run"
meta implementer Implement > "$run/agent-a1.meta.json"
{
    user "2026-11-16T10:00:00.000Z" "task"
    asst m1 "2026-11-16T10:00:01.000Z" claude-opus-5-5 5 50 '[{"type":"thinking","thinking":"x"}]'
    asst m1 "2026-11-16T10:00:01.100Z" claude-opus-5-5 5 50 "$(use t1 Read '{"file_path":"/workspace/shared/A.java"}')"
    asst m1 "2026-11-16T10:00:01.200Z" claude-opus-5-5 5 50 "$(use t2 Edit "$(jq -cn --arg s "$SECRET_CONTENT" '{file_path: "/workspace/shared/B.java", old_string: "a", new_string: $s}')")"
    result "2026-11-16T10:00:02.000Z" t1 false "file text"
    result "2026-11-16T10:00:02.100Z" t2 false "edited"
    asst m2 "2026-11-16T10:00:03.000Z" claude-opus-5-5 7 70 "$(use t3 Bash "$(jq -cn --arg tok "$GH_TOKEN_LIKE" '{command: ("GH_TOKEN=" + $tok + " gh pr view 12 --json body")}')")"
    asst m2 "2026-11-16T10:00:03.100Z" claude-opus-5-5 7 70 "$(use t4 Bash '{"command":"git add -f .ai/runs"}')"
    asst m2 "2026-11-16T10:00:03.200Z" claude-opus-5-5 7 70 "$(use t5 Bash '{"command":"curl https://example.com"}')"
    asst m2 "2026-11-16T10:00:03.300Z" claude-opus-5-5 7 70 "$(use t6 Bash '{"command":"./mvnw -q verify -pl shared"}')"
    asst m2 "2026-11-16T10:00:03.400Z" claude-opus-5-5 7 70 "$(use t7 Read "$(jq -cn --arg tok "$GH_TOKEN_LIKE" '{file_path: ("/tmp/" + $tok)}')")"
    asst m2 "2026-11-16T10:00:03.500Z" claude-opus-5-5 7 70 "$(use t8 Bash '{"command":"scripts/factory/state.sh 3f2a9c1d"}')"
    asst m2 "2026-11-16T10:00:03.600Z" claude-opus-5-5 7 70 "$(use t10 Bash '{"command":"echo mypassphrase"}')"
    asst m2 "2026-11-16T10:00:03.700Z" claude-opus-5-5 7 70 "$(use t11 Bash '{"command":"mysql -u root -p hunter"}')"
    asst m2 "2026-11-16T10:00:03.800Z" claude-opus-5-5 7 70 "$(use t12 Bash '{"command":"scripts/factory/state.sh record --item x"}')"
    result "2026-11-16T10:00:04.000Z" t3 false "body"
    # shellcheck disable=SC2016  # the hook's message as Claude Code writes it, $CLAUDE_PROJECT_DIR unexpanded
    result "2026-11-16T10:00:04.100Z" t4 true 'PreToolUse:Bash hook error: ["$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-protected-bash.sh]: BLOCKED by guard-protected-bash.sh: .ai/runs is runtime state'
    result "2026-11-16T10:00:04.200Z" t5 true "Permission to use Bash has been denied because Claude Code is running in don't ask mode."
    result "2026-11-16T10:00:04.300Z" t6 true "Exit code 1"
    result "2026-11-16T10:00:05.5Z" t7 false "x"
} > "$run/agent-a1.jsonl"
meta review-general Review > "$run/agent-b2.meta.json"
{
    user "2026-11-16T10:00:06.250Z" "review"
    asst m3 "2026-11-16T10:00:07.000Z" claude-sonnet-5-5 3 1 '[{"type":"thinking","thinking":"x"}]'
    asst m3 "2026-11-16T10:00:07.100Z" claude-sonnet-5-5 3 30 "$(use t9 Bash '{"command":"git diff abc123...HEAD"}')"
    asst m3 "2026-11-16T10:00:07.200Z" claude-sonnet-5-5 3 30 "$(use t13 Bash '{"command":"git -C repo status"}')"
    result "2026-11-16T10:00:08.000Z" t9 false "diff"
    asst m4 "2026-11-16T10:00:09.000Z" claude-sonnet-5-5 2 20 '[{"type":"text","text":"done"}]'
    user "2026-11-16T10:00:10.250Z" "end"
} > "$run/agent-b2.jsonl"
printf '%s\n' '{"type":"launched"}' \
    '{"type":"started","key":"k1","agentId":"a1","label":"implement","phase":"Implement"}' \
    '{"type":"result","key":"k1","agentId":"a1","result":"{}"}' \
    '{"type":"started","key":"k2","agentId":"b2","label":"review general r1","phase":"Review"}' > "$run/journal.jsonl"

out=$("$SUMMARY" "$run")
check() {   # check <name> <jq expression>
    if jq -e "$2" <<<"$out" >/dev/null 2>&1; then ok "$1"; else fail "$1: $(jq -c "${3:-.}" <<<"$out" 2>/dev/null || echo "$out")"; fi
}
echo "== a run's summary"
check "ok, two calls, run id from the directory" '.ok == true and .run.id == "wf_test-run" and .run.calls == 2'
check "a message split over lines is one turn, its tokens counted once" \
    '(.calls[] | select(.agentId == "a1")) | .turns == 2 and .tokens == {input: 12, output: 120, cacheRead: 200, cacheCreation: 20}' '.calls[0]'
check "a message written with partial usage on an early line counts its final usage" \
    '(.calls[] | select(.agentId == "b2")) | .turns == 2 and .tokens.output == 50' '.calls'
check "the one word kept after a program with subcommands may be an option's value (git -C repo status)" \
    '(.calls[] | select(.agentId == "b2")) | .commands == {"git diff": 1, "git repo": 1}' '.calls'
check "the run's tokens are the sum of its calls" \
    '.run.turns == 4 and .run.tokens == {input: 17, output: 170, cacheRead: 400, cacheCreation: 40}' '.run'
check "duration from the first to the last line, to the millisecond (a one-digit fraction too)" \
    '(.calls[] | select(.agentId == "a1") | .durationMs == 5500) and (.calls[] | select(.agentId == "b2") | .durationMs == 4000)' '.calls'
check "the run's wall time spans its calls, from a call that starts within a second" '.run.wallMs == 10250 and .run.startedAt == "2026-11-16T10:00:00Z"' '.run'
check "type, phase, model and the journal's label" \
    '(.calls[] | select(.agentId == "b2")) | .type == "review-general" and .phase == "Review" and .label == "review general r1" and .models == ["claude-sonnet-5-5"]'
check "answered from the journal; the unanswered call is named" \
    '(.calls[] | select(.agentId == "a1") | .answered == true) and (.calls[] | select(.agentId == "b2") | .answered == false) and .run.unanswered == ["b2"]'
check "tools counted by name" '(.calls[] | select(.agentId == "a1")) | .tools == {Bash: 8, Edit: 1, Read: 2}' '.calls[0].tools'
check "paths read and written" \
    '(.calls[] | select(.agentId == "a1")) | .paths.written == ["/workspace/shared/B.java"] and (.paths.read | index("/workspace/shared/A.java") != null)' '.calls[0].paths'
check "a command is its program, and its subcommand only for a program that takes one: env prefix, options and arguments dropped" \
    '(.calls[] | select(.agentId == "a1")) | .commands == {"gh pr": 1, "git add": 1, "curl": 1, "./mvnw verify": 1, "scripts/factory/state.sh": 1, "scripts/factory/state.sh record": 1, "echo": 1, "mysql": 1}' '.calls[0].commands'
check "a hook refusal names its hook, a dontAsk denial is a permission refusal" \
    '(.calls[] | select(.agentId == "a1")) | .refusals == [{kind: "hook", tool: "Bash", by: "guard-protected-bash.sh"}, {kind: "permission", tool: "Bash", by: null}]' '.calls[0].refusals'
check "a failed command is an error, not a refusal" '(.calls[] | select(.agentId == "a1")) | .errors == 1'
check "the run counts refusals by hook or tool" '.run.refusals == {"hook:guard-protected-bash.sh": 1, "permission:Bash": 1}' '.run.refusals'
check "the run counts calls by type and by model" \
    '.run.byType["review-general"].calls == 1 and .run.byModel == {"claude-opus-5-5": {calls: 1}, "claude-sonnet-5-5": {calls: 1}}' '.run'

echo "== nothing it must not copy (#0-205 AC2)"
if grep -q "$SECRET_CONTENT" <<<"$out"; then fail "an edit's text reached the summary"; else ok "no file content"; fi
if grep -q "$GH_TOKEN_LIKE" <<<"$out"; then fail "a token-shaped string reached the summary"; else ok "no token, as an argument or in a path"; fi
check "a token-shaped path is redacted, not dropped" '(.calls[] | select(.agentId == "a1")) | .paths.read | index("[redacted]") != null' '.calls[0].paths'
if grep -q "3f2a9c1d\|abc123\|example.com\|pr view 12\|mypassphrase\|hunter\|root" <<<"$out"; then fail "a command's argument reached the summary"; else ok "no command argument"; fi

echo "== no journal"
nj=$WORK/wf_no-journal; mkdir -p "$nj"; cp "$run"/agent-* "$nj/"
out=$("$SUMMARY" "$nj")
check "still summarised; label and answered are null" '.ok == true and (.calls | all(.label == null and .answered == null)) and .run.unanswered == []'

echo "== refusals: a shape it does not know"
refused() {   # refused <name> <reason regex> <dir>
    local o; o=$("$SUMMARY" "$3")
    if jq -e --arg re "$2" '.ok == false and (.reason | test($re))' <<<"$o" >/dev/null; then ok "$1"; else fail "$1: $o"; fi
}
refused "no such directory" "no such directory" "$WORK/missing"
mkdir -p "$WORK/empty"; refused "no agent" "no agent" "$WORK/empty"
mk() { local d=$WORK/$1; mkdir -p "$d"; cp "$run"/agent-* "$run/journal.jsonl" "$d/"; echo "$d"; }
d=$(mk no-type); echo '{"isBuiltIn":false}' > "$d/agent-a1.meta.json"; refused "a meta file without agentType" "agentType" "$d"
d=$(mk no-transcript); rm "$d/agent-b2.jsonl"; refused "a meta file without its transcript" "no transcript" "$d"
d=$(mk not-json); echo 'not json' >> "$d/agent-b2.jsonl"; refused "a transcript line that is not JSON" "not JSON lines" "$d"
d=$(mk no-usage); jq -cn '{type: "assistant", timestamp: "2026-11-16T10:00:11Z", message: {id: "m9", model: "claude-opus-5-5", content: []}}' >> "$d/agent-b2.jsonl"
refused "an assistant message without usage" "without its id, model, usage or timestamp" "$d"
d=$(mk bad-journal); echo '{' >> "$d/journal.jsonl"; refused "a journal that is not JSON" "journal.jsonl is not JSON" "$d"
o=$("$SUMMARY")
if jq -e '.ok == false and (.reason | test("usage:"))' <<<"$o" >/dev/null; then ok "no argument"; else fail "no argument: $o"; fi

echo
if [ "$failures" -gt 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "all run-summary tests passed"
