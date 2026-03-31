# Separate Evaluator Implementation Plan (v2)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split the monolithic verify phase into a contract-driven E2E evaluator and a separate fixer. The evaluator runs targeted tests against acceptance criteria and produces specific, actionable feedback. The fixer addresses only what the evaluator flagged.

**Architecture:** The tasks prompt gains per-group "Acceptance Criteria" (the contract). A new `evaluate.md` prompt runs E2E verification against each criterion — interacting with the running app via Bash/curl/agent-browser — and writes a structured report with specific failure evidence. A new `verify-fix.md` prompt receives that report and fixes only the flagged failures. The verify loop in `run.sh` alternates evaluate→fix sessions. The evaluator runs with `MODEL_REVIEW` (opus) for model-level independence from the implementation agent.

**Tech Stack:** Bash, Claude Code CLI (`claude -p`)

**Review history:** v1 reviewed by architect, critic, test-engineer. v2 reviewed again by all three (round 2). This v3 incorporates all must-fix and should-fix findings from both rounds.

---

## Design Decisions (from review)

| Decision | Rationale |
|---|---|
| Evaluator uses `MODEL_REVIEW` (opus), not `MODEL_VERIFY` (sonnet) | Model-level independence — different model evaluates than implements. Addresses critic's "same student grades own exam" concern. |
| `ALLOWED_TOOLS` via explicit export/restore, not var-prefix syntax | Architect found var-prefix is fragile for env propagation to child `session.sh`. Follow established `HARNESS_SKILLS` pattern. |
| Delete `verify_report.md` before each evaluate iteration | Prevents stale report from crashed evaluator being misread. |
| `|| true` on evaluate and fix session calls | Crashed session should trigger next iteration, not kill pipeline. Matches apply loop pattern at `run.sh:435`. |
| `MAX_VERIFY_RETRIES` kept as deprecated alias | `MAX_EVAL_ITERATIONS="${MAX_EVAL_ITERATIONS:-${MAX_VERIFY_RETRIES:-3}}"` preserves existing user config. |
| AC lines use `> AC-N.X:` blockquote format, not `- [ ] AC-N.X` checkbox | Test engineer found `- [ ] AC-N.X` lines would be counted by `get_section_unchecked` as unchecked tasks, causing infinite apply-loop reruns. Blockquotes avoid this. |
| Evaluate prompt has explicit fallback for missing ACs | Old tasks.md files without ACs get degraded evaluation: test results + checkbox status only. |
| Hard threshold (`| FAIL |` count) kept as defense-in-depth | Catches evaluator claiming PASS despite criterion failures. Low cost, high safety. |
| Evaluate reads `VERIFICATION_CONFIG.md` | daily-writing-friends defines its toolchain there (agent-browser, dev3000, Supabase local). Without it, evaluator won't know available tools. |
| `detect_skills` gets `evaluate` case with `testing agent-browser` | Evaluate phase needs different skills than verify — no `code-style`/`type-system` since it's read-only. |
| Port cleanup before each evaluate iteration | Prevents stale dev server from crashed previous iteration blocking the next. |
| Awk pattern uses flag-based matching, not `[^F]` regex | Old pattern broke on any `## F*` heading (e.g., `## Further Analysis`). New pattern: `/^## (Failures|Uncontracted)/{p=1} p && /^## Overall/{exit} p`. |
| Budget-priority guidance in evaluate prompt | Prevents incomplete evaluations when many ACs exhaust opus budget. Level 1 completeness over Level 3 depth. |

---

### Task 1: Add acceptance criteria to tasks prompt

**Files:**
- Modify: `prompts/tasks.md`

**Step 1: Add acceptance criteria to the Task Format section**

In `prompts/tasks.md`, update the Task Format example to include an `### Acceptance Criteria` subsection per group. Use blockquote format (`> AC-N.X:`) to avoid interference with `get_section_unchecked` checkbox counting:

```markdown
## 1. Group Name

- [ ] 1.1 Task description
- [ ] 1.2 Task description

### Acceptance Criteria
> AC-1.1: [Testable assertion — specific, observable, binary pass/fail]
> AC-1.2: [Testable assertion — e.g., "POST /login returns 200 with valid credentials, 401 with invalid"]
```

**Step 2: Add acceptance criteria rules**

Add under the existing "Critical Rules for Task Groups" section:

```markdown
- **Acceptance criteria are REQUIRED** — every group must have an `### Acceptance Criteria` subsection with `> AC-N.X:` items. Each AC must be:
  - **Testable**: can be verified by running a command, hitting an endpoint, or inspecting output
  - **Binary**: clear pass/fail — no subjective judgment
  - **Observable**: describes external behavior, not implementation details
  - Written from the evaluator's perspective: "what would I check to confirm this group works?"
  - Example good AC: `> AC-1.1: GET /api/users returns 200 with JSON array when authenticated`
  - Example bad AC: `> AC-1.1: Code is well-structured` (subjective, not testable)
