# ADR-0055 stage 2: the build VM — DONE (2026-11-17)

## 1. Goal and exit

ADR-0055's row: "Build VM (provisioned as code) running today's devcontainer". Exit: "3 items with no environment
problem". Rollback: "the devcontainer on the Mac".

Why it exists (#0-238 "Problem"): three gaps came from where the factory ran, not from its logic. Code an agent runs
reached the Mac's Docker (#0-116); the owner and the bot shared one checkout, its `.git` and its gitignored files
(#0-202); a secret file in that tree was one file tool away from an agent (#0-225). Stage 2 moves the same
devcontainer, unchanged, into a VM that holds only what the factory needs, created from code a cloud VM can later
read unchanged (stage C).

## 2. What exists now

- **The Lima instance `factory-build`** (ADR-0056), defined by `scripts/factory-admin/build-vm/factory-build.yaml`:
  `vmType: vz`, Ubuntu 24.04's arm64 cloud image pinned by its dated directory and sha256, 6 CPUs, 12 GiB, 60 GiB,
  no `base:` template, `mounts: []`, no VM port forwarded to the Mac, Lima's containerd off.
- **Its contents, one file:** `provision.sh`, run by Lima as a `mode: system` provision on every boot, idempotent, and
  written so that a cloud VM takes it unchanged as its user-data. It installs Docker CE rootless, git, Node at
  `.node-version`'s version (sha256-pinned) and the devcontainer CLI (sha512-pinned, `--ignore-scripts`).
- **Users:** `factory` runs the rootless Docker daemon and is in no docker group; the rootful `docker.service`,
  `docker.socket` and `containerd.service` are masked. Root in any container is `factory` in the VM. Inside the
  devcontainer the agents run as `dev` (uid 1000, `"updateRemoteUserUID": false`). Lima's own user takes the Mac's
  uid 501.
- **The egress filter:** root's chain `FACTORY-EGRESS` (`/usr/local/sbin/factory-egress.sh`, `factory-egress.service`
  and `factory-egress.timer`) takes every socket of a uid from 1000 up: DNS to the VM's own resolver only, the
  gateway (the Mac's loopback through `host.lima.internal`), the VM's network, link-local and private, shared and
  reserved networks rejected, an allow-list accepted, everything else rejected, IPv6 rejected. It fails closed:
  `factory`'s session requires the unit.
- **The resolver** (#0-247): dnsmasq as the system user `dnsmasq` (`factory-dns.service`), on the VM's address, port
  5300; a nat `OUTPUT` DNAT (`FACTORY-DNS`) sends it every DNS query of those uids; it adds each address it answers
  for a listed name (with its subdomains) to the set `factory-dns` before the asker gets it.
- **The allow-list:** a copy of the devcontainer's (`DOMAINS`, `OPTIONAL_DOMAINS`) plus `VM_ONLY_DOMAINS` (Docker
  Hub's registries and CDNs, `download.docker.com`, `ghcr.io`, Ubuntu's archive, `cli.github.com`,
  `downloads.claude.ai`). `check-allowlists.sh` holds the copy equal to `.devcontainer/init-firewall.sh`.
- **The clone:** `/home/factory/incident-platform`, cloned anonymously from `github.com/profitbuild/incident-platform`
  by `create.sh`, owned by the subordinate uid `dev` maps to. Nothing of the Mac is mounted (#0-202).
- **The devcontainer inside:** today's `.devcontainer/`, started with the devcontainer CLI; its own firewall as on
  the Mac.
- **Logins:** the bot's `gh` token and Claude Code's login, entered once by the owner, live in the devcontainer's
  volumes on the VM's disk. `delete.sh` removes them with the VM.

## 3. How it was done, in order

1. **#0-238 written** (PR #627, 2026-11-13): criteria S1-S3 fixed before the spike, UTM first, Lima as the fallback.
2. **Spike, 2026-11-13** (owner's UTM 4.7.4, M1 Pro, 32 GB; at most three VM starts per tool). UTM failed S1 in 3
   starts: the cloud-init seed, attached as a removable USB drive, did not reach the guest (cloud-init never ran); a
   VirtIO removable drive was refused by QEMU; in shared network mode the guest got no DHCP lease; a second VM of the
   same name left a registry entry `utmctl` could not delete (removed in the GUI). Lima 2.3.0 passed S1, S2 (reworded)
   and S3 in 2 starts. S3 first failed on the repository: the devcontainer image had no `unzip`, so `mvnw`
   checked Maven's `.tar.gz` against the `.zip`'s sum; `.devcontainer/Dockerfile` installs `unzip` since.
3. **PR #628** (2026-11-14): `scripts/factory-admin/build-vm/` (create, provision, delete, verify-pins) and ADR-0056.
   Review round 3 found the VM reached the Mac's loopback services (#0-240). **PR #629** accepted ADR-0056.
4. **PR #632** (2026-11-14, #0-116, closes #0-240): Docker CE rootless, `FACTORY-EGRESS`, `check-allowlists.sh`,
   `create.sh`'s boundary checks after creation and after one reboot; ADR-0057. **PR #633** accepted ADR-0057.
5. **PRs #630, #631, #634** (#0-241): Factory guards runs the agent command check tests only when their inputs change
   (the owner's question on PR #629 about the job's 7 minutes).
6. **PRs #635-#638** (2026-11-14): #0-58, #0-25 and #0-23 made ready, and the queue of 2026-11-14.
7. **Owner steps in the VM:** `create.sh`, enter as `factory`, `devcontainer up`, log in to Claude Code and `gh`,
   start each run by hand (#0-238 Approach 3: unattended authentication stays open).
8. **Exit runs and their fixes** (section 6): PR #640 (#0-247), PR #641 (#0-248), PR #642 (#0-250), PR #643 (#0-252,
   ADR-0058), PR #644 closed #0-250 and #0-252; 1 of 3 shipped as PR #639 (#0-58), 2 of 3 as PR #645 (#0-25); PR #646
   recorded run 2 in #0-238 AC5; PR #648 (#0-266); 3 of 3 shipped as PR #649 (#0-23), which the owner approved and
   merged without the bypass.
9. **PR #650** (2026-11-17) closed #0-238 and #0-266: ADR-0055's exit for stage 2 met (owner, 2026-11-17).

## 4. How to operate it

From `docs/ai-factory.md` "Build VM" and "Running it". The Mac needs Lima (`brew install lima`) and, for
`verify-pins.sh`, Docker. Run `create.sh` from an up-to-date `main`: the contents come from your checkout's
`provision.sh`, the clone from GitHub's `main`.

```bash
scripts/factory-admin/build-vm/create.sh            # refuses an existing instance; about 65 s from Lima's cache
limactl shell factory-build sudo -iu factory        # always as factory, never `sudo docker`
cd incident-platform
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . bash
git status --ignored --short                        # prints nothing (#0-202)
claude                                              # login: open the URL on the Mac, paste the code back
gh auth login --with-token                          # the bot's token
claude --settings .claude/settings.autopilot.json   # on a clean main, then:
> /backlog-autopilot                                # or /backlog-autopilot #0-N [branch]
limactl stop factory-build                          # frees 12 GiB; limactl start factory-build brings it back
scripts/factory-admin/build-vm/delete.sh            # deletes the VM, its clone and the logins
```

Changing the VM: contents only in `provision.sh`, size or image only in `factory-build.yaml`, then `delete.sh` and
`create.sh`; a VM is recreated, never patched by hand. Phone notifications need the ntfy host in `VM_ONLY_DOMAINS`
(not there by default). The local model is not reached from the VM (`localReview` skips).

## 5. Decisions made on the way and why

- **ADR-0056, Lima.** UTM failed S1 within the three starts; what was left untried added AppleScript raw codes and
  UTM's registry quirks to an unattended script. OrbStack shares `/Users` by default; Docker Desktop only is what
  stage 2 ends. S2 reworded: Lima takes no raw cloud-init user-data, so the portable part is one provision script.
  `create.sh` checks the isolation the template only states, because Lima merges `~/.lima/_config/default.yaml` and
  `override.yaml` into every instance.
- **ADR-0057, rootless Docker behind a VM egress filter.** Docker access is root over its daemon; an `iptables` rule
  with rootful Docker binds nothing a test cannot remove. Spike criteria R1-R3 (owner, 2026-11-14) passed. Not chosen:
  no Docker in the devcontainer, a Docker API proxy, waiting for stage C, Claude Code's Bash sandbox, Podman.
- **ADR-0057 amended by #0-247, a resolver.** A set resolved every 30 minutes missed CloudFront's changing answers.
  A resolver that fills the set (as dnsmasq's `ipset=` or Cilium's FQDN policies) was chosen over an HTTP proxy, which
  would put Maven, npm, the image build and Testcontainers behind proxy settings. Consequence: the list is of
  domains, with their subdomains.
- **ADR-0058, the isolation probe (#0-252).** The check read a fact the runtime sets (the hook's `agent_type`), not
  the model's answer, which it may decline or misjudge.
- **#0-250, `BASH_DEFAULT_TIMEOUT_MS=1800000`** (and `BASH_MAX_TIMEOUT_MS`) in `settings.autopilot.json`'s `env`;
  the preflight refuses less. Claude Code moves a foreground command to the background at its timeout (2 minutes by
  default), and factory-ops, with one call per task, lost the gate's answer.
- **#0-266, factory-ops on `claude-sonnet-5-5`** instead of Haiku 4.5, until the dispatcher removes the relay
  (stage 4, #0-261). Enough because every PR still needs the owner's approval and CI's checks. Not chosen: a digest
  of each answer, two calls compared.

## 6. Runs on the way and what each taught

| Run | Item | Outcome | Fix |
|---|---|---|---|
| 20261114-155647 | #0-58 | BLOCKED: Testcontainers pulls refused on CloudFront addresses not in the static set | #0-247, resolver (PR #640) |
| wf_1e3befc7-a08, wf_477d7545-796 | (not recorded in the repository) | `NOT_STARTED`: review-general answered `definitionLoaded: false` with its definition loaded | #0-248 (PR #641) |
| 20261115-170407 | #0-58, resumed | BLOCKED, "test gate returned no result": the gate moved to the background after 120 s | #0-250 (PR #642) |
| wf_24c48844-aa4 | #0-58, resumed | refused by `guard-factory-scripts.sh` (base predated #0-250's `preflight.sh`), left `.ai/runs/LOCK` | owner merged `main`, `state.sh unlock` by hand; #0-253 (frozen, superseded by stage 4) |
| wf_71cca984-ef4 | (not recorded in the repository) | `NOT_STARTED`: the model declined to quote its prompt | #0-252, isolation probe (PR #643, ADR-0058) |
| wf_207ec85e-4ad | #0-58, resumed at the gate | **1 of 3**: gate 03:03 min on all nine modules, probe recorded `review-general`, panel round 1; PR #639 | PR kept "(BLOCKED)" in its title: #0-254 |
| wf_5135023f-b7d | #0-25 | **2 of 3**: six reviewers round 1, ADR-0059; PR #645 | Haiku factory-ops garbled a relayed path (`a35aa6ee/context/...`): #0-266 (PR #648) |
| wf_e5a616a0-073 | #0-23 | **3 of 3**: 943 tests, five reviewers round 1, AC1-AC6 met; PR #649 | 10 of 11 Sonnet answers equal; `run-tests.sh`'s `summary` shortened, left to #0-261 |

None of the failed runs was a problem of the VM itself except 20261114-155647; the rest were factory defects that
the VM's runs exposed (#0-258 proposes running a factory change on a real item first).

## 7. How to verify it still holds

- `scripts/factory-admin/build-vm/verify-pins.sh`: five `verified:` lines (image against signed `SHA256SUMS`, Node
  against signed `SHASUMS256.txt.asc`, the CLI's `dist.integrity` and no dependencies, Docker's apt key fingerprint,
  Docker CE's versions for arm64 and amd64). Run with every pin change, in the same PR.
- `scripts/factory-admin/build-vm/check-allowlists.sh`: one line and exit 0 when the VM's copy equals
  `init-firewall.sh` both ways; also run by Factory guards on every pull request and by `create.sh`.
- `create.sh` itself: on every new VM, after creation and after one reboot, it checks the isolation (no mount, agent,
  X11 or port forward, network, proxy propagation, `copyToHost`, extra disk, provision or probe) and the boundary
  (rootful daemon masked, `factory` rootless and in no docker group, chain in place, gateway rejected, `example.com`
  refused and `api.github.com` reached, the resolver's checks from a container) and deletes the VM on any failure.
- Inside the devcontainer: `git status --ignored --short` prints nothing.

## 8. Rollback

The devcontainer on the Mac, unchanged (ADR-0055; the owner keeps it as the rollback). Going back is starting the
autopilot there as before stage 2; `delete.sh` removes the VM. Because the Mac path stays usable, #0-116, #0-202 and
#0-225 are narrowed, not closed, and keep their "Stage 2" notes.

## 9. Left open

- #0-116: code a test runs is still `factory` in the VM and reads its volumes (the bot's token, Claude Code's login);
  stage 4's token-less task container.
- #0-202: settled for the build VM, open while the Mac devcontainer stays the rollback.
- #0-225: the VM's clone holds no secret file of the owner's; what a task writes is stage 4's.
- #0-239: the build VM's scripts have no repeatable test.
- #0-242: the listener check runs only when the VM is created.
- #0-243: two parsers read the devcontainer's allow-list.
- #0-244: no review rule covers the VM's own allow-list (`VM_ONLY_DOMAINS`).
- #0-249: Claude Code in the devcontainer image is whatever version was current at build time.
- #0-253: a run stopped by the factory-scripts guard keeps its lock (frozen, superseded by stage 4, #0-261).
- #0-254: a resumed item that ships keeps its draft PR's "(BLOCKED)" title.
- Named in ADR-0057, not closed: DNS as a channel, shared front ends and push-taking registries in the list, the
  resolver's `CAP_NET_ADMIN`, the VM's kernel. The clone is anonymous while the repository is public (stage 9).

## 10. Sources

- `.ai/decisions/0055-the-factory-moves-to-three-zones.md` (stage 2 row), `0056-the-build-vm-is-a-lima-instance.md`,
  `0057-the-build-vms-docker-is-rootless-behind-a-vm-egress-filter.md`,
  `0058-the-isolation-check-reads-the-runtimes-agent-type.md`.
- `BACKLOG-DONE.md`: #0-238, #0-240, #0-241, #0-247, #0-248, #0-250, #0-252, #0-266 (rows and "Details").
- `BACKLOG.md`: #0-116, #0-202, #0-225 ("Stage 2" notes), #0-239, #0-242, #0-243, #0-244, #0-249, #0-253, #0-254,
  #0-258, #0-261.
- `scripts/factory-admin/build-vm/` (`factory-build.yaml`, `provision.sh`, `create.sh`, `delete.sh`,
  `verify-pins.sh`, `check-allowlists.sh`); `docs/ai-factory.md` "Build VM" and "Running it".
- Merged PRs #627-#650 (`git log --merges`).
