# Handoff: create-monorepo — Session 2 (Group 1: Repository & Workspace Setup)

## What was done

Completed all 7 tasks in group "1. Repository & Workspace Setup":

1. **GitHub repo created**: `BumgeunSong/daily-writing-friends-mono` (public)
   - **Naming note**: The desired name `daily-writing-friends` was already taken by the existing main app repo (`BumgeunSong/daily-writing-friends`). Used `daily-writing-friends-mono` instead.

2. **Root `package.json`** created with:
   - `"private": true`
   - `"packageManager": "pnpm@9.15.4"` (latest stable pnpm 9.x)
   - Workspace fan-out scripts: `build`, `test`, `dev` via `pnpm -r run <script>`

3. **`pnpm-workspace.yaml`** with globs `apps/*` and `packages/*`

4. **Root `.npmrc`** with security defaults:
   - `ignore-scripts=true`
   - `shamefully-hoist=false`
   - `strict-peer-dependencies=true`

5. **`packages/`** directory with `.gitkeep`

6. **`apps/`** directory with `.gitkeep`

7. **Initial commit** `chore: init monorepo scaffold` pushed to `main` branch on GitHub

## Files changed

**New repository** (not in BashRalph): `/Users/bumgeunsong/coding/tutorial/daily-writing-friends-mono/`
- `package.json`
- `pnpm-workspace.yaml`
- `.npmrc`
- `packages/.gitkeep`
- `apps/.gitkeep`

**In BashRalph repo** (this repo):
- `openspec/changes/create-monorepo/tasks.md` — tasks 1.1–1.7 marked `[x]`
- `openspec/changes/create-monorepo/handoff.md` — this file

## Key decisions

- **Repo name**: Used `daily-writing-friends-mono` instead of `daily-writing-friends` due to naming conflict with existing main app. The existing `daily-writing-friends` repo is the original main writing app.
- **pnpm version**: Pinned to `9.15.4` (latest stable 9.x). System pnpm is 10.12.1 — use `corepack enable` or install pnpm@9 explicitly for consistency.

## Notes for next session (Group 2: App Integration)

- **Monorepo location**: `/Users/bumgeunsong/coding/tutorial/daily-writing-friends-mono/`
- **GitHub repo**: `https://github.com/BumgeunSong/daily-writing-friends-mono`
- **Source repos** (all exist locally and on GitHub):
  - Main app: `/Users/bumgeunsong/coding/tutorial/DailyWritingFriends/` → `https://github.com/BumgeunSong/daily-writing-friends.git`
  - Admin: `/Users/bumgeunsong/coding/tutorial/admin-daily-writing-friends/` → `https://github.com/BumgeunSong/daily-writing-friends-admin.git`
  - MCP: `/Users/bumgeunsong/coding/tutorial/daily-writing-friends-mcp/` → `https://github.com/BumgeunSong/daily-writing-friends-mcp.git`
- Task 2.1 git subtree command: `git subtree add --prefix=apps/web https://github.com/BumgeunSong/daily-writing-friends.git main --squash`
- Tasks 2.2 and 2.3 copy admin and MCP source directly (no subtree)
- All group 2 work should be done from `/Users/bumgeunsong/coding/tutorial/daily-writing-friends-mono/`