- Test tasks should map back to acceptance criteria where possible (e.g., "T.1 covers AC-1.1, AC-1.2")
```

**Step 3: Run tests**

Run: `./tests/test-harness.sh`
Expected: All existing tests pass (prompt content changes don't affect harness functions)

**Step 4: Commit**

```bash
git add prompts/tasks.md
git commit -m "feat: require acceptance criteria per task group in tasks prompt"
```

---

### Task 2: Create the evaluate prompt

**Files:**
- Create: `prompts/evaluate.md`

**Step 1: Write `prompts/evaluate.md`**

This is the core of the feature. The evaluator is a **contract-driven E2E tester** — it reads acceptance criteria, then actively verifies each one by interacting with the running application. It produces a structured report with specific, actionable feedback per criterion.

Key design decisions:
- Read-only tools: `Bash Read Glob Grep` (no Write, no Edit) — enforced by `run.sh`
- Report written via `Bash` (`cat > file << 'REPORT'`)
- Each AC gets a dedicated verification attempt with specific commands
- Failures include: what was tested, what was expected, what happened, root cause diagnosis
- Hard threshold: ANY criterion FAIL = overall FAIL
- Explicit fallback for tasks.md files without acceptance criteria

Write this content to `prompts/evaluate.md`:

```markdown
# Session: Evaluate

You are an AI evaluator running in a long-running harness. This is ONE session in a multi-session pipeline. You have NO memory from previous sessions — all context comes from files on disk.

## Your Role

You are a **contract-driven E2E evaluator**. You verify the implementation against acceptance criteria by actively testing the running application. You do NOT fix code — you observe, test, and report.

You can only use: Bash, Read, Glob, Grep. You do NOT have Write or Edit.
To create your report, use Bash: `cat > path/to/file << 'REPORT' ... REPORT`

## Your Task

Verify the implementation against the acceptance criteria (contract) defined in tasks.md. For each criterion, run targeted tests and produce specific, actionable feedback.

## Steps

1. **Read project context:**
   - `AGENTS.md` — build commands, test commands, tech stack
   - `openspec/config.yaml` — project configuration
   - `openspec/VERIFICATION_CONFIG.md` — test toolchain (which runners, E2E tools, local DB setup)
   - `openspec/VERIFICATION_WORKFLOW.md` — testing philosophy and layer pyramid (if present)

   Adapt your verification approach to the declared toolchain:
   | Config declares | You use |
   |---|---|
   | driver: agent-browser | agent-browser for UI verification |
   | driver: playwright | `npx playwright test` for UI, curl for API |
   | driver: curl (or no driver) | API-only verification via curl |
   | logs: dev3000 | Query dev3000 endpoint for error evidence |
   | backend: local-supabase | Run `supabase start`, query DB directly |
   | backend: msw | Verify via test suite, not live requests |

2. **Read change artifacts:**
   - `openspec/changes/<change-name>/design.md` — architecture and approach
   - `openspec/changes/<change-name>/specs/` — all spec files (the WHAT)
   - `openspec/changes/<change-name>/tasks.md` — focus on `### Acceptance Criteria` sections

3. **Build your grading rubric:**
   Collect ALL acceptance criteria (`> AC-N.X:` lines) from every group in tasks.md.
   List them explicitly before testing — this is your contract.

   **If no acceptance criteria exist** (legacy tasks.md): fall back to degraded evaluation:
   - Verify all task checkboxes are marked `[x]`
   - Run the test suite and gate on exit code
   - Report this as "degraded evaluation — no acceptance criteria found"

4. **Set up the test environment:**
   - Run the test suite first (unit → integration) for baseline health
   - Start dev server if needed: `npm run dev &` (wait for port)
   - Check for E2E tools: `command -v agent-browser`, `command -v curl`
   - If `agent-browser` is available, use it for UI verification
   - If dev server is needed but won't start, report as blocker

