# Proposal Review: create-monorepo

## Objectives Challenger

**Is this solving the right problem?**

The proposal identifies three pain points: cross-project navigation difficulty, duplicated configuration, and limited agent observability. These are real problems, but the proposal conflates them.

- **Cross-project navigation**: A monorepo solves this directly. **Valid.** (Minor)
- **Duplicated configuration**: The proposal says "each app keeps its own dependencies, build config, and dev server unchanged." This means the monorepo does NOT actually address config duplication in its initial scope — shared config extraction is deferred to the future `packages/` directory. The stated problem and the proposed solution are misaligned. **Important.**
- **Agent observability**: Having all code in one repo helps AI agents see the full picture. This is the strongest practical justification and should be stated more explicitly. (Minor)

**Are there simpler ways?**

The core benefit — a single workspace for navigation and agent context — could also be achieved with:
1. VS Code multi-root workspaces (zero migration cost)
2. Git submodules (keeps separate repos, adds unified view)

However, neither gives pnpm workspace dependency sharing, and submodules add complexity. The monorepo approach is reasonable if the team plans to share code between apps.

**Finding**: The "Why" section overpromises. It claims the monorepo solves config duplication, but the "What Changes" section explicitly defers shared code. The justification should focus on navigation and agent observability as the immediate wins, with shared code as a future benefit. **Important.**

---

## Alternatives Explorer

**Alternative 1: Git submodules**
- Pros: Each repo stays independent, CI unchanged, no package manager migration
- Cons: Submodule UX is notoriously painful, no shared dependency management
- Verdict: Worse than monorepo for this use case

**Alternative 2: Do nothing + VS Code multi-root workspace**
- Pros: Zero migration cost, no CI changes, no risk
- Cons: No shared dependencies, agent tools still need multiple repo contexts
- Verdict: Viable short-term, but doesn't scale if shared code is planned

**Alternative 3: Turborepo instead of plain pnpm workspaces**
- Pros: Built-in caching, task orchestration, better DX for monorepos
- Cons: Additional dependency, learning curve, may be overkill for 3 small apps
- Verdict: Worth mentioning as a future enhancement but not necessary for initial setup

**Alternative 4: npm workspaces (no pnpm migration)**
- Pros: No package manager switch, npm workspaces are stable
- Cons: pnpm is faster, stricter dependency isolation, better disk usage
- Verdict: The proposal should justify the npm→pnpm switch explicitly since it's a separate decision from the monorepo decision

**Finding**: The npm→pnpm switch is bundled into the monorepo migration without justification. These are two independent decisions. The proposal should either justify the package manager change or decouple it. **Important.**

---

## User Advocate

**Developer experience during migration:**

1. **History preservation is inconsistent**: The main app gets `git subtree add` (history preserved), but admin and MCP are copied without history. The proposal should explain *why* the asymmetry — is it because the main app has more valuable history? Or is subtree too complex for all three? Developers losing `git blame` on admin/MCP code may find this frustrating. **Minor.**

2. **Local setup changes**: Developers currently clone 3 repos and run `npm install` in each. After migration, they clone 1 repo and run `pnpm install`. The proposal doesn't mention:
   - Whether pnpm needs to be installed globally (and which version)
   - Whether `.npmrc` configuration is needed
   - Whether existing `package-lock.json` files need special handling
   **Minor** (these are implementation details, but worth noting in the proposal for completeness).

3. **Running individual apps**: "Each app keeps its own dev server unchanged" is good, but the proposal should clarify how developers run individual apps. Will `pnpm --filter web dev` work? Or do they `cd apps/web && pnpm dev`? **Minor.**

4. **CI/CD breakage**: The proposal acknowledges CI needs updating but treats it casually ("if any"). If there IS CI, this is a blocking migration step, not an afterthought. **Minor.**

---

## Scope Analyst

**Is the scope right-sized?**

The scope is reasonable for an initial monorepo setup. The explicit deferral of shared packages (`@dwf/db`, `@dwf/types`) to future work is a good decision — it keeps the migration focused.

**Hidden dependencies and risks:**

