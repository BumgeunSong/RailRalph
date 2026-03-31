# RailRalph

**Put Autonomous Ralph on Deterministic Rails.**

---

Geoffrey Huntley defined the Ralph technique as:

> "The technique is deterministically bad in an undeterministic world."

RailRalph is the opposite:

> **Deterministically good in an undeterministic world.**

## The Problem

- The core insight of the Ralph Loop is right: long-running, autonomous, git as memory
- But as Geoffrey Huntley defined it: "The technique is deterministically bad in an undeterministic world."
- Naive persistence doesn't converge without a good plan and clear verification criteria
- The problem isn't Claude — it's the lack of structure in the process

## The Insight

- Coding phases are always the same — plan, design, specify, implement, verify, ship
- Fix the process as code. Let Claude handle the execution at each step.
- **Deterministic process + autonomous execution = reliable autonomous coding**

## How RailRalph Works

- **Bash script is the orchestrator. Claude is the executor.**
- 13+ `claude -p` sessions: each gets fresh context, clear inputs, clear outputs
- Gates (`tsc`, tests) must pass before the train proceeds to the next station
- State lives in files (OpenSpec artifacts, `tasks.md`) — not in context

## The Journey

```
DEPARTURE: railralph my-feature 'add user auth'
     |
     v
+- LINE 1: PLANNING ----------------------------------+
|                                                       |
|  Station 1: Proposal        * ==>                    |
|  Station 2: Proposal Review * ==>                    |
|  Station 3: Design          * ==>                    |
|  Station 4: Design Review   * ==>                    |
|  Station 5: Specs           * ==>                    |
|  Station 6: Tasks           * ==>                    |
|                                                       |
|  Cargo loaded: specs, tasks.md, acceptance criteria   |
+-------------------------------------------------------+
     |
     v
+- LINE 2: APPLY -------------------------------------+
|                                                       |
|  Station 7:  Task Group 1   * ==> tsc gate           |
|  Station 8:  Task Group 2   * ==> tsc gate           |
|  Station 9:  Task Group 3   * ==> tsc gate           |
|  ...                                                  |
|                                                       |
|  Gate blocked? -> retry at same station               |
+-------------------------------------------------------+
     |
     v
+- LINE 3: ROUNDHOUSE (evaluate -> fix loop) ----------+
|                                                       |
|       +---- Inspector (opus, read-only) <--+         |
|       |     Tests every AC with evidence    |         |
|       v                                     |         |
|    All pass? -- yes --> EXIT ROUNDHOUSE     |         |
|       |                                     |         |
|       no                                    |         |
|       v                                     |         |
|    Mechanic (sonnet, full tools) -----------+         |
|    Fixes only what the inspector flagged              |
|                                                       |
+-------------------------------------------------------+
     |
     v
+- LINE 4: CLOSING ------------------------------------+
|                                                       |
|  Station: Spec Alignment    * ==>                    |
|  Station: Pull Request      * ==>                    |
|  Station: Review Response   * ==>                    |
|  Station: Final Alignment   * ==>                    |
|  Station: Retro             * ==>                    |
|                                                       |
+-------------------------------------------------------+
     |
     v
ARRIVAL: merged PR + full audit trail
```

Each **station** is a single `claude -p` session. **Gates** are validation checkpoints (`tsc --noEmit`, test suites) that must pass before the train proceeds. The **roundhouse** is where the inspector (opus, read-only) judges the mechanic's (sonnet) work — a different model evaluates a different model's code.

## Why Inspector != Mechanic

Most agent harnesses let the same agent build and judge its own work. This creates **self-evaluation bias** — agents approve mediocre work because they wrote it.

RailRalph solves this with a contract-based separate evaluator:

- **opus (read-only) judges sonnet's implementation** against acceptance criteria — not the same model grading its own homework
- **Three-level verification**: literal AC check -> spec-driven edge cases -> adversarial probing
- **A single FAIL overrides an overall PASS** — no averaging away real problems

Based on Anthropic's research on [harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps).

## Prerequisites

- `claude` CLI ([Claude Code](https://docs.anthropic.com/en/docs/claude-code))
- `openspec` CLI — https://github.com/Fission-AI/OpenSpec
- `gh` CLI — GitHub CLI
- `npx tsc` — TypeScript compiler
- `git` — version control
- Target project must have an `openspec/` directory

## Quick Start

```bash
# Install
git clone https://github.com/your-org/railralph.git
cd RailRalph
make install

# Run from your project directory
cd /path/to/your-project
railralph my-change-name 'Brief description of the change'
```

RailRalph will:
1. Create an OpenSpec artifact at `openspec/changes/my-change-name/`
2. Run 6 planning sessions (proposal, design, specs, tasks)
3. Apply changes in batches with type safety gates
4. Evaluate and fix in a loop until all acceptance criteria pass
5. Create a pull request and generate a retrospective

Logs are written to `.railralph/logs/$RUN_ID/` for full auditability.

## Configuration

Create `.railralph.config.sh` in your project root. All variables are optional with sensible defaults.

| Variable | Default | Purpose |
|---|---|---|
| `DESIGN_SKILLS` | (empty) | Skills injected during design phase |
| `APPLY_SKILLS` | `code-style` | Skills injected during apply phase |
| `VERIFY_SKILLS` | `testing type-system code-style agent-browser` | Skills for verify phase |
| `SKILL_KEYWORDS` | `test spec coverage api/ fetch endpoint type interface` | Keywords for dynamic skill matching |
| `OPENSPEC_SCHEMA` | `eddys-flow` | OpenSpec schema for `openspec new change` |
| `MODEL_PLANNING` | `sonnet` | Model for planning sessions |
| `MODEL_REVIEW` | `opus` | Model for review sessions |
| `MODEL_APPLY` | `sonnet` | Model for apply sessions |
| `MODEL_VERIFY` | `sonnet` | Model for verify sessions |

## Design Principles

- **Process determinism over model intelligence** — the rails are fixed, Claude fills in the stops
- **Gates over retries** — fail at the checkpoint, not at the end
- **Auditability** — every station logged, full trail from proposal to merged PR
- **Zero runtime dependencies** — pure bash, any model is a replaceable executor

## Based On

- [Ralph Loop](https://ghuntley.com/specs/ralph/) by Geoffrey Huntley
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents) by Anthropic
- [Harness Design for Long-Running Apps](https://www.anthropic.com/engineering/harness-design-long-running-apps) by Anthropic
- [OpenSpec](https://github.com/Fission-AI/OpenSpec) by Fission AI