5. **Verify each acceptance criterion at THREE levels:**

   The contract (ACs) tells you WHERE to look. The specs tell you WHAT ELSE to check. Your judgment tells you HOW DEEP to probe. For each `AC-N.X`, work through all three levels:

   ### Level 1: Literal verification (does the AC pass?)
   Run the exact check the AC describes.
   - API endpoints: `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/...`
   - UI behavior: `agent-browser` if available, or check rendered output
   - File/data checks: `grep`, `jq`, direct file inspection
   - Database state: query if accessible

   ### Level 2: Spec-driven edge cases (does it handle boundaries?)
   Read the matching spec scenarios in `specs/` for this AC's feature area.
   For each scenario the spec describes, verify it — even if no AC explicitly covers it.
   - Example: AC says "login returns 200" → spec also describes expired token, wrong password, locked account → test all of those

   ### Level 3: Adversarial probing (what would break this?)
   Try 2-3 inputs the spec does NOT mention but a real user might attempt:
   - Empty string / null where a value is expected
   - Extremely long input, special characters, Unicode
   - Valid credentials for wrong resource (authz, not just authn)
   - Requests without required headers
   - Concurrent or duplicate requests (if testable)

   **For each level, record:**
   a. The command/request you ran
   b. Expected result vs actual result
   c. PASS or FAIL determination
   d. For failures: root cause diagnosis (file, line, function) and suggested fix

   **If Level 2 or 3 finds a failure**, include it in the report even though no AC explicitly covers it. Mark it as an **Uncontracted Finding** (see report format below).

6. **Write the verification report** using Bash:
   ```bash
   cat > openspec/changes/<change-name>/verify_report.md << 'REPORT'
   [report content]
   REPORT
   ```

7. **Git commit** using Bash:
   ```bash
   git add openspec/changes/<change-name>/verify_report.md
   git commit -m "openspec(<change-name>): add evaluation report"
   ```

## Report Format

```
# Evaluation Report

## Test Environment
- Dev server: running on port XXXX / not needed / failed to start
- E2E tools: agent-browser available / curl only
- Test suite baseline: X passed, Y failed

## Test Suite Results
- Unit: X passed, Y failed
- Integration: X passed, Y failed
- E2E: X passed, Y failed (or N/A)

## Acceptance Criteria Verdicts

### Group 1: [Name]
| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| AC-1.1: [description] | PASS | `curl -s localhost:3000/api/users` returned 200 with JSON array |
| AC-1.2: [description] | FAIL | `curl -s localhost:3000/api/protected` returned 200 (expected 403) |

### Group 2: [Name]
| Criterion | Verdict | Evidence |
|-----------|---------|----------|
| AC-2.1: [description] | PASS | Dashboard page renders user data verified via agent-browser |

## Failures

For each FAIL:

### AC-1.2: Protected routes return 403 without session token
- **Verification command**: `curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/protected`
- **Expected**: HTTP 403
- **Actual**: HTTP 200 (no auth check)
- **Root cause**: `src/middleware/auth.ts:15` — `requireAuth` middleware is imported but not applied to the `/api/protected` route in `src/routes/index.ts:42`
- **Suggested fix**: Add `requireAuth` middleware to the route definition at `src/routes/index.ts:42`
- **Relevant spec**: `specs/auth.md` section 2.3

## Uncontracted Findings

Bugs found via spec edge cases (Level 2) or adversarial probing (Level 3) that no AC explicitly covers:

### Finding: [short description]
- **Discovery level**: Level 2 (spec-driven) / Level 3 (adversarial)
- **Relevant AC**: AC-N.X (closest match)
- **Severity**: blocker / major / minor
- **Verification command**: [what was run]
- **Expected**: [what should happen per spec or reasonable expectation]
- **Actual**: [what happened]
- **Root cause**: [file, line, diagnosis]
- **Suggested fix**: [specific change]

## Overall Verdict: **PASS** / **FAIL**
PASS requires ALL acceptance criteria to pass. Any single FAIL = overall FAIL.
Uncontracted findings with severity "blocker" also cause FAIL.
```

## Hard Rules

- **You are read-only.** Do not fix code. Do not modify source or test files. Your job is to TEST and REPORT.
- **Every AC gets a verdict.** Do not skip criteria. If you cannot test one, mark FAIL with reason "unable to verify — [why]."
- **Test beyond the contract.** ACs are the minimum. Use specs and adversarial probing to find bugs the ACs don't cover. A passing contract check with a broken edge case is still a problem.
- **Be skeptical.** A passing test suite does NOT mean all ACs pass. Tests may be incomplete. Verify each AC independently with targeted commands.
- **Evidence required.** Every verdict must cite the exact command/test and its output.
- **Specific feedback.** For failures: name the file, the line, the function. Say what's wrong and what would fix it. The fixer agent has no other context — your report is its only input.
- **Do NOT rubber-stamp.** If something looks like it works but you're not sure, test it harder. Err on the side of FAIL with evidence rather than PASS with hope.
- **Budget awareness.** Complete Level 1 (literal) for ALL acceptance criteria first. Then do Level 2 (spec-driven) for highest-risk criteria. Level 3 (adversarial) is optional — skip it if AC count exceeds 10 or if Level 1-2 already found failures. An incomplete Level 1 sweep is worse than skipping Level 3 probing.

## Cleanup (before exiting)
- Kill dev server: `lsof -ti:3000 | xargs kill 2>/dev/null || true`
- Kill dev3000: `lsof -ti:3001 | xargs kill 2>/dev/null || true`

