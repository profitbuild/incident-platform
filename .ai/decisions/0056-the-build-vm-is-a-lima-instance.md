# ADR-0056: The build VM is a Lima instance, created by a script, its contents from one provision file

- **Status:** Accepted (2026-11-14, by the owner, after PR #628 merged); amended by ADR-0057 (the VM's Docker is
  rootless, behind a VM egress filter)
- **Amends:** ADR-0055 ("Local first, portable from the first VM": Lima reads no raw cloud-init user-data; the
  portable part is one provision script, "S2, reworded" below)
- **Backlog:** #0-238 (stage 2 of ADR-0055)
- **Date:** 2026-11-14
- **Author:** human (the owner's spike of 2026-11-13, drafted in an interactive session)
- **Reversible:** yes. The VM is the factory's place to run, not a format anything else reads; going back is the
  devcontainer on the Mac, as before stage 2, and another VM tool needs only another `create.sh`, since the provision
  file knows no tool

## Context

Stage 2 of ADR-0055 moves today's devcontainer from the owner's Mac into a VM provisioned as code, so that the Docker
the test gate's Testcontainers reach is the VM's (#0-116), and the repository the factory works on is a clone of its
own (#0-202). #0-238 fixed three criteria before the spike, and the tool to try first: UTM 4.7.4, which the owner
already used (M1 Pro, 32 GB), with Lima as the fallback.

- **S1.** One script in the repository creates the VM, and recreates it from nothing, with no step in a GUI.
- **S2.** Its contents come from one cloud-init `user-data` file that a cloud VM could read unchanged.
- **S3.** In it, today's devcontainer starts, its firewall comes up, and a test gate with Testcontainers passes.

The owner's rule for the spike: at most three VM starts per tool.

## Decision

**The tool is Lima** (2.3.0, Homebrew), `vmType: vz` (Apple's Virtualization.framework). The build VM is the Lima
instance `factory-build`, under `scripts/factory-admin/build-vm/` (owner-run, like the rest of `factory-admin/`; it
moves to the `factory` repository in stage 4):

- `factory-build.yaml`: Ubuntu 24.04's cloud image for arm64, pinned by Ubuntu's dated directory and its sha256 (Lima
  refuses another digest); 6 CPUs, 12 GiB, 60 GiB; **no `base:` template and `mounts: []`**; no port of the VM
  forwarded to the Mac; Lima's containerd off. 12 GiB is below `devcontainer.json`'s `hostRequirements` (16 GB) on
  purpose, to leave the Mac (32 GB) room: S3 proved it with Postgres only, so AC5's items, with Kafka and several
  modules, are where it holds or is raised.
- `provision.sh`: the VM's whole contents. Docker Engine and git from Ubuntu's archive (amended by ADR-0057: Docker CE rootless, from
  Docker's apt repository); Node from nodejs.org at
  `.node-version`'s version (the one CI runs, ADR-0043; Ubuntu's noble ships 18 and the devcontainer CLI needs 20 or
  later), checked against a pinned sha256; the devcontainer CLI from npm's tarball, checked against a pinned sha512
  and installed from the file with `--ignore-scripts` (it has no dependencies, so npm fetches nothing, and runs no
  script of it as root); user `factory` in the docker group (amended by ADR-0057: Docker CE rootless for `factory`, in no docker group, and an
  egress filter for everything it sends).
  Every step is guarded by what it installs (each apt package by `dpkg -s`), so Lima's every-boot run changes
  nothing. Lima runs it as a `mode: system` provision; a cloud VM takes the same file as its user-data (a user-data
  starting with `#!` is run as a script). Nothing in it names Lima or a cloud, and it reads no file of the repository.
- `create.sh` refuses an existing instance and a Node pin that differs from `.node-version`, creates and starts the
  VM, and then **checks the isolation the template only states**: Lima merges `~/.lima/_config/default.yaml` and
  `override.yaml` into every instance, so it deletes the VM and fails if Lima reports a mount, SSH agent forwarding or
  a port forward that is not ignored, an extra network, X11 forwarding or proxy propagation (`propagateProxyEnv`, on by
  default in Lima, is off in the template), a copy to the Mac (`copyToHost`), an extra disk, provision or probe, if the guest shows a host file system or an agent socket, or if a check cannot
  answer; any failure from `limactl create` until the clone is done deletes the VM. Then it checks that the provision ran and clones the
  repository from `origin` as `factory`; `delete.sh` deletes the VM. The logins (the bot's `gh`, Claude Code) are the
  owner's manual steps, in `docs/ai-factory.md` "Build VM".
- `verify-pins.sh` checks every pin against its publisher, in a digest-pinned Ubuntu container (the Mac has no gpg):
  the image's digest is in `SHA256SUMS` of the pinned directory, with a good signature by Canonical's cloud image key
  `D2EB 4462 6FDD C30B 513D 5BB7 1A5D 6C4C 7DB8 7C81`, taken from the `ubuntu-cloudimage-keyring` package (the
  fingerprint confirmed on keyserver.ubuntu.com, Ubuntu's "Verify an image checksum" page and that package, ADR-0033's
  three places); Node's two sha256 are in its `SHASUMS256.txt.asc`, signed by a key of `nodejs/release-keys` at a
  pinned commit; the CLI's sha512 is npm's `dist.integrity` and it still declares no dependency (peer and optional
  ones included). Run with every
  change of a pin.

**S2, reworded.** Lima takes no raw cloud-init user-data: it writes its own NoCloud seed, and accepts provision
scripts. So S2 now reads "the VM's contents come from one script that a cloud VM takes unchanged as its user-data",
which is what portability to stage C needed; the YAML around it is Lima's, as a cloud VM's launch call will be the
provider's.

### What the spike showed (2026-11-13)

| | UTM 4.7.4 | Lima 2.3.0 |
|---|---|---|
| S1 | **failed.** AppleScript `make new virtual machine` creates a QEMU VM (aarch64, hvf, UEFI, the cloud image as a VirtIO qcow2 `source`), and `utmctl start --hide <UUID>` starts it with no window. But the cloud-init seed, attached as a removable USB drive, did not reach the guest (no USB storage in it; cloud-init never ran, the hostname stayed `ubuntu`); a VirtIO removable drive was refused by QEMU; in shared network mode the guest got no DHCP lease. A second VM of the same name left a registry entry `utmctl` cannot delete (removed in the GUI). 3 starts used | **passed.** `limactl create` + `start` 35 s; delete and recreate from nothing 48 s, the same result |
| S2 | not reached (no seed in the guest) | **passed, reworded** (above): the same `provision.sh` as a system provision |
| S3 | not reached | **passed.** `devcontainer up` 95 s, the firewall up (`example.com` blocked), user `dev`; `./mvnw -B verify -pl oncall-service -am`: BUILD SUCCESS, 152 tests in 101 s, Testcontainers' Postgres on the VM's Docker. 2 starts used |

S3 first failed in the VM, and the failure was the repository's, not Lima's: the devcontainer image had no `unzip`,
so `mvnw` downloaded Maven's `.tar.gz` and checked it against `distributionSha256Sum`, the `.zip`'s. Every fresh
environment (a new VM, a new `.m2` volume, the cloud) hit it; the Mac did not, because its volume already held Maven.
`.devcontainer/Dockerfile` installs `unzip` since (#0-238).

**Re-run with the scripts of this change (2026-11-14, instance `factory-build`).**
- S1: `create.sh` from nothing 68 s with the image's download, 34–44 s from Lima's cache after `delete.sh`; on an
  existing instance refused; `delete.sh` of a missing one a no-op.
- Isolation: no mount of the Mac (`findmnt` finds none), `git status --ignored` in the clone empty, a server on the
  VM's `0.0.0.0:18080` not reachable from the Mac. With a `LIMA_HOME` whose `_config/override.yaml` adds a mount, and
  one whose `override.yaml` adds a port forward, `create.sh` refused and deleted the VM: Lima does merge those files
  into this instance, and `limactl list` reports the merged values. One whose `override.yaml` sets
  `propagateProxyEnv: true` was refused too, and so was one adding a `copyToHost`; each VM deleted by the exit trap. A server on `::` in the VM was not
  reachable from the Mac; a server on the Mac's `127.0.0.1` was reachable from the VM and its Docker (#0-240).
- Contents: Node v24.22.1 from nodejs.org (no Ubuntu `nodejs`), the devcontainer CLI 0.89.0 from its tarball;
  `verify-pins.sh` printed its three `verified:` lines and refused a changed image digest, Node sum and CLI sum.
- S3 with this Dockerfile: `devcontainer up` 103 s, firewall up, `example.com` blocked, `unzip` present,
  `./mvnw -B verify -pl oncall-service -am` passed in 96 s (639 tests of `shared` and `oncall-service`, 0 failures,
  its repository tests on Testcontainers).

## Alternatives considered

- **UTM.** Failed S1 within the three starts; what was left untried (the seed as a fixed VirtIO disk, bridged
  networking) would add AppleScript raw codes (`«property SrPt»`) and UTM's registry quirks to a script that has to
  recreate the VM unattended. UTM stays the owner's tool for other VMs.
- **OrbStack.** Its Linux machines take cloud-init, but it is a commercial app whose machines share the Mac's files by
  default (`/Users` mounted), the opposite of #0-202; not tried.
- **Docker Desktop only, no VM** (today). The Docker an escaped test reaches is the Mac's, with the owner's files
  shared to it: what stage 2 exists to end.
- **The cloud now.** ADR-0055 puts it at stage C, after the dispatcher and the review VM; a provision file that already
  runs in the cloud's form keeps that move to a new `create.sh`.

## Consequences

- The autopilot runs in the devcontainer inside `factory-build`; the owner's sessions stay on the Mac. What isolates
  it is in README "Infrastructure Hardening" and `docs/ai-factory.md` "What isolates what".
- **#0-202** is settled for the build VM: its clone is its own, with no gitignored file of the owner's.
- **#0-116** is narrowed, not closed (ADR-0057 narrows it further: the daemon is rootless, its egress filtered): code an agent runs still reaches Docker with root, now the VM's, which holds no
  file of the owner's but does hold the factory's own logins (the bot's token, Claude Code's) in the devcontainer's
  volumes. A boundary around the code an agent runs (Docker API proxy, Sysbox, stage 4's token-less container) is
  still #0-116's.
- **The VM reaches the Mac's loopback services** (checked 2026-11-14, review round 3; closed by ADR-0057, #0-240): a server bound to the Mac's
  `127.0.0.1` answered from the VM and from a container on the VM's Docker, through `host.lima.internal`
  (192.168.5.2), which Lima's user-mode network forwards to the Mac's loopback. That reaches Grafana (every tenant's
  logs, behind its password), Ollama and anything else listening there. The devcontainer's firewall denies it from
  inside the container; from the VM's Docker (root) it is open. Not a regression: Docker Desktop's
  `host.docker.internal` gave the same reach. Closing it is #0-240; listed in README "Infrastructure Hardening".
- **The local model does not carry over.** `devcontainer.json`'s `OLLAMA_URL` names `host.docker.internal`, which in
  the build VM is the VM, not the Mac where Ollama runs: the autopilot's advisory `localReview` finds no model there
  and skips, as it does whenever the model is down. Making it reach the Mac would open the devcontainer's
  firewall to the path the gap above describes, so it waits for a decision of its own (#0-240).
- **The clone is anonymous** and works while the repository is public. Stage 9 of ADR-0055 makes it private; from
  then `create.sh` needs a credential in the VM, which is stage 4's question (where builder-app's credential lives).
- **Pins outside CI.** The image, Node, the CLI and the Ubuntu container of `verify-pins.sh` are pinned in
  `scripts/factory-admin/build-vm/`, where neither Renovate nor `check-pinned-tools.sh` (ADR-0033) reads: they are
  bumped by hand, each with a passing `verify-pins.sh`, and Node with `.node-version` (`create.sh` refuses a
  mismatch). They move to the `factory` repository in stage 4, whose pin checks cover them then.
- Changing the image: the two lines in `factory-build.yaml` and a passing `verify-pins.sh`, in one PR. Changing
  the VM's contents: `provision.sh` only; a VM is then recreated (`delete.sh`, `create.sh`), never patched by hand.
- AC5 of #0-238 (three autopilot items in the VM, ADR-0055's exit of stage 2) comes after this is merged and the owner
  has logged in inside the VM.
