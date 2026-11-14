#!/usr/bin/env bash
# ============================================================
# Owner-run (scripts/factory-admin/). Checks every pin of the build VM against its publisher (backlog #0-238,
# ADR-0056); run it whenever a pin changes, in the same PR, and whenever in doubt. The VM's creation does not need
# it: Lima checks the image's digest, provision.sh the sums of Node and the CLI. This answers the other question,
# whether the pinned value is the publisher's.
#
#   1. Ubuntu's cloud image (factory-build.yaml): its sha256 is the one SHA256SUMS of the same dated directory names
#      for the file, and SHA256SUMS carries a good signature by Canonical's cloud image key, D2EB 4462 6FDD C30B 513D
#      5BB7 1A5D 6C4C 7DB8 7C81, taken from the `ubuntu-cloudimage-keyring` package of the Ubuntu container below
#      (Ubuntu's archive, whose signature apt checks), never a keyserver. The fingerprint was confirmed in three
#      places on 2026-11-14 (keyserver.ubuntu.com, Ubuntu's "Verify an image checksum" page, that package),
#      ADR-0033's rule for a signing key.
#   2. Node (provision.sh): both sha256 lines are in nodejs.org's SHASUMS256.txt.asc of that version, which carries a
#      good signature by a key of Node's releasers, the keyring of github.com/nodejs/release-keys at the commit pinned
#      below (where Node's README sends a verifier). Bump that commit when a new releaser signs.
#   3. The devcontainer CLI (provision.sh): the sha512 is npm's `dist.integrity` of that version, and the package
#      still declares no dependencies, peer or optional ones included (provision.sh installs the tarball alone).
#   4. Docker's apt key (provision.sh, DOCKER_KEY_FPR; backlog #0-116, ADR-0057): the key download.docker.com serves
#      is one key, with the pinned fingerprint, which provision.sh also checks before trusting the file; a mismatch here is Docker
#      rotating its key, to confirm in three places again before the pin changes.
#   5. Docker CE's versions (provision.sh, DOCKER_VERSION and CONTAINERD_VERSION): each package is in the index of
#      Docker's noble repository at its pinned version, for arm64 and amd64, the index read by apt with the key of 4.
# Everything that reads a downloaded file runs in the container (the Mac has no gpg): the Mac passes it the pins only.
#
#   verify-pins.sh       prints one "verified: ..." line per pin and exits 0, or names what failed and exits 1
# ============================================================
set -euo pipefail

UBUNTU_KEY_FPR=D2EB44626FDDC30B513D5BB71A5D6C4C7DB87C81  # gitleaks:allow: a public key fingerprint (Canonical's cloud image key), no secret
# github.com/nodejs/release-keys, main as of 2026-11-14.
NODE_KEYS_COMMIT=481637f813e912c4aa3622d7964ab426c97b8e8d  # gitleaks:allow: a public commit id of github.com/nodejs/release-keys, no secret
# ubuntu:24.04, linux/arm64 and amd64 (the index digest), as pulled on 2026-11-14.
CONTAINER=ubuntu@sha256:68ee22004a9109b44973313b02ff7b1de250f1de0f5ecb628d73f579aaff33ac
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
yaml=$here/factory-build.yaml
prov=$here/provision.sh

fail() { echo "verify-pins.sh: $*" >&2; exit 1; }
command -v docker >/dev/null || fail "docker not found"
# One value per pattern, or the script refuses: a second image or a moved line must not pass unchecked.
one() {
  local value
  value=$(sed -n "$1" "$2")
  [ -n "$value" ] && [ "$(printf '%s\n' "$value" | grep -c .)" -eq 1 ] || fail "expected one match of $1 in $2"
  printf '%s' "$value"
}

location=$(one 's/^- location: *"\(.*\)"$/\1/p' "$yaml")
digest=$(one 's/^ *digest: *"sha256:\([0-9a-f]\{64\}\)"$/\1/p' "$yaml")
case "$location" in
  https://cloud-images.ubuntu.com/releases/*/release-[0-9]*/*.img) ;;
  *) fail "the location is not a dated directory of cloud-images.ubuntu.com: $location" ;;
