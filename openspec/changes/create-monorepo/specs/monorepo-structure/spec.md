# Spec: monorepo-structure

## ADDED Requirements

### Requirement: Workspace Configuration

The monorepo SHALL use pnpm workspaces. A root `pnpm-workspace.yaml` MUST declare two workspace globs: `apps/*` and `packages/*`. A root `package.json` MUST include a `packageManager` field pinning the pnpm version (e.g., `"pnpm@9.x.x"`).

#### Scenario: Workspace globs resolve all apps

WHEN `pnpm install` is run from the monorepo root
THEN all three apps (`apps/web`, `apps/admin`, `apps/mcp`) are recognized as workspace packages without error

#### Scenario: pnpm version is pinned

WHEN a developer runs `corepack enable` and then `pnpm --version` in the monorepo root
THEN the version printed matches the `packageManager` field in root `package.json`

---

### Requirement: Directory Layout

The monorepo root MUST contain the following structure:
- `apps/web/` — main writing app
- `apps/admin/` — admin dashboard
- `apps/mcp/` — MCP server
- `packages/` — empty placeholder for future shared packages (MUST contain a `.gitkeep` to preserve in git)

No application source code SHALL live at the monorepo root.

#### Scenario: All app directories present after setup

WHEN the monorepo repository is cloned and `pnpm install` is run
THEN directories `apps/web`, `apps/admin`, `apps/mcp`, and `packages` all exist

#### Scenario: packages directory tracked in git

WHEN the repository is freshly cloned
THEN `packages/` directory exists and contains `.gitkeep`

---

### Requirement: Package Naming Convention

Each app's `package.json` `name` field MUST be set to its short alias: `web` for the main app, `admin` for the admin dashboard, and `mcp` for the MCP server. This is required for `pnpm --filter` commands to resolve correctly.

#### Scenario: Filter by name resolves main app

WHEN `pnpm --filter web build` is run from the monorepo root
THEN only `apps/web` is built and the command exits without error

#### Scenario: Filter by name resolves admin app

WHEN `pnpm --filter admin build` is run from the monorepo root
THEN only `apps/admin` is built and the command exits without error

#### Scenario: Filter by name resolves MCP server

WHEN `pnpm --filter mcp build` is run from the monorepo root
THEN only `apps/mcp` is built and the command exits without error

---

### Requirement: Root Scripts

The root `package.json` MUST provide workspace-level scripts that fan out to all apps. At minimum: `build` (builds all apps), `test` (tests all apps), and `dev` (starts all apps in dev mode). Individual apps MUST remain runnable via `pnpm --filter <name> <script>` from the root.

#### Scenario: Root build script builds all apps

WHEN `pnpm build` is run from the monorepo root
THEN all three apps (`web`, `admin`, `mcp`) are built sequentially or in parallel and all build scripts exit with code 0

#### Scenario: Per-app command runs in isolation

WHEN `pnpm --filter web dev` is run from the monorepo root
THEN only the `apps/web` dev server starts; `apps/admin` and `apps/mcp` are unaffected

---

### Requirement: Security Defaults via .npmrc

A root `.npmrc` MUST be committed to the repository with the following settings:
- `ignore-scripts=true` — prevents automatic post-install script execution
- `shamefully-hoist=false` — enforces pnpm's strict isolation
- `strict-peer-dependencies=true` — fails on unresolved peer dependencies

#### Scenario: Post-install scripts are blocked by default

WHEN `pnpm install` is run from the monorepo root with an added package that has a post-install script
THEN the post-install script does NOT execute automatically

#### Scenario: Phantom dependencies are not accessible

WHEN an app imports a package that is not declared in its own `package.json`
THEN the import fails with a module-not-found error (not silently resolved via hoisting)

---

### Requirement: Phantom Dependency Audit

Before migration is considered complete, each app MUST be verified to start and build correctly under pnpm. All of the following MUST pass for each app before the original repositories are archived:
1. `pnpm install` completes without errors from the monorepo root
2. `pnpm --filter <app> build` exits with code 0
3. `pnpm --filter <app> test` passes (where a test script exists)
4. The app's dev server starts and renders its initial page (or, for MCP, responds to a health check)
5. No unresolved import errors occur at runtime

#### Scenario: Verification script passes for all apps

WHEN the migration verification script is run from the monorepo root after phantom dependency fixes are applied
THEN `pnpm install`, `pnpm --filter web build`, `pnpm --filter admin build`, `pnpm --filter mcp build` all exit with code 0

#### Scenario: Missing dependency is caught before archiving

WHEN an app uses a package not declared in its own `package.json` (a phantom dependency)
THEN `pnpm --filter <app> build` or `pnpm --filter <app> dev` fails with an explicit error identifying the missing package
AND the dependency is added to the app's `package.json` before proceeding

---

### Requirement: Lockfile at Root

The monorepo MUST have a single `pnpm-lock.yaml` at the root. Individual apps MUST NOT retain or create their own `package-lock.json` or `yarn.lock` files. Any pre-existing lockfiles from the original npm-managed apps SHALL be deleted as part of the migration.

#### Scenario: Only root lockfile exists after install

WHEN `pnpm install` is run from the monorepo root
THEN a single `pnpm-lock.yaml` exists at the root and no `package-lock.json` files exist anywhere in `apps/`

---

### Requirement: Deployment Pipeline Reconnection

Each app's deployment pipeline MUST be reconnected to the new monorepo repository before original repositories are archived. The root directory setting in the deployment platform MUST be updated to point to the app's subdirectory (`apps/web`, `apps/admin`, `apps/mcp`). Vercel (or equivalent) MUST configure an `ignoreCommand` per app so that a push only triggers a build when files in that app's subdirectory changed.

#### Scenario: Web app deploy ignores admin-only changes

WHEN a commit is pushed to the monorepo that only modifies files under `apps/admin/`
THEN the deployment platform does NOT trigger a new build for the `web` app

#### Scenario: Admin app deploy ignores web-only changes

WHEN a commit is pushed to the monorepo that only modifies files under `apps/web/`
THEN the deployment platform does NOT trigger a new build for the `admin` app

#### Scenario: Preview deployment succeeds from new repo

WHEN a preview branch is deployed from the monorepo for the main app
THEN the deployment succeeds and the app is reachable at its preview URL
