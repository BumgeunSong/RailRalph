# Handoff: create-monorepo design

## What was done
- Read the reviewed `proposal.md` and `proposal-review.md` to understand all decisions and accepted trade-offs
- Noted that AGENTS.md, config.yaml, VERIFICATION_CONFIG.md, and VERIFICATION_WORKFLOW.md do not exist in this repo
- Wrote `design.md` covering all required sections: Context, Goals/Non-Goals, Decisions, Risks/Trade-offs, Migration Plan, Open Questions, and Testability Notes (4-layer pyramid)
- Committed the design with message `openspec(create-monorepo): add design`

## Files changed
- `openspec/changes/create-monorepo/design.md` — **created**: full design document
- `openspec/changes/create-monorepo/handoff.md` — **updated**: this file (replaces previous session's handoff)

## Key decisions
- **6 core design decisions documented** (D1–D6): new repo, git subtree with `--squash` for main app, pnpm workspaces, each app owns its own `package.json`, mandatory phantom dependency audit, archive (not delete) original repos
- **`--squash` flag for git subtree**: recommended default to keep the commit graph clean; noted as reversible only by re-running the import — team should confirm preference before executing
- **Phantom dependency audit placed in Phase 2** of the migration plan as the highest-risk step
- **Rollback strategy**: original repos stay live until Phase 4 (archiving), making rollback purely a git/infrastructure concern with no backend impact

## Notes for next session
- Design is complete and committed — next step is writing **specs** (task-level specifications) and **tasks** (implementation task list)
- The 6 open questions in the design should be answered during specs/tasks planning:
  1. Which pnpm version to pin?
  2. Which deployment platform (Vercel assumed)?
  3. Are there active CI/CD pipelines to update?
  4. `.npmrc` configuration needed?
  5. Do Vercel env vars migrate automatically?
  6. Squash vs. full history preference for main app?
- The migration plan in the design (Phase 0–4) maps directly to implementation tasks
- Phantom dependency audit task should be flagged as high-risk in the task list
