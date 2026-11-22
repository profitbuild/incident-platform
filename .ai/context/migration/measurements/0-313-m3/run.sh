#!/bin/bash
# #0-313 measurement 3 (AC9): does the pinned Claude Code send its calls through ANTHROPIC_UNIX_SOCKET under F3?
# Usage: run.sh <variant> <settings dir> [VAR=value ...]   (the call container has no network at all)
set -uo pipefail
S=$(cd "$(dirname "$0")" && pwd); v=$1; etc=$2; shift 2
IMG=ip-devc-0313:c26c6cf7; out="$S/out/$v"; mkdir -p "$out"
docker rm -f m313-gw >/dev/null 2>&1; docker volume rm m313sock >/dev/null 2>&1; docker volume create m313sock >/dev/null
docker run -d --name m313-gw --network none -v m313sock:/sock -v "$S/gw.mjs:/gw/gw.mjs:ro" -e SOCK=/sock/api.sock \
  node:22-alpine node /gw/gw.mjs >/dev/null
# Wait for the gateway's "ready" line, so a gateway that did not start stops the run instead of passing for a result.
for _ in $(seq 1 20); do docker logs m313-gw 2>&1 | grep -q '"ready"' && break; sleep 0.5; done
docker logs m313-gw 2>&1 | grep -q '"ready"' \
  || { echo "run.sh: the gateway did not start:" >&2; docker logs m313-gw >&2
       docker rm -f m313-gw >/dev/null; exit 1; }
# EXTRA_ARGS is split into words on purpose (several flags, or none), so it is not quoted below.
# shellcheck disable=SC2086
echo 'Answer with one word.' | docker run -i --rm --network none --user dev -w /workspace \
  -v m313sock:/run/sock -v "$S/factory:/opt/factory:ro" -v "$S/$etc:/etc/claude-code:ro" \
  -v "$S/token:/run/factory:ro" -v "$S/workspace:/workspace" --entrypoint /usr/bin/timeout "$IMG" \
  -s TERM -k 10 "${LIMIT:-90}" /usr/bin/env -i HOME=/home/dev LANG=C.UTF-8 \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin DISABLE_AUTOUPDATER=1 DISABLE_UPDATES=1 \
  CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 "$@" \
  /usr/local/bin/claude -p --output-format stream-json --verbose --permission-mode dontAsk \
  --plugin-dir /opt/factory --agent factory:implementer --restricted --tools Read Grep Glob Bash Edit Write \
  --add-dir /workspace --max-turns 1 ${EXTRA_ARGS:-} > "$out/stream.jsonl" 2> "$out/stderr.txt"
echo "exit=$?" > "$out/exit.txt"
docker logs m313-gw > "$out/gw.jsonl" 2>&1; docker rm -f m313-gw >/dev/null; docker volume rm m313sock >/dev/null
echo "== $v $(cat "$out/exit.txt")"
jq -c 'select(.type=="system" and .subtype=="init") | {apiKeySource, model, claude_code_version, tools}' "$out/stream.jsonl" 2>/dev/null
jq -c 'select(.type=="result") | {subtype, is_error, result: (.result|tostring|.[0:160])}' "$out/stream.jsonl" 2>/dev/null
echo "-- gateway:"; grep -v '"ready"' "$out/gw.jsonl" | jq -c '{via,method,path,host,authorization,xApiKey}' 2>/dev/null | sort | uniq -c
echo "-- stderr:"; head -c 600 "$out/stderr.txt"
