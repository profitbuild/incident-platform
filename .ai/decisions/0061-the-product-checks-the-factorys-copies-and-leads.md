# ADR-0061: The product checks the factory's copies of its controls, and leads

- **Status:** Accepted (2026-11-19, by the owner); amended by #0-272 (2026-11-20: a fifth comparison, below)
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
   `.factory/adapter.json` (ADR-0060 D6).
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
