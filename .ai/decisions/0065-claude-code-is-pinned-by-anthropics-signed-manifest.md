# ADR-0065: Claude Code in the devcontainer image is the pinned version from Anthropic's signed manifest, root's, and the firewall's sudo rule takes no arguments

- **Status:** Accepted (2026-11-21, by the owner); amends ADR-0039 point 3 (the preflight's floor becomes the pin),
  takes the binary's part of ADR-0064 point 5's direction without a mount
- **Backlog:** #0-249, #0-283
- **Date:** 2026-11-21
- **Author:** human (the owner's choice on `/research 0-249 0-283`, 2026-11-21: option A, the sudo rule S2, an exact
  version; drafted in an interactive session)
- **Reversible:** yes — one file of pins, one install script, the sudoers line and one preflight check

## Context

`.devcontainer/Dockerfile` built the owner's container and, since #0-282, every task container with
`curl -fsSL https://claude.ai/install.sh | bash` as `dev`. That is the `latest` channel on the day of the build
(on 2026-11-21: `latest` 2.1.330, `stable` 2.1.323, the build VM 2.1.328), checked only against a manifest from the
same server, and laid out by `claude install` under `dev`'s `~/.local`, where a call's code can replace the next
call's binary (ADR-0064's residual). `DISABLE_AUTOUPDATER` stops only the background check: `claude update` and
`claude install` still worked. ADR-0064 points 3 and 4 need a pinned version (the init event's `claude_code_version`,
the agents' `tools` and the hooks are recorded per version), and spike #0-300 measures on 2.1.328.

The sudoers line `dev ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh` allowed any arguments, and the script
added each to its allow-list (FAC-S02). The one caller that passed one was the owner's `postStartCommand`, the ntfy
host derived from `FACTORY_NTFY_SERVER` at each start.

Anthropic signs each release's `manifest.json` (detached `manifest.json.sig`, since 2.1.89) with the key
`31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE`, and the manifest lists every platform binary's SHA-256 (Claude
Code's setup documentation, "Binary integrity and code signing").

## Decision

1. **One pin file**, `.devcontainer/claude-code.pin`: `CLAUDE_CODE_VERSION`, `CLAUDE_CODE_KEY` (the fingerprint) and
   the SHA-256 of the linux-x64 and linux-arm64 binaries. Read, never sourced. 2.1.328 today.
2. **`.devcontainer/install-claude-code.sh`** is the one place that fetches Claude Code: the key file
   `.devcontainer/keys/<fingerprint>.asc` must hold exactly that primary key; the manifest's signature must be good and
   by it (VALIDSIG), from a key neither revoked nor expired; the manifest's `version` and both checksums must be the
   pin's; then (`--into`) this machine's binary, its SHA-256 compared with the pin before it runs, is installed as
   root's `/usr/local/bin/claude`, 0755. `--check` does all but the download, in Lint Workflows (`ci.yml`) on every pull request, beside the CI tools' pins.
3. **The image** runs it as root, sets `DISABLE_AUTOUPDATER=1` and `DISABLE_UPDATES=1`, and no longer puts
   `~/.local/bin` first on `PATH`.
4. **The preflight** (old path) refuses a running version other than the pin's, and a pin below 2.1.295 (ADR-0039's
   reason, kept as the pin's floor).
5. **Sudo:** `dev ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh ""` (no arguments). The script refuses any
   argument after its fail-closed trap, and reads its one extra host from `/etc/factory-firewall/extra-hosts`, root's,
   which the image writes from the build argument `FACTORY_NTFY_SERVER` (the owner's `devcontainer.json` passes the
   host's variable; `task.json` passes none, so a task container has no file). `dev` leaves the base image's `sudo`
   and `admin` groups.
6. **A new key** is a new key file after its fingerprint matches in three places (as ADR-0033 does for Snyk's: here
   the key's URL, the documentation, keys.openpgp.org) and a `CLAUDE_CODE_KEY` change. The key is not watched yet:
   `watch-signing-keys.sh` reads `.github/keys/` only, and its sources are GitHub paths, this one a URL (#0-312). A
   revocation reaches the check only once the key file is refreshed; the installed binary stays held by the pin's hash.

## Alternatives considered

- **`install.sh | bash -s <version>`:** a version, but the installer itself fetched unpinned at build time and run,
  its checksum from the same server (trust on first use, as #0-142 found for the Maven wrapper), and the binary
  still under `~/.local`.
- **The binary from a read-only mount the factory provides (ADR-0064 point 5):** the version would be the factory's
  alone, but it amends ADR-0062 point 4 again, ties a factory binary to the product image's userland, and the old
  path (the owner's container) has no such mount, so the image needs a pin anyway. Left open, not rejected.
- **Two sudoers lines, `""` and the ntfy host baked in:** a server changed on the host without a rebuild makes sudo
  refuse; the script never starts, its trap is never set, and the container runs with the default ACCEPT policies.
  The host in a root-owned file makes that mismatch impossible: a stale host fails notifications, not the firewall.
- **The script ignoring arguments when a task label is set:** a decision made on what a process in the container
  can see; sudoers decides before the script runs.
- **A floor (2.1.295) instead of an exact version:** ADR-0064 needs the exact one on the dispatcher's path; a floor
  here would be a third, looser rule.
- **Renovate proposing bumps:** the binaries are no GitHub release assets, so `renovate.json`'s custom manager cannot
  compute their hashes; a bump comes with re-measurements anyway.

## Consequences

- Two images built from one commit run one version, the pin's. A bump is one pull request changing the pin's lines,
  then the seed-bugs benchmark and ADR-0064's re-measurements (docs/ai-factory.md "Pinned versions").
- The dispatcher's expected version (ADR-0064 point 3) has a second holder besides this file. *Decided for #0-301
  (2026-11-22):* it is the factory's own value, beside its expected `tools` and managed file, and Lint Workflows
  compares it with this file (#0-301's AC6); the init event check still fails closed on a difference. *Built with
  #0-301's AC6 (2026-11-22):* not through `check-factory-copies.rb` against `factory@main`, as first decided, but in
  `factory` at the adapter's pinned `factoryVersion`, by `check-claude-code-expectations.sh`, a difference always
  failing (ADR-0061 as amended): the version the build VM's `factory` expects, not the one its `main` does.
- `profitbuild/factory`'s own `.devcontainer/Dockerfile` installs Claude Code and grants sudo the old way:
  #0-311.
- Left open: the key's weekly watch (#0-312); root in the container (the Docker socket, #0-116, #0-285) can still replace the binary and the firewall,
  for that container's life; `dev` owns its home, so a login shell's `~/.profile` (which adds `~/.local/bin`) or a line
  code adds to `~/.bashrc` can put another `claude` first on `PATH`. The preflight reads the running binary's version
  (`CLAUDE_CODE_EXECPATH`), not who started it: a wrapper that execs the real binary would pass, and a check of the path
  would not stop it either, as the binary sets that variable itself. The boundary is the dispatcher's call of
  `/usr/local/bin/claude` by absolute path (ADR-0064 point 5, #0-301); the owner's container is the old path, gone at
  M4 (review round 2 of #0-249).
- A violation looks like: a `curl … | bash` or `claude install` in the Dockerfile; a pin line changed without the
  others; a hash not from the signed manifest (Lint Workflows fails); an argument in a `postStartCommand`; a sudoers
  line without `""`.
