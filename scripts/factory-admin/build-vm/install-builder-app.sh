#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/), on the Mac. Puts builder-app's key and ids on the build VM for the user
# `dispatcher`, checks them where they land, runs factory's `check-app` there, and only then deletes the downloaded key
# (backlog #0-272, ADR-0060 D3, the owner's choice E2: the key has one copy, the VM's).
#
#   install-builder-app.sh <app id> <installation id> <downloaded key .pem>
#
# The key goes on stdin straight into its file, as `dispatcher`, under umask 077: never through /tmp (`limactl copy`
# lands there with the default umask, readable by `factory` for a moment) and never in an argument (argv is readable
# by every user of the VM). It is written next to its place and renamed over it, so a key being replaced (a rotation)
# is never half written. The script never prints the key or its digest; it compares the digests of the two copies.
#
# What it checks, failing closed (a command that cannot answer is no pass):
#   - the VM runs and was provisioned with `dispatcher` at a factory commit (provision.sh's last line);
#   - after writing: the VM's copy has the digest of the downloaded file; /home/dispatcher and .config/factory are mode
#     700, the env file and the key mode 600, all of them `dispatcher`'s (AC8: the env file is trusted as code, since
#     Node loads it before any check of factory's, builder-env.mjs);
#   - `check-app`, run as `dispatcher` with that env file: the key is a file only `dispatcher` reads, the installation
#     on incident-platform is the app's and holds exactly its permissions, a token narrowed to incident-platform
#     reaches only it, and the app has no installation on factory (AC5).
# Only when all of it passed is the downloaded file deleted; on a failure it stays, so the run can be repeated.
#
# The env file it writes is the dispatcher's whole configuration (backlog #0-277: one author, so a rotation loses
# nothing), each value from one source, never typed here: BUILDER_APP_ID and BUILDER_APP_INSTALLATION_ID from the
# arguments; FACTORY_STATE_DIR, FACTORY_REPO_DIR and FACTORY_HELPER_IMAGE from provision.sh (DISPATCHER_STATE,
# DISPATCHER_REPO, HELPER_IMAGE); the three limits from .claude/settings.autopilot.json, today's autopilot's, one
# source for both paths until stage 4.7's switch. It refuses a VM whose provisioning marker names another
# FACTORY_COMMIT, helper image, clone or state directory than this checkout's provision.sh, so what it writes is what
# that VM holds. The limits are a snapshot of that file at the run: after a change of them, run it again (with the
# current key's file, or at the next rotation) for the dispatcher to follow.
# The env file holds no secret (stage-4.md: it reaches process.env whole).
#
# Rotation: generate a second key in the app's settings, run this script with it (the VM's key is replaced), then
# delete the old key on GitHub. A new VM (delete.sh, create.sh) gets a new key the same way, and the old VM's key is
# deleted on GitHub.
# ============================================================
set -euo pipefail

NAME=factory-build
DISPATCHER=dispatcher
DISPATCHER_HOME=/home/dispatcher
CONF=$DISPATCHER_HOME/.config/factory
# factory's paths (dispatcher/src/config/builder-env.mjs: DISPATCHER_ENV_FILE and DEFAULT_KEY_PATH): the env file is
# loaded by `node --env-file`, the key is read where BUILDER_APP_KEY would point when it is not set.
ENV_FILE=$CONF/env
KEY_FILE=$CONF/builder-app.pem
# The one factory checkout on the VM, root's (ADR-0062 point 3, backlog #0-277), which the dispatcher runs from.
CHECK_APP=/opt/factory-checkout/dispatcher/bin/check-app.mjs
NODE=/usr/local/bin/node
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../../.." && pwd)

