# ADR-0057: The build VM's Docker is rootless, and everything it sends passes a VM egress filter

- **Status:** Proposed
- **Amends:** ADR-0056 (the build VM's Docker Engine: Docker CE run rootless for `factory`, not Ubuntu's `docker.io`
  run by root with `factory` in the docker group)
- **Backlog:** #0-116, #0-240
- **Date:** 2026-11-14
- **Author:** human (the owner's spike of 2026-11-14, drafted in an interactive session)
- **Reversible:** yes. The VM is recreated from `provision.sh`; going back is the previous `provision.sh` (rootful
  Docker, no egress chain), or the devcontainer on the Mac

## Context

Code an agent runs (a test) needs Docker for Testcontainers, and Docker access is root over whatever its daemon runs
as (#0-116). ADR-0056 moved that daemon from Docker Desktop on the Mac to the build VM, which narrowed what the root
reaches but not that it is root: a test could start a container with `--network host` and send data anywhere around
the devcontainer's firewall, flush `iptables`, and, through Lima's user-mode network (`host.lima.internal`,
192.168.5.2), reach the Mac's loopback services, Grafana with every tenant's logs and Ollama among them (#0-240,
checked 2026-11-14). An `iptables` rule in the VM alone (#0-240's first option) binds nothing that is root in the VM.

The owner approved a spike with three criteria before it started (2026-11-14):
- **R1.** On rootless Docker in the VM, `devcontainer up`, its firewall, and `./mvnw verify -pl oncall-service -am`
  with Testcontainers pass.
- **R2.** From a container a test starts, the VM's `iptables` cannot be changed, no host outside the allow-list is
  reached (with `--network host` either), and the Mac's `127.0.0.1` is not reached.
- **R3.** All of it comes from `provision.sh`, with no manual step.

## Decision

**The VM's Docker daemon runs rootless, as `factory`; the VM's root filters everything `factory` sends.**

- **Rootless Docker.** Docker CE and `docker-ce-rootless-extras` from Docker's apt repository, its key pinned by
  fingerprint `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88` in `provision.sh` (refused if the key served has
  another; confirmed on download.docker.com, keyserver.ubuntu.com and Docker's install documentation; checked again
  by `verify-pins.sh`). Ubuntu's `docker.io` ships no rootless scripts. The rootful `docker.service`, `docker.socket`
  and `containerd.service` are masked, and `factory` is in no docker group. Root in any container is `factory` in the
  VM; a container's other users map onto `factory`'s subordinate range.
- **What it took** (each found in the spike):
  - an AppArmor profile for `/usr/bin/rootlesskit`, as Ubuntu 24.04 confines unprivileged user namespaces;
  - `host-gateway-ip` set to the VM's address in the rootless daemon's `daemon.json`: rootlesskit publishes a
    container's ports there, not on the bridge's gateway, and Testcontainers' Ryuk was unreachable until
    `host.docker.internal` pointed at it;
  - `/var/run/docker.sock` a link to the rootless socket, so `docker`, the devcontainer CLI and the devcontainer's
    docker-outside-of-docker feature need no `DOCKER_HOST`. Made by `systemd-tmpfiles` early in every boot: the
    rootless daemon sees `/run` as it was when it started, and after a reboot it starts before `provision.sh` runs
    (found in review round 1: the feature's mount failed after a reboot only);
  - the clone owned by the subordinate uid the devcontainer's `dev` (uid 1000) maps to, so `dev` can write its
    workspace (`create.sh`). Running the agents as root in the container instead would let them change its firewall.
- **The VM egress filter** (`/usr/local/sbin/factory-egress.sh`, written by `provision.sh`; `factory-egress.service`
  at boot, before `factory`'s session, and `factory-egress.timer` every 30 minutes). Root's chain `FACTORY-EGRESS`
  takes every socket of a **uid from 1000 up**: `factory`, whose rootless Docker's packets all carry its uid
  (slirp4netns runs as `factory`), its subordinate range (100000 up), and any user added later. Only system accounts
  (below 1000: root, systemd-resolve, `_apt`, and Lima's user, who takes the Mac's uid 501) are unfiltered, and
  `factory` can become none of them (no sudo; `newuidmap` maps only its own range). Matching `factory`'s uid alone was
  not enough: `rootlesskit --net=host -- setpriv --reuid=1 curl` ran as a subordinate uid in the VM's own network
  namespace and reached `example.com` (review round 2). The chain: on loopback, only the local resolver and the VM's
  own address on the kernel's ephemeral ports, where Docker publishes a container's (Testcontainers' mapped ports),
  so not sshd or a listener below that range; DNS to systemd-resolved's resolvers only (under Lima the gateway, which
  is one); then the gateway, the VM's own
  network and `169.254.0.0/16` rejected (under Lima the Mac's loopback services, #0-240; in a cloud the provider's
  network and its metadata service); then an allow-list of networks (GitHub's published ranges, and the addresses of
  a list of domains); then everything rejected. IPv6 is rejected for the same uids, loopback included (`::1` reaches
  the listeners on `[::]`). The VM forwards nothing (`ip_forward` 0), so no packet escapes the owner match. It fails closed: the chain is built and swapped in before its
  allow-list is loaded, never flushed in place; `factory`'s session (`user@<uid>.service`) requires the unit, so it
  does not start unfiltered if the script fails; the timer runs `factory-egress-refresh.service`, which resolves the
  domains again and swaps the set whole.
- **Root writes nothing under `factory`'s home.** `factory` owns it, and so does root in any container a test starts,
  which can plant a link there. `provision.sh` runs as root on every boot; writing `daemon.json` through a planted
  link (`daemon.json -> /usr/local/sbin/factory-egress.sh`) and `chown`ing it gave `factory` a root file, then root
  (shown in the VM in review round 1: a root-owned file under `/etc` became `factory`'s after a reboot). Every write
  there is done as `factory` (`runuser`); `create.sh`'s `chown -R -h` of the fresh clone changes links, never targets.
- **A copy of the devcontainer's allow-list, and the VM's own beside it.** The devcontainer's (`init-firewall.sh`)
  binds the agents' commands; the VM's binds everything `factory`'s Docker sends, image builds and pulls included. So
  `factory-egress.sh` holds a copy of the devcontainer's (`DOMAINS`, `OPTIONAL_DOMAINS`) and, apart, what only the VM
  needs (`VM_ONLY_DOMAINS`: the registries and CDNs of Docker Hub, `download.docker.com`, `ghcr.io`, Ubuntu's
  archive, `cli.github.com`, `downloads.claude.ai`, each group with its reason). `check-allowlists.sh` holds the copy
  equal both ways, required to required and optional to optional, and `VM_ONLY_DOMAINS` apart from it; Factory guards
  runs it on every pull request and `create.sh` before every VM, so a host added to or removed from `init-firewall.sh`
  alone fails CI, not the running VM (FAC-A01, review rounds 1 and 2).
- **`dev` keeps uid 1000** (`"updateRemoteUserUID": false` in `devcontainer.json`): the clone's owner is the
  subordinate uid that uid 1000 maps to, which a CLI renumbering `dev` to `factory`'s uid would miss on a cloud image.
- **Checked on every VM `create.sh` makes, after its creation and again after a reboot** (what holds only on a fresh
  VM fails there), deleting it otherwise: `docker.service` masked, `factory` in no docker
  group, `factory`'s daemon rootless, the chain in place with the gateway rejected, `example.com` unreachable and
  `api.github.com` reachable for `factory`, the rootless daemon able to mount `/var/run/docker.sock`, and after the
  reboot `provision.sh` finished in that boot (its marker names the boot id).

### What the spike showed (2026-11-14, VM `rootless-spike`, then `factory-build` from `create.sh`)

| Attempt, as `dev` in the devcontainer, through `docker` | Before (rootful, no filter) | After |
|---|---|---|
| a) a `--network host` container reaches `example.com` | reached | blocked |
| a2) a bridged container reaches `example.com` | reached | blocked |
| b) a container reaches a server on the Mac's `127.0.0.1` (via 192.168.5.2) | reached | blocked |
| c) a `--privileged --network host` container flushes `iptables` | — | refused; the VM's chain unchanged |
| d) `--privileged -v /:/host` writes `/etc`, reads `/etc/shadow`, reads the Lima user's home | — | the write lands in rootlesskit's private copy of `/etc` (`--copy-up=/etc`), the VM's `/etc` unchanged; both reads refused |

R1: the devcontainer image built from nothing behind both filters, its firewall up, and the gate passed: 639 tests
of `shared` and `oncall-service`, 0 failures (65–97 s). R3: `create.sh` builds the same from `provision.sh` alone
(49 s), and a reboot runs `provision.sh` again with no duplicate rule or chain.

## Alternatives considered

- **A. No Docker in the devcontainer** (#0-116's option A): the Testcontainers tests leave the autopilot's gate for CI,
  so failures of repositories, migrations and Kafka show only on the pull request.
- **B. A filtering Docker API proxy** (#0-116's option B): a security component of our own, kept in step with every
  call Testcontainers makes; rootless Docker gets the same containment from the kernel's user namespaces.
- **An `iptables` rule in the VM with rootful Docker** (#0-240's first option): root in the VM, which a test has
  through Docker, removes it.
- **Waiting for stage C** (a cloud VM with the provider's firewall outside it): #0-116 and #0-240 open for months;
  the chain here is written for a cloud VM too (the gateway, the VM's network and link-local rejected).
- **Claude Code's Bash sandbox** (#0-116's option D): the Testcontainers tests need the Docker socket
  (`allowUnixSockets`), the access this decision removes; at most a layer under this one.
- **Podman** (rootless by design, in Ubuntu's archive): a second container engine under the devcontainer CLI and
  Testcontainers, each with its Podman caveats; Docker rootless keeps the tools as they are.

## Consequences

- **#0-240 is closed** for the build VM: neither the VM's `factory` nor any container it starts reaches the Mac's
  loopback. The devcontainer on the Mac, the way back until #0-238's AC5, still reaches it through
  `host.docker.internal`, as before.
- **#0-116's AC1 holds in the build VM**: code run as `dev` cannot change a firewall that binds it or reach a host
  outside the VM's allow-list, directly or through a container it starts; AC2 too (the gate runs Testcontainers). The
  item closes with #0-238's AC5, once the autopilot runs only there.
- **Left open, named:** code a test runs is still `factory` in the VM, so it reads `factory`'s files, the
  devcontainer's volumes with the bot's token and Claude Code's login among them: stage 4 of ADR-0055 (a task
  container with no token). DNS to the VM's resolvers is a channel, as in the devcontainer. The allow-list is of
  addresses: a CDN that moves between two refreshes fails a download until the next (30 minutes), as the devcontainer's
  own list can.
- **The VM's kernel is part of the boundary:** rootless Docker needs unprivileged user namespaces, which the AppArmor
  profile for `rootlesskit` grants, so a kernel privilege escalation from `factory` to the VM's root removes
  `FACTORY-EGRESS` and reopens #0-240's path. The image is pinned by digest, so its kernel is the one of that image's
  date until Ubuntu's unattended-upgrades (on by default) installs a newer one and the VM reboots; recreating the VM
  from a bumped image (`verify-pins.sh`) is the other way. Named here, not closed (review round 5).
- **Shared front ends are open by address:** Docker Hub's `production.cloudflare.docker.com` (Cloudflare),
  `production.cloudfront.docker.com` and `download.docker.com` (CloudFront) are allowed by the addresses they resolve
  to, so `factory` reaches any site those front ends serve; with the token volume readable (above), a channel out,
  as the devcontainer's own list has for the advisory hosts it allows. So is `downloads.claude.ai`, behind a front end
  shared with other sites. And two of the VM's hosts take a push with credentials of the pusher's own:
  `registry-1.docker.io` (Docker Hub) and `ghcr.io`. Neither is a channel the GitHub ranges, which the devcontainer
  allows for `git push`, do not already give; named so a future narrowing of those ranges does not miss them (review
  round 4).
- **What the chain does not tell apart, and `create.sh` checks instead:** the ephemeral-port rule admits any listener
  of the VM on its own address in that range, not only Docker's published ports, so `create.sh` refuses a VM where a
  process other than `factory` listens in it on a non-loopback address (review round 3). On a cloud VM (stage C), `factory`'s published ports
  listen on all addresses and the ESTABLISHED rule answers what reaches them, an inbound channel the provider's
  firewall must close.
- **Failing closed costs availability:** a required domain that does not resolve at boot fails
  `factory-egress.service`, which `factory`'s session requires, so no rootless Docker until the next boot or a manual
  `systemctl start factory-egress.service`; a refresh that fails keeps the previous set.
- **New source of software:** Docker's apt repository, pinned by its key's fingerprint (and refused if the file holds
  any other key), its packages by exact version (`DOCKER_VERSION`, `CONTAINERD_VERSION`), each checked by apt against
  the repository's signed index; `verify-pins.sh` checks the versions are there for arm64 and amd64. A key rotation
  shows in `verify-pins.sh` and stops `provision.sh` until the pin is confirmed again.
- **The rootful daemon runs once, at install**, before it is masked: it turns IPv4 forwarding on and leaves its
  iptables chains and `docker0` until the next boot. `provision.sh` turns forwarding off again and removes the rest;
  `create.sh` checks both (review round 3).
- **The local model is further away:** `host.docker.internal` is now the VM's own address, and the Mac is rejected
  for `factory`; reaching Ollama on the Mac would need a rule of its own (ADR-0056 already left it out).
- A new input of the devcontainer's allow-list goes into `factory-egress.sh`'s list in the same change, which
  `create.sh` enforces; a new download of the image build goes there too, or the build fails in the VM, visibly.
