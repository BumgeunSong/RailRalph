## Why

Three related projects — the main writing app (DailyWritingFriends), the admin dashboard (admin-daily-writing-friends), and the MCP server (daily-writing-friends-mcp) — live in separate repositories despite sharing the same Supabase/Firebase backend. This causes two immediate problems:

1. **Cross-project navigation is difficult**: Developers and AI agents cannot see the full ecosystem in a single workspace, making cross-cutting changes slow and error-prone.
2. **Agent observability is limited**: AI coding agents working on one app have no context about the others, leading to inconsistencies and missed integration points.

A future benefit (not in this scope) is extracting shared code into workspace packages to eliminate configuration duplication across the three apps.

## What Changes

- Create a new GitHub repository `daily-writing-friends` as the monorepo
- Move the main app into `apps/web/` via `git subtree add` (preserving commit history — this app has the most valuable history; admin and MCP have minimal history worth preserving)
- Copy the admin dashboard into `apps/admin/` (fresh history)
- Copy the MCP server into `apps/mcp/` (fresh history)
- Add root `pnpm-workspace.yaml` and root `package.json` with workspace scripts
- Add empty `packages/` directory for future shared code (`@dwf/db`, `@dwf/types`)
- Each app keeps its own dependencies, build config, and dev server unchanged

### Why pnpm over npm

pnpm is chosen over npm workspaces for three reasons:
1. **Strict dependency isolation** — pnpm's content-addressable store prevents phantom dependencies, catching undeclared deps early rather than letting them silently work
2. **Faster installs and less disk usage** — pnpm hardlinks shared dependencies
3. **Better monorepo conventions** — `pnpm --filter` provides ergonomic per-app commands

### Phantom dependency risk

pnpm's strict isolation means any undeclared dependencies that currently work via npm hoisting will break. Before finalizing the migration, each app must be tested under pnpm to identify and explicitly declare any missing dependencies. This is the highest-risk item in the migration.

## Capabilities

### New Capabilities
- `monorepo-structure`: pnpm workspace configuration, root scripts, and directory layout for colocating three apps
- `history-preservation`: Git subtree integration to preserve main app commit history in the monorepo

### Modified Capabilities

(none — no existing specs)

## Impact

- **Repositories**: Three separate repos consolidated into one **new** GitHub repository. Original repos are archived after migration is verified. PR history and issues on original repos remain accessible in archived state.
- **Package manager**: All three apps switch from npm to pnpm (see justification above)
- **Dependencies**: Each app's `node_modules` managed by pnpm with strict isolation (not hoisted). Phantom dependencies must be resolved before migration is complete.
- **Deployment**: Each app's deployment pipeline (Vercel, etc.) must be reconnected to the new repo with updated root directory settings (e.g., `apps/web` for the main app). This is a blocking migration step.
- **CI/CD**: Existing CI pipelines must be updated to point to the new repo and adjusted paths. This is a blocking migration step.
- **Git remotes**: After migration is verified, original repos are archived. The main app's subtree remote can be removed once the team confirms history is intact.
- **Developer setup**: Developers need pnpm installed globally (`corepack enable` or `npm i -g pnpm`). Individual apps are run via `pnpm --filter <app> dev` from the root, or `pnpm dev` from within the app directory.
