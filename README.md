# BashRalph

Multi-session Claude pipeline orchestrator for OpenSpec-based development workflows.

## What is BashRalph?

BashRalph chains `claude -p` sessions through a **planning → apply → verify** lifecycle for structured development. It orchestrates 13+ Claude sessions using pure bash with zero runtime dependencies, driving changes through design, implementation, verification, and pull request creation.

The real value lies in the prompt templates: each phase injects context-aware skills, validates outputs with gates (e.g., `npx tsc`), and persists state to enable retry and resumption. BashRalph is designed for **high-fidelity, long-running agent workflows** where reliability and auditability matter.

Built on [OpenSpec](https://github.com/Fission-AI/OpenSpec) artifacts for specification-driven development.

## Prerequisites

- `claude` CLI (Claude Code)
- `openspec` CLI — https://github.com/Fission-AI/OpenSpec
- `gh` CLI — GitHub CLI
- `npx tsc` — TypeScript compiler
- `git` — version control
- Target project must have an `openspec/` directory

## Quick Start

```bash
# Install
git clone https://github.com/your-org/bashralph.git
cd BashRalph
make install

# Run from your project directory
cd /path/to/your-project
bashralph my-change-name 'Brief description of the change'
```

BashRalph will:
1. Create an OpenSpec artifact at `openspec/changes/my-change-name/`
2. Run 6 planning sessions (proposal, design, specs, tasks)
3. Apply changes in batches with type safety gates
4. Verify and create a pull request
5. Generate a retrospective

Logs are written to `.bashralph/logs/$RUN_ID/` for full auditability.

## Configuration

Create `.bashralph.config.sh` in your project root. All variables are optional with sensible defaults.

### Skills and Validation

| Variable | Default | Purpose |
|---|---|---|
| `SAFETY_COMMIT_PATHS` | `openspec/` | Paths for `git add` in safety commits |
| `DESIGN_SKILLS` | (empty) | Skills injected during design phase (`design`, `architecture`, etc.) |
| `APPLY_SKILLS` | `code-style` | Skills injected during apply phase |
| `VERIFY_SKILLS` | `testing type-system code-style agent-browser` | Skills for verify phase |
| `SKILL_KEYWORDS` | `test spec coverage api/ fetch endpoint type interface` | Keywords for dynamic skill matching in apply phase |
| `OPENSPEC_SCHEMA` | `eddys-flow` | OpenSpec schema for `openspec new change` |

### Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `BASHRALPH_PROJECT_DIR` | Auto-detected (git root) | Override project directory |
| `BASHRALPH_LOG_DIR` | `$PROJECT_DIR/.bashralph/logs/$RUN_ID` | Override log directory |
| `MODEL_PLANNING` | `sonnet` | Model for planning sessions |
| `MODEL_REVIEW` | `opus` | Model for review sessions |
| `MODEL_APPLY` | `sonnet` | Model for apply sessions |
| `MODEL_VERIFY` | `sonnet` | Model for verify sessions |

Example `.bashralph.config.sh`:

```bash
export DESIGN_SKILLS="architecture design-review"
export VERIFY_SKILLS="testing type-system code-style integration-tests"
export MODEL_PLANNING="opus"
export SKILL_KEYWORDS="test spec coverage api/ endpoint"
```

## Pipeline Phases

### Phase 1: Planning (6 sessions)

Planning runs sequentially through these sessions:

1. **Proposal** — Draft the change proposal with brief rationale
2. **Proposal Review** — Review and refine proposal quality
3. **Design** — Detailed design with architecture and approach (injects `DESIGN_SKILLS`)
4. **Design Review** — Review design for completeness and feasibility
5. **Specs** — Formalize design into OpenSpec structured specs
6. **Tasks** — Decompose specs into concrete, assignable tasks in `tasks.md`

Output: OpenSpec artifact with fully structured change specification.

### Phase 2: Apply (one session per task group)

Apply phase iterates through task groups in `tasks.md`. Each group:

1. Receives a Claude session with dynamically matched and injected skills
2. Processes the grouped tasks with context from previous completions
3. Applies changes to source files
4. **Type safety gate** — runs `npx tsc --noEmit` between groups; blocks on type errors
5. Retries on failure with context from error output

Skills are dynamically matched using keywords in `tasks.md` + configured `SKILL_KEYWORDS`.

Output: All changes applied to source; artifacts committed to `openspec/`.

### Phase 3: Verification & Closing (5+ sessions)

Verification runs sequentially (with retry loops on failure):

1. **Verify** — Run test suite, linters, and full spec validation (injects `VERIFY_SKILLS`)
2. **Spec Alignment** — Ensure OpenSpec artifact matches applied changes
3. **Pull Request** — Create GitHub pull request with full context
4. **Review Response** — Iterate on PR review feedback
5. **Final Spec Alignment** — Finalize specs to match merged change
6. **Retro** — Generate retrospective documenting what was learned

Output: Merged PR, finalized OpenSpec artifact, full audit trail.

## Logs and State

BashRalph writes full logs to `.bashralph/logs/$RUN_ID/`:

```
.bashralph/logs/
└── RUN_ID/
    ├── plan/
    │   ├── 01-proposal.log
    │   ├── 02-proposal-review.log
    │   ├── 03-design.log
    │   ├── 04-design-review.log
    │   ├── 05-specs.log
    │   └── 06-tasks.log
    ├── apply/
    │   ├── group-1.log
    │   ├── group-2.log
    │   └── ...
    ├── verify/
    │   ├── 01-verify.log
    │   ├── 02-spec-alignment.log
    │   ├── 03-pull-request.log
    │   ├── 04-review-response.log
    │   ├── 05-final-spec-alignment.log
    │   └── 06-retro.log
    └── STATE.json
```

Logs are **never deleted** — they form a complete audit trail of the change lifecycle.

## .gitignore

Add `.bashralph/` to your project's `.gitignore`:

```gitignore
.bashralph/
```

## Commands

### Run a Change

```bash
bashralph <change-name> '<brief description>'
```

### Resume a Run

```bash
bashralph resume <RUN_ID>
```

### View Logs

```bash
bashralph logs <RUN_ID>
```

### List Runs

```bash
bashralph list
```

## Design Principles

**Reliability through structure:** BashRalph relies on OpenSpec to provide a shared source of truth. Each phase produces artifacts that feed the next; failures are logged with full context for resumption.

**Long-running agent best practices:** Inspired by [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), BashRalph:
- Breaks work into discrete sessions with clear inputs/outputs
- Validates between phases (type gates, spec alignment checks)
- Logs everything for auditability and resumption
- Injects context-appropriate skills at each phase

**Pure bash, zero dependencies:** No Python, Node.js runtime, or external orchestration. BashRalph is a shell script that invokes standard CLI tools.

## Based On

- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) by Anthropic
- [OpenSpec](https://github.com/Fission-AI/OpenSpec) by Fission AI
