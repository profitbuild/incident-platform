#!/usr/bin/env bash
# ============================================================
# Tests for scripts/factory-admin/build-vm/install-builder-app.sh (backlog #0-272), offline: `limactl` is a stub on
# PATH that runs the VM's commands here, with the VM's paths (/home/dispatcher, /etc/factory-build-provisioned, Node)
# moved under one temporary directory per case, and `sudo` dropped. What a case checks:
#   - a good run writes the key (equal to the downloaded one) and the env file (the two ids and the dispatcher's six
#     settings, each from its one source: provision.sh and .claude/settings.autopilot.json; backlog #0-277), both mode
#     600 with no `.new` left, runs check-app with that env file and `--adapter-from-repo` (the whole call matched, #0-278 AC8), and
#     deletes the downloaded key;
#   - the key never travels in an argument (argv is readable by every user of the VM): no call holds its text;
#   - every refusal names its cause and keeps the downloaded key: wrong arguments, a link or a file that is no key, no
#     VM, a stopped one, one provisioned without `dispatcher` or from another provision.sh (its pin, helper image or
#     clone not this checkout's), modes or owners not as required, a copy whose digest
#     differs, check-app failing;
#   - a second key replaces the first (a rotation).
# Needs GNU stat (Linux): run by .github/workflows/factory-guards.yml and .github/scripts/ci-local.sh.
# ============================================================
set -uo pipefail

SRC=$(cd "$(dirname "$0")/../.." && pwd)
SCRIPT=$SRC/scripts/factory-admin/build-vm/install-builder-app.sh
PROV=$SRC/scripts/factory-admin/build-vm/provision.sh
LIMITS=$SRC/.claude/settings.autopilot.json
# What the script must write and check, read here independently of it: plain sed and jq on the same sources.
P_COMMIT=$(sed -n 's/^FACTORY_COMMIT=\([0-9a-f]\{40\}\).*$/\1/p' "$PROV")
P_HELPER=$(sed -n 's/^HELPER_IMAGE=\(.*\)$/\1/p' "$PROV")
P_STATE=$(sed -n 's/^DISPATCHER_STATE=\(.*\)$/\1/p' "$PROV")
P_REPO=$(sed -n 's/^DISPATCHER_REPO=\(.*\)$/\1/p' "$PROV")
MARKER="factory-build provisioned: docker; node v24; dispatcher at factory $P_COMMIT in /opt/factory-checkout; helper $P_HELPER; repo $P_REPO; state $P_STATE; boot 1"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
failures=0
n=0
ok()   { echo "  ok: $1"; }
fail() { echo "::error::$1"; failures=$((failures+1)); }

mkdir -p "$WORK/bin"
# limactl stub. $VM is the case's VM root; every call is logged, one argument per line, in $VM/calls.
cat > "$WORK/bin/limactl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "--- $*" >> "$VM/calls"
if [ "$1" = list ]; then
  if [ "$2" = --quiet ]; then printf '%s\n' ${STUB_INSTANCES-factory-build}; exit 0; fi
  echo "${STUB_STATUS:-Running}"; exit 0
fi
[ "$1" = shell ] && [ "$2" = --workdir ] && [ "$3" = / ] && [ "$4" = factory-build ] || { echo "stub: unexpected $*" >&2; exit 2; }
shift 4
if [ "$1" = sudo ]; then
  shift
  while [ "$#" -gt 0 ]; do
    case $1 in
      -n|-H) shift ;;
      -u) shift 2 ;;
      --) shift; break ;;
      *) break ;;
    esac
  done