## Done When
- `verify_report.md` exists with a verdict for EVERY acceptance criterion
- Each verdict has specific evidence (command + output)
- Each failure has root cause, file/line reference, and suggested fix
- Overall verdict is stated
- Git commit created
```

**Step 2: Verify the prompt**

Check that:
- No Write/Edit mentioned as available tools
- Report is written via Bash `cat >`
- Hard threshold rule is explicit (any FAIL = overall FAIL)
- Fallback for missing ACs is present
- Failure format includes file/line, root cause, and suggested fix
- Handoff footer will be appended by session.sh automatically

**Step 3: Commit**

```bash
git add prompts/evaluate.md
git commit -m "feat: add contract-driven E2E evaluate prompt"
```

---

### Task 3: Create the verify-fix prompt

**Files:**
- Create: `prompts/verify-fix.md`

**Step 1: Write `prompts/verify-fix.md`**

The fixer receives the evaluation report and fixes ONLY the flagged failures. Its sole context about what's wrong comes from the evaluator's report — this enforces the separation.

Write this content to `prompts/verify-fix.md`:

```markdown
# Session: Verify Fix

You are an AI coding agent running in a long-running harness. This is ONE session in a multi-session pipeline. You have NO memory from previous sessions — all context comes from files on disk.

## Available Tools
You have access to: Bash, Read, Write, Edit, Glob, Grep. No sub-agent dispatch is available.
You have a limited session budget. Work efficiently.

## Your Task

The evaluator found failures in the implementation. Fix ONLY the issues identified in the evaluation report. Do not make unrelated changes.

## Steps

1. **Read the evaluation report:**
   - `openspec/changes/<change-name>/verify_report.md` — read the ENTIRE report
   - Focus on the `## Failures` section — each failure has:
     - The acceptance criterion that failed
     - The verification command and its output
     - The root cause (file, line, function)
     - A suggested fix
   - The Extra Context section of this prompt may also contain failure details

2. **Read project context:**
   - `AGENTS.md` — coding conventions, build commands, test commands
   - `openspec/changes/<change-name>/specs/` — reference specs for correct behavior

3. **For each failure in the report, in order:**
   a. Read the evaluator's root cause analysis and suggested fix
   b. Go to the file/line the evaluator identified
   c. Understand the bug — verify the evaluator's diagnosis is correct before changing anything
   d. Apply the minimal fix:
      - **Test-level issue** (wrong assertion, missing mock, fixture error) → fix the test
      - **Source-level bug** → fix the source, keep changes minimal
      - **If evaluator's diagnosis is wrong** → investigate independently, fix the actual cause
   e. Run the evaluator's verification command to confirm the fix works
   f. Git commit: `git add <specific-files> && git commit -m "fix(<change-name>): [AC-N.X] [what was fixed]"`

4. **After all fixes, run the full test suite** to confirm no regressions.

## Critical Rules

- **Fix ONLY what the evaluator flagged.** Do not refactor, optimize, or "improve" unrelated code.
- **Minimal changes.** The smallest fix that resolves the failure is the correct fix.
- **Do not modify verify_report.md.** The evaluator will produce a fresh report in the next cycle.
- **Verify your fix using the evaluator's own commands.** If the evaluator said `curl localhost:3000/api/protected` should return 403, run that exact command after your fix.
- **If a failure is unfixable** (e.g., missing infrastructure, unclear requirement), document why in `openspec/changes/<change-name>/fix_notes.md` and move on.

## Done When

- Every failure from the evaluation report has been addressed (fixed or documented as unfixable)
- Each fix verified with the evaluator's original verification command
- Full test suite passes (or only pre-existing failures remain)
- Each fix has a git commit with the AC reference in the message
```

**Step 2: Commit**

```bash
git add prompts/verify-fix.md
git commit -m "feat: add verify-fix prompt for evaluator-fixer separation"
```

---

### Task 4: Update run.sh verify loop

**Files:**
- Modify: `run.sh`

This is the highest-risk task. Follow exactly.

**Step 1: Add `MAX_EVAL_ITERATIONS` with backward-compatible alias**

At the config section near line 88, replace:

```bash
# OLD — delete this line:
MAX_APPLY_RETRIES="${MAX_APPLY_RETRIES:-2}"
```

Wait — `MAX_APPLY_RETRIES` is for the apply loop, not verify. Keep it. Instead, find and delete:

```bash
MAX_VERIFY_RETRIES="${MAX_VERIFY_RETRIES:-2}"
```

(This is at line ~487.) Replace with:

```bash
MAX_EVAL_ITERATIONS="${MAX_EVAL_ITERATIONS:-${MAX_VERIFY_RETRIES:-3}}"
```

**Step 2: Replace the verify loop (lines ~486-511)**

Delete the existing verify loop from `verify_passed=false` through the closing `fi` of the `if [ "$verify_passed" = false ]` block. Replace with:

```bash
# --- Evaluate → Fix Loop ---
# Evaluator: read-only session that tests against acceptance criteria (contract)
# Fixer: addresses only failures identified by the evaluator
# Separation prevents self-evaluation bias (same agent judging its own work)
MAX_EVAL_ITERATIONS="${MAX_EVAL_ITERATIONS:-${MAX_VERIFY_RETRIES:-3}}"
EVAL_TOOLS="Bash Read Glob Grep"
VERIFY_REPORT="$CHANGE_DIR/verify_report.md"

