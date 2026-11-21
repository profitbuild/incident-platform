# ADR-0061: The product checks the factory's copies of its controls, and leads

- **Status:** Accepted (2026-11-19, by the owner); amended by #0-272 (2026-11-20: a fifth comparison, below) and by
  #0-278 (2026-11-21: a copy at a path of its own, the adapter against its version's schema, the version's tag, below)
- **Backlog:** #0-268
- **Date:** 2026-11-19
- **Author:** human (the owner chose option B and the lead direction (b) in an interactive session); written by Claude Code
- **Reversible:** yes — the check is one script and one CI step; stage T's template replaces the copies it compares

## Context

`profitbuild/factory` (ADR-0060 D5) copies this repository's CI tool pins and actions' SHAs, `install-pinned-tool.sh`,
`secret-scan.sh`, `test-secret-scan.sh`, the `setup-node` action, `zizmor.yml`, `.node-version` and the owner session's
denies (`.claude/settings.json`). Renovate and `check-pinned-tools.sh` run here alone (ADR-0033), so a bump here left
`factory` on the old value with no signal, the drift of #0-122. `factory` names no product (ADR-0060 D5), so a check
comparing the two cannot live there. The review of `factory` PR #5 found the next problem: a check against the moving
`factory@main` that fails on every difference turns every pull request here red, unrelated ones included, as soon
as `factory` starts a difference; a red `main` stops the autopilot (main-guard).

## Decision

