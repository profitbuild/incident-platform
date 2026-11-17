# ADR-0055 stage 1: the organisation `profitbuild` and the transfer — DONE (2026-11-13)

A record of how stage 1 was carried out, so nobody has to guess what was done, how and why. The stages themselves,
their exits and rollbacks are ADR-0055's; the map of items per stage is `.ai/context/migration.md`. The item is
#0-237, kept in full in `BACKLOG-DONE.md` ("Details", section 0-237).

## 1. Goal and exit

ADR-0055's table, row 1:

> Organisation `profitbuild`, incident-platform transferred (its frontend not); the owner read from `repository.json`,
> not the repository's owner (#0-237); `repository-settings.rb check` | one item merged the usual way | transfer back

Why: `profitbuild` holds the factory and its products (ADR-0055, "The factory is a product of its own"): the
`factory` repository from stage 4, the new application from stage N. Only incident-platform moved;
`incident-platform-frontend` stays on the owner's account, outside the factory.

## 2. Stage 0 in brief

Exit: ADR-0055 merged and set to Accepted by the owner. Done: merged in PR #620 (`ec62b670`), Accepted 2026-11-13.
The freeze: open items that harden what a later stage removes wait as `Blocked`, each naming the stage that
supersedes it. The list lives in ADR-0055, "Stage 0, the freeze" (and items frozen later, e.g. 2026-11-17, are added
there). Rollback: revert the statuses.

## 3. What exists now

- **Organisation** `profitbuild` (free plan), the owner its only owner and only member. The name was free
  (not recorded in the repository).
- **Repository** `https://github.com/profitbuild/incident-platform` (was `lukaszplawiak/incident-platform`; GitHub
  redirects the old URLs). Every clone's `origin` is the HTTPS URL, not SSH.
- **Identities.** The owner, `lukaszplawiak`, is the one admin in `.github/repository-settings/repository.json`
  (`"admins": ["lukaszplawiak"]`); that list is now also the owner's identity for the audits and Factory guards. The
  machine account `lukaszplawiakbot` is an outside collaborator with Write on this repository only, until builder-app
  replaces it (stage 4). Its token is a classic PAT (`repo`, `read:org`, no `workflow`).
- **Settings that matter.** The ruleset of `main` (`.github/repository-settings/rulesets/main.json`): bypass by the
  admin role (`actor_id: 5`, `RepositoryRole`, `bypass_mode: pull_request`) and `dismissal_restriction` at
  `enabled: false`. Kept through the transfer: issues, PRs, environments, the collaborator, secret scanning and push
  protection, the workflow token's read-only default, `sha_pinning_required` (ADR-0020). Organisation: base permission
  "No permission", members cannot create repositories or change visibility, Actions pinned to a full SHA.