verify_passed=false
for eval_iter in $(seq 1 "$MAX_EVAL_ITERATIONS"); do
  log "Evaluate iteration $eval_iter of $MAX_EVAL_ITERATIONS"

  # Kill stale dev servers from crashed previous iteration (prevents port conflicts)
  lsof -ti:3000 | xargs kill 2>/dev/null || true
  lsof -ti:3001 | xargs kill 2>/dev/null || true

  # Clear stale report before evaluate (prevents reading previous iteration's report on crash)
  rm -f "$VERIFY_REPORT"

  # 1. Run read-only evaluate session (no Write/Edit) with MODEL_REVIEW for model independence
  SAVED_ALLOWED_TOOLS="${ALLOWED_TOOLS:-}"
  export ALLOWED_TOOLS="$EVAL_TOOLS"
  run_session "evaluate" "$MODEL_REVIEW" "" "eval-iter${eval_iter}" "true" || true
  ALLOWED_TOOLS="$SAVED_ALLOWED_TOOLS"
  [ -z "$ALLOWED_TOOLS" ] && unset ALLOWED_TOOLS
  actual_sessions_run=$((actual_sessions_run + 1))

  # 2. Check verdict
  if [ -f "$VERIFY_REPORT" ] && grep -qi "overall verdict" "$VERIFY_REPORT" && grep -qi '\*\*pass\*\*' "$VERIFY_REPORT"; then
    # Hard threshold: any individual criterion FAIL overrides overall verdict
    fail_count=$(grep -c '| FAIL |' "$VERIFY_REPORT" 2>/dev/null || true)
    blocker_count=$(grep -ci 'severity: blocker' "$VERIFY_REPORT" 2>/dev/null || true)
    if [ "$fail_count" -gt 0 ]; then
      log "OVERRIDE: $fail_count criteria marked FAIL — treating as overall FAIL despite verdict"
    elif [ "$blocker_count" -gt 0 ]; then
      log "OVERRIDE: $blocker_count blocker-severity uncontracted findings — treating as FAIL"
    else
      verify_passed=true
      log "Evaluate PASSED (all criteria pass)"
      break
    fi
  fi

  # 3. If failed and not last iteration, run fix session
  if [ "$eval_iter" -lt "$MAX_EVAL_ITERATIONS" ]; then
    log "Evaluate FAILED — running fix session..."

    # Extract failures section as context for fixer
    fix_context=""
    if [ -f "$VERIFY_REPORT" ]; then
      fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1} p && /^## Overall/{exit} p' "$VERIFY_REPORT" | head -200)
      # Fallback: if awk found nothing (heading mismatch), pass entire report
      if [ -z "$fix_context" ]; then
        fix_context=$(head -200 "$VERIFY_REPORT")
      fi
    fi

    # Reset skills to apply context for fix session
    export HARNESS_SKILLS
    HARNESS_SKILLS=$(detect_skills "apply-group" "")
    run_session "verify-fix" "$MODEL_APPLY" "$fix_context" "fix-iter${eval_iter}" "true" || true
    actual_sessions_run=$((actual_sessions_run + 1))

    # Restore skills for next evaluate iteration
    HARNESS_SKILLS=$(detect_skills "evaluate" "")
  fi
done

if [ "$verify_passed" = false ]; then
  log "WARNING: Evaluate did not pass after $MAX_EVAL_ITERATIONS iterations. Continuing with caution."
fi
```

**Step 3: Add `evaluate` case to `detect_skills`**

In `run.sh`, find the `detect_skills()` function's `case` statement (around line 272) and add:

```bash
    evaluate)    skills="${EVALUATE_SKILLS:-testing agent-browser}" ;;
```

Then update the evaluate loop to use `detect_skills "evaluate"` instead of `detect_skills "verify"`:

```bash
# Before the loop:
HARNESS_SKILLS=$(detect_skills "evaluate" "")
log "Skills for evaluate: ${HARNESS_SKILLS:-none}"