esac
node_version=$(one 's/^NODE_VERSION=\([0-9.]*\)$/\1/p' "$prov")
node_arm64=$(one 's/^NODE_SHA256_ARM64=\([0-9a-f]\{64\}\)$/\1/p' "$prov")
node_x64=$(one 's/^NODE_SHA256_X64=\([0-9a-f]\{64\}\)$/\1/p' "$prov")
cli_version=$(one 's/^DEVCONTAINER_CLI_VERSION=\([0-9.]*\)$/\1/p' "$prov")
cli_sha512=$(one 's/^DEVCONTAINER_CLI_SHA512=\([0-9a-f]\{128\}\)$/\1/p' "$prov")
docker_fpr=$(one 's/^DOCKER_KEY_FPR=\([0-9A-F]\{40\}\).*$/\1/p' "$prov")
docker_version=$(one 's/^DOCKER_VERSION=\([0-9A-Za-z.:~+-]*\)$/\1/p' "$prov")
containerd_version=$(one 's/^CONTAINERD_VERSION=\([0-9A-Za-z.:~+-]*\)$/\1/p' "$prov")

docker run --rm \
  -e IMG_DIR="${location%/*}" -e IMG_FILE="${location##*/}" -e IMG_DIGEST="$digest" -e UBUNTU_KEY_FPR="$UBUNTU_KEY_FPR" \
  -e NODE_VERSION="$node_version" -e NODE_ARM64="$node_arm64" -e NODE_X64="$node_x64" -e NODE_KEYS_COMMIT="$NODE_KEYS_COMMIT" \
  -e CLI_VERSION="$cli_version" -e CLI_SHA512="$cli_sha512" -e DOCKER_FPR="$docker_fpr" \
  -e DOCKER_VERSION="$docker_version" -e CONTAINERD_VERSION="$containerd_version" \
  "$CONTAINER" bash -euo pipefail -c '
  bad() { echo "verify-pins.sh: $*" >&2; exit 1; }
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq --no-install-recommends ca-certificates curl gpg gpgv openssl jq ubuntu-cloudimage-keyring >/dev/null
  cd "$(mktemp -d)"

  # 1. The image. --status-fd gives the machine-readable result: VALIDSIG ends with the primary key that signed.
  curl -fsSL -o SHA256SUMS "$IMG_DIR/SHA256SUMS"
  curl -fsSL -o SHA256SUMS.gpg "$IMG_DIR/SHA256SUMS.gpg"
  status=$(gpgv --status-fd 1 --keyring /usr/share/keyrings/ubuntu-cloudimage-keyring.gpg SHA256SUMS.gpg SHA256SUMS 2>/dev/null) \
    || bad "bad or missing signature on $IMG_DIR/SHA256SUMS"
  printf "%s\n" "$status" | grep -q "^\[GNUPG:\] VALIDSIG .* $UBUNTU_KEY_FPR\$" || bad "SHA256SUMS is not signed by $UBUNTU_KEY_FPR"
  grep -Fqx "$IMG_DIGEST *$IMG_FILE" SHA256SUMS || bad "SHA256SUMS of $IMG_DIR does not give $IMG_DIGEST for $IMG_FILE"
  echo "verified: $IMG_FILE sha256 $IMG_DIGEST is in $IMG_DIR/SHA256SUMS, signed by $UBUNTU_KEY_FPR"

  # 2. Node.
  curl -fsSL -o node-keys.kbx "https://raw.githubusercontent.com/nodejs/release-keys/$NODE_KEYS_COMMIT/gpg-only-active-keys/pubring.kbx"
  curl -fsSL -o SHASUMS256.txt.asc "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc"
  status=$(gpgv --status-fd 1 --keyring ./node-keys.kbx --output SHASUMS256.txt SHASUMS256.txt.asc 2>/dev/null) \
    || bad "bad or missing signature on Node $NODE_VERSION SHASUMS256.txt.asc (keys at release-keys $NODE_KEYS_COMMIT)"
  signer=$(printf "%s\n" "$status" | sed -n "s/^\[GNUPG:\] VALIDSIG .* \([0-9A-F]\{40\}\)\$/\1/p")
  for pin in "$NODE_ARM64  node-v$NODE_VERSION-linux-arm64.tar.xz" "$NODE_X64  node-v$NODE_VERSION-linux-x64.tar.xz"; do
    grep -Fqx "$pin" SHASUMS256.txt || bad "Node SHASUMS256 of v$NODE_VERSION does not hold: $pin"
  done
  echo "verified: Node v$NODE_VERSION linux-arm64 and linux-x64 sha256 are in its SHASUMS256, signed by $signer"

  # 3. The devcontainer CLI.
  meta=$(curl -fsSL "https://registry.npmjs.org/@devcontainers%2fcli/$CLI_VERSION")
  integrity=$(jq -r .dist.integrity <<<"$meta")
  case "$integrity" in sha512-*) ;; *) bad "npm gives no sha512 integrity for @devcontainers/cli@$CLI_VERSION: $integrity" ;; esac
  npm_hex=$(printf "%s" "${integrity#sha512-}" | openssl base64 -d -A | od -An -v -tx1 | tr -d " \n")
  [ "$npm_hex" = "$CLI_SHA512" ] || bad "npm gives sha512 $npm_hex for @devcontainers/cli@$CLI_VERSION, provision.sh pins $CLI_SHA512"
  # npm 7+ installs peer and optional dependencies too: any of the three would be fetched unpinned, as root.
  deps=$(jq -c "{dependencies, peerDependencies, optionalDependencies} | map_values(. // {}) | add" <<<"$meta")
  [ "$deps" = "{}" ] \
    || bad "@devcontainers/cli@$CLI_VERSION declares dependencies ($deps): provision.sh installs the tarball alone"
  echo "verified: @devcontainers/cli@$CLI_VERSION sha512 is npm'"'"'s dist.integrity, no dependencies"

  # 4. Docker'"'"'s apt key.
  curl -fsSL -o docker.asc https://download.docker.com/linux/ubuntu/gpg
  served=$(gpg --show-keys --with-colons docker.asc 2>/dev/null | awk -F: "/^fpr/ {print \$10; exit}")
  keys=$(gpg --show-keys --with-colons docker.asc 2>/dev/null | grep -c "^pub:" || true)
  [ "$keys" = 1 ] || bad "download.docker.com serves $keys keys in one file: provision.sh trusts the whole file, so it refuses it"
  [ "$served" = "$DOCKER_FPR" ] || bad "download.docker.com serves key $served, provision.sh pins $DOCKER_FPR"
  echo "verified: Docker'"'"'s apt key at download.docker.com is $DOCKER_FPR"

  # 5. Docker CE'"'"'s versions, through apt and the key just checked.
  dpkg --add-architecture amd64; dpkg --add-architecture arm64
  install -m 0644 docker.asc /etc/apt/keyrings/docker.asc 2>/dev/null || { mkdir -p /etc/apt/keyrings; install -m 0644 docker.asc /etc/apt/keyrings/docker.asc; }
  echo "deb [arch=arm64,amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -qq -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/docker.list -o Dir::Etc::sourceparts=- >/dev/null \
    || bad "apt cannot read Docker'"'"'s repository with its key"
  for arch in arm64 amd64; do
    for p in docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io; do
      want=$DOCKER_VERSION; [ "$p" = containerd.io ] && want=$CONTAINERD_VERSION
      apt-cache madison "$p:$arch" | awk -F"|" "{gsub(/ /, \"\", \$2); print \$2}" | grep -Fqx "$want" \
        || bad "Docker'"'"'s noble repository has no $p $want for $arch"
    done
  done
  echo "verified: Docker CE $DOCKER_VERSION and containerd.io $CONTAINERD_VERSION are in Docker'"'"'s noble repository for arm64 and amd64"
'
