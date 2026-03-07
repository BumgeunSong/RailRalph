# Design Review: create-monorepo

## Architecture Reviewer

**Does the design fit existing patterns? Are boundaries and interfaces well-defined?**

| # | Finding | Severity |
|---|---------|----------|
| A1 | `--squash` contradicted the stated goal of "preserving commit history" — with squash, per-commit blame/log is unavailable within the monorepo itself | **Important** |
| A2 | `pnpm --filter web` assumes package `name` is `web`, but existing apps likely have different names (e.g., `daily-writing-friends`) — filter commands would silently fail | **Important** |
| A3 | No root-level TypeScript or linting strategy — IDE experience in a monorepo differs from single-app repos (language server scope, eslint config resolution) | Minor |
| A4 | Migration plan is strictly sequential — Phase 2 app audits could run in parallel since apps are independent | Minor |
| A5 | No mention of long-horizon monorepo scaling (what happens when a 4th or 5th app is added) — acceptable for 3 apps but worth a sentence | Minor |

**A1 detail**: The original Goals section said "Preserve the main app's git commit history via `git subtree add`" while D2 recommended `--squash`, which collapses all history into one commit. `git log apps/web/` would only show the squash commit. This was a contradiction between stated goals and recommended approach.

**A2 detail**: pnpm's `--filter` matches against the `name` field in `package.json`, not the directory path. If the main app's `package.json` has `"name": "daily-writing-friends"`, `pnpm --filter web dev` won't match it. The design used `--filter web` throughout without specifying the required naming convention.

---

## Security Reviewer

**Vulnerabilities, trust boundaries, authn/authz gaps, supply chain concerns.**

| # | Finding | Severity |
|---|---------|----------|
| S1 | No `.npmrc` security configuration — monorepo aggregates deps from 3 apps, increasing supply chain attack surface; `ignore-scripts=true` should be a baseline | **Important** |
| S2 | Repository permission consolidation risk — if original repos had different access controls, merging into one repo may unintentionally broaden access | Minor |
| S3 | Environment variable cross-exposure — shared CI pipelines may expose secrets from one app to build steps of another | Minor |
| S4 | No `pnpm audit` security baseline — migration is an opportunity to establish a vulnerability scan | Minor |
| S5 | Archived repos may contain secrets in git history (committed `.env` files, API keys) — archiving preserves that exposure | Minor |

**S1 detail**: A root `.npmrc` with `ignore-scripts=true` prevents post-install scripts in dependencies from executing automatically. This is particularly important in a monorepo where the aggregate dependency count is higher. Without this, a single compromised package in any of the three apps could execute arbitrary code during `pnpm install`.

---

## Quality Reviewer

**Logic defects, maintainability, anti-patterns, SOLID violations, complexity hotspots.**

| # | Finding | Severity |
|---|---------|----------|
| Q1 | 6 open questions included unresolved design decisions (`.npmrc` config, squash vs. full history) that should have been decided in the design, not deferred to implementation | **Important** |
| Q2 | Phase 2 audit process lacked concrete success criteria — "verify the app starts without import errors" is vague (what constitutes "starts"? renders a page? passes tests? builds?) | **Important** |
| Q3 | Rollback strategy doesn't address work done post-migration — if the team works in the monorepo for weeks then needs to rollback, changes must be back-ported to original repos | Minor |
| Q4 | Phase 4 cutover says "verify all apps start and deploy correctly" without defining what "correctly" means (preview deployment? production traffic? manual smoke test?) | Minor |
| Q5 | Migration plan mixes git operations, package manager operations, deployment operations, and organizational operations without ownership assignments | Minor |

**Q1 detail**: Open questions in a design document signal incomplete design. The `.npmrc` configuration and squash-vs-full-history questions are design-level decisions with enough information to resolve. Deferring them pushes decision-making to implementation time when there's more pressure and less context.

**Q2 detail**: The difference between "app starts" and "app works" is significant. An app can start its dev server but fail to render because of a missing runtime dependency. Clear criteria (install succeeds, build succeeds, tests pass, dev server renders initial page) prevent false confidence.

---

## Testability Reviewer

**Is this design testable? What's the test strategy? Hard-to-test areas?**

| # | Finding | Severity |
|---|---------|----------|
| T1 | No automated verification script — the entire migration hinges on "apps work after moving" but verification is described as manual commands, not an automatable checklist | **Important** |
| T2 | Layer 2 "integration tests" are manual `pnpm install` and `pnpm dev` commands, not automated checks — there's no way to run a single command that validates the migration | **Important** |
| T3 | Layer 3 E2E tests require a running Supabase instance but the design doesn't specify which environment (local, staging, production) | Minor |
| T4 | MCP server testing says "verify it responds to a sample tool call" but provides no mechanism — unlike web apps, MCP servers need a specific client or test harness | Minor |
| T5 | The 4-layer test pyramid is applied to a migration that introduces no new code — Layers 1 and 4 essentially say "run existing tests," which is a verification checklist, not a testing strategy | Minor |

**T1 detail**: A simple bash script that runs `pnpm install && pnpm --filter web build && pnpm --filter admin build && pnpm --filter mcp build && pnpm --filter web test` would provide a single command to validate the migration. This is critical for confidence and repeatability.

---

## Integration Reviewer

**API contracts, backward compatibility, naming consistency, integration concerns.**