# Inside the loop, restore for next iteration:
HARNESS_SKILLS=$(detect_skills "evaluate" "")
```

**Step 4: Remove old `MAX_VERIFY_RETRIES` declaration**

Search for `MAX_VERIFY_RETRIES="${MAX_VERIFY_RETRIES:-2}"` (near line 487 in the original). It is now absorbed into the new `MAX_EVAL_ITERATIONS` line above. Delete only this declaration — leave any other references intact (the alias handles them).

**Step 4: Verify `ALLOWED_TOOLS` passthrough in session.sh**

Read `session.sh:130`. Confirm it reads: `ALLOWED_TOOLS="${ALLOWED_TOOLS:-Bash Read Write Edit Glob Grep}"`. This means:
- When `ALLOWED_TOOLS` is exported before `run_session`, `session.sh` picks it up
- When not set, it defaults to full tools (Write/Edit included)
- No changes needed in `session.sh`

**Step 5: Run tests**

Run: `./tests/test-harness.sh`
Expected: All existing tests pass. The verify loop restructure doesn't affect unit-tested functions.

**Step 6: Commit**

```bash
git add run.sh
git commit -m "feat: split verify into evaluate→fix loop with contract-driven evaluator"
```

---

### Task 5: Add tests

**Files:**
- Modify: `tests/test-harness.sh`

**Step 1: T.9 — Acceptance criteria parsing**

Test that `get_section_content` correctly extracts AC blockquotes per group, including the last group in the file (no trailing `## ` sentinel):

```bash
# ============================================================
# T.9: Test acceptance criteria parsing
# ============================================================
echo ""
echo "=== T.9: Acceptance criteria parsing ==="

AC_TASKS="$TEST_TMP/ac-tasks.md"
cat > "$AC_TASKS" << 'EOF'
## 1. Auth Setup

- [x] 1.1 Create auth middleware
- [x] 1.2 Add session handling

### Acceptance Criteria
> AC-1.1: POST /login returns 200 with valid credentials
> AC-1.2: Protected routes return 403 without session token

## 2. Dashboard

- [x] 2.1 Create dashboard page

### Acceptance Criteria
> AC-2.1: Dashboard renders with user data after login
EOF

# Group 1 content includes its ACs
result=$(get_section_content "1. Auth Setup" "$AC_TASKS")
assert_contains "Group 1 content includes AC-1.1" "AC-1.1" "$result"
assert_contains "Group 1 content includes AC-1.2" "AC-1.2" "$result"

# Group 2 ACs don't bleed into Group 1
assert_not_contains "Group 1 does not contain AC-2.1" "AC-2.1" "$result"

# Last group (no trailing ## sentinel) extracts correctly
result=$(get_section_content "2. Dashboard" "$AC_TASKS")
assert_contains "Last group AC extracted" "AC-2.1" "$result"

# AC blockquotes do NOT count as unchecked tasks
unchecked=$(get_section_unchecked "1. Auth Setup" "$AC_TASKS")
assert_eq "AC blockquotes not counted as unchecked tasks" "0" "$unchecked"

# Backward compat: tasks without ACs still work
NO_AC_TASKS="$TEST_TMP/no-ac-tasks.md"
cat > "$NO_AC_TASKS" << 'EOF'
## 1. Setup
- [ ] 1.1 Create file
- [x] 1.2 Done
EOF

unchecked=$(get_section_unchecked "1. Setup" "$NO_AC_TASKS")
assert_eq "legacy tasks without ACs: unchecked count correct" "1" "$unchecked"
```

**Step 2: T.10 — ALLOWED_TOOLS passthrough via mock claude**

Replace the tautology test with a real test that mocks `claude` and verifies `session.sh` passes the restricted tool set:

