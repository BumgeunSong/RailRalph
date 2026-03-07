# Tasks: create-monorepo

## 1. Repository & Workspace Setup

- [ ] 1.1 Create new GitHub repository `daily-writing-friends` (public or private per team convention)
- [ ] 1.2 Initialize root `package.json` with `"private": true`, `"packageManager": "pnpm@9.x.x"` (latest stable 9.x), and workspace scripts: `build`, `test`, `dev` (each fanning out via `pnpm -r run <script>`)
- [ ] 1.3 Create `pnpm-workspace.yaml` declaring globs `apps/*` and `packages/*`
- [ ] 1.4 Create root `.npmrc` with `ignore-scripts=true`, `shamefully-hoist=false`, `strict-peer-dependencies=true`
- [ ] 1.5 Create `packages/` directory with a `.gitkeep` file
- [ ] 1.6 Create `apps/` directory placeholder (add `.gitkeep` temporarily if needed)
- [ ] 1.7 Commit initial monorepo scaffold: `chore: init monorepo scaffold`

## 2. App Integration

- [ ] 2.1 Add main app via `git subtree add --prefix=apps/web <DailyWritingFriends-remote> main --squash`
- [ ] 2.2 Copy admin dashboard source into `apps/admin/` and commit as `feat: add admin app`
- [ ] 2.3 Copy MCP server source into `apps/mcp/` and commit as `feat: add mcp server`
- [ ] 2.4 Remove any pre-existing `package-lock.json` or `yarn.lock` files from all `apps/` subdirectories
- [ ] 2.5 Update `package.json` `name` field in `apps/web` to `"web"`, `apps/admin` to `"admin"`, `apps/mcp` to `"mcp"`
- [ ] 2.6 Run `pnpm install` from monorepo root; confirm a single `pnpm-lock.yaml` is generated at root

## 3. Phantom Dependency Audit

- [ ] 3.1 Run `pnpm --filter web dev`; fix any import-time or module-not-found errors by adding missing packages to `apps/web/package.json`
- [ ] 3.2 Run `pnpm --filter admin dev`; fix any phantom dependency errors in `apps/admin/package.json`
- [ ] 3.3 Run `pnpm --filter mcp dev`; fix any phantom dependency errors in `apps/mcp/package.json`
- [ ] 3.4 Run `pnpm --filter web build` and confirm exit code 0
- [ ] 3.5 Run `pnpm --filter admin build` and confirm exit code 0
- [ ] 3.6 Run `pnpm --filter mcp build` and confirm exit code 0
- [ ] 3.7 Commit any `package.json` fixes: `fix: resolve phantom dependencies under pnpm`

## 4. CI/CD Reconnection

- [ ] 4.1 Update Vercel (or equivalent) project for the main app: set root directory to `apps/web`, point to new repo
- [ ] 4.2 Update Vercel project for admin: set root directory to `apps/admin`, point to new repo
- [ ] 4.3 Configure `ignoreCommand` in Vercel per app (e.g., `git diff --quiet HEAD^ HEAD -- apps/web/` for web) so pushes only trigger builds for the affected app
- [ ] 4.4 Inventory and update any GitHub Actions or other CI pipelines to reference new paths (`apps/web`, `apps/admin`, `apps/mcp`)
- [ ] 4.5 Deploy a preview branch from the monorepo for the main app and verify deployment succeeds

## 5. Cutover

- [ ] 5.1 Confirm all three apps build, test, and deploy successfully from the monorepo (checklist from Phase 2 success criteria all pass)
- [ ] 5.2 Archive the three original repositories on GitHub (`DailyWritingFriends`, `admin-daily-writing-friends`, `daily-writing-friends-mcp`)
- [ ] 5.3 Update any internal links, Notion docs, or bookmarks pointing to old repository URLs
- [ ] 5.4 Notify team of new repository location and pnpm requirement (`corepack enable` or `npm i -g pnpm`)

## Tests

### Unit

- [ ] T.1 Run `pnpm --filter web test` from monorepo root — verify existing web app unit tests pass (Vitest or Jest per app's test runner)
- [ ] T.2 Run `pnpm --filter admin test` — verify existing admin unit tests pass
- [ ] T.3 Run `pnpm --filter mcp test` — verify existing MCP unit tests pass (acceptable to skip if no test script exists)

### Integration

- [ ] T.4 Run `pnpm install` from monorepo root — verify all three workspace packages resolve without error and a single `pnpm-lock.yaml` is created (no `package-lock.json` in `apps/`)
- [ ] T.5 Run the migration verification script from the design (`pnpm install` + `pnpm --filter <app> build` for all three apps) — verify all exit codes are 0
- [ ] T.6 Verify `pnpm --filter web dev`, `pnpm --filter admin dev`, and `pnpm --filter mcp dev` each start without import errors (phantom dependency audit complete)

### E2E

- [ ] T.7 Start `pnpm --filter web dev` and walk through a full user flow (sign up, create writing entry, view history) — verify no runtime errors (agent-browser)
- [ ] T.8 Start `pnpm --filter admin dev` and verify the dashboard loads and connects to Supabase correctly (agent-browser)
- [ ] T.9 Start `pnpm --filter mcp dev` and verify the MCP server responds to a sample tool call / health check
- [ ] T.10 Verify a Vercel preview deployment for the main app succeeds from the monorepo and the app is reachable at its preview URL (agent-browser)