- **Files changed** (PR #623): `scripts/factory/owner-login.sh` (new), `.github/scripts/test-owner-login.sh` (new),
  `scripts/factory/audit-data.sh`, `.github/scripts/test-audit-data.sh`, `.github/workflows/factory-guards.yml`,
  `.ai/rules/audit.md`, ADR-0034, ADR-0055, `.ai/decisions/README.md`, README, `docs/ai-factory.md`, `BACKLOG.md`.
  (PR #624): `rulesets/main.json`, ADR-0034, README (badge and links), `BACKLOG.md`.

## 4. How it was done, in order

1. **PR #623 (1a, `1ec73134`, from the owner's account before the move).** `owner-login.sh` prints the one admin of
   `repository.json`: `--github <owner/repo>` reads it on `refs/heads/main` through GitHub's API (`audit-data.sh`),
   `<commit>` reads the blob with replace refs and grafts off (Factory guards, at the PR's base). Factory guards counts
   only that owner's approval. ADR-0034 amended; ADR-0055 amended with the factory-as-product decision (stages T and
   N) and set Accepted.
2. **Owner: create the organisation** `profitbuild`, the owner its only owner.
3. **Owner: transfer** (Settings → Transfer) `lukaszplawiak/incident-platform` to `profitbuild`, then in every clone
   (the Mac, the devcontainer):
   `git remote set-url origin https://github.com/profitbuild/incident-platform.git`.
   An SSH form was refused with "Permission denied (publickey)"; HTTPS is what `gh` authenticates.
4. **Owner: reinstall what is bound to the account**: Renovate (GitHub App, for the organisation, this repository
   only); check that Snyk's and the NVD key's secrets and the environments survived.
5. **Owner: organisation settings** as in section 3; `sha_pinning_required` checked still on.
6. **Owner: `ruby .github/scripts/repository-settings.rb check`** with the owner's token. It found the empty bypass
   list and the new `dismissal_restriction` (section 6). Then `ruby .github/scripts/repository-settings.rb apply`
   restored the bypass from `rulesets/main.json` (whether `plan` ran first is not recorded in the repository).
7. **PR #624 (1b, `91990164`, the first from `profitbuild`).** `dismissal_restriction` written into `main.json`,
   README's badge and links to the new URL, ADR-0034's consequences, point 4 of #0-153, #0-237's findings and rollback.
   Merged by the owner with `--admin`, which proved the restored bypass (not recorded in the repository).
8. **Owner, after #624:** Dependabot alerts on, the organisation's Actions settings set; the devcontainer rebuilt
   (`devcontainer up --remove-existing-container`). The bot's token showed as classic, its permission `push` without
   `admin`/`maintain`; a test branch it pushed (`3985c1c6`) reached GitHub and was deleted.
9. **Exit met:** full CI and Factory guards green on `main` at `91990164`.
10. **PR #625 (`77bf62a6`)** closed #0-237. **PR #626 (`b8a2b99c`)** then restructured the backlog: finished items'
    sections move to `BACKLOG-DONE.md` "Details", which is where #0-237's section now is.

## 5. Decisions made on the way, and why

- **The owner comes from `repository.json`, not the repository's owner.** In an organisation `gh repo view`'s owner
  and `github.repository_owner` are the organisation, which never labels or opens a PR: the audits would have counted
  no owner decision, silently, and Factory guards would have refused the owner's own guarded PRs. The file is a
  `.github/` path only the owner's reviewed PRs change. Exactly one admin or no owner (fail closed).
- **ADR-0034 amended**: its `admins` list is also the owner's identity, so adding an admin is a decision about who the
  owner is. GitHub's admins are compared with the file only by the owner's `check` (CI's token cannot see them).
- **`owner-login.sh` lives in `scripts/factory/`**, with the helpers CI calls, so it moves with the factory in stage 4.
  It reads GitHub or an untouched commit, never local refs that code in a session could rewrite.
- **The factory is a product of its own** (ADR-0055 amendment): one organisation holds the factory and its products;
  from stage 4 its code is in a `factory` repository on which builder-app is never installed.

## 6. What surprised us

- **The transfer emptied the ruleset's `bypass_actors`** (`[]`, confirmed in the UI): no owner PR could merge, since
  CODEOWNERS covers every path and nobody else approves. Only the owner's `check` sees it. Recorded in ADR-0034: after
  any transfer, the owner runs `check` before the next merge.
- **GitHub added `pull_request.dismissal_restriction`**, an organisation-only parameter, so `check` failed until the
  file held it. Restricting dismissals to the owner is a possible hardening, point 4 of #0-153 (stage 6a).
- **A fine-grained token owned by the owner could not cover an organisation's repository**, so the bot keeps a classic
  `ghp_` PAT with `repo` and `read:org` (not recorded in the repository; that the token is classic is).

## 7. How to verify it still holds

```bash
git remote get-url origin                                  # https://github.com/profitbuild/incident-platform.git
scripts/factory/owner-login.sh --github profitbuild/incident-platform   # lukaszplawiak
scripts/factory/owner-login.sh origin/main                 # same, from the commit
.github/scripts/test-owner-login.sh                        # the refusals of AC3
ruby .github/scripts/repository-settings.rb check          # with the owner's token: bypass, admins, settings too
gh api repos/profitbuild/incident-platform/collaborators/lukaszplawiakbot/permission --jq .permission  # write
```

## 8. Rollback

Transfer back to the owner's account (the redirects follow); `owner-login.sh` reads the same file there. Then the
owner runs `repository-settings.rb check` before the next merge, since a transfer may empty the bypass list again.
If GitHub no longer returns `dismissal_restriction` on a personal account's repository, take that key out of
`rulesets/main.json` first, so that `apply` sends only parameters GitHub accepts and can restore the bypass.

## 9. Left open

- **2FA required in the organisation** (Settings → Access → Authentication security): the owner's step. It changes no
  file and, while the owner is the only member, nobody's access.
- `audit-data.sh` takes `<owner/repo>` from `gh repo view`, the clone's remote, which code run in a session can
  repoint; stage 4's dispatcher names the repository from its environment (ADR-0055 stage 4).
- #0-153 point 4 (`dismissal_restriction` to the owner), stage 6a.
- The bot's classic PAT is replaced by builder-app's installation tokens in stage 4 (ADR-0055; the push by the
  dispatcher is #0-212).

## 10. Sources

- PRs: #620 (ADR-0055, stage 0), #623 (1a), #624 (1b, stage 1's exit), #625 (#0-237 closed), #626 (backlog layout).
- Items: #0-237 (`BACKLOG-DONE.md`, row and "Details"), #0-153 point 4 (`BACKLOG.md`), #0-212.
- ADRs: ADR-0055 (table rows 0 and 1, "Stage 0, the freeze"), ADR-0034 (amendment by #0-237, consequences), ADR-0020.
- Files: `scripts/factory/owner-login.sh`, `.github/repository-settings/repository.json`,
  `.github/repository-settings/rulesets/main.json`, README "Infrastructure Hardening", `docs/ai-factory.md`.