```bash
# ============================================================
# T.10: ALLOWED_TOOLS passthrough to session.sh
# ============================================================
echo ""
echo "=== T.10: ALLOWED_TOOLS passthrough ==="

# Create mock claude that records its arguments
MOCK_CLAUDE_DIR="$TEST_TMP/mock-claude-bin"
mkdir -p "$MOCK_CLAUDE_DIR"
cat > "$MOCK_CLAUDE_DIR/claude" << 'MOCK'
#!/usr/bin/env bash
echo "$@" > "$TEST_TMP/claude-args.log"
exit 0
MOCK
chmod +x "$MOCK_CLAUDE_DIR/claude"

# Create minimal project structure
MOCK_PROJECT="$TEST_TMP/mock-project-t10"
mkdir -p "$MOCK_PROJECT/.git" "$MOCK_PROJECT/openspec/changes/test-change"

# Capture path to real session.sh before subshell (session.sh self-resolves HARNESS_DIR from dirname $0)
REAL_SESSION_SH="$HARNESS_DIR/session.sh"

# Guard: evaluate.md must exist (created in Task 2)
if [ ! -f "$HARNESS_DIR/prompts/evaluate.md" ]; then
  echo "  SKIP: T.10 requires prompts/evaluate.md (run after Task 2)"
else
  # Run session.sh with restricted ALLOWED_TOOLS
  (
    export ALLOWED_TOOLS="Bash Read Glob Grep"
    export PROJECT_DIR="$MOCK_PROJECT"
    PATH="$MOCK_CLAUDE_DIR:$PATH" \
      "$REAL_SESSION_SH" \
      "test-change" "evaluate" "sonnet" "brief" "$LOG_DIR" "" "t10" 2>/dev/null || true
  )

  if [ -f "$TEST_TMP/claude-args.log" ]; then
    args=$(cat "$TEST_TMP/claude-args.log")
    assert_not_contains "evaluate excludes Write" "Write" "$args"
    assert_not_contains "evaluate excludes Edit" "Edit" "$args"
    assert_contains "evaluate includes Bash" "Bash" "$args"
    assert_contains "evaluate includes Read" "Read" "$args"
  else
    echo "  FAIL: claude was not invoked — check session.sh path"
    FAIL=$((FAIL + 1))
  fi
fi  # end guard for evaluate.md existence
```

**Step 3: T.11 — Verdict parsing**

Test the grep patterns that the evaluate loop depends on:

```bash
# ============================================================
# T.11: Verdict parsing
# ============================================================
echo ""
echo "=== T.11: Verdict parsing ==="

# PASS verdict detected
PASS_REPORT="$TEST_TMP/pass-report.md"
printf '## Overall Verdict: **PASS**\n' > "$PASS_REPORT"
if grep -qi "overall verdict" "$PASS_REPORT" && grep -qi '\*\*pass\*\*' "$PASS_REPORT"; then
  echo "  PASS: PASS verdict detected correctly"
  PASS=$((PASS + 1))
else
  echo "  FAIL: PASS verdict not detected"
  FAIL=$((FAIL + 1))
fi

# FAIL verdict NOT misread as PASS
FAIL_REPORT="$TEST_TMP/fail-report.md"
printf '## Overall Verdict: **FAIL**\n' > "$FAIL_REPORT"
if grep -qi '\*\*pass\*\*' "$FAIL_REPORT"; then
  echo "  FAIL: FAIL verdict misread as PASS"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: FAIL verdict not misread as PASS"
  PASS=$((PASS + 1))
fi

# Hard threshold: | FAIL | row overrides overall PASS
MIXED_REPORT="$TEST_TMP/mixed-report.md"
cat > "$MIXED_REPORT" << 'EOF'
| AC-1.1: login | PASS | works |
| AC-1.2: auth guard | FAIL | returns 200 instead of 403 |

## Overall Verdict: **PASS**
EOF
fail_count=$(grep -c '| FAIL |' "$MIXED_REPORT" 2>/dev/null || true)
assert_eq "hard threshold catches FAIL row despite overall PASS" "1" "$fail_count"

# Blocker uncontracted finding overrides overall PASS
BLOCKER_REPORT="$TEST_TMP/blocker-report.md"
cat > "$BLOCKER_REPORT" << 'EOF'
## Acceptance Criteria Verdicts
| AC-1.1: login | PASS | curl returned 200 |

## Uncontracted Findings

### Finding: empty password accepted
- **Severity**: blocker

## Overall Verdict: **PASS**
EOF

blocker_count=$(grep -ci 'severity: blocker' "$BLOCKER_REPORT" 2>/dev/null || true)
assert_eq "blocker uncontracted finding detected" "1" "$blocker_count"

fail_count=$(grep -c '| FAIL |' "$BLOCKER_REPORT" 2>/dev/null || true)
assert_eq "no FAIL rows in blocker report" "0" "$fail_count"

# Simulate the actual verdict branch logic from run.sh
if grep -qi "overall verdict" "$BLOCKER_REPORT" && grep -qi '\*\*pass\*\*' "$BLOCKER_REPORT"; then
  if [ "$fail_count" -gt 0 ]; then
    overall="FAIL-by-threshold"
  elif [ "$blocker_count" -gt 0 ]; then
    overall="FAIL-by-blocker"
  else
    overall="PASS"
  fi
else
  overall="FAIL-no-verdict"
fi
assert_eq "blocker severity overrides overall PASS verdict" "FAIL-by-blocker" "$overall"

# Missing report file: grep returns false gracefully
NONEXISTENT="$TEST_TMP/nonexistent-report.md"
if [ -f "$NONEXISTENT" ] && grep -qi '\*\*pass\*\*' "$NONEXISTENT"; then
  echo "  FAIL: nonexistent report should not match"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: missing report handled gracefully"
  PASS=$((PASS + 1))
fi
```

