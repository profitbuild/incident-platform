# ADR-0060: A dispatcher on the build VM runs each agent of a task in a container that holds no credential

- **Status:** Accepted (2026-11-18, by the owner; D1–D8 below chosen by the owner on 2026-11-17, in an
  interactive session); D5 amended on 2026-11-18 by backlog #0-269 (`factory`'s code is
  written with an app of its own), its open points settled on 2026-11-19 (where the app's key lives, how the session
  starts)
- **Backlog:** #0-267 (stage 4.1); stage 4's later items are created as their turn comes, each from its step of the
  plan `.ai/context/migration/stage-4.md`
- **Date:** 2026-11-17
- **Author:** human (owner's decisions, drafted in an interactive session)
- **Reversible:** yes — today's path (`/backlog-autopilot` in the devcontainer) stays as the rollback until stage 5's exit

## Context

ADR-0055 stage 4: "Dispatcher v0, in the new `factory` repository: the container has no token; push, PR and commit
trailers by the dispatcher (#0-212), the trace of each agent call (#0-204) and its transcripts' summary (#0-205's
script); builder-app (not on `factory`); the gate contract, incident-platform's adapter the first". Exit: 3 PRs opened
by it.

Today one Claude Code session in the devcontainer runs `.claude/workflows/backlog-autopilot.js`; its scripts run
through `factory-ops`, one call each (ADR-0053), a model that relays their JSON (it garbled it on Haiku, #0-266, and
shortens the gate's summary on Sonnet). Only the shipper pushes and runs `gh pr create/edit/ready`; the bot's PAT is in
the container's `incident-platform-gh` volume, readable by any code `./mvnw` runs (#0-116), and the implementer's
unrestricted Bash could push the run's branch (its prompt alone says not to). The state the factory trusts (`LOCK`,
`state.json`, `ops-calls/`) is in the working tree the agents' git commands reach (#0-236). Claude Code documents that
`claude -p` runs workflows but waits for them 10 minutes by default, that a private plugin cannot be cloned without a
git credential, that its transcript format "can break on any release" (capture `stream-json`), and that products built
on it should use an API key from the Console rather than a subscription's OAuth token.

Claude Code's documentation, read 2026-11-17: the 10-minute wait of `-p` for a workflow and
`CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS` (code.claude.com/docs/en/workflows.md); "Claude Code has no git token of its
own" for a plugin marketplace (code.claude.com/docs/en/plugins/host-marketplace.md); the transcript format "can break on
any release" (code.claude.com/docs/en/sessions.md); API keys for products built on it, OAuth "designed to support
ordinary use" (code.claude.com/docs/en/legal-and-compliance.md); `ANTHROPIC_BASE_URL`, `--json-schema`, `stream-json`
and `--plugin-dir` (code.claude.com/docs/en/headless.md, cli-reference.md).

## Decision

- **D1. The dispatcher runs the phases itself.** Each agent call is one `claude -p --agents … --json-schema …
  --output-format stream-json` inside the task's container (`docker exec`); the test gate is run by the dispatcher
  (`docker exec <gate command>`), whose JSON it reads itself. The control flow of `backlog-autopilot.js` (phases,
  schemas, rounds, `stopItem`, the breaker) is ported with its tests (`test-autopilot-workflow.mjs`'s fake `agent()`).
  No `factory-ops`: ADR-0053 is superseded when stage 4 exits.
- **D2. Node, ES modules, built-in modules only, tested with `node:test`**, at `.node-version`. No npm (the Agent SDK
  waits until a callback is missing).
- **D3. builder-app pushes and opens the PR.** Its private key is a file of mode 0600 owned by a new VM user
  `dispatcher`, not `factory` (rootless Docker runs as `factory`, so a container escape lands there). Installation
  tokens are minted per use (JWT RS256 by `node:crypto`), never written into a container. Rotation: a second key is
  added, the dispatcher switched, the old key deleted. Stage C moves the key to the provider's secret store.
- **D4. Claude's credential stays outside the container.** A Console API key, in a workspace with a spend limit, is
  held by a proxy of the dispatcher on the VM; the container gets `ANTHROPIC_BASE_URL` pointing at it and a token of its
  own task, which the proxy checks (step 4.6). The proxy logs each request's usage.
- **D5. `factory` is a public repository of `profitbuild`, without builder-app.** In stage 4 it gets the dispatcher,
  `scripts/factory-admin/build-vm/`, the product-neutral scripts and the agent definitions; the review rules split in
  stage 5. A task loads the factory through a read-only mount of a `factory` checkout at the pinned tag, passed as
  `--plugin-dir`; a run whose `stream-json` init event lists a `plugin_errors` entry stops. The task image built in CI
  (GHCR) is stage C's.
  **Amended (2026-11-18, #0-269, the owner): who writes `factory`'s code.** The rulesets bind everyone but an admin,
  and a session that holds the owner's token is an admin: there only the session's deny rules, which match command
  text, keep it from a merge, a ruleset or a tag. So the code of `factory` (4.2 onwards) is to be written by a session that
  holds neither the owner's token nor a builder's, but the token of a GitHub App of its own, `profitbuild-factory-dev`:
  installed on `factory` alone, with Contents and Pull requests read and write and Metadata read, nothing else (no
  Workflows, no Administration, no Checks, no Statuses), its key where neither the autopilot's devcontainer nor the
  build VM's task code reaches it. The app is no bypass actor, so the rulesets bind it: GitHub refuses it a push to
  `main`, a review that counts, a merge of a pull request the owner has not approved since its last push (`main`'s
  ruleset: the code owner's review, `require_last_push_approval`, `dismiss_stale_reviews_on_push`; a PR the owner
  approved it may merge, its code read), a change to `.github/workflows/` (no Workflows permission) and, through a
  ruleset of its own that restricts tag creation to the admin role, a tag; the ruleset `tags` keeps no bypass.
  Contents write still lets it publish a release, and its assets, on a tag that exists: harmless while a product
  loads the git checkout at its tag, not a release's assets. A branch the app pushes is a pull request of the same
  repository, whose CI runs with the repository's Actions secrets and needs no approval; the missing Workflows
  permission guards `.github/workflows/`, not the scripts they run. So `factory` holds no Actions secret a
  `pull_request` run can read: a secret its CI needs lives in an environment limited to `main`, as `scans` does in
  incident-platform. Merging, tagging and every setting stay the
  owner's. ADR-0055 holds as decided: no builder credential (neither the bot's token nor builder-app) is on `factory`,
  so no agent that builds a product can propose a change to the factory's own rules. Text and plans are still
  prepared in the owner's sessions on the Mac, under the denies of their project's settings, and `factory` carries a
  copy of those denies for a session started in its clone. Where that key lives and how its session starts (settled
  by #0-269 on 2026-11-19): the key stays on the owner's Mac, outside every repository
  (`~/.config/profitbuild-factory-dev/app.pem`, mode 600), not in the volumes of a devcontainer as first proposed; the
  session works in `factory`'s own devcontainer, on a clone in a volume of its own, since a workspace bind-mounted from
  the host would let the container change what the host runs next to the key, or plant a git hook the owner's next
  `git` runs with the admin token. `factory`'s `dispatcher/bin/dev-token.mjs`, run on the host from the owner's clone on
  `main`, mints the hour's token, checking against GitHub that the installation and the token hold exactly the three
  permissions and reach `factory` alone, into a directory the devcontainer mounts read-only. Its limits are named in
  `factory`'s README and #0-269's Result.
- **D6. The product's adapter is `.factory/adapter.json`**: repository, gate command, changed-paths command, queue
  source (`BACKLOG.md` until stage 7), protected-paths file, `trustedPaths` (the product's scripts the dispatcher runs
  from `main` and a task branch may not change; for incident-platform `scripts/factory/`), task image, profile,
  `factory` version. `factory` holds its
  JSON Schema and the gate contract (today's `run-tests.sh` JSON: `pass`, `fixable` or `stop`, an artifact, a summary).
  The dispatcher runs product code only from `main` (`next-item.sh`); code of a task branch runs only in its container.
- **D7. Before a push the dispatcher checks, outside the container:** the branch descends from the base it recorded;
  no Owner-only path changed (changed-paths from `main`), else stop or the owner's label; no path of the adapter's `trustedPaths` changed;
  it writes the `Factory-Run` and `Factory-Agent` trailers and the per-call trace (head before and after each call);
  the PR body keeps the fields `audit-data.sh` reads. Task state lives in the dispatcher's own directory, outside any
  repository, one `flock` per task (#0-261).
- **D8. v0 starts by hand** (`dispatcher run [#0-N]`), one task at a time, in shadow; a timer comes with stage 7's
  queue. #0-261's restart and idempotence requirements hold from v0 (an existing PR for the branch is reused).

## Alternatives considered

- **Wrap today's workflow** (`claude -p "/backlog-autopilot"` in the container, push from outside): least work, but
  `factory-ops` stays, and #0-204's trace and #0-212's `Factory-Agent` would come from the workflow's journal inside the
  container, which an agent can edit; also the 10-minute wait of `-p` against runs of 7 to 19 minutes (#0-205's baseline).
- **The Agent SDK** (in-process `canUseTool`): an npm dependency to pin, for callbacks the hooks still give.
- **Bash or Python**: retries, per-task state and GraphQL limits in Bash are brittle; Python adds a language the
  repository does not use.
- **Keep the bot's PAT in v0**: a long-lived token, and stage 4 would be rewritten for builder-app anyway.
- **A subscription token (`setup-token`) or a bare API key in the container**: the first is "designed to support
  ordinary use"; both put a usable secret where `./mvnw` reads everything (#0-116).
- **A private `factory`, or a git-hosted plugin**: the container has no git credential, and builder-app is never on
  `factory`, so the dispatcher would need a deploy key of its own.
- **Move everything to `factory` at once**: two factory changes in one stage; the review rules are split by stage 5.

## Consequences

- The task container holds no GitHub and no Claude credential; what it still reaches is the network its allow-list
  gives (ADR-0057) and the proxy's address. #0-236, #0-251, #0-253, #0-213, #0-217, #0-226, #0-228 and #0-234 are closed
  by stage 4's exit, not hardened.
- **Amends ADR-0055** (its "Local first, portable" decision and stage 4's row): until stage 7 the dispatcher keeps the
  state of its tasks in `$FACTORY_STATE_DIR` on the VM (the queue and the PRs stay in GitHub); until stage C the task
  image is the devcontainer image built on the VM, not one built in CI and pulled from GHCR; the per-call summary is
  made from the `stream-json` records, the successor of #0-205's `run-summary.sh`, which reads files Claude Code calls
  internal.
- ADR-0052 (`FACTORY_BOT_LOGIN`) and ADR-0034 (the ruleset's actors and bypass) are amended when builder-app lands
  (stage 4.2); ADR-0050 (the agents' command lists: no git writing commands once the dispatcher commits, 4.4) and
  ADR-0058 (the isolation probe's successor, 4.4) are amended by 4.4; ADR-0053 is superseded at stage 4's exit.
- `factory` has one non-admin writer, `profitbuild-factory-dev` (D5 as amended by #0-269): a new credential, a
  private key whose tokens last an hour and reach `factory` alone; its PRs wait for the owner's review like the bot's on
  incident-platform. The bot's token still reaches incident-platform only.
- `factory`'s copies of this repository's controls are compared from here, this repository leading (ADR-0061, #0-268).
- Where it lives: ADR-0060 stays in incident-platform with ADR-0050 to ADR-0059 (written before `factory` existed);
  the ADRs stage 4's items write about the factory go to `factory`.
- The PR body's audit fields and the gate's JSON are contracts: a change to either changes `audit-data.sh` or every
  adapter in the same PR.
- Open, decided in the items: the proxy's streaming and its address in the egress filter (4.6); the trailer of the
  start commit (#0-212); the exact adapter schema (4.3).
- A reviewer recognises a violation as: a credential mounted or passed into a task container, a push or `gh` write from
  inside one, product code from a task branch run outside its container, task state inside a repository, an agent's
  answer taken as the trace, or `factory` code naming incident-platform's paths or modules.
