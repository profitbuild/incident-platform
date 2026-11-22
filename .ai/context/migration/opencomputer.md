# What the factory takes from opencomputer, and what it does not (2026-11-22)

A review of [diggerhq/opencomputer](https://github.com/diggerhq/opencomputer) at commit `40bd39d` (2026-11-21,
Apache 2.0), its `computer/` part: the sandbox, the model proxy, GitHub tokens, egress and telemetry. The rest of that
repository is a hosted product the factory does not need.

- **What was compared:** a first analysis by another session, then a check of each of its claims in opencomputer's
  code (read only, nothing run), against `factory` at `5576c992` (`v0.1.4`) and this repository's `main`.
- **What came of it:** each decision below is recorded in the item it changes. This file keeps the reasons and the
  evidence, so a later reader can tell a borrowed design from our own.
- **What is borrowed:** designs only. No code is taken: the dispatcher uses Node's built-in modules only, and
  opencomputer's proxy is Go.

## What opencomputer is, next to the factory

opencomputer runs interactive agent sessions, one thread per session, for many people:
- **runtime:** rootless Podman, as the runners' user;
- **credentials:** a Go model proxy on unix sockets, and git credentials handed out through a per-session socket;
- **control:** a hosted gateway (Cloudflare Workers, Slack).

It has no queue, no review panel, no gate and no ruleset that alone merges. The agent pushes its branch from inside
its sandbox with a GitHub App token.

The factory's process is stronger:
- the container holds no GitHub token;
- the dispatcher pushes from a bundle;
- trusted paths are checked outside the container;
- the PR's CI on a fresh runner is the gate that counts.

opencomputer's isolation layer is more mature in one respect: **a session holds no socket of the host's container
runtime**, because its containers are nested inside it.

## The claims checked