fi
args=()
for a in "$@"; do
  a=${a//\/home\/dispatcher/$VM/home/dispatcher}
  a=${a//\/etc\/factory-build-provisioned/$VM/etc/factory-build-provisioned}
  a=${a//\/opt\/factory-checkout/$VM/opt/factory-checkout}
  a=${a//\/usr\/local\/bin\/node/$VM/node}
  args+=("$a")
done
if [ "${args[0]}" = stat ]; then
  "${args[@]}" | sed -e "s| $(id -un) $(id -gn) | ${STUB_OWNER:-dispatcher} ${STUB_OWNER:-dispatcher} |" -e "s|$VM||"
  exit 0
fi
"${args[@]}"
if [ -n "${STUB_CORRUPT:-}" ] && [ "${args[0]}" = sh ] && [[ "${args[*]}" == *builder-app.pem ]]; then
  printf 'x' >> "$VM/home/dispatcher/.config/factory/builder-app.pem"
fi
STUB
chmod +x "$WORK/bin/limactl"
# macOS has shasum, a Linux runner may not: the same digest from sha256sum, for the script's Mac-side hash.
if ! command -v shasum >/dev/null; then
  # shellcheck disable=SC2016 # the stub's own text: its $1 and $2 are the stub's arguments, not this shell's
  printf '#!/bin/sh\n[ "$1" = -a ] && [ "$2" = 256 ] && exec sha256sum\nexit 2\n' > "$WORK/bin/shasum"
  chmod +x "$WORK/bin/shasum"
fi
export PATH="$WORK/bin:$PATH"

# Not a key: a PEM frame around a marker line. The frame is joined from two parts, so no secret scanner reads a key
# block in this file (review round 2 of #0-272's second pull request); the script under test still gets it whole.
PEM="RSA PRIVATE"" KEY"
KEYTEXT="-----BEGIN $PEM-----
MIIEsecretLINEnotarealkey0123456789
-----END $PEM-----"

# new_case: a VM root as provision.sh leaves it (home and .config/factory 700), a fake Node, a downloaded key.
new_case() {
  n=$((n+1))
  VM=$WORK/vm$n
  export VM
  mkdir -p "$VM/etc" "$VM/home/dispatcher/.config/factory" "$VM/opt/factory-checkout/dispatcher/bin"
  chmod 700 "$VM/home/dispatcher" "$VM/home/dispatcher/.config" "$VM/home/dispatcher/.config/factory"
  echo "$MARKER" > "$VM/etc/factory-build-provisioned"
  # The fake check-app: logs the env file it was given and what it holds, exits $STUB_CHECK_RC.
  cat > "$VM/node" <<'NODE'
#!/usr/bin/env bash
echo "node $*" >> "$VM/node.log"
case $1 in --env-file=*) cat "${1#--env-file=}" >> "$VM/node.log" ;; esac
echo "check-app: ok"
exit "${STUB_CHECK_RC:-0}"
NODE
  chmod +x "$VM/node"
  KEY=$WORK/download$n.pem
  printf '%s\n' "$KEYTEXT" > "$KEY"
}
run() { OUT=$("$SCRIPT" "$@" 2>&1); RC=$?; }
expect_fail() {  # <name> <text>: exit 1, the text in the output, the downloaded key kept
  if [ "$RC" -ne 1 ]; then fail "$1: exit $RC, wanted 1 ($OUT)"
  elif ! grep -qF -- "$2" <<<"$OUT"; then fail "$1: output lacks '$2' ($OUT)"
  elif [ ! -f "$KEY" ]; then fail "$1: the downloaded key was deleted on a failure"
  else ok "$1"; fi
}
mode() { stat -c %a "$1"; }
conf() { echo "$VM/home/dispatcher/.config/factory"; }

echo "install-builder-app: a good run"
new_case
run 5844656 183942865 "$KEY"
if [ "$RC" -ne 0 ]; then fail "good run: exit $RC ($OUT)"
else
  if [ "$(cat "$(conf)/builder-app.pem")" = "$KEYTEXT" ]; then ok "the VM's key is the downloaded one"
  else fail "the VM's key differs"; fi
  want_env=$(printf '%s\n' BUILDER_APP_ID=5844656 BUILDER_APP_INSTALLATION_ID=183942865 \
    "FACTORY_STATE_DIR=$P_STATE" "FACTORY_REPO_DIR=$P_REPO" "FACTORY_HELPER_IMAGE=$P_HELPER" \
    "FACTORY_MAX_BLOCKED=$(jq -r .env.FACTORY_MAX_BLOCKED "$LIMITS")" \
    "FACTORY_AUDIT_EVERY=$(jq -r .env.FACTORY_AUDIT_EVERY "$LIMITS")" \
    "FACTORY_MAX_MERGES_PER_DAY=$(jq -r .env.FACTORY_MAX_MERGES_PER_DAY "$LIMITS")")
  if [ "$(cat "$(conf)/env")" = "$want_env" ]; then
    ok "the env file holds the two ids and the dispatcher's six settings, from their sources, and nothing else"
  else fail "env file: $(cat "$(conf)/env")"; fi
  if [ "$(mode "$(conf)/builder-app.pem")" = 600 ] && [ "$(mode "$(conf)/env")" = 600 ]; then ok "key and env file are mode 600"
  else fail "modes: key $(mode "$(conf)/builder-app.pem"), env $(mode "$(conf)/env")"; fi
  if ls "$(conf)"/*.new >/dev/null 2>&1; then fail "a .new file is left"; else ok "no .new file is left"; fi
  if grep -qxF "node --env-file=$(conf)/env $VM/opt/factory-checkout/dispatcher/bin/check-app.mjs --adapter-from-repo" "$VM/node.log" \
    && grep -qx 'BUILDER_APP_ID=5844656' "$VM/node.log"; then ok "check-app ran with that env file and --adapter-from-repo, no --repository of its own (the whole call)"
  else fail "check-app call: $(cat "$VM/node.log" 2>/dev/null)"; fi
  if [ ! -e "$KEY" ]; then ok "the downloaded key is deleted"; else fail "the downloaded key is still there"; fi
  if grep -qF 'MIIEsecretLINE' "$VM/calls"; then fail "the key's text is in a limactl argument"
  else ok "the key never travels in an argument"; fi
  if grep -qiE '[0-9a-f]{64}' <<<"$OUT"; then fail "a digest is printed ($OUT)"; else ok "no digest is printed"; fi
fi

echo "install-builder-app: what it refuses"
new_case; run 5844656 "$KEY"; expect_fail "two arguments" "usage:"
new_case; run 0 183942865 "$KEY"; expect_fail "an app id of 0" "app id must be a positive integer"
new_case; run 5844656 18394x "$KEY"; expect_fail "an installation id with a letter" "installation id must be a positive integer"
new_case; ln -s "$KEY" "$WORK/link$n.pem"; run 5844656 183942865 "$WORK/link$n.pem"
expect_fail "a link to a key" "is not a regular file"
if [ -e "$(conf)/builder-app.pem" ]; then fail "a link's key was written"; else ok "nothing written for a link"; fi
new_case; printf 'not a key\n' > "$KEY"; run 5844656 183942865 "$KEY"; expect_fail "a file that is no key" "does not start as a GitHub App private key"
if [ "$(id -u)" -ne 0 ]; then
  new_case; chmod 000 "$KEY"; run 5844656 183942865 "$KEY"; chmod 600 "$KEY"; expect_fail "a key this process cannot read" "cannot read"
else ok "a key this process cannot read: skipped as root (root reads a mode-000 file)"; fi
new_case; STUB_INSTANCES="" run 5844656 183942865 "$KEY"; expect_fail "no VM" "no instance factory-build"
new_case; STUB_STATUS=Stopped run 5844656 183942865 "$KEY"; expect_fail "a stopped VM" "is Stopped, not Running"
new_case; echo "factory-build provisioned: docker; boot 1" > "$VM/etc/factory-build-provisioned"
run 5844656 183942865 "$KEY"; expect_fail "a VM provisioned without dispatcher" "was not provisioned with dispatcher"
zeros=0000000000000000000000000000000000000000
for pair in "factory $P_COMMIT|factory $zeros" "helper $P_HELPER;|helper other:tag@sha256:$zeros$zeros${zeros:0:24};" \
            "repo $P_REPO;|repo /home/dispatcher/other;" "state $P_STATE;|state /home/dispatcher/other;"; do
  from=${pair%%|*} to=${pair#*|}
  new_case; m=$(cat "$VM/etc/factory-build-provisioned"); printf '%s\n' "${m/"$from"/"$to"}" > "$VM/etc/factory-build-provisioned"
  run 5844656 183942865 "$KEY"; expect_fail "a VM from another provision.sh (${from%% *})" "provisioned from another provision.sh"
  if [ -e "$(conf)/builder-app.pem" ]; then fail "a VM from another provision.sh (${from%% *}): the key was written"; fi
done
new_case; echo "factory-build provisioned: docker; node v24; dispatcher at factory 3888a900; boot 1" > "$VM/etc/factory-build-provisioned"
run 5844656 183942865 "$KEY"; expect_fail "a VM from before /opt/factory-checkout" "provisioned before /opt/factory-checkout"
if [ -e "$(conf)/builder-app.pem" ] || [ -e "$(conf)/env" ]; then fail "a VM from before /opt/factory-checkout: something was written"
else ok "a VM from before /opt/factory-checkout: nothing written"; fi
if [ -e "$(conf)/builder-app.pem" ]; then fail "a key was written to a VM without dispatcher"; else ok "nothing written to it"; fi
new_case; chmod 755 "$(conf)"; run 5844656 183942865 "$KEY"; expect_fail ".config/factory mode 755" "is not mode 700 and dispatcher's: nothing written"
if [ -e "$(conf)/builder-app.pem" ] || [ -e "$(conf)/builder-app.pem.new" ]; then fail "a key was written into a directory of mode 755"
else ok "nothing written before the directories were checked"; fi
new_case; STUB_OWNER=factory run 5844656 183942865 "$KEY"; expect_fail "directories owned by another user" "is not mode 700 and dispatcher's: nothing written"
new_case; printf 'x' > "$(conf)/env"; chmod 644 "$(conf)/env"
run 5844656 183942865 "$KEY"
if [ "$RC" -eq 0 ]; then ok "an env file of mode 644 is replaced by one of 600"; else fail "env file 644: exit $RC ($OUT)"; fi
new_case; STUB_CORRUPT=1 run 5844656 183942865 "$KEY"; expect_fail "a copy whose digest differs" "the key on factory-build differs from"
new_case; STUB_CHECK_RC=1 run 5844656 183942865 "$KEY"; expect_fail "check-app failing" "check-app failed: the key stays in"

echo "install-builder-app: a .new a failed run left, or one planted"
new_case; printf 'outside\n' > "$WORK/outside$n"; ln -s "$WORK/outside$n" "$(conf)/builder-app.pem.new"
run 5844656 183942865 "$KEY"
if [ "$RC" -eq 0 ] && [ "$(cat "$WORK/outside$n")" = outside ] && [ "$(cat "$(conf)/builder-app.pem")" = "$KEYTEXT" ]; then
  ok "a .new link is removed, never written through"
else fail "a .new link: exit $RC, outside holds $(cat "$WORK/outside$n") ($OUT)"; fi

echo "install-builder-app: a rotation"
new_case
printf 'old key\n' > "$(conf)/builder-app.pem"; chmod 600 "$(conf)/builder-app.pem"
run 5844656 183942865 "$KEY"
if [ "$RC" -eq 0 ] && [ "$(cat "$(conf)/builder-app.pem")" = "$KEYTEXT" ]; then ok "a second key replaces the first"
else fail "rotation: exit $RC, key $(head -c 20 "$(conf)/builder-app.pem") ($OUT)"; fi

if [ "$failures" -gt 0 ]; then echo "$failures failure(s)"; exit 1; fi
echo "All cases passed."
