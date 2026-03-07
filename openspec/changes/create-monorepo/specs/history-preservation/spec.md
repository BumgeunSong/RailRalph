# Spec: history-preservation

## ADDED Requirements

### Requirement: Main App History via Git Subtree

The main writing app (DailyWritingFriends) MUST be integrated into the monorepo at `apps/web/` using `git subtree add`. This preserves a traceability link to the original repository's commit history. The subtree MUST be added with `--squash` by default, which collapses all upstream history into a single merge commit in the monorepo. Teams that require per-commit blame within the monorepo MAY omit `--squash`, accepting a noisier commit graph.

With `--squash`, `git log apps/web/` and `git blame apps/web/<file>` will only surface the squash commit. Per-commit history remains accessible in the archived original repository.

#### Scenario: Main app code present after subtree add

WHEN `git subtree add --prefix=apps/web <remote> main --squash` is run on the new monorepo
THEN all source files from the main app's `main` branch are present under `apps/web/`
AND `git log --oneline` shows a squash merge commit referencing the original repository

#### Scenario: Subtree commit is traceable to origin

WHEN the squash merge commit created by `git subtree add` is inspected
THEN the commit message references the original repository URL or branch
AND the commit is present in `git log` output for the monorepo

---

### Requirement: Admin and MCP Apps via Direct Copy

The admin dashboard and MCP server MUST be copied into the monorepo as fresh commits with no subtree link. Their source files SHALL be placed at `apps/admin/` and `apps/mcp/` respectively. The original commit histories of these apps are not required to be preserved in the monorepo.

#### Scenario: Admin app source present after copy

WHEN the admin app source is committed to `apps/admin/`
THEN all files from the admin app's working tree are present under `apps/admin/`
AND the commit message is `feat: add admin app`

#### Scenario: MCP server source present after copy

WHEN the MCP server source is committed to `apps/mcp/`
THEN all files from the MCP server's working tree are present under `apps/mcp/`
AND the commit message is `feat: add mcp server`

---

### Requirement: Original Repository Archiving

After migration is verified (all apps build, test, and deploy successfully from the monorepo), all three original repositories MUST be archived on GitHub. Archived repositories MUST remain readable — their PR history, issue threads, and git history SHALL be preserved. Archived repositories MUST become read-only; no further pushes SHALL be accepted.

Archiving MUST NOT occur before all of the following are confirmed:
1. All apps build and test successfully from the monorepo (phantom dependency audit complete)
2. All deployment pipelines are reconnected to the new repo and a preview deployment has succeeded
3. The team has been notified of the new repository location

#### Scenario: Repositories are read-only after archiving

WHEN an attempt is made to push a commit to an original archived repository
THEN the push is rejected by GitHub with an error indicating the repository is archived

#### Scenario: Historical content remains accessible after archiving

WHEN a developer navigates to an archived original repository on GitHub
THEN all commits, pull requests, issues, and file history are visible and browsable

#### Scenario: Archiving does not precede deployment verification

WHEN a deployment from the monorepo has not yet succeeded on a preview branch
THEN the original repositories SHALL NOT be archived
AND the migration is not considered complete

---

### Requirement: Rollback Window Preserved Until Archiving

Original repositories MUST remain live and unarchived until all migration phases are complete. This preserves a rollback path: if the monorepo migration fails at any point before archiving, the team can revert to using the original repositories by restoring their deployment pipeline connections.

#### Scenario: Rollback is possible before archiving

WHEN any migration phase fails before the original repositories are archived
THEN the team can restore the original deployment connections (Vercel or equivalent) to the original repositories
AND the original repositories remain functional for continued development

#### Scenario: No rollback path after archiving without admin action

WHEN the original repositories have been archived
THEN restoring them requires a GitHub organization admin to unarchive the repository
AND this represents the only mechanism to restore the pre-migration state