| Claim of the first analysis | Verdict | Evidence in opencomputer |
|---|---|---|
| The model proxy listens on unix sockets, and a container gets the API socket's file alone | true | `modelproxy/main.go:121-122`; `src/host/sandbox/podman-args.ts:16-18, 66` ("the file and not its directory: the control socket beside it stays outside") |
| The session gets `ANTHROPIC_BASE_URL=http://api.anthropic.com`, `ANTHROPIC_UNIX_SOCKET`, a placeholder key and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` | true | `src/runner/harness/claude/model-env.ts:29-42` |
| `ANTHROPIC_UNIX_SOCKET` is not an official variable | partly | Claude Code 2.1.330's binary handles it, with messages of its own ("sessions would send their model calls through that socket"). Measured on the pinned 2.1.328 in #0-313 AC9 (`m2.md` Record, measurement 3): it carries the calls as a transport only, with an `http://` base URL and `apiKeyHelper` still needed, and a missing socket does not fall back to TCP |
| With a socket per task, "a leaked token yields nothing" | **not in the factory** | opencomputer names the caller by `SO_PEERCRED` → pid → the cgroup of its systemd unit (`modelproxy/identity.go:131-139`), and a session holds no runtime socket of the host. In the factory a task's code holds `factory`'s daemon socket (ADR-0057, ADR-0064's residual). `factory`'s daemon must reach every task's socket to mount it, so a task can mount another task's socket with `docker run -v`, just as it can read another's token with `docker inspect`. A socket per task becomes a boundary only together with a model in which the task holds no host daemon socket (#0-285) |
| A route allowlist, client credentials stripped, rate-limit headers reported, concurrency limits, throttled denial logs, bodies never read, an overhead benchmark | true | `modelproxy/profiles/default.json`, `proxy.go:118-191`, `outbound.go:84-85`, `observed.go`, `inflight.go`, `refuse.go:132`, `outbound.go:17`, `bench_test.go:29-30` |
| A global in-flight limit | **no** | Only an in-flight limit per caller (32), a connection limit per caller (128) and an upstream pool (256, 503 after a 10 s hold) |
| Resource limits per session | true | `src/host/runner-limits.ts:16-39`: `MemoryHigh` min(12 GiB, 60 %) and `MemoryMax` min(16 GiB, 75 %); `--pids-limit=4096`. `deploy/vm/limits.sh`: the user's and the runners' slices, with `CPUQuota`, `MemoryHigh`, `MemoryMax` and `TasksMax`, root-owned so the agent cannot raise them. No CPU limit per session |
| The factory has no limit today | true | `factory`'s `dispatcher/src/container/host-config.mjs:167-182` requires `Memory`, `NanoCpus` and `CpuQuota` at 0 and `PidsLimit` 0 or unset |
| Nested rootless Podman per session, and a gates script | true | `podman-args.ts:48-58` (`--userns=keep-id`, `--security-opt unmask=/proc/*`, `--device /dev/fuse`, `--device /dev/net/tun`); `deploy/image/Containerfile:5`; `deploy/vm/sandbox-gates.sh` G1–G9 (runtime, cold start, mounts, identity, network from inside, exec cost, cleanup as root, Docker inside) |
| "An IMDS block and an egress filter for the agent's user" | **overstated** | Only IMDS and Azure's wireserver are rejected for the agent's uid (`deploy/vm/provision.sh:741-770`); there is no allowlist. The factory's `FACTORY-EGRESS` with its resolver allowlist is the stronger of the two |
| The agent pushes with a GitHub App token from inside its sandbox | true | `src/github/app.ts:80-97` (1 h, narrowed to repositories, the app's full permissions); the credential helper over the session's socket (`bin/git-credential-slack-presence`) |
| A session gets a git worktree of a shared clone | true | `src/workspaces/index.ts:5-10`, `bin/ws-add.sh:73-75` |

## What the first analysis did not see

1. **`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.** opencomputer sets it so that "remote settings and other extras
   would go direct, around the socket" do not (`model-env.ts:38`). In the factory, #0-313's measurement found every
   call loads Claude Code's built-in plugins, telemetry among them. The proxy refuses any path but its own, but
   traffic that bypasses the proxy goes straight to Anthropic, which the task container's allowlist still allows. One
   literal in ADR-0064 point 5's list turns it off.
2. **The task container still allows Anthropic.** `.devcontainer/init-firewall.sh` allows "the Anthropic API and
   login", for the owner's container and every task container alike. With K2, every model call goes through the
   dispatcher's proxy, so a task needs no Anthropic host at all. #0-289 (M3.5) already planned to take them out ("the
   other Anthropic hosts out of the task allow-list"); it moves to #0-313, before the first real call.
   **Alone, that closes only the traffic from inside the task container** (corrected by the security review of this
   change, round 1). The VM's `FACTORY-EGRESS` takes every uid from 1000 up as one set
   (`scripts/factory-admin/build-vm/provision.sh:183`, `FILTERED=1000-4294967294`), and it allows
   `api.anthropic.com`, `claude.ai`, `platform.claude.com`, `console.anthropic.com` and `statsig.anthropic.com`
   (`:189`, `:193`) to all of them, `factory` included. A task's code holds `factory`'s daemon socket, so it can start
   a sibling container, which `init-firewall.sh` does not filter (its line 31: such a container "has the host's
   network, not this firewall"), and reach Anthropic from there. It becomes a boundary only with `FACTORY-EGRESS`
   split by uid: Anthropic's addresses allowed to `dispatcher`'s uid only, whose proxy needs `api.anthropic.com`, and
   closed to `factory`'s. Both are in #0-313.
3. **Refusals in Anthropic's error shape, with `X-Should-Retry`.** opencomputer answers in Anthropic's own shape
   (`refuse.go:4`):
   - `X-Should-Retry: false` on 401, 403 and 404 (`refuse.go:126-127`);
   - `true` with `Retry-After: 1` on 429 and 503.

   Claude Code then retries only what can succeed. A refusal in another shape would let a looping agent spend turns
   on it.
4. **A limit on `factory`'s slice already protects M2.** The dispatcher runs as another user. A limit on
   `user-<factory's uid>.slice` covers every container of `factory`'s rootless daemon: the task's container and its
   Testcontainers siblings, which a container's own limit does not cover. A runaway build then kills its task, not
   the VM and the dispatcher, which matters with one slot already.
5. **This repository's `CLAUDE.md` is 21.5 KB,** and every agent call reads it first (#0-299). opencomputer's rule
   for its root `AGENTS.md` (lines 14-25: "the durable starting point for agents ... stable and high-level ... should
   not become a runbook") fits the product's `CLAUDE.md` better than `factory`'s README, which the build agents do not
   read.

## Decided, and where

| Change | Where | When | Why |
|---|---|---|---|
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` in the call's `env -i` list | ADR-0064 point 5, #0-301's code | now (M2) | Point 1 above. One literal, measured with the first call on the VM |
| The task container's allowlist without Anthropic's hosts, and `FACTORY-EGRESS` split by uid so that `factory`'s uid reaches no Anthropic host and `dispatcher`'s does | #0-313 (the first moved from #0-289) | M2.7 | Point 2 above. Only the two together make the proxy the one way to the model: the first alone leaves a sibling container's way open |
| The proxy's missing parts: client credentials stripped, refusals in Anthropic's shape with `X-Should-Retry`, the request body never read, an in-flight limit per task, refusals logged at most once per 10 s per task and reason, rate-limit headers reported to the dispatcher, a test that it does not buffer a stream | #0-313's ACs | M2.7 | Each is small while the proxy is being written; the rate-limit headers are the signal M5's two slots need to stop taking work before a limit |
| A unix socket per task, instead of TCP on the host-gateway address | measured in #0-313; decided in #0-285 | measure now, build with #0-285 | Not a boundary between tasks while a task holds `factory`'s daemon socket (the claims above). It narrows who can reach the proxy (no container on the bridge network without the mount) at the cost of a new mount (ADR-0062 point 4) and a socket shared between `dispatcher` and `factory`. It becomes a boundary with a model in which the task holds no host daemon socket |
| A limit on `factory`'s `user-<uid>.slice` (memory, tasks) | new #0-315 | before the next trial on the VM | Point 4 above. The slice, root's unit above `user@<uid>.service`, which holds the daemon and every container. First written "so it also holds a `sudo -u factory` session": measured on the VM, it does not (sudo's PAM has no `pam_systemd`), and those are clients only (`m2.md`, #0-315's record) |
| Limits per task container instead of zeros in `host-config.mjs` | #0-285, with its model | before M5 | Without a nested runtime they do not cover the task's test containers |
| Nested rootless Podman in the task container, holding no host daemon socket | #0-285, as an option beside Sysbox and a user per slot | #0-285's spike, before M5 | It would close at once: the token readable across tasks, the limits of test containers, the cleanup after a task (part of #0-309), and ADR-0064's residual (root through the socket). Its cost: the outer task container gives things up (`unmask=/proc/*`, which Docker spells `systempaths=unconfined`, `/dev/fuse`, `/dev/net/tun`, likely a seccomp profile that allows user namespaces), against ADR-0062 point 6's closed `HostConfig` table; choosing it amends ADR-0063 G1-b and revisits ADR-0057's rejected Podman alternative; and opencomputer's outer runtime is rootless Podman, not rootless Docker, so its gates do not carry over as they are. A spike first; the choice stays #0-285's |
| Events from the proxy and a thresholds file | #0-306 (M3.3), a note of the plan; its ACs when #0-306 is made ready | M3 | One event per model call (time to first byte, status, limit headers, refusals), held by thresholds `audit-data.sh` reads |
| A second provider through the same proxy | #0-259 (M6.7) | M6 | A provider is a profile of routes and a key, so a second model's key stays out of the container too |
| The product's `CLAUDE.md` as a short starting point | new #0-316 | any time | Point 5 above |
| A file-size ratchet in `factory`'s CI | new #0-317 | any time | Cheap. `factory`'s longest module is 446 lines today |

## Not taken, and why

- **opencomputer as the factory's platform:** a hosted product built around interactive threads (Workers, Durable
  Objects, Slack), not around a queue and gates, and changing fast (design notes marked superseded, historical names
  in its code).
- **A push from inside the sandbox with an app token:** the factory's bundle and the dispatcher's push with trusted
  paths checked outside are safer.
- **Worktrees of a shared clone:** faster, but they share an object store across sessions. The factory's clone from a
  bundle shares no inode with the repository, on purpose.
- **Warm containers in reserve:** they save seconds at a task's start, and a task lasts tens of minutes.
- **Steering and approvals in Slack:** perhaps for a high-risk lane after M6; a large cost for today's needs.
- **Egress filtered by SNI, or opencomputer's egress at all:** theirs is an IMDS block only. The factory's resolver
  allowlist was chosen because an HTTP proxy broke Maven (ADR-0057), and it is the stronger of the two.
- **opencomputer's proxy binary:** its caller identity rests on systemd units' cgroups (`sp-runner-<id>.service`),
  which rootless Docker's containers do not have, and the dispatcher takes no dependency.