fail() { echo "install-builder-app.sh: $*" >&2; exit 1; }
[ "$#" -eq 3 ] || fail "usage: install-builder-app.sh <app id> <installation id> <downloaded key .pem>"
app_id=$1 installation_id=$2 key=$3
positive() { [[ "$1" =~ ^[1-9][0-9]{0,18}$ ]]; }
positive "$app_id" || fail "the app id must be a positive integer"
positive "$installation_id" || fail "the installation id must be a positive integer"
# A regular file, not a link (a link could point at another file of the owner's, which would then be sent and deleted).
[ -f "$key" ] && [ ! -L "$key" ] || fail "$key is not a regular file"
# Its first line read once (head -n 1, as macOS's head and GNU's both take it): a file this process may not read is
# named so, not "not a key" (macOS refuses an app ~/Downloads unless the owner allowed it: a run through Claude Code's
# `!` was refused so, 2026-11-20). GitHub gives an app's key as a PKCS#1 RSA key in PEM; that line holds nothing secret.
first=$(head -n 1 "$key" 2>/dev/null) || fail "cannot read $key (on macOS, run this from a terminal that may read that folder)"
[ "$first" = "-----BEGIN RSA PRIVATE KEY-----" ] || fail "$key does not start as a GitHub App private key"
command -v limactl >/dev/null || fail "limactl not found (brew install lima)"
command -v jq >/dev/null || fail "jq not found (brew install jq)"

# The dispatcher's settings, each read from its one source and checked for its shape (an empty or reshaped line in the
# source is a refusal, never a value).
pv() { sed -n "s|^$1=\\($2\\)\\( .*\\)\\{0,1\\}\$|\\1|p" "$here/provision.sh"; }
factory_commit=$(pv FACTORY_COMMIT '[0-9a-f]\{40\}')
helper_image=$(pv HELPER_IMAGE '[a-z0-9._-]*:[a-z0-9._-]*@sha256:[0-9a-f]\{64\}')
state_dir=$(pv DISPATCHER_STATE '/[A-Za-z0-9/_.-]*')
repo_dir=$(pv DISPATCHER_REPO '/[A-Za-z0-9/_.-]*')
for v in factory_commit helper_image state_dir repo_dir; do
  [ -n "${!v}" ] && [ "$(wc -l <<<"${!v}")" -eq 1 ] || fail "cannot read $v from provision.sh"
done
limits=$root/.claude/settings.autopilot.json
limit() {
  local v; v=$(jq -er --arg k "$1" '.env[$k] | strings' "$limits") || return 1
  positive "$v" && printf '%s' "$v"
}
max_blocked=$(limit FACTORY_MAX_BLOCKED) || fail "cannot read FACTORY_MAX_BLOCKED from $limits"
audit_every=$(limit FACTORY_AUDIT_EVERY) || fail "cannot read FACTORY_AUDIT_EVERY from $limits"
max_merges=$(limit FACTORY_MAX_MERGES_PER_DAY) || fail "cannot read FACTORY_MAX_MERGES_PER_DAY from $limits"

vm() { limactl shell --workdir / "$NAME" "$@"; }
# As `dispatcher`, without its login shell (it has none) and without the Mac's environment: sudo resets it.
as_dispatcher() { vm sudo -n -u "$DISPATCHER" -H -- "$@"; }

# Into a variable first: a pipe under pipefail could fail on SIGPIPE and read as "no such instance" (create.sh).
instances=$(limactl list --quiet) || fail "cannot list the Lima instances"
grep -qx "$NAME" <<<"$instances" || fail "no instance $NAME: run create.sh first"
status=$(limactl list "$NAME" --format '{{.Status}}') || fail "cannot read the status of $NAME"
[ "$status" = Running ] || fail "$NAME is $status, not Running: limactl start $NAME"
provisioned=$(vm cat /etc/factory-build-provisioned) || fail "cannot read /etc/factory-build-provisioned on $NAME"
[[ "$provisioned" == *"$DISPATCHER at factory "* ]] \
  || fail "$NAME was not provisioned with $DISPATCHER: recreate it (delete.sh, create.sh) with a provision.sh that adds it"
# A VM from a provision.sh before #0-277 has factory in dispatcher's home, not in /opt/factory-checkout: refused here,
# before the key is written, so a rotation on it never leaves a new key that check-app could not check (review round 1
# of #0-277's VM part). provision.sh's marker names the checkout from #0-277 on.
[[ "$provisioned" == *" in /opt/factory-checkout;"* ]] \
  || fail "$NAME was provisioned before /opt/factory-checkout (backlog #0-277): recreate it (delete.sh, create.sh) first"
# The VM holds what this checkout's provision.sh pins, or the settings written below would name another commit's
# paths or a helper image its daemon never pulled (the dispatcher runs it with --pull=never).
[[ "$provisioned" == *" at factory $factory_commit in /opt/factory-checkout; helper $helper_image; repo $repo_dir; state $state_dir;"* ]] \
  || fail "$NAME was provisioned from another provision.sh (FACTORY_COMMIT, HELPER_IMAGE, the clone or the state directory differ): recreate it (delete.sh, create.sh) from this checkout"