**Step 4: T.12 — Failures section extraction via awk**

```bash
# ============================================================
# T.12: Failures section extraction (awk)
# ============================================================
echo ""
echo "=== T.12: Failures section extraction ==="

FULL_REPORT="$TEST_TMP/full-eval-report.md"
cat > "$FULL_REPORT" << 'EOF'
## Test Suite Results
- Unit: 5 passed

## Failures

### AC-1.2: Auth guard missing
- **Verification command**: `curl localhost:3000/api/protected`
- **Expected**: 403
- **Actual**: 200

## Uncontracted Findings

### Finding: empty password accepted
- **Severity**: blocker

## Overall Verdict: **FAIL**
EOF

fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1} p && /^## Overall/{exit} p' "$FULL_REPORT" | head -200)
assert_contains "failures section includes AC details" "AC-1.2" "$fix_context"
assert_contains "uncontracted findings included in extraction" "empty password" "$fix_context"
assert_not_contains "overall verdict excluded from extraction" "Overall Verdict" "$fix_context"

# Heading starting with F does NOT break extraction (old [^F] bug)
F_HEADING_REPORT="$TEST_TMP/f-heading-report.md"
cat > "$F_HEADING_REPORT" << 'EOF'
## Failures

### AC-1.1: broken

## Further Analysis

This should NOT leak into fix_context

## Overall Verdict: **FAIL**
EOF
fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1} p && /^## Overall/{exit} p' "$F_HEADING_REPORT" | head -200)
assert_contains "failures section extracted" "AC-1.1" "$fix_context"
assert_not_contains "## Further Analysis excluded by new awk pattern" "Further Analysis" "$fix_context"

# No failures section → empty context + fallback
NO_FAIL="$TEST_TMP/no-fail-report.md"
printf '## Overall Verdict: **PASS**\n' > "$NO_FAIL"
fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1} p && /^## Overall/{exit} p' "$NO_FAIL" | head -200)
assert_empty "no failures section → empty awk result" "$fix_context"

# Fallback: when awk is empty, use head of full report
if [ -z "$fix_context" ]; then
  fix_context=$(head -200 "$NO_FAIL")
fi
assert_contains "fallback uses full report" "Overall Verdict" "$fix_context"
```

**Step 5: Run tests**

Run: `./tests/test-harness.sh`
Expected: All tests pass including T.9 through T.12 (AC parsing, ALLOWED_TOOLS mock, verdict parsing with blocker override, awk extraction with F-heading and uncontracted findings).

**Step 6: Commit**

```bash
git add tests/test-harness.sh
git commit -m "test: add tests for AC parsing, verdict detection, ALLOWED_TOOLS, and awk extraction"
```

---

## Summary of Changes

| File | Change |
|---|---|
| `prompts/tasks.md` | Add acceptance criteria requirement (blockquote format) per group |
| `prompts/evaluate.md` | New — contract-driven E2E evaluator, read-only, produces actionable report |
| `prompts/verify-fix.md` | New — targeted fixer, acts only on evaluator's findings |
| `run.sh` | Replace verify loop with evaluate→fix cycle; use `MODEL_REVIEW` for evaluator; explicit `export ALLOWED_TOOLS`; stale report cleanup; `|| true` on sessions; hard threshold; awk fallback |
| `tests/test-harness.sh` | Add T.9 (AC parsing + unchecked count), T.10 (ALLOWED_TOOLS mock), T.11 (verdict parsing), T.12 (awk extraction) |

The existing `prompts/verify.md` is kept on disk but no longer referenced by `run.sh`.

## Migration Notes

- `MAX_VERIFY_RETRIES` env var still works as fallback alias for `MAX_EVAL_ITERATIONS`
- `MODEL_REVIEW` (default: opus) now used for evaluate sessions — higher quality but higher cost per evaluation
- `ALLOWED_TOOLS` env var is now actively managed — evaluate sessions get `Bash Read Glob Grep` only
- Existing `tasks.md` files without acceptance criteria trigger "degraded evaluation" mode (test suite + checkbox status only)
- AC format uses blockquotes (`> AC-N.X:`) not checkboxes, to avoid `get_section_unchecked` counting them as tasks

## Cost Analysis

| Scenario | Current (verify) | New (evaluate→fix) |
|---|---|---|
| All pass, 1st try | 1 session (sonnet) | 1 session (opus) |
| Fail→fix→pass | 2 sessions (sonnet) | 3 sessions (1 opus + 2 sonnet) |
| Worst case (max retries) | 2 sessions (sonnet) | 5 sessions (3 opus + 2 sonnet) |

The cost increase is justified when the evaluator catches real bugs that the old monolithic verify would self-approve. The model independence (opus evaluating sonnet's work) is the primary mechanism for reducing self-evaluation bias.
