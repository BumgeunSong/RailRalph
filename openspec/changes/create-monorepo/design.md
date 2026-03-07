# Design: create-monorepo

## Context

**Current state**: Three related projects live in separate GitHub repositories:
- `DailyWritingFriends` — the main writing web app (Next.js/React, Supabase backend, Firebase for some features)
- `admin-daily-writing-friends` — the admin dashboard
- `daily-writing-friends-mcp` — an MCP server exposing app functionality to AI agents

All three share the same Supabase/Firebase backend but have no shared code. They are maintained independently, which creates friction when making cross-cutting changes and limits AI agent observability (agents working on one app cannot see the others).

**Constraints**:
- The main app has meaningful commit history that should be preserved
- Admin and MCP have minimal commit history — preserving it is not worth the complexity
- Each app must continue to run independently; no shared runtime coupling in this phase
- Deployment pipelines exist (likely Vercel for web/admin) and must be reconnected — this is a blocking step
- pnpm must be adopted as part of the migration (justified in proposal)

**Stakeholders**: Developers working across the three apps; AI coding agents needing full-ecosystem context; deployment infrastructure (Vercel or equivalent).

---

## Goals / Non-Goals

### Goals
- Colocate all three apps in a single GitHub repository with pnpm workspace structure
- Preserve the main app's git commit history via `git subtree add`
- Enable per-app commands from the monorepo root (`pnpm --filter <app> dev`)
- Establish an empty `packages/` directory as a placeholder for future shared code
- Archive original repos (keeping history readable) after migration is verified
- Reconnect all deployment pipelines to the new repo with updated root directory settings

### Non-Goals
- Extracting shared code into `packages/` (deferred to future change)
- Consolidating build configs, environment files, or CI scripts beyond path updates
- Adding Turborepo or build caching (can be added later if needed)
- Changing how any app works functionally

---

## Decisions

### D1: New GitHub repository, not converting an existing one

**Decision**: Create a brand-new repo `daily-writing-friends` as the monorepo home.

**Rationale**: No single existing repo is a natural "parent." Promoting one app's repo would create confusion about ownership. A clean new repo gives a clear starting point and avoids polluting the main app's root with monorepo infrastructure files.

**Alternative considered**: Convert the main app's repo into the monorepo root. Rejected — this makes the main app's repo the implicit "default" and complicates history (monorepo infra commits mixed into app history).

---

### D2: `git subtree add` for the main app, direct copy for admin and MCP

**Decision**: Use `git subtree add` to bring in the main app with full history under `apps/web/`. Copy admin and MCP source directly (fresh history).

**Rationale**: The main app's commit history has the most context value (bug fixes, feature decisions, architectural choices documented in commits). Admin and MCP have minimal history — the subtree overhead (command complexity, ongoing discipline) is not worth it for them.

**Command**:
```bash
git subtree add --prefix=apps/web https://github.com/org/DailyWritingFriends.git main --squash
```
The `--squash` flag collapses all history into one commit in the monorepo, avoiding a bloated graph while still being traceable to the original repo. Without `--squash`, the full graph is merged, which is noisier but more complete. **Recommended default: `--squash`**, unless the team needs full per-commit blame across the rewrite boundary.

**Alternative considered**: Copy all three apps without history. Simpler, but loses the most valuable history. Rejected for the main app; accepted for admin/MCP.

---

### D3: pnpm workspaces, not npm workspaces or Turborepo

**Decision**: Use pnpm with a root `pnpm-workspace.yaml`.

**Rationale**:
- pnpm's strict dependency isolation (content-addressable store, no hoisting by default) catches undeclared dependencies at setup time rather than at runtime
- Faster installs and less disk usage via hardlinking
- `pnpm --filter` provides ergonomic per-app commands without needing a separate tool

**Turborepo considered**: Good for caching, but overkill for 3 small apps with no shared build outputs. Can be layered on later.

**npm workspaces considered**: Stable, no package manager switch needed. Rejected because npm hoisting behavior would mask phantom dependency bugs rather than surface them.

---

### D4: Each app retains its own `package.json`, lockfile managed at root

**Decision**: No root-level dependencies beyond workspace tooling. Each app owns its own `dependencies` and `devDependencies`.

**Rationale**: The goal is colocation, not tight coupling. Mixing app deps into a root package.json creates ambiguity about which package belongs where. pnpm manages deduplication automatically via its store — no manual root-level dep merging needed.

---

### D5: Phantom dependency audit before finalizing migration

**Decision**: Before archiving original repos, each app must be installed and tested under pnpm to surface any phantom dependencies.

**Rationale**: npm's hoisting allowed apps to use packages they didn't explicitly declare. pnpm's strict isolation breaks this silently — the app installs fine but fails at import time. This is the highest-risk item in the migration and must be resolved before considering the migration complete.

**Process**:
1. Run `pnpm install` in each app directory
2. Run `pnpm dev` and verify the app starts without import errors
3. Run any existing test suite
4. Fix any missing `dependencies` entries in `package.json`

---

### D6: Original repos archived, not deleted

**Decision**: After migration is verified, archive the original three repos on GitHub.

**Rationale**: Archiving preserves PR history, issue threads, and external links. The repos become read-only — no accidental pushes, but full historical context remains. This is preferable to deletion and safer than leaving them active (which risks confusion about where the "real" repo is).

---

## Risks / Trade-offs