1. **What runs where (option B).** `factory` runs only what must run before a merge there: the secret scan
   (ADR-0036's job and scripts, a required check) and the test that its devcontainer's `FROM node` equals
   `.node-version`. Everything that is a copy is compared from here, by `.github/scripts/check-factory-copies.rb` in
   Lint Workflows, on a fresh clone of `factory@main`.
2. **What it compares.** Pins (`<NAME>_VERSION`, `<NAME>_SHA256`, with those of actionlint, shellcheck, zizmor and
   betterleaks required there), actions' SHAs, `COPIES` minus their notice paragraph (`# A copy of
   profitbuild/incident-platform's …` up to the next bare `#`), and every file of `factory` with that notice in
   `COPIES`. Also `setup-node` and `zizmor.yml` minus their comments, `.node-version`, and the denies both ways:
   `OPTIONAL_DENIES`, named entries only (what `factory` does not have: `repository-settings.rb`, this repository's
   `docker/` files), are neither required nor refused there; the generic `.env` denies are required.
3. **This repository leads.** On a pull request, a difference fails only if the pull request changes a file of
   `COMPARED` and `main` (the merge commit's first parent) does not have the difference already. Every other
   difference, and every push, is a warning. A copy is changed here first, then the owner mirrors it in `factory`
   and re-runs; Renovate's bumps are mirrored by hand, since Renovate stays here (a second app with Workflows write
   on `factory` would break #0-269's "no other bot or app").
4. **`factory`'s own findings are warnings.** `check-downloads.rb`, `check-runtime-setup.rb` and `check-shell.rb` run
   on the clone (`factory` has no Ruby, ADR-0060 D2); no change here causes them.
5. **The clone is outside input.** A symlink anywhere in it fails the check before anything reads it, the
   sub-checks included; a settings file that does not parse is reported by its error class only (SEC-31: the parser
   quotes the text, and the log is public). A copy's difference names a digest of the original, so a further change
   here cannot hide behind drift `main` already has.
6. **The reference moves at step 4.7** from `factory@main` to the `factory` tag the product pins in
   `.factory/adapter.json` (ADR-0060 D6). Moved to M3.6 (#0-307) by ADR-0063; the adapter itself is already checked
   against that tag's schema (the #0-278 amendment below).
7. **No deny for deleting a branch by a push** in either repository (D1): CLAUDE.md "Working style" has sessions run
   `git push origin --delete <branch>` after a merge; `main` and the tags are the rulesets'.

## Alternatives considered

- **Copy every control into `factory`** (Ruby, the four checks, Renovate there): more copies, the problem itself;
  Ruby in a repository ADR-0060 D2 keeps Node-only; Renovate an app with write on `factory`.
- **Fail on every difference** (variant (a)): drift `factory` starts turns unrelated pull requests and `main` red.
- **Compare with a commit of `factory` recorded here** (variant (c), now): a pull request here per merge in
  `factory` that touches a copy, and drift there unseen until the next bump; kept for 4.7, when the tag exists anyway.
- **Everything to stage T:** no secret scan before 4.2's code handles builder-app's key (#0-268 AC2).

## Amendment (#0-272, 2026-11-20): builder-app's permissions

`check-factory-copies.rb` also compares the `permissions` of `.github/repository-settings/apps/profitbuild-builder.json`
(what GitHub's installation of builder-app must hold, which `repository-settings.rb` compares with GitHub) with
`factory`'s `dispatcher/src/github/builder-permissions.json` (what builder-app's token asks for and is checked against),
exactly, both ways. The rule of point 3 holds: this repository leads, so a pull request here that changes the file
fails until `factory` matches, and a difference `factory` starts is a warning here; `factory`'s own test holds its file
to a literal, so a widening there fails its CI.

## Amendment (#0-278, 2026-11-21): the item lock's cases, the adapter and the factory version

- **A copy at a path of its own.** The item lock's cases, `.github/scripts/fixtures/item-lock-branches.tsv` (one rule,
  `next-item.sh`'s and the dispatcher's, ADR-0060 D8), are copied to `factory`'s
  `dispatcher/testing/fixtures/item-lock-branches.tsv`, a path of its own: `check-factory-copies.rb`'s `MOVED_COPIES`
  maps the original to it, compared as `COPIES` are, and the original is in `COMPARED` (this repository leads).
  `test-queue.sh` runs every case through `next-item.sh`'s own definition (`_backlog.sh`'s `LOCKED_BY_JQ`), and
  `factory`'s `item-lock.test.mjs` through the dispatcher's, so either side's drift fails a test (#0-278 AC11). The
  `protectedPaths` parser's half of AC11 comes with the Owner-only check before a push (M3.1, #0-305).
- **The adapter against its version.** CI's step "The adapter keeps its factory version's schema" clones `factory` at
  the adapter's `factoryVersion` and checks `.factory/adapter.json` with that version's own `checkAdapter`, the code the
  dispatcher reads it with, not a second validator here. The adapter's `gate.contract`, `gate.schema.json`, is a
  constant of that schema naming `factory`'s own `schemas/gate.schema.json`, not a file of this repository. It runs that code of `factory` in this repository's CI,
  accepted: a tag is the admin's alone and cannot move, and the job's token is read-only. Chosen over a check in
  Factory guards with its own clone (the owner's choice A(a), 2026-11-21): one clone, one validator.
- **The version's tag is `FACTORY_COMMIT`.** The same step, `verify-pins.sh` (against GitHub's API, the tag peeled) and
  `create.sh` (in the VM's checkout) refuse a `factoryVersion` whose tag is not at `provision.sh`'s `FACTORY_COMMIT`:
  two pins of one version, held equal, until #0-307 makes the adapter's the one source (the owner's choice B(c)).

## Consequences

- A pull request here that changes a compared file waits for `factory`: the owner opens the mirror PR there first.
- Drift that `factory` starts (a copy changed there first) is only a warning here; the owner's review of `factory`'s
  pull requests (and #0-270's panel) is what catches it. `factory`'s own findings show after its merge.
- A new copy in `factory` is added to `COPIES` here in the same step; a new deny here is required in `factory` unless
  it is added to `OPTIONAL_DENIES` on purpose.
- The firewall copy and the dev app's identity in two files are compared by nothing until stage T (#0-268's table).
- A reviewer recognises a violation as: a copy kept in `factory` without a notice, or listed nowhere here; a check of
  `factory` that fails a pull request here on a difference `main` already has; a value of the clone printed outside
  a finding about it.
