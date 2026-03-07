# Handoff: create-monorepo design-review

## What was done
- Reviewed `design.md` from 5 perspectives: Architecture, Security, Quality, Testability, Integration
- Found 7 Important findings and 15 Minor findings (no Critical)
- Updated `design.md` to address all 7 Important findings (added D7, D8, Phase 2 success criteria, verification script, Vercel ignoreCommand, clarified --squash trade-off, trimmed open questions)
- Re-reviewed the updated design (Round 2) — all Important findings resolved, only Minor items remain
- Wrote `design-review.md` with full findings, resolutions, and accepted trade-offs
- Fixed step numbering issue in migration plan (duplicate step 18)

## Files changed
- `openspec/changes/create-monorepo/design.md` — **modified**: added D7 (.npmrc security), D8 (package naming), Phase 2 success criteria, verification script, Vercel ignoreCommand step, clarified --squash caveat, resolved 2 open questions, fixed step numbering
- `openspec/changes/create-monorepo/design-review.md` — **created**: full 5-perspective review with 2 rounds
- `openspec/changes/create-monorepo/handoff.md` — **updated**: this file

## Key decisions
- **D7 added**: Root `.npmrc` with `ignore-scripts=true`, `shamefully-hoist=false`, `strict-peer-dependencies=true` for supply chain security
- **D8 added**: Each app's `package.json` `name` must be `web`, `admin`, `mcp` to match `pnpm --filter` commands
- **--squash clarified**: Goals reworded from "preserve history" to "maintain traceability" — per-commit blame only available in archived original repo with --squash
- **Vercel ignoreCommand**: Added as required step in Phase 3 to prevent unnecessary builds across apps
- **Verification script**: Concrete bash script added for automated migration validation

## Notes for next session
- Design and design-review are complete — next step is writing **specs** (`specs.md`) and **tasks** (`tasks.md`)
- 4 open questions remain that need team input before Phase 0: pnpm version, deployment platform, CI inventory, env var migration
- The migration plan (Phase 0–4, 22 steps) maps directly to implementation tasks
- D7's `ignore-scripts=true` may need per-app overrides if apps use post-install scripts (prisma generate, husky install) — flag during task planning
- Phantom dependency audit (Phase 2) remains the highest-risk step
