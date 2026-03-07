# Handoff: create-monorepo proposal review

## What was done
- Reviewed the original `proposal.md` from 4 perspectives (Objectives Challenger, Alternatives Explorer, User Advocate, Scope Analyst)
- Found 1 Critical issue (phantom dependency risk under pnpm) and 4 Important issues (overpromising in "Why", unjustified npm→pnpm switch, missing deployment paths, unspecified new vs existing repo)
- Rewrote `proposal.md` to address all Critical and Important findings
- Re-reviewed the updated proposal (round 2) — all issues resolved
- Wrote `proposal-review.md` with full review and round 2 assessment

## Files changed
- `openspec/changes/create-monorepo/proposal.md` — **modified**: rewrote to address review findings (added pnpm justification, phantom dependency risk section, deployment/CI as blocking steps, developer setup details, history asymmetry explanation)
- `openspec/changes/create-monorepo/proposal-review.md` — **created**: full 4-perspective review with severity ratings and round 2 re-assessment
- `openspec/changes/create-monorepo/handoff.md` — **created**: this file

## Key decisions
- Phantom dependency risk is the highest-risk migration item — proposal now requires testing each app under pnpm before finalizing
- Deployment reconnection and CI/CD updates are blocking migration steps, not optional
- History preservation via `git subtree add` only for the main app (most valuable history); admin and MCP get fresh history
- Original repos archived (not deleted) after migration verification — PR history/issues remain readable
- Turborepo deferred — plain pnpm workspaces sufficient for 3 apps

## Notes for next session
- Proposal is **ready for implementation planning** (design/specs/tasks)
- The highest-risk task will be testing each app under pnpm to find phantom dependencies
- Deployment reconnection details will depend on what platform each app uses (Vercel, etc.) — this should be investigated during design
- No AGENTS.md or config.yaml exists in this repo yet