# modes <path...>: each path as stat names it (mode, owner, group, type), asked as root, so a path dispatcher cannot
# see is no gap.
modes() { vm sudo -n stat -c '%a %U %G %F %n' "$@"; }

# The two directories first, before the key goes anywhere (review round 1 of #0-272's second pull request): a
# .config/factory another user could write would let it plant the file the key is written to.
dirs=$(modes "$DISPATCHER_HOME" "$CONF") || fail "cannot read the modes on $NAME"
expected_dirs="700 $DISPATCHER $DISPATCHER directory $DISPATCHER_HOME
700 $DISPATCHER $DISPATCHER directory $CONF"
[ "$dirs" = "$expected_dirs" ] || fail "$DISPATCHER_HOME or $CONF on $NAME is not mode 700 and $DISPATCHER's: nothing written
$dirs"

# write <path>: stdin into <path>, as dispatcher, mode 600 from the start, renamed over the old file. A <path>.new a
# failed run left is removed first (rm removes a link, never what it points at), so cat creates a file of its own.
# shellcheck disable=SC2016 # $1 is expanded by the VM's sh, which gets the path as its argument, not in the script
write() { as_dispatcher sh -c 'umask 077 && rm -f -- "$1.new" && cat > "$1.new" && mv -f "$1.new" "$1"' sh "$1"; }

write "$KEY_FILE" < "$key" || fail "could not write the key on $NAME"
local_digest=$(shasum -a 256 < "$key" | cut -d ' ' -f 1) || fail "cannot hash $key"
vm_digest=$(as_dispatcher sha256sum "$KEY_FILE" | cut -d ' ' -f 1) || fail "cannot hash the key on $NAME"
[ -n "$vm_digest" ] && [ "$vm_digest" = "$local_digest" ] || fail "the key on $NAME differs from $key"
echo "key written to $KEY_FILE on $NAME (digests equal)"

printf '%s\n' "BUILDER_APP_ID=$app_id" "BUILDER_APP_INSTALLATION_ID=$installation_id" \
  "FACTORY_STATE_DIR=$state_dir" "FACTORY_REPO_DIR=$repo_dir" "FACTORY_HELPER_IMAGE=$helper_image" \
  "FACTORY_MAX_BLOCKED=$max_blocked" "FACTORY_AUDIT_EVERY=$audit_every" "FACTORY_MAX_MERGES_PER_DAY=$max_merges" \
  | write "$ENV_FILE" || fail "could not write the env file on $NAME"
echo "ids and the dispatcher's settings written to $ENV_FILE on $NAME"

modes=$(modes "$DISPATCHER_HOME" "$CONF" "$ENV_FILE" "$KEY_FILE") || fail "cannot read the modes on $NAME"
expected="700 $DISPATCHER $DISPATCHER directory $DISPATCHER_HOME
700 $DISPATCHER $DISPATCHER directory $CONF
600 $DISPATCHER $DISPATCHER regular file $ENV_FILE
600 $DISPATCHER $DISPATCHER regular file $KEY_FILE"
[ "$modes" = "$expected" ] || fail "modes or owners on $NAME are not as required:
$modes
expected:
$expected"
echo "modes and owners: ok (home and .config/factory 700, env and key 600, all $DISPATCHER's)"

echo "check-app as $DISPATCHER on $NAME:"
# --adapter-from-repo: check-app reads the repository a token is narrowed to from .factory/adapter.json at the base of
# the dispatcher's clone (FACTORY_REPO_DIR, in the env file), the one source the dispatcher reads too (backlog #0-278
# AC8, `factory` PR #20). Fixed: this script passed --repository, taken from provision.sh's PRODUCT_REPO_URL, a second
# source of the same value (review of #0-276, #0-277 AC8). The adapter must be on main before this runs.
as_dispatcher "$NODE" --env-file="$ENV_FILE" "$CHECK_APP" --adapter-from-repo || fail "check-app failed: the key stays in $key, and on $NAME"

rm -f -- "$key"
[ ! -e "$key" ] || fail "could not delete $key: delete it by hand"
echo "deleted $key: the VM's copy is the only one (on a rotation, delete the old key in the app's settings now)"