| Risk | Mitigation |
|------|-----------|
| Phantom dependencies break apps under pnpm | Audit each app under pnpm before archiving originals (D5). Fix missing `package.json` entries. |
| Deployment pipelines break during migration window | Reconnect Vercel (or equivalent) to new repo with `apps/web`, `apps/admin` as root directory before archiving originals. Test deployments on a branch first. |
| `git subtree add --squash` loses per-commit blame for the main app | Teams that need full blame history can omit `--squash`. Trade-off: noisier commit graph. |
| pnpm version mismatch between developers | Specify `packageManager` field in root `package.json` and use `corepack enable` to pin the pnpm version. |
| Developer confusion about where to run commands | Document root-level commands (`pnpm --filter web dev`) and per-app commands (`cd apps/web && pnpm dev`) in root `README.md`. |
| CI pipelines break on new repo | CI configs must be updated to reference new paths (`apps/web`, `apps/admin`, `apps/mcp`). Treat as a blocking step alongside deployment. |

---

## Migration Plan

### Phase 0: Preparation (no production impact)
1. Create new GitHub repository `daily-writing-friends`
2. Initialize root `package.json` with `"packageManager": "pnpm@<version>"` and workspace scripts
3. Create `pnpm-workspace.yaml`:
   ```yaml
   packages:
     - 'apps/*'
     - 'packages/*'
   ```
4. Create empty `packages/` directory with a `.gitkeep`
5. Create `apps/` directory

### Phase 1: Bring in the apps
6. `git subtree add --prefix=apps/web <main-app-remote> main --squash`
7. Copy admin source into `apps/admin/` — commit as `feat: add admin app`
8. Copy MCP source into `apps/mcp/` — commit as `feat: add mcp server`
9. Run `pnpm install` from the root

### Phase 2: Phantom dependency audit (highest-risk step)
10. `cd apps/web && pnpm dev` — observe for import errors, fix `package.json` as needed
11. `cd apps/admin && pnpm dev` — same
12. `cd apps/mcp && pnpm dev` — same
13. Run each app's test suite under pnpm
14. Commit any `package.json` fixes

### Phase 3: CI/CD reconnection (blocking)
15. Update Vercel (or deployment platform) to point to new repo:
    - Main app: root directory = `apps/web`
    - Admin: root directory = `apps/admin`
16. Update any CI pipelines (GitHub Actions, etc.) with new paths
17. Verify a deployment succeeds from the new repo on a preview branch

### Phase 4: Cutover
18. Verify all apps start and deploy correctly from the monorepo
19. Archive the three original repos on GitHub
20. Update any internal links, Notion docs, or bookmarks pointing to old repos
21. Notify team of new setup and `pnpm` requirement (`corepack enable`)

### Rollback strategy
- Original repos remain live until Phase 4 — rollback is possible at any point before archiving by reverting to original repos
- After archiving: restore from archived repo (GitHub archives are reversible by org admins) and revert Vercel connections
- There is no database or backend change in this migration — rollback is purely a git/infrastructure concern

---

## Open Questions

1. **Which pnpm version to pin?** Should be decided and set in `packageManager` field before migration. Latest stable pnpm 9.x is recommended.
2. **Which deployment platform?** The plan assumes Vercel, but the actual platform for each app should be confirmed. If apps use different platforms, reconnection steps differ.
3. **CI/CD configuration**: Do any of the three apps have active GitHub Actions or other CI? If yes, their configs must be updated in Phase 3. This needs to be inventoried before starting.
4. **`.npmrc` configuration**: pnpm may need `.npmrc` settings (e.g., `shamefully-hoist=false` is the default — confirm this is intentional and doesn't break any app).
5. **Environment variables**: Do Vercel environment variables need to be reconfigured for the new repo, or do they migrate automatically? Confirm before Phase 4.
6. **Squash vs. full history for main app**: Confirm team preference before running `git subtree add`. This decision cannot be reversed without rerunning the subtree import.

---

## Testability Notes

This change is a repository/infrastructure migration with no functional code changes. Testing focuses on verifying that each app works correctly after the migration, not on testing new features.

### Layer 1 — Unit (Pure logic)

**Applicable scope**: Minimal. The migration introduces no new logic. Unit tests in each app continue to run against existing code.

- Verify each app's existing unit test suite passes under pnpm: `pnpm --filter web test`, `pnpm --filter admin test`, `pnpm --filter mcp test`
- These tests serve as a regression check — any failure indicates a phantom dependency issue or environment misconfiguration introduced by the migration

### Layer 2 — Integration (Boundary contracts between layers)

**Focus**: Workspace wiring and inter-app tooling.

- `pnpm install` resolves without errors from the monorepo root — confirms workspace configuration is valid
- Each app's `pnpm dev` starts the dev server without import-time errors — confirms phantom dependencies were resolved
- `pnpm --filter web build` and equivalent for admin/mcp complete without errors — confirms build tooling works under new workspace context
- If any shared config (e.g., TypeScript base config) is extracted to `packages/` in the future, integration tests should verify that app-level `tsconfig.json` extends correctly

### Layer 3 — E2E Network Passthrough (Full UI flows with real dev server)

**Focus**: Verify the main app and admin dashboard are functionally intact post-migration.

- Start the main app dev server (`pnpm --filter web dev`) and run through a full user flow: sign up, create a writing entry, view history
- Start the admin dashboard dev server and verify it loads and connects to Supabase correctly
- Start the MCP server and verify it responds to a sample tool call
- These tests confirm that no environment variable, build config, or dependency was silently broken during the copy/subtree import

### Layer 4 — E2E Local DB (RLS, triggers, data integrity)

**Focus**: Confirm Supabase backend is unaffected.

- The backend (Supabase/Firebase) is not changed in this migration — no schema, RLS policy, or trigger changes
- Layer 4 tests should confirm that apps can still connect to the local Supabase instance and that existing RLS policies enforce correctly for the test user roles
- Any existing seed data and fixture scripts should run without modification after the migration
- If CI runs migrations against a local Supabase container, verify the migration scripts are still correctly referenced from the new `apps/web` path

---

*Design written: 2026-03-08*
