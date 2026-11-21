#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory/notify.sh (backlog #0-283): no topic sends nothing; a topic without FACTORY_NTFY_SERVER
# sends nothing either and says why (no default server since #0-283: the devcontainer's firewall opens only the server
# the image was built with); with both, one POST to <server>/<topic>; a failed curl is reported. Every answer is the
# JSON the autopilot's workflow reads (NOTIFIED: `sent` a boolean, `reason` a string). curl is a stub on PATH that
# records its arguments, so nothing is sent.
# Run: .github/scripts/test-notify.sh   (also run by .github/workflows/factory-guards.yml)
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

mkdir -p "$WORK/bin"
# curl: appends its arguments, one per line, to $WORK/calls, then exits $CURL_EXIT (0 when unset).
cat > "$WORK/bin/curl" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$WORK/calls"
exit "\${CURL_EXIT:-0}"
STUB
chmod +x "$WORK/bin/curl"

# run <name> <jq expression true of the answer> [VAR=value ...] — runs notify.sh blocked 0-1 with only those variables.
run() {
    local name=$1 want=$2 out; shift 2
    rm -f "$WORK/calls"
    out=$(env -u FACTORY_NTFY_TOPIC -u FACTORY_NTFY_SERVER "$@" PATH="$WORK/bin:$PATH" "$SRC/scripts/factory/notify.sh" blocked 0-1)
    if printf '%s' "$out" | jq -e "(.sent | type) == \"boolean\" and ((.reason // \"\") | type) == \"string\" and ($want)" >/dev/null 2>&1
    then ok "$name"; else fail "$name: '$want' is false for: $out"; fi
}
no_call() { if [ ! -e "$WORK/calls" ]; then ok "... and curl was not called"; else fail "curl was called: $(tr '\n' ' ' < "$WORK/calls")"; fi; }

echo "notify.sh"
run "no topic sends nothing" '.sent == false and .reason == "FACTORY_NTFY_TOPIC not set"'
no_call
run "a topic without a server sends nothing and says what to set" \
    '.sent == false and (.reason | startswith("FACTORY_NTFY_SERVER not set"))' FACTORY_NTFY_TOPIC=t0p1c
no_call
run "an empty server is no server" '.sent == false and (.reason | startswith("FACTORY_NTFY_SERVER not set"))' \
    FACTORY_NTFY_TOPIC=t0p1c FACTORY_NTFY_SERVER=
no_call
run "a topic and a server send" '.sent == true' FACTORY_NTFY_TOPIC=t0p1c FACTORY_NTFY_SERVER=https://ntfy.example.test
if [ -e "$WORK/calls" ] && grep -qx 'https://ntfy.example.test/t0p1c' "$WORK/calls" && grep -qx 'Title: Autopilot: blocked' "$WORK/calls"; then
    ok "... one POST to <server>/<topic>, titled by the event"
else fail "curl's arguments: $(tr '\n' ' ' < "$WORK/calls" 2>/dev/null)"; fi
run "a failed curl is reported" '.sent == false and .reason == "curl failed"' \
    FACTORY_NTFY_TOPIC=t0p1c FACTORY_NTFY_SERVER=https://ntfy.example.test CURL_EXIT=7

if [ "$failures" -ne 0 ]; then echo "$failures notify.sh test(s) failed."; exit 1; fi
echo "All notify.sh tests passed."