| # | Finding | Severity |
|---|---------|----------|
| I1 | Vercel `ignoreCommand` not addressed — without it, every push to the monorepo triggers builds for all three apps, wasting build minutes and causing unnecessary deployments | **Important** |
| I2 | Lockfile transition strategy unclear — existing `package-lock.json` files in each app need to be deleted, and the relationship to the root `pnpm-lock.yaml` should be specified | Minor |
| I3 | Root `package.json` scripts not specified — common monorepo root scripts (`dev`, `build`, `test`, `lint` that fan out to all apps) are implied but not defined | Minor |
| I4 | `.env` file handling strategy missing — apps likely use `.env` files for Supabase/Firebase config, but the design doesn't address per-app vs. root `.env` | Minor |
| I5 | Step numbering in migration plan had a duplicate (step 18 appeared in both Phase 3 and Phase 4) | Minor |

**I1 detail**: Vercel supports an `ignoreCommand` setting per project that determines whether a push should trigger a build. For monorepos, the standard pattern is `git diff --quiet HEAD^ HEAD -- apps/<app>/`. Without this, the web app rebuilds when only admin code changes, and vice versa. This is a practical necessity for monorepo deployments, not an optimization.

---

## Round 1 Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| Important | 7 |
| Minor | 15 |

**Important findings:**
1. (A1) `--squash` contradicted history preservation goal
2. (A2) `pnpm --filter` naming assumed non-existent package names
3. (S1) No `.npmrc` security configuration
4. (Q1) Open questions included resolvable design decisions
5. (Q2) Phase 2 lacked concrete success criteria
6. (T1+T2) No automated verification script
7. (I1) Vercel `ignoreCommand` not addressed

---

## Round 1 → Design Updates

The design was updated to address all Important findings:

| Finding | Resolution |
|---------|-----------|
| A1: `--squash` contradiction | Goals section reworded to "maintain traceability" with explicit note that per-commit blame is only in archived repo. D2 adds an "Important caveat" paragraph. |
| A2: Package naming | New **D8** added: each app's `package.json` `name` field must be `web`, `admin`, `mcp` to match `--filter` commands. |
| S1: `.npmrc` security | New **D7** added: root `.npmrc` with `ignore-scripts=true`, `shamefully-hoist=false`, `strict-peer-dependencies=true`. |
| Q1: Unresolved open questions | `.npmrc` and squash decisions resolved in-design. Open questions trimmed from 6 to 4 (remaining ones genuinely need team input). |
| Q2: Phase 2 success criteria | Explicit success criteria block added after Phase 2 steps: install, build, test, dev server renders, no import errors. |
| T1+T2: No verification script | Concrete bash verification script added to Layer 2 testability notes. |
| I1: Vercel ignoreCommand | New step 17 in Phase 3: configure `ignoreCommand` per-app. |

Additionally fixed: Phase 4 step numbering corrected (was duplicate step 18).

---

## Round 2: Re-review of Updated Design

### Architecture Reviewer
- A1 **Resolved**: Goals now say "maintain traceability" with clear caveat. No contradiction.
- A2 **Resolved**: D8 specifies naming convention. `pnpm --filter web` will work as documented.
- A3–A5 remain Minor and acceptable as-is.

### Security Reviewer
- S1 **Resolved**: D7 provides concrete `.npmrc` with security defaults.
- S2–S5 remain Minor. **New observation**: D7's `ignore-scripts=true` may break apps that rely on post-install scripts (e.g., `prisma generate`, `husky install`). The design notes scripts can be "opted into explicitly per-package" but doesn't specify the mechanism (`pnpm.allowedScripts` in `package.json` or per-app `.npmrc` override). **Minor** — implementation detail.

### Quality Reviewer
- Q1 **Resolved**: Open questions trimmed to genuinely external decisions.
- Q2 **Resolved**: Phase 2 now has 5 concrete success criteria.
- Q3–Q5 remain Minor and acceptable.

### Testability Reviewer
- T1+T2 **Resolved**: Verification script provided. Single command validates the migration.
- T3–T5 remain Minor. **New observation**: The verification script doesn't test `pnpm dev` (only `build` and `test`). Dev server testing requires manual verification since it's a long-running process. **Minor** — acceptable trade-off.

### Integration Reviewer
- I1 **Resolved**: Phase 3 now includes `ignoreCommand` configuration.
- I2–I5 remain Minor. Step numbering fixed.

### Round 2 Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| Important | 0 (all resolved) |
| Minor | 15 (unchanged) + 2 new Minor |

---

## Accepted Trade-offs

1. **No Turborepo**: Plain pnpm workspaces are sufficient for 3 small apps. Can be added later if build caching becomes valuable.
2. **Root-level tooling deferred**: No shared ESLint/TypeScript/Prettier config at the root. Each app keeps its own. This is consistent with the non-goal of "not consolidating build configs."
3. **Manual E2E verification**: Layer 3 E2E tests (full user flows) require manual testing since they need a running backend. Automated build/test verification covers the most likely failure modes.
4. **`--squash` loses in-monorepo blame**: Accepted as the default recommendation. Teams needing full blame can omit `--squash` at execution time.
5. **Remaining open questions**: 4 questions require team input (pnpm version, deployment platform, CI inventory, env vars). These cannot be resolved in the design and are correctly deferred to pre-execution.
6. **Rollback scope limited**: Rollback strategy covers the migration window but not post-migration work. This is acceptable — once the team is working in the monorepo, rollback becomes a team coordination issue, not a technical one.

---

## Final Verdict

**The design is ready for specs and task planning.** All Important findings from Round 1 have been addressed. The remaining Minor findings are either implementation details or accepted trade-offs that don't affect the design's viability.

---

*Review completed: 2026-03-08*
