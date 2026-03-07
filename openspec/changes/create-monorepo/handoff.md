# Handoff: create-monorepo specs

## What was done
- Generated spec files for both capabilities listed in the proposal
- `monorepo-structure`: 7 requirements covering workspace config, directory layout, package naming, root scripts, security defaults (.npmrc), phantom dependency audit, lockfile strategy, and deployment reconnection
- `history-preservation`: 4 requirements covering git subtree for main app, direct copy for admin/MCP, repository archiving conditions, and rollback window preservation

## Files changed
- `openspec/changes/create-monorepo/specs/monorepo-structure/spec.md` — **created**
- `openspec/changes/create-monorepo/specs/history-preservation/spec.md` — **created**
- `openspec/changes/create-monorepo/handoff.md` — **updated**: this file

## Key decisions
- All spec requirements use ADDED delta (no existing specs were modified — confirmed `openspec/specs/` is empty)
- `monorepo-structure` captures all structural and operational behaviors: workspace wiring, naming conventions, security defaults, phantom dep audit, deployment ignoreCommand
- `history-preservation` captures the git integration strategy including the --squash trade-off, direct copy for admin/MCP, archiving conditions, and rollback window
- Scenarios align directly with the Phase 2 success criteria and testability notes from the design

## Notes for next session
- Next step is **tasks** — create `openspec/changes/create-monorepo/tasks.md` mapping the 22-step migration plan to actionable implementation tasks
- 4 open questions still need team input before Phase 0: pnpm version to pin, deployment platform confirmation, CI/CD inventory, env var migration strategy
- D7's `ignore-scripts=true` may need per-app `.npmrc` overrides for post-install scripts (prisma generate, husky install) — flag as a task during Phase 1/2
- Phantom dependency audit (Phase 2) is the highest-risk step — the tasks file should treat it as a blocking gate before Phase 3
