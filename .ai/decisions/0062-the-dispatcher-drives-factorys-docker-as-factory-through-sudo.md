# ADR-0062: The dispatcher drives `factory`'s Docker as `factory`, through one sudo rule, and hands it the task's clone as a bundle

- **Status:** Accepted (2026-11-20, by the owner; points 2 to 5 and 7 completed on review round 1, points 2, 4, 5, 6 and
  8 on review round 2, points 4 and 5 on review round 3, points 4, 5 and 7 on review round 4, points 5 and 7 on review round 5, the same day, before any code); amends ADR-0060's
  Consequences on the task image (point 6)
- **Backlog:** #0-277
- **Date:** 2026-11-20
- **Author:** human (the owner chose the options of a `/research` of #0-277 in an interactive session); written by
  Claude Code
- **Reversible:** yes — one sudoers file of `provision.sh`, one starter of the dispatcher's container commands, and
  where the task's work directory lives

## Context

ADR-0060 has the dispatcher (user `dispatcher` on the build VM, the uid that reads builder-app's key) run each agent
in a container of `factory`'s rootless Docker (ADR-0057). That daemon runs as `factory`, its socket is
`/run/user/<factory uid>/docker.sock` in a tmpfs of mode 0700 that `factory` owns, its unit is `factory`'s own file,
and `/run/docker.sock` links to it (`provision.sh`). ADR-0057's boundary: code an agent runs reaches that daemon (the
devcontainer's `docker-outside-of-docker` mounts the socket, for Testcontainers), so the uid `factory` is the agent's
side. `dispatcher` cannot reach the daemon today (#0-277). `create.sh` already drives it as `factory`
(`sudo -u factory -H env DOCKER_HOST=... docker`).

Two facts the item had not weighed (the `/research` of 2026-11-20):
- whoever runs the `devcontainer` CLI runs `devcontainer.json`'s `initializeCommand` on the host as that user, and the
  `docker` CLI loads plugins and credential helpers from its user's `~/.docker/`: both are code a configuration an
  agent or a product writes can name;
- the task's work directory as #0-277 placed it, `$FACTORY_STATE_DIR/tasks/<runId>/work`, is under a directory of
  mode 700 of `dispatcher`'s, which the daemon (as `factory`) cannot reach to bind-mount; opening it to `factory` lets
  the agent's uid into the dispatcher's state, and the dispatcher writing a clone into a directory of `factory`'s
  writes where the agent can plant a link.

## Decision

1. **The dispatcher runs `docker` and `devcontainer` as `factory`, never as itself**, through one sudoers rule that
   `provision.sh` writes to `/etc/sudoers.d/factory-dispatcher` (no `.` in the name: `#includedir` skips such a
   file silently; `root:root`, 0440) and checks with `visudo -c`: `dispatcher` may run, as `factory` and
   with no prompt (`sudo -n`), exactly `/usr/bin/docker` and the pinned `devcontainer` CLI (full paths), with `env_reset` and no
   `setenv`; nothing else, and `factory` has no sudo rule at all. Every such call is `sudo -n -u factory ...`, started
   by one function of the dispatcher with an environment from `childEnv` (#0-276); under `env_reset` the programs get
   sudo's reset environment and reach the daemon through ADR-0057's `/run/docker.sock` link. What the configuration of
   an agent or a product names (a CLI plugin, a credential helper) runs as `factory`, inside ADR-0057's boundary. A
   secret is never an argument of such a call (sudo logs a command's arguments): 4.6's task token goes on stdin or the
   like, decided there.
2. **The task's work directory lives and dies by one-shot containers of `factory`'s daemon**, so the rule stays at
   two programs and no git runs as `factory` on its agent-writable `~/.gitconfig`. The helper image is
   `buildpack-deps:noble-scm`, a Docker official image (git 2.43, coreutils), pinned by digest in `verify-pins.sh`
   (point 8). Under `/home/factory/tasks` (made by `provision.sh` as `factory`, mode 700), a helper that mounts that
   parent makes `<runId>/`, writes what arrives on its stdin to a file (git reads no bundle from a pipe), clones it
   with `git clone -b base` into `<runId>/w` (the bundle is `git bundle create - refs/heads/base`, made in the
   dispatcher's own `FACTORY_REPO_DIR`: a bare sha makes an empty bundle, and a bundle with no `HEAD` checks out
   nothing unless the branch is named), and `chown -R -h 1000:1000`s it, so the workspace belongs to the uid the
   container's `dev` maps to (ADR-0057) without root on the VM. Removal is a helper mounting the parent that runs
   `rm -rf <runId>` (dot entries and the directory itself included), at the task's end, BLOCKED or not, and at the
   next run's start for what a killed run left. The dispatcher writes nothing in a directory of `factory`'s; the
   clone shares no inode with `FACTORY_REPO_DIR`.
3. **The factory the containers load is one checkout owned by root**, `/opt/factory-checkout` at `FACTORY_COMMIT`
   (`root:root`, 0755), made by `provision.sh` outside every user's home and checked at boot as the dispatcher's clone
   is today; the daemon mounts it read-only at `/opt/factory`, and as `factory` it could not write it anyway. The
   dispatcher runs from the same checkout, so there is one copy of the factory on the VM, not two.
4. **The container's configuration is the dispatcher's, from a task configuration the product ships for it.**
   `taskImage` names a devcontainer configuration written for the task container (incident-platform's is #0-282),
   not the owner's interactive one, which mounts credentials and carries the bot's environment. The dispatcher reads
   it from the base in its own `FACTORY_REPO_DIR` (`git show <base>:<path>`, as data, with a JSONC reader of its own:
   built-ins only, ADR-0060 D2), checks it against a closed list, and writes the override that `devcontainer up
   --override-config` reads (absolute paths into `<runId>/w`) through the same helper's stdin, never a file of its own
   in a directory of `factory`'s:
   - carried: `build.dockerfile` and `build.context` (both in the configuration's directory or under it; `build.options`,
     `build.args` and `build.target` refused), `remoteUser` (the agents' user), the commands run inside the container
     (`postCreateCommand`, `postStartCommand`); no carried string may hold `${localEnv:...}` or `${localWorkspaceFolder}`
     (the host's environment and paths);
   - a closed set of values: `capAdd` from `NET_ADMIN` and `NET_RAW` only; `runArgs` holding only
     `--add-host=host.docker.internal:host-gateway`; `containerEnv` keys from a list, with literal values only (no
     `${localEnv:...}`, which reads the host's environment; none of the bot's `GIT_AUTHOR_*`, `FACTORY_BOT_LOGIN`, or a
     secret's shape);
   - features by id and the digest of the product's `devcontainer-lock.json`, from a list, with their options from a
     list too (`docker-outside-of-docker`'s `moby: false` among them); its Docker socket mount is accepted by name,
     since it is ADR-0057's boundary (Testcontainers needs it);
   - set by the dispatcher: `mounts` (`<runId>/w`, `/opt/factory` read-only, a per-task `~/.claude` volume, the shared
     `~/.m2` cache), `workspaceMount`, `workspaceFolder`, `updateRemoteUserUID: false` (ADR-0057), `containerUser:
     root` (the feature's start script needs it; the agents run as `remoteUser`), the label;
   - refused: any other field or value, `initializeCommand` included. No product code on the host, no mount the
     product chose but the listed feature's;
   - after the build, the image's own `devcontainer.metadata` label (which `devcontainer up` merges into the
     configuration, and a Dockerfile's `LABEL` can fill) is read and held to the same list; a difference refuses the
     task.
5. **No credential lives on `factory`'s daemon while the dispatcher runs; the rollback shares the VM by time.** A
   test with the Docker socket (`docker-outside-of-docker`, for Testcontainers) can mount any volume of that daemon
   itself, whatever the dispatcher mounts. So the rollback (today's `/backlog-autopilot` in the VM's devcontainer)
   runs only while no dispatcher run is active, with the owner's logins entered again before it:
   - the owner starts a rollback with `scripts/factory-admin/build-vm/rollback-start.sh`, which refuses while an object
     labelled `factory.task` exists (a dispatcher run is on), gives the rollback's container a positive label,
     `factory.rollback=1` (`devcontainer up --id-label`), and checks again once `up` has returned and before it tells
     the owner to log in: if a `factory.task` object exists by then, it removes its own container and refuses. Every
     command of the rollback goes through the label (`rollback-start.sh`, and `rollback-exec.sh` for `devcontainer
     exec`): a bare `devcontainer up` or `exec --workspace-folder` would not find the labelled container and would make
     a second, unlabelled one on the same credential volumes;
   - the dispatcher **refuses to start while a running container carries `factory.rollback`**; after its sweep it
     makes itself visible first (the task's network, labelled `factory.task=<runId>`) and only then checks again,
     before it creates the task container: with each side visible before it looks at the other, a rollback still
     building its image when the run starts is seen by one of the two checks;
   - a refusal on either side names the containers it found and the command that clears them (`cli.mjs sweep`, the
     dispatcher's sweep alone, for what a killed run left);
   - otherwise its start-of-run sweep (point 7) removes everything of the daemon but its own cache volume
     `factory-dispatcher-m2`: a killed run's task container and what its tests left running (Testcontainers' and Ryuk's,
     unlabelled), a rollback's stopped container and the compose stack it started, every network, and every volume, the
     rollback's credential volumes (`incident-platform-gh`, `incident-platform-claude`) and its `incident-platform-m2`
     and anonymous ones included. Each dispatcher run after a rollback therefore erases the rollback's logins, entered
     again before the next rollback. A label is positive, never inferred from its absence: the absence cannot tell a
     rollback from a killed run's leftovers (review round 4, arc-5e17).
   The rollback does not move to the Mac, which would reopen for it what ADR-0056 and ADR-0057 closed (#0-240: the
   Mac's loopback through `host.docker.internal`; #0-116: Docker Desktop's daemon).
6. **The task image in v0 is built on the VM from the product's task configuration** (ADR-0055: "until stage C
   the task image is built there"): `taskImage` is that configuration's path in the product (relative, never a value
   starting with `-`, never leaving the clone); `devcontainer up` builds it as `factory`; the dispatcher records the
   image's ID (`sha256:<64 hex>`) in `task.json` and runs every container of the task from that ID. A registry digest
   (`<name>@sha256:<64 hex>`) comes with the image built in CI and pulled from GHCR (stage C, or the stage that moves
   the images to CI first); a tag is never taken. The image must hold `timeout` (coreutils), which point 7 runs.
7. **Ends and kills:** a call runs in the container under `timeout -s TERM -k <grace> <limit>`, since `docker exec`
   without a tty forwards no signal to the process it started (probed 2026-11-20); past the limit the dispatcher kills
   the task's containers through the starter (`docker kill` by the label), stops reading the call's output without
   waiting for the stream to close (an orphaned CLI holds it open), and the task ends BLOCKED. Every container, volume
   and network of a task carries the label `factory.task=<runId>`; at the task's end and at the next run's start the
   dispatcher removes every container and user-defined network of the daemon (`bridge`, `host` and `none` stay; none
   other is kept on it, point 5) and every volume
   but `factory-dispatcher-m2`, and the work directory by point 2: containers first, then networks, then volumes
   (`docker volume rm` refuses a volume a stopped container still uses: probed), and the sweep's result is checked
   (no container left, no volume but `factory-dispatcher-m2`), or the run is refused. A long-lived container of the
   dispatcher's own (4.6's proxy, if one) carries a label of the run (`factory.task=<runId>`), so a sweep at a later
   run's start removes it as any other.
8. **New source of software for the VM:** `buildpack-deps:noble-scm` from Docker Hub, pinned by digest in
   `verify-pins.sh` (which checks it is published for arm64 and amd64), its update path #0-281's with the other
   `ubuntu`-based digest.

## Alternatives considered

- **An ACL on the socket for `dispatcher`, set by a root unit at each start of the daemon** (the item's first
  option): the `devcontainer` CLI would parse a product's configuration and run its host-side parts as `dispatcher`,
  the uid of builder-app's key; and `factory` can restart its daemon or change the ACL of its own runtime directory at
  any moment, so the ACL needs a root unit kept in step with a unit `factory` owns. (Docker's plugins and credential
  helpers alone could be kept off with a `DOCKER_CONFIG` of the dispatcher's own.) It does not solve the work
  directory either.
- **git as a third program of the rule**, cloning as `factory`: git would read `factory`'s `~/.gitconfig`, which a
  previous task's code can write (a hook, a smudge filter run over the base's checkout).
- **The rollback's credentials kept on the VM's daemon while the dispatcher runs**, or a second uid and daemon for
  the rollback: the first lets a test mount them; the second is another zone on the same VM, for a path that ends at
  stage 5.
- **The rollback on the Mac's devcontainer** (first chosen, then reversed on review round 2 the same day): it reopens
  for every rollback run #0-240 and #0-116, which stage 2 closed; sharing the VM by time keeps them closed at the cost
  of the owner's logins entered again.
- **A list of allowed fields and values over the product's interactive `devcontainer.json`**: incident-platform's
  mounts credentials, carries the bot's environment and needs `runArgs` the dispatcher would have to pass by name,
  putting a product's needs into the factory's code (ADR-0055, ADR-0060); a task configuration the product writes for
  the dispatcher states them as the product's own.
- **A filtering socket proxy (root) for `dispatcher`**, as the log pipeline's docker-socket-proxy: it guards the
  daemon from its client, the trusted side here, and adds a root service; the client's own risks stay.
- **`systemd-run --uid=factory` or `machinectl shell`**: the same separation as sudo, with polkit or root needed and
  stdin/stdout for the bundles harder to carry.
- **The work directory under `$FACTORY_STATE_DIR`**, or a clone the dispatcher writes into `factory`'s directory:
  above, Context.

## Consequences

- `dispatcher` controls `factory`'s containers; `factory` gains nothing of `dispatcher`'s. `create.sh` checks on a new
  VM that `dispatcher` runs a container through the rule, that the rule allows no other program, that `factory` has
  no sudo, and that `factory` reads nothing of `dispatcher`'s (#0-277 AC2).
- The dispatcher reads only data from that side: a bundle, a gate's JSON, an exit code. Anything it parses from
  `docker` or `devcontainer` output is untrusted input, as the bundle is.
- `~/.m2` stays a shared cache volume in v0 (a task can poison it for the next; a per-task copy if a seeded case
  shows it, `stage-4.md` "4.3").
- What the recorded image ID and the helper's digest do not guarantee: the daemon's image store and build cache are
  `factory`'s, the agent's side, so a task's code can change what the next build makes, what an ID points to on disk,
  or the helper that fills the next clone. The ID and the digest stop a tag swap and a changed pull, no more; the same
  holds for `factory`'s home, which lives across tasks (accepted in v0, as `~/.m2`). A container or network a task's
  test starts without the label is removed by point 7's sweep of the whole daemon.
- The rollback and the dispatcher share the VM by time (point 5): the owner starts a rollback with
  `rollback-start.sh`, enters the logins again, and ends it (its labelled container stopped) before the next dispatcher
  run, whose sweep removes the logins and every other container the rollback started. docs/ai-factory.md "Build VM"
  says so once #0-277's pull request changes it.
- A task's code can start a container labelled `factory.rollback`: that run's end-of-task sweep removes it, and it
  stops the next runs only if the dispatcher is killed before its sweep; a refusal the owner clears with `cli.mjs
  sweep`, never a leak; accepted in v0.
- ADR-0060's Consequences, "the task image is the devcontainer image built on the VM", now read: built on the VM from
  the product's task configuration (point 6); ADR-0060 carries a pointer here.
- The dispatcher runs from `/opt/factory-checkout` (point 3): the dispatcher's own clone of `factory` in its home
  is retired, `install-builder-app.sh`'s `check-app` path moves with it, and the checkout's fetch is root's (no longer
  through the egress chain as `dispatcher`), a choice `provision.sh` states.
- A reviewer recognises a violation as: a `docker`, `devcontainer` or container command run as `dispatcher`; a sudo
  rule wider than the two programs, or one for `factory`; a secret in such a command's arguments; a git run as
  `factory` on the VM; a file the dispatcher writes in a directory of `factory`'s; a path of the dispatcher's state
  mounted into a container; a factory checkout `factory` can write; a mount, run argument or host command the product's
  configuration chose beyond the listed feature's; a field or value off the task configuration's list carried; a
  credential on `factory`'s daemon while the dispatcher runs; an image by tag, or one other than the ID recorded for
  the task; a call's process left running past its timeout.