1. **pnpm hoisting behavior**: The proposal says dependencies are "hoisted where possible." pnpm's default is strict isolation (non-hoisted). If apps rely on phantom dependencies (undeclared deps that work via npm hoisting), they will break under pnpm. This is the highest-risk item in the migration. **Critical.**

2. **Deployment paths**: The proposal says nothing about how each app is deployed. If apps deploy from their own repos (e.g., Vercel connected to a GitHub repo), the monorepo migration breaks all deployment connections. This needs to be addressed. **Important.**

3. **The "new repo" question**: The proposal says "consolidated into one new repo." Is this a brand-new GitHub repository? Or does one existing repo become the monorepo? If new, all PR history, issues, and GitHub integrations are lost. If existing, which one? **Important.**

4. **Subtree maintenance burden**: `git subtree` requires ongoing discipline. Future pulls from the original repo need `git subtree pull`. If the original repos are archived, this isn't needed — but then why use subtree instead of a simple copy + initial commit with the old history squashed? **Minor.**

---

## Summary of Findings

| # | Finding | Severity | Perspective |
|---|---------|----------|-------------|
| 1 | pnpm strict isolation may break phantom dependencies | **Critical** | Scope Analyst |
| 2 | "Why" section overpromises — config duplication not addressed in scope | **Important** | Objectives Challenger |
| 3 | npm→pnpm switch bundled without justification | **Important** | Alternatives Explorer |
| 4 | Deployment paths not addressed | **Important** | Scope Analyst |
| 5 | "New repo" vs "existing repo" unspecified | **Important** | Scope Analyst |
| 6 | History preservation asymmetry unexplained | Minor | User Advocate |
| 7 | Developer setup steps (pnpm version, .npmrc) missing | Minor | User Advocate |
| 8 | App-running commands not specified | Minor | User Advocate |
| 9 | CI/CD treated too casually | Minor | User Advocate |
| 10 | Subtree vs copy tradeoff not justified | Minor | Scope Analyst |

---

## Round 2: Re-review after proposal update

The proposal was updated to address all Critical and Important findings. Here is the re-assessment:

### Resolved findings

| # | Original Finding | Resolution |
|---|-----------------|------------|
| 1 | pnpm strict isolation may break phantom dependencies | **Resolved.** New "Phantom dependency risk" section explicitly calls this out as the highest-risk item and requires testing before finalization. |
| 2 | "Why" overpromises config duplication | **Resolved.** "Why" now focuses on navigation and agent observability. Config duplication is explicitly deferred as a future benefit. |
| 3 | npm→pnpm switch unjustified | **Resolved.** New "Why pnpm over npm" section gives three concrete reasons. |
| 4 | Deployment paths not addressed | **Resolved.** Impact section now lists deployment reconnection as a blocking migration step. |
| 5 | "New repo" unspecified | **Resolved.** Explicitly states "Create a new GitHub repository" and that originals are archived (remaining accessible). |

### Also addressed (Minor findings from round 1)

- **#6 History asymmetry**: Now explained inline — "this app has the most valuable history; admin and MCP have minimal history worth preserving."
- **#7 Developer setup**: Now covered — `corepack enable` or `npm i -g pnpm`, plus how to run apps.
- **#8 App-running commands**: Now specified — `pnpm --filter <app> dev` or `pnpm dev` from app directory.
- **#9 CI/CD**: Now listed as a "blocking migration step" instead of casual mention.
- **#10 Subtree tradeoff**: Implicitly addressed — subtree is used only for the main app where history matters, and originals are archived so no ongoing subtree pulls needed.

### Remaining accepted trade-offs

1. **No Turborepo**: Plain pnpm workspaces are sufficient for 3 apps. Turborepo can be added later if build caching becomes valuable. Accepted.
2. **No `.npmrc` details**: Specific pnpm configuration is an implementation detail better suited for the task specs than the proposal. Accepted.
3. **Original repo archives lose active GitHub integrations**: PR history and issues remain readable in archived repos. New integrations attach to the monorepo. Accepted.

### Round 2 verdict

All Critical and Important findings have been addressed. The proposal is **ready for implementation planning**. No further revisions needed.
