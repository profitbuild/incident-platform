# ADR-0064: An agent call of the dispatcher takes its settings from the factory alone, and its init event is its isolation check

- **Status:** Accepted (2026-11-21, by the owner, before the spike); amends ADR-0062 point 4 (the dispatcher's mounts
  gain `/etc/claude-code`); points 1, 2, 3 and 5 amended by the spike's result (2026-11-21, `factory` PR #23, rounds
  A–D in `factory`'s container): the call is F3, `--restricted` with `--add-dir /workspace`, the new decision point
  2's rule required, accepted by the owner on 2026-11-21 after the spike; points 3 and 5 amended for #0-301
  (2026-11-22: the token's channel through `apiKeyHelper`, the expected version's place); point 3 amended for #0-301
  and #0-313 (2026-11-22: the built-in plugins, `apiKeySource`)
- **Backlog:** #0-300, #0-301, #0-313
- **Date:** 2026-11-21
- **Author:** human (owner's decision on the options of `/research #0-300`, 2026-11-21, drafted in an interactive session)
- **Reversible:** yes — one mounted directory, the call's environment and flags, and one check of the dispatcher's
  agent call (#0-301)

## Context

M2's agent call (#0-301) runs a plugin agent as the main thread of `claude -p` in the task container:
`claude -p --plugin-dir /opt/factory --agent factory:<agent> --output-format stream-json`. M2.0 measured that this
runs the plugin's agent and its hook (`m2.md` Record, measurements 2, 3, 5). Two questions remain (#0-300).

**First question: what the session reads besides the factory.** Each call is a new session, and it reads two
places that the previous call of the same task can write:
- **the clone:** `/workspace/.claude/` (`settings.json`, `settings.local.json`, `agents/`, skills, hooks), Claude Code's
  "project" and "local" sources;
- **the run's volume:** `/home/<user>/.claude`, mounted by `dispatcherMounts` in `factory`'s `task-config.mjs`, the
  "user" source.

What a call can leave there for the next one: `disableAllHooks: true`, which turns off `foreground-bash`, the turn
budget (#0-206) and from M7 a second layer; hooks of its own; allow rules; an agent definition; `model`, `env` and
other keys.

The container is the security boundary (ADR-0057): the agent can already run any Bash there, and holds no credential.
So this is not a privilege the agent lacks. It is the factory's own controls and the call's repeatability, which must
depend on the factory's version, not on what a branch left in `.claude/`.

**What this ADR protects against, and what it does not** (review round 2 of these decisions):
- It holds against configuration a previous call left in files: a setting, a hook, an agent, a plugin, a memory
  file, an environment variable. That can come from an agent's mistake, from text in the repository that steers the
  model to write `.claude/`, or from the image's `ENV`.
- It does not hold against the product's instruction files a previous call of the same run wrote. F3 (point 2, as
  amended) loads the clone's `CLAUDE.md`, `.claude/CLAUDE.md` and `.claude/rules/*.md` by design, and those lie in the
  `/workspace` that a call can write. They are instructions, never a ground for the dispatcher's decisions (ADR-0060
  D6). They are tracked files, so the boundary against them is the dispatcher's commit check (#0-302) and the review,
  which see them in the branch's diff. `CLAUDE.local.md`, which is not tracked, was not measured under F3. #0-301's
  first call on the VM measures it (its AC4, moved from #0-300 AC3 on 2026-11-22).
- It does not hold against code a previous call of the same run ran in the container:
  - `claude` was installed by the image under `/home/<user>/.local/bin`, which the agent's user owns. Since ADR-0065
    it is root's `/usr/local/bin/claude`, which the agent's user cannot write, but root in the container can (next
    line);
  - the agent holds the Docker socket, so it can act as root in its own container (ADR-0057, #0-285).

  Such code can change the next call's binary, and with it the init event point 3 reads. The init event is evidence
  about configuration, not about the binary.

**How far that residual reaches:**
- **A run** is one invocation of `cli.mjs run`, new or `--resume`. It is not one `runId`, which a task keeps across
  its resumes (M2.5, M2.6).
- **A container lives one run.** The invocation makes it from a fresh clone of the base, and sweeps the daemon at
  its end (`factory` v0.1.1, `cli.mjs` steps 8 and 10). A resume, by branch or by `runId`, always makes a new
  container from the recorded image ID.
- **Review fixes are a new run.**
- So the container's own filesystem (`~/.local`, the image's layers as the container changed them, the files outside
  `/workspace`) and the `~/.claude` volume reach no other run.
- **Two carriers ADR-0062 accepted do cross runs** (its Consequences, #0-285):
  - the shared `factory-dispatcher-m2` volume (`~/.m2`), where a run can replace a Maven plugin's jar that the next
    run's agent and gate then execute;
  - the daemon's image store and build cache, where a task's code can change what the next build makes and what an
    image ID points to on disk, the layer that installs `claude` included.

  Besides them, the branch passes: the dispatcher's commits (#0-302), which the review reads.
- **The boundaries that hold against code are outside the container:**
  - the dispatcher's check of each call's commit, in the task's repository with the dispatcher's git (#0-302);
  - the pull request's CI, on fresh runners;
  - the review;
  - the push, which only the dispatcher makes.

  The path gate and the test gate run inside the task container (M2.3). Their answers are held to a schema, but they
  count only against honest code: code from an earlier call of the same run can make them answer green.

**Second question: how to keep `CLAUDE.md`.** The agent must still load the product's `CLAUDE.md` natively, the way
the plugin's agents learn the product (#0-299). Claude Code ties both to one source. The Agent SDK's table of setting
sources (https://code.claude.com/docs/en/agent-sdk/claude-code-features.md) lists, for `"project"`: "Project
`settings.json` and hooks; project CLAUDE.md and `.claude/rules/*.md`; project skills, commands, and subagents". So
`--setting-sources user` drops `CLAUDE.md`. `--bare` skips hooks, plugins' discovery and `CLAUDE.md` (cli-reference),
so neither fits.

**Third question: what replaces ADR-0058's probe.** ADR-0058 is the old path's isolation check: a hook that records
the `agent_type` of a probe command. The dispatcher's path has no such hook. Each call already gives the `stream-json`
init event, whose fields are, per `SDKSystemMessage` (https://code.claude.com/docs/en/agent-sdk/typescript.md):
- `agents`, `tools`, `model`, `permissionMode` and `claude_code_version`;
- `plugins` and `plugin_errors` ("a plugin that didn't load and is absent from `plugins`, or a plugin that loaded
  without one of its parts, such as its hooks file").

It has no field for hooks or for the sources of settings.

## Decision

1. **The factory's managed settings, read-only, on the whole of `/etc/claude-code`.** The dispatcher mounts a
   directory of its checkout read-only on `/etc/claude-code` of every task container, beside `/opt/factory`.

   It is the whole directory, not one file. `managed-settings.d/*.json` merges with `managed-settings.json`
   (https://code.claude.com/docs/en/managed-settings.md). The task image is built from the product's Dockerfile, and
   #0-284 checks its label, not its files, so the mount covers anything an image or its build cache put there.

   The file holds:
   - `allowManagedPermissionRulesOnly: true`. Per settings-reference it "ignores `allow`, `ask`, and `deny` rules in
     user, project, local, and `--settings` files, ignores `--allowedTools`", so the call's permission rules live
     here and nowhere else;
   - `strictPluginOnlyCustomization: true` (amended by the spike: Claude Code 2.1.328 reports the object form, with
     each kind named, as "present but invalid" and treats it as `true`, so the value is written as `true`): skills,
     agents, hooks and MCP blocked "from user and project sources", the plugin's kept;
   - `strictKnownMarketplaces: []`, so the clone's or the volume's `extraKnownMarketplaces` and `enabledPlugins`
     enable no second plugin. A plugin's hooks, agents and MCP pass `strictPluginOnlyCustomization`, and only
     `--plugin-dir`'s plugin is the factory's. Measured: `--plugin-dir` still loads under it (point 2, as amended);
   - `disableAllHooks: false`. Per settings precedence ("managed settings, command line, project local, shared project,
     user", settings.md) a managed value is the one left;
   - the dispatcher's permission rules.

   It holds neither `allowManagedHooksOnly` nor `disableSideloadFlags`:
   - per hooks.md, `allowManagedHooksOnly` blocks "user, project, local, and plugin hooks", which would drop
     `foreground-bash`;
   - `disableSideloadFlags` rejects `--plugin-dir`.

   The agent runs as the image's `remoteUser`, not root, and cannot change a read-only bind mount.

   **This amends ADR-0062 point 4.** The dispatcher's mounts gain this directory, read-only on `/etc/claude-code`.
   It is compared exactly after `up` like the others, and #0-284's closed `HostConfig` table holds it among "the
   mounts of the list".

   The managed settings are the container's, not one call's: within a task, every agent runs under the same
   permission rules. What differs between agents is their definition's `tools` and, under `--restricted`, `--tools`.
2. **`--restricted` on top, if the spike shows it keeps what the call needs.** `--restricted` "loads only managed
   settings and `--settings`" and "confines the built-in file tools to the working directories" (cli-reference,
   Claude Code v2.1.248 or later). It would drop the clone's and the volume's settings files entirely, so no key of
   theirs (`model`, `env`, `apiKeyHelper`, …) is read. The spike (#0-300) measures, on Claude Code 2.1.328 in
   `factory`'s container and then on the VM's:
   - whether it still loads the clone's `CLAUDE.md`, checked with a marker the model must repeat;
   - whether `--plugin-dir` and `--agent factory:implementer` still work;
   - whether the plugin's hook still refuses `run_in_background` with Bash named in `--tools`;
   - that without Bash in `--tools` the agent has none;
   - that the following, planted in the clone's `.claude/` and in `~/.claude`, all take no effect:
     - a `disableAllHooks: true`, a hook and an `implementer.md`;
     - an `env` block, e.g. `CLAUDE_CONFIG_DIR` and a `CLAUDE_CODE_*` variable;
     - a second plugin enabled through `extraKnownMarketplaces` and `enabledPlugins`;
     - and, in `~/.claude` and `$HOME`, `~/.claude/CLAUDE.md`, `~/.claude/rules/`, an output style and
       `~/.claude.json`: user memory and state, which are not settings, last across a run's calls and never show
       in the branch's diff.

   The rule, decided now:
   - **If `--restricted` keeps `CLAUDE.md` and the plugin, the call uses it** with `--tools` naming each tool the
     agent's frontmatter names. Bash then comes only through `--tools`, which the init event check (point 3) holds,
     so the turn budget cannot drop unnoticed.
   - **If not, the call runs without it**, on point 1 alone, but only if the spike shows that none of the planted set
     takes effect. That includes the keys that merge across sources rather than being replaced (`env`,
     `enabledPlugins`, `extraKnownMarketplaces`, `permissions.additionalDirectories`), which pinning in the managed
     file cannot close.
     - If any of them does take effect, point 1 alone is not enough. That is a new decision of this ADR's
       amendment.
     - Should user memory or state take effect (`~/.claude/CLAUDE.md`, `rules/`, `~/.claude.json`), the user's
       Claude Code state is made fresh for each call: the `~/.claude` volume, and `~/.claude.json` in `$HOME`, which
       lies outside that volume.
     - The amendment lists the settings keys the managed file pins. Each later version of Claude Code is re-measured
       at its pin (#0-249, #0-283), since a key added by a new version would be read from the clone.
   **Amended with the spike's result** (2026-11-21, `factory` PR #23, `dispatcher/testing/spike-0-300.mjs`; Claude
   Code 2.1.328 in `factory`'s container, the managed settings above in `/etc/claude-code`; each round's planted
   clone and `HOME` in `m2.md`'s Record):
   - **F1 (point 1 alone) fails.**
     - The `env` of the clone's `.claude/settings.json` reaches the tools (`CLAUDE_CODE_PLANTED=1`).
     - The user's `env` moves Claude Code's own configuration directory (`CLAUDE_CONFIG_DIR`, the login with it).
     - The user's memory, rules and output style take effect.

     Hooks, agents, plugins and MCP of both sources took no effect, and neither did `disableAllHooks: true`. But
     `env` merges across sources and cannot be pinned. So by this point's rule, point 1 alone is not enough.
   - **F2 (`--restricted`) holds every planted element out, but loads none of the clone's `CLAUDE.md`.**
   - **F3, F2 with `--add-dir <the clone>` and `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`, `cwd` the clone:**
     - it loads the clone's `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md` and an `@` import;
     - no planted element takes effect, of the clone or of the user: `env`, hooks, agents, a second plugin, a skill,
       `.mcp.json`, a command, memory, rules, output style;
     - the factory's plugin loads under `strictKnownMarketplaces: []`.

     That the clone's and the user's settings are not read rests on three observations (rounds C and D):
     - `printenv CLAUDE_CODE_PLANTED` is empty;
     - `output_style` is `default`;
     - no marker of the user's memory or rules came back.

     Round D's D1 (F3's flags, no `--agent`, the clone's and the user's `disableAllHooks: true`) shows the factory's
     hook blocking a background call. It does not show the settings unread: the managed `disableAllHooks: false`
     wins by precedence, as F1 had already shown.
     - **F3b** (the clone only by `--add-dir`, an empty `cwd`) loses the `@` import.
     - **F4** (`--append-system-prompt-file`) brings only the root `CLAUDE.md`, as the Alternatives expected.
   - **Decided: the call is F3:**
     ```
     docker exec <task ID> /usr/bin/timeout … /usr/bin/env -i <point 5's list>
       /usr/local/bin/claude -p --plugin-dir /opt/factory --agent factory:<agent> --restricted
       --tools <the agent's frontmatter tools>
       --add-dir /workspace --output-format stream-json --verbose --json-schema <schema> --permission-mode dontAsk
       --max-turns <n>
     ```
     `cwd` is `/workspace`. The prompt goes on stdin: `--tools` takes several values and would take an argument
     after it as one of them. `--tools` is built from the agent's frontmatter `tools`, never a copy of them.
   - **Known limit:** a `CLAUDE.md` in a subdirectory of the clone loads in none of the forms. Today this product has
     none (one root `CLAUDE.md`, no `@` imports, no `.claude/rules/`). A product that relies on subdirectories'
     `CLAUDE.md` would not reach its agents through them.
   - **Not measured in `factory`'s container, measured on the VM in a task container (#0-301 AC4, moved from #0-300
     AC3 on 2026-11-22):**
     - the exact argv with `--agent factory:implementer`, as `docker exec` runs it. Its hook result is today an
       inference from D1 (no `--agent`) and round A's F2 (with `--agent`, without `--add-dir`). The VM's prompt asks
       for a background call the implementer's text does not refuse;
     - `result.subtype` of a call with `--agent`, since D2's `--max-turns 1` call with `--agent` exited 1 for a
       reason the record does not show;
     - the init event's `tools` on the VM's Claude Code.
3. **The init event of every call is checked whole, before its answer is read.** The run stops when anything differs
   from what the dispatcher expects:
   - `agents` holds `factory:<agent>`, and no plugin agent but the factory's;
   - `plugins` is exactly one entry, `factory` at `/opt/factory`, and `plugin_errors` is absent; *amended for #0-301
     (2026-11-22):* besides it, Claude Code's own built-in plugins (`path` `"builtin"`), which every call on 2.1.328
     loads, five of them (the spike's rounds and #0-313's measurement 1): exactly one entry that is not built in,
     `factory` at `/opt/factory` (`factory@inline`), and the built-in ones equal to a closed list of their names the
     factory keeps beside its expected Claude Code version (an entry carries `name`, `path` and `source`, no version),
     re-measured at a version bump; any other entry stops the run;
   - from #0-313 on, `apiKeySource` is `"apiKeyHelper"`. Measured 2026-11-22: `"apiKeyHelper"` for the managed helper
     (also with a planted user-settings helper, which `--restricted` ignores), `"none"` without a credential and
     `"none"` with `ANTHROPIC_AUTH_TOKEN` in the environment, whose Bearer header is still sent. So the field shows a
     missing or replaced helper, not every credential that leaves: `ANTHROPIC_API_KEY`, and an environment token next
     to the helper, were not measured. What keeps a credential of the environment out of the call is point 5's
     `env -i`, not this check;
   - `tools` equals the expected list for that agent on the pinned Claude Code, re-recorded at a version bump (the
     expected version and these lists are the factory's, beside its managed file; Lint Workflows compares the version
     with the product's `.devcontainer/claude-code.pin` through `check-factory-copies.rb`, decided for #0-301 on
     2026-11-22, ADR-0065)
     (`m2.md` M2.2). Under F3 it is exactly the `--tools` list (D2: Grep and Glob next to Bash, unlike M2.0's call
     without `--tools`), and nothing else: a tool beyond it, such as an `mcp__…` tool of an account's connectors
     that appeared in some calls on the owner's login, stops the run;
   - `mcp_servers` is empty. The factory's plugin carries no MCP server today; a plugin change that adds one needs
     this check amended first;
   - `model` and `permissionMode` are the call's;
   - `claude_code_version` is the pinned one.

   This is the dispatcher's path's isolation check, in #0-301's agent call. It reads what Claude Code reports, never
   the model's answer, as ADR-0058 decided for the old path. It is evidence about the configuration the session
   loaded, not about the binary that reports it (Context, "What this ADR protects against").

   Each call's `docker exec` targets the container by the ID the daemon assigned and the post-`up` check held, never
   by a name or label, as `factory`'s `execInTask` already does (`docker exec … container.id`). A container replaced
   under the same name or label is not the one the call reaches, and the call fails.
4. **The plugin's hooks are measured once per pinned Claude Code version, not probed in every call.** The init event
   shows no hooks; only `plugin_errors` shows a hooks file that did not load. The hook's behaviour (M2.0's
   measurements 3, 5, 6) is re-measured at each version bump with the pin, as a step of #0-249/#0-283's bump. So are
   Claude Code's built-in plugins, which every call loads (point 3 as amended for #0-301): the bump records their
   names and what each carries (hooks, agents, MCP), as nothing in a call shows their hooks.
5. **The call's environment is closed.** The task image's `ENV` comes from the product's Dockerfile (or its build
   cache), and ADR-0062's `containerEnv` list does not hold it. So the image could set a variable that moves or adds
   a source of Claude Code's configuration, such as `CLAUDE_CONFIG_DIR`, or a `CLAUDE_CODE_*` variable, around
   point 1. The call runs as `docker exec <task ID> /usr/bin/timeout -s TERM -k <grace> <limit> /usr/bin/env -i
   <name>=<value>… claude …`:
   - ADR-0062 point 7's `timeout` comes first and `env -i` after it, both by absolute path, so neither is found
     through a `PATH` the image or the agent set;
   - `env -i` then takes a closed list and no other variable.

   The list holds, each as a literal the dispatcher writes, never a value read back from the container:
   - `HOME` and the locale;
   - a `PATH` the dispatcher sets: the system directories only, with no `~/.local/bin` (ADR-0065: `claude` is
     `/usr/local/bin/claude`, and the call names it by absolute path);
   - the `containerEnv` keys and values ADR-0062 point 4's list accepted, from the task configuration the dispatcher
     checked. Today these are `TESTCONTAINERS_HOST_OVERRIDE` and `TESTCONTAINERS_RYUK_DISABLED`, without which the
     agent's own Testcontainers tests fail under rootless Docker while the gate's pass;
   - `DISABLE_AUTOUPDATER=1` and `DISABLE_UPDATES=1`, the image's (ADR-0065), which `env -i` would otherwise drop, so
     Claude Code does not update itself during a run and fail point 3's version check;
   - `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`, for F3's `--add-dir /workspace` (point 2, as amended);
   - what the call itself needs to reach the model: `ANTHROPIC_BASE_URL`, the proxy's address (decided for #0-301,
     below); the task's token is not in this list.

   `CLAUDE_CODE_MANAGED_SETTINGS_PATH` is one of the variables this closes. Claude Code 2.1.328 reads it as the
   folder of its managed settings, so an image's `ENV` could move them. The spike measured that `env -i` keeps it
   out, and that a settings file's `env` setting it does not move them either.

   These literals are command-line arguments of `env`, which any process in the container can read (`ps`,
   `/proc/<pid>/cmdline`), and so can anyone holding the socket. So the list is for values that are not secret. A
   credential, should the call ever need one in the container, never goes in an argument: #0-301 decides its channel.
   (Today the container holds none, ADR-0060.)

   **Decided for #0-301 (2026-11-22, the owner's K2; built by #0-313; amends ADR-0062 points 4 and 5: one more mount,
   and the one credential on the daemon):** the container holds no Claude key, only its
   task's token for the dispatcher's proxy (ADR-0060 D4). `ANTHROPIC_BASE_URL`, the proxy's address, is a literal of
   the list (no secret). The token reaches Claude Code through `apiKeyHelper` in the managed settings, a command that
   prints a file the dispatcher mounts read-only into the task's container (its path in the managed file, its mount in
   the exact comparison and the `HostConfig` table), so it is in no argument and no environment `env -i` would clear.
   Claude Code sends the helper's output in both `Authorization` and `x-api-key` (its authentication documentation),
   and the proxy reads either. Code a call runs can read the file, as it can read anything of its container: what a
   leaked token yields is the proxy's, from the VM only and only while the task runs. #0-313 measures first that
   `apiKeyHelper` from the managed settings is read under F3's `--restricted`; if it is not, this point is amended
   before any code.

   This is an allowlist, not a denylist, as `factory`'s `childEnv` (`dispatcher/src/process/child-env.mjs`, #0-276)
   builds every child process's environment on the VM. One difference: there the values come from the dispatcher's
   own environment; here they come from its configuration.

   Until ADR-0065, the image installed `claude` with the native installer in `~/.local/bin`, which is the agent
   user's: the binary's part of the residual named in the Context.
   Claude Code run by absolute path from a read-only mount the factory provides, owned by root and at the pinned
   version, would close the binary's part of that residual. That is the direction for #0-249/#0-283, which change
   how Claude Code is installed and pinned anyway. It does not close the in-container root through the socket
   (#0-285).
   *ADR-0065 (2026-11-21, #0-249/#0-283)* took the binary's part without a mount: the image installs the pinned
   version from Anthropic's signed manifest as root's `/usr/local/bin/claude`, `~/.local/bin` is off `PATH`, and
   `DISABLE_UPDATES=1` is set. The call names `/usr/local/bin/claude` by absolute path (a login shell's `~/.profile`
   still adds `~/.local/bin`). The mount stays an option, for one source of the version.
6. **Where it is written:**
   - #0-301 writes:
     - the managed file in `factory` (it replaces the `settings/autopilot.json` #0-301 named);
     - its mount, and its place in the mount comparison and the `HostConfig` table;
     - point 5's environment and its order with `timeout`;
     - the call's flags, as point 2's measurement decides;
     - point 3's check;
   - #0-300 holds the measurements, in `m2.md`'s Record, and this ADR's amendment with their result.

## Alternatives considered

- **`--setting-sources user` and the clone's `CLAUDE.md` passed by `--append-system-prompt-file`.** A copy, not
  Claude Code's loader: it loses the subdirectories' `CLAUDE.md`, the `@` imports and `.claude/rules/`. The agent
  would then know the product differently from a session of the owner's, and the dispatcher would read the clone's
  text into a prompt. Kept only as the last resort, should neither point 1 nor point 2 keep `CLAUDE.md`, which would
  be a new decision.
- **Hiding `/workspace/.claude` under an empty mount and clearing `~/.claude` before each call.** Git in the clone
  would see `.claude/`'s tracked files as deleted, so #0-302's commit of the call could carry their deletion; and it
  is a second mechanism beside managed settings.
- **`allowManagedHooksOnly` with `foreground-bash` moved into the managed file.** It blocks every plugin hook, so the
  plugin would no longer carry its own guard (#0-299's decision, ADR-0060 D5 as amended), and the hook would live in
  two places.
- **A `SessionStart` hook of the plugin as a liveness probe read from `--include-hook-events`.** It checks every call,
  but adds a mechanism. The hooks can change only with Claude Code's version, which is pinned, so measuring them at
  the pin covers the same change.
- **Amending ADR-0058 instead of a new ADR.** ADR-0058's mechanism (a hook, a symlink, a probe command) stays on the
  old path until M4 (#0-290). The dispatcher's check is another mechanism in another place, and folding it into
  ADR-0058 would blur which path each holds.
- **No isolation, the call as M2.0 measured it.** The factory's controls would hold only as long as no branch writes
  `.claude/`; refused.

## Consequences

**What becomes true:**
- An agent call's settings, permission rules, hooks and agents come from the factory's checkout (`/opt/factory`, the
  managed directory) and from the call's own flags. The product contributes its `CLAUDE.md` and its rules files, read
  as context, never as a ground for the dispatcher's decisions (ADR-0060 D6).
- The old path keeps ADR-0058 until M4. ADR-0058 says so: "superseded for the dispatcher's path by ADR-0064".
- **Accepted residual:** code a call ran in its container can change a later call of the same run (its binary,
  `~/.local`, the files outside `/workspace` and `~/.claude`), as root through the Docker socket if need be.
  - Across runs it reaches through `~/.m2` and the daemon's image store and build cache, which ADR-0062 accepted
    (#0-285), and through the branch.
  - The boundaries against it are outside the container: the dispatcher's commit check, the pull request's CI, the
    review and the push. The in-container gates are not among them (Context).

**What every later change must respect:**
- A permission rule of the call lives in the managed file. A rule passed by `--settings` or `--allowedTools` is
  ignored under `allowManagedPermissionRulesOnly`. The review zone (M6.2, #0-294) runs on a VM without Docker,
  with no task container the dispatcher mounts. Whether its sessions use the same mechanism (managed settings of
  their own, on that VM) is M6.2's to decide.
- Bash reaches an agent only through its definition's `tools` and, under `--restricted`, `--tools`.
- A Claude Code version bump re-records the expected `tools` and re-measures the plugin's hooks.
- A container lives one run (one `cli.mjs run` invocation), a resume always makes a new one, and review fixes are a
  new run. A change that keeps a container across runs (through a review, or a crashed invocation's container kept
  on resume) widens the residual above, and needs this ADR amended first.

**Left open:**
- point 2's VM part: the exact F3 argv with `--agent` through `docker exec`, its `result.subtype`, and the VM's Claude
  Code (#0-300 AC3), moved to #0-301's first call on the VM (2026-11-22): it needs a Claude credential in the task
  container, which ADR-0062 point 5 keeps off the daemon until M3.5's proxy; how that call gets one is #0-301's first
  decision, taken on 2026-11-22: the task's token for #0-313's proxy (point 5 as amended);
- `CLAUDE.md` in a clone's subdirectories, which F3 does not load;
- Claude Code's own defaults that no source shows;
- Claude Code from a factory-provided read-only mount (#0-249, #0-283);
- the daemon reach of a task's code (#0-285).

**How a reviewer recognises a violation:**
- a call made without the managed mount, or the mount writable or only on one file;
- a call whose environment is not the closed list (no `env -i`, a variable inherited from the image, or the
  accepted `containerEnv` or `DISABLE_AUTOUPDATER` missing), or `timeout` and `env` found through `PATH`;
- `strictKnownMarketplaces` missing from the managed file, or `plugins` checked as "holds" rather than "is exactly";
- a call that reaches its container by name or label rather than by the checked ID;
- a container kept across runs;
- the mount missing from the comparison after `up` or from the `HostConfig` table;
- a permission rule outside the managed file;
- `allowManagedHooksOnly` or `disableSideloadFlags` in it;
- an init event field read without the run stopping on a difference;
- the answer read before the init event's check;
- a decision of the dispatcher taken from the clone's `.claude/`;
- from point 2 as amended:
  - a call without `--restricted`, without `--tools`, or with `--tools` not built from the agent's frontmatter;
  - a call without `--add-dir /workspace`;
  - the prompt passed as an argument rather than on stdin;
  - `tools` not compared exactly to `--tools`, or `mcp_servers` not checked empty;
  - `strictPluginOnlyCustomization` written as an object.
