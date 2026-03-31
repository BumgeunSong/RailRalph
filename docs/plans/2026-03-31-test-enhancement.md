# Test Enhancement Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Expand test coverage from 54 tests across 12 suites to comprehensive coverage of all rail.sh functions, edge cases, integration paths, and the evaluate→fix pipeline.

**Architecture:** All tests live in `tests/test-rail.sh`. Tests extract functions from `rail.sh` via `eval/sed` and use mock binaries for external tools (`claude`, `npx`, `git`). No external test framework — pure bash assertions.

**Tech Stack:** Bash, git (for checkpoint/snapshot tests), mock binaries

---

## Current coverage audit

| Function | Tested? | Notes |
|---|---|---|
| `resolve_project_dir()` | ❌ | |
| `log()` | ❌ | Trivial, but log file creation matters |
| `checkpoint_done()` | ❌ | |
| `checkpoint_save()` | ❌ | |
| `git_snapshot()` | ❌ | |
| `git_rollback()` | ❌ | |
| `git_ensure_committed()` | ❌ | |
| `git_cleanup_tags()` | ❌ | |
| `run_session()` | ❌ | Complex — needs mock claude |
| `run_tsc_gate()` | ✅ T.1 | pass/fail/timeout |
| `get_section_content()` | ✅ T.3 | |
| `get_section_unchecked()` | ✅ T.3/T.9 | |
| `detect_skills()` | ✅ T.5b | |
| `run_session_if_needed()` | ❌ | |
| match-skills.sh | ✅ T.2 | |
| station.sh passthrough | ✅ T.10 | |
| Verdict parsing | ✅ T.11 | |
| Failures extraction | ✅ T.12 | |
| AC parsing | ✅ T.9 | |
| Gap report | ✅ T.5 | |
| PR extraction | ✅ T.4 | |

---

## Task Group 1: Checkpoint functions

### Task 1.1: Test checkpoint_save and checkpoint_done

**Files:**
- Modify: `tests/test-rail.sh` (append after T.5b section)

**Step 1: Add test suite**

```bash
# ============================================================
# T.13: Checkpoint functions
# ============================================================
echo ""
echo "=== T.13: Checkpoint functions ==="

# Source checkpoint functions
CHECKPOINT_FILE="$TEST_TMP/checkpoint-test"
rm -f "$CHECKPOINT_FILE"

eval "$(sed -n '/^checkpoint_done()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^checkpoint_save()/,/^}/p' "$RAIL_DIR/rail.sh")"

# checkpoint_done returns false when file doesn't exist
if checkpoint_done "phase-a"; then
  echo "  FAIL: checkpoint_done should return false when no file"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: checkpoint_done returns false when no checkpoint file"
  PASS=$((PASS + 1))
fi

# checkpoint_save creates the file and records the phase
checkpoint_save "phase-a"
if [ -f "$CHECKPOINT_FILE" ]; then
  echo "  PASS: checkpoint_save creates checkpoint file"
  PASS=$((PASS + 1))
else
  echo "  FAIL: checkpoint_save should create checkpoint file"
  FAIL=$((FAIL + 1))
fi

# checkpoint_done returns true for saved phase
if checkpoint_done "phase-a"; then
  echo "  PASS: checkpoint_done returns true for saved phase"
  PASS=$((PASS + 1))
else
  echo "  FAIL: checkpoint_done should return true for saved phase"
  FAIL=$((FAIL + 1))
fi

# checkpoint_done returns false for unsaved phase
if checkpoint_done "phase-b"; then
  echo "  FAIL: checkpoint_done should return false for unsaved phase"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: checkpoint_done returns false for unsaved phase"
  PASS=$((PASS + 1))
fi

# Multiple saves don't corrupt the file
checkpoint_save "phase-b"
checkpoint_save "phase-c"
if checkpoint_done "phase-a" && checkpoint_done "phase-b" && checkpoint_done "phase-c"; then
  echo "  PASS: multiple checkpoints coexist"
  PASS=$((PASS + 1))
else
  echo "  FAIL: multiple checkpoints should coexist"
  FAIL=$((FAIL + 1))
fi

# Checkpoint with special characters (spaces in group names)
checkpoint_save "apply-group:Task_Group_1"
if checkpoint_done "apply-group:Task_Group_1"; then
  echo "  PASS: checkpoint with colon/underscore works"
  PASS=$((PASS + 1))
else
  echo "  FAIL: checkpoint with colon/underscore should work"
  FAIL=$((FAIL + 1))
fi
```

**Step 2: Run tests**

Run: `bash tests/test-rail.sh`
Expected: All existing 54 tests pass + 6 new checkpoint tests pass (total: 60)

**Step 3: Commit**

```bash
git add tests/test-rail.sh
git commit -m "test: add checkpoint_done/checkpoint_save tests (T.13)"
```

---

## Task Group 2: Git safety functions

### Task 2.1: Test git_snapshot, git_rollback, git_ensure_committed, git_cleanup_tags

**Files:**
- Modify: `tests/test-rail.sh` (append after T.13)

**Step 1: Add test suite**

These tests need a real git repo in the temp directory.

```bash
# ============================================================
# T.14: Git safety functions
# ============================================================
echo ""
echo "=== T.14: Git safety functions ==="

# Create a real git repo for testing
GIT_TEST_DIR="$TEST_TMP/git-test-project"
mkdir -p "$GIT_TEST_DIR"
(
  cd "$GIT_TEST_DIR"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "initial" > file.txt
  git add file.txt
  git commit -q -m "initial"
)

# Source git functions (they use PROJECT_DIR and CHANGE_NAME)
SAVED_PROJECT_DIR="$PROJECT_DIR"
SAVED_CHANGE_NAME="$CHANGE_NAME"
export PROJECT_DIR="$GIT_TEST_DIR"
export CHANGE_NAME="test-feature"

eval "$(sed -n '/^git_snapshot()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_rollback()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_ensure_committed()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_cleanup_tags()/,/^}/p' "$RAIL_DIR/rail.sh")"

# git_snapshot creates a tag
git_snapshot "phase1-001"
tag_exists=$(cd "$GIT_TEST_DIR" && git tag -l "rail/test-feature/phase1-001" | head -1)
assert_eq "git_snapshot creates tag" "rail/test-feature/phase1-001" "$tag_exists"

# git_snapshot overwrites existing tag (idempotent)
git_snapshot "phase1-001"
tag_count=$(cd "$GIT_TEST_DIR" && git tag -l "rail/test-feature/phase1-001" | wc -l | tr -d ' ')
assert_eq "git_snapshot is idempotent" "1" "$tag_count"

# git_rollback reverts uncommitted changes
echo "dirty" > "$GIT_TEST_DIR/file.txt"
git_rollback "phase1-001"
content=$(cat "$GIT_TEST_DIR/file.txt")
assert_eq "git_rollback reverts dirty changes" "initial" "$content"

# git_rollback with nonexistent tag doesn't crash
git_rollback "nonexistent-tag"
echo "  PASS: git_rollback with missing tag doesn't crash"
PASS=$((PASS + 1))

# git_ensure_committed creates safety commit when dirty
echo "uncommitted work" > "$GIT_TEST_DIR/newfile.txt"
(cd "$GIT_TEST_DIR" && git add newfile.txt)
git_ensure_committed "apply-phase"
commit_msg=$(cd "$GIT_TEST_DIR" && git log -1 --format=%s)
assert_contains "git_ensure_committed creates safety commit" "railralph" "$commit_msg"

# git_ensure_committed does nothing when clean
before_hash=$(cd "$GIT_TEST_DIR" && git rev-parse HEAD)
git_ensure_committed "clean-phase"
after_hash=$(cd "$GIT_TEST_DIR" && git rev-parse HEAD)
assert_eq "git_ensure_committed no-op when clean" "$before_hash" "$after_hash"

# git_cleanup_tags removes all rail/ tags
git_snapshot "phase2-001"
git_snapshot "phase3-001"
git_cleanup_tags
remaining=$(cd "$GIT_TEST_DIR" && git tag -l "rail/test-feature/*" | wc -l | tr -d ' ')
assert_eq "git_cleanup_tags removes all tags" "0" "$remaining"

# Restore
export PROJECT_DIR="$SAVED_PROJECT_DIR"
export CHANGE_NAME="$SAVED_CHANGE_NAME"
```

**Step 2: Run tests**

Run: `bash tests/test-rail.sh`
Expected: 60 + 8 = 68 tests pass

**Step 3: Commit**

```bash
git add tests/test-rail.sh
git commit -m "test: add git safety function tests (T.14)"
```

---

## Task Group 3: Edge cases

### Task 3.1: Test resolve_project_dir, config parsing, input validation, malformed tasks.md

**Files:**
- Modify: `tests/test-rail.sh` (append after T.14)

**Step 1: Add test suite**

```bash
# ============================================================
# T.15: resolve_project_dir()
# ============================================================
echo ""
echo "=== T.15: resolve_project_dir() ==="

# Source resolve_project_dir
eval "$(sed -n '/^resolve_project_dir()/,/^}/p' "$RAIL_DIR/rail.sh")"

# Finds git root from subdirectory
NESTED_DIR="$TEST_TMP/git-nested/src/deep"
mkdir -p "$NESTED_DIR"
(cd "$TEST_TMP/git-nested" && git init -q)
result=$(cd "$NESTED_DIR" && resolve_project_dir)
expected=$(cd "$TEST_TMP/git-nested" && pwd)
assert_eq "resolve_project_dir finds git root from nested dir" "$expected" "$result"

# RAILRALPH_PROJECT_DIR overrides git detection
OVERRIDE_DIR="$TEST_TMP/override-project"
mkdir -p "$OVERRIDE_DIR"
result=$(RAILRALPH_PROJECT_DIR="$OVERRIDE_DIR" resolve_project_dir)
assert_eq "RAILRALPH_PROJECT_DIR overrides git detection" "$OVERRIDE_DIR" "$result"

# Fails when no git repo and no override
result=$(cd /tmp && unset RAILRALPH_PROJECT_DIR && resolve_project_dir 2>/dev/null) || true
if [ -z "$result" ]; then
  echo "  PASS: resolve_project_dir fails outside git repo"
  PASS=$((PASS + 1))
else
  echo "  FAIL: should fail outside git repo"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# T.16: Input validation
# ============================================================
echo ""
echo "=== T.16: Input validation ==="

# Valid change names
for name in "my-feature" "add-auth" "fix-123" "a"; do
  if [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]; then
    echo "  PASS: '$name' passes validation"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: '$name' should pass validation"
    FAIL=$((FAIL + 1))
  fi
done

# Invalid change names
for name in "My-Feature" "UPPERCASE" "has spaces" "has_underscore" "-starts-with-dash" "" "a-very-long-name-that-exceeds-the-sixty-four-character-limit-for-change-names-in-rail"; do
  if [[ "$name" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]; then
    echo "  FAIL: '$name' should fail validation"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: '$name' correctly rejected"
    PASS=$((PASS + 1))
  fi
done

# ============================================================
# T.17: Malformed tasks.md edge cases
# ============================================================
echo ""
echo "=== T.17: Malformed tasks.md ==="

# Empty tasks.md → 0 groups
EMPTY_TASKS="$TEST_TMP/empty-tasks.md"
echo "" > "$EMPTY_TASKS"
group_count=$(grep -c '^## ' "$EMPTY_TASKS" || true)
assert_eq "empty tasks.md → 0 groups" "0" "$group_count"

# tasks.md with only headers, no tasks
HEADER_ONLY="$TEST_TMP/header-only-tasks.md"
cat > "$HEADER_ONLY" << 'EOF'
## Group A
## Group B
EOF
unchecked=$(get_section_unchecked "Group A" "$HEADER_ONLY")
assert_eq "header-only group → 0 unchecked" "0" "$unchecked"

# Nonexistent group → 0 unchecked (no crash)
unchecked=$(get_section_unchecked "Nonexistent Group" "$FIXTURE_TASKS")
assert_eq "nonexistent group → 0 unchecked" "0" "$unchecked"

# Group with only checked tasks
ALL_DONE="$TEST_TMP/all-done-tasks.md"
cat > "$ALL_DONE" << 'EOF'
## Group Done
- [x] task 1
- [x] task 2
- [x] task 3
EOF
unchecked=$(get_section_unchecked "Group Done" "$ALL_DONE")
assert_eq "all checked → 0 unchecked" "0" "$unchecked"

# Single task, single group
SINGLE="$TEST_TMP/single-tasks.md"
cat > "$SINGLE" << 'EOF'
## Solo
- [ ] only task
EOF
unchecked=$(get_section_unchecked "Solo" "$SINGLE")
assert_eq "single unchecked task" "1" "$unchecked"

# Config parsing: .railralph.config.sh with various formats
# ============================================================
# T.18: Config file parsing
# ============================================================
echo ""
echo "=== T.18: Config file parsing ==="

CONFIG_TEST_DIR="$TEST_TMP/config-test"
mkdir -p "$CONFIG_TEST_DIR"
CONFIG_FILE="$CONFIG_TEST_DIR/.railralph.config.sh"

cat > "$CONFIG_FILE" << 'CONF'
DESIGN_SKILLS="architecture design-review"
VERIFY_SKILLS='testing type-system'
APPLY_SKILLS=code-style
OPENSPEC_SCHEMA=eddys-flow
# This is a comment
INVALID_VAR=should-not-load
CONF

# Parse config the same way rail.sh does
unset DESIGN_SKILLS VERIFY_SKILLS APPLY_SKILLS OPENSPEC_SCHEMA INVALID_VAR
while IFS='=' read -r key value; do
  value="${value%\"}"
  value="${value#\"}"
  value="${value%\'}"
  value="${value#\'}"
  case "$key" in
    SAFETY_COMMIT_PATHS|DESIGN_SKILLS|APPLY_SKILLS|VERIFY_SKILLS|SKILL_KEYWORDS|OPENSPEC_SCHEMA)
      eval "$key='$value'" ;;
  esac
done < <(grep -E '^[A-Z_]+=.' "$CONFIG_FILE")

assert_eq "config: DESIGN_SKILLS parsed (double quotes)" "architecture design-review" "${DESIGN_SKILLS:-}"
assert_eq "config: VERIFY_SKILLS parsed (single quotes)" "testing type-system" "${VERIFY_SKILLS:-}"
assert_eq "config: APPLY_SKILLS parsed (no quotes)" "code-style" "${APPLY_SKILLS:-}"
assert_eq "config: OPENSPEC_SCHEMA parsed" "eddys-flow" "${OPENSPEC_SCHEMA:-}"
assert_empty "config: INVALID_VAR not loaded" "${INVALID_VAR:-}"
```

**Step 2: Run tests**

Run: `bash tests/test-rail.sh`
Expected: 68 + ~22 = ~90 tests pass

**Step 3: Commit**

```bash
git add tests/test-rail.sh
git commit -m "test: add edge case tests — resolve_project_dir, validation, malformed tasks, config (T.15-T.18)"
```

---

## Task Group 4: Integration tests (replace placeholders)

### Task 4.1: Test run_session with mock claude, skill injection, and apply loop

**Files:**
- Modify: `tests/test-rail.sh` (replace T.6-T.8 placeholders)

**Step 1: Replace placeholder section**

```bash
# ============================================================
# T.6: Integration — run_session with mock claude
# ============================================================
echo ""
echo "=== T.6: run_session with mock claude ==="

# Set up mock project with real git
INT_PROJECT="$TEST_TMP/int-project"
mkdir -p "$INT_PROJECT/openspec/changes/int-test"
(
  cd "$INT_PROJECT"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > base.txt
  git add base.txt
  git commit -q -m "init"
)

# Mock claude that creates a handoff file (simulating agent work)
INT_MOCK_DIR="$TEST_TMP/int-mock-bin"
mkdir -p "$INT_MOCK_DIR"
cat > "$INT_MOCK_DIR/claude" << 'MOCK'
#!/usr/bin/env bash
# Simulate agent: write handoff file
cat > openspec/changes/int-test/handoff.md << 'HO'
- **What was done**: mock session
- **Files changed**: none
HO
exit 0
MOCK
chmod +x "$INT_MOCK_DIR/claude"

# Source run_session and dependencies
SAVED_PROJECT_DIR="$PROJECT_DIR"
SAVED_LOG_DIR="$LOG_DIR"
SAVED_CHANGE_NAME="$CHANGE_NAME"
export PROJECT_DIR="$INT_PROJECT"
export CHANGE_NAME="int-test"
INT_LOG_DIR="$TEST_TMP/int-logs"
export LOG_DIR="$INT_LOG_DIR"
mkdir -p "$INT_LOG_DIR"
CHECKPOINT_FILE="$INT_LOG_DIR/checkpoint"
rm -f "$CHECKPOINT_FILE"

eval "$(sed -n '/^checkpoint_done()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^checkpoint_save()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_snapshot()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_rollback()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_ensure_committed()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^run_session()/,/^}/p' "$RAIL_DIR/rail.sh")"

# Run a session using mock claude
(
  export PATH="$INT_MOCK_DIR:$PATH"
  export RAIL_DIR="$RAIL_DIR"
  run_session "proposal" "sonnet" "" "001" 2>/dev/null
) && session_exit=0 || session_exit=$?

assert_eq "run_session exits 0 with mock claude" "0" "$session_exit"

# Checkpoint was saved
if checkpoint_done "proposal"; then
  echo "  PASS: run_session saves checkpoint on success"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run_session should save checkpoint on success"
  FAIL=$((FAIL + 1))
fi

# Log file was created
if ls "$INT_LOG_DIR"/proposal-*.log 1>/dev/null 2>&1; then
  echo "  PASS: run_session creates log file"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run_session should create log file"
  FAIL=$((FAIL + 1))
fi

# Skip on repeat (checkpoint already saved)
(
  export PATH="$INT_MOCK_DIR:$PATH"
  export RAIL_DIR="$RAIL_DIR"
  run_session "proposal" "sonnet" "" "002" 2>/dev/null
) && skip_exit=0 || skip_exit=$?

# Should have been skipped — check log
if grep -q "SKIP (checkpoint)" "$INT_LOG_DIR/rail.log" 2>/dev/null; then
  echo "  PASS: run_session skips completed checkpoint"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run_session should skip completed checkpoint"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# T.7: Integration — run_session handles failure + rollback
# ============================================================
echo ""
echo "=== T.7: run_session failure + rollback ==="

# Mock claude that fails
cat > "$INT_MOCK_DIR/claude" << 'MOCK'
#!/usr/bin/env bash
echo "dirty content" > newfile.txt
exit 1
MOCK
chmod +x "$INT_MOCK_DIR/claude"

(
  export PATH="$INT_MOCK_DIR:$PATH"
  export RAIL_DIR="$RAIL_DIR"
  run_session "design" "sonnet" "" "003" "true" 2>/dev/null
) && fail_exit=0 || fail_exit=$?

assert_eq "run_session returns non-zero on claude failure" "1" "$fail_exit"

# Verify rollback happened (dirty file should be gone)
if [ ! -f "$INT_PROJECT/newfile.txt" ]; then
  echo "  PASS: run_session rolls back on failure"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run_session should rollback on failure"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# T.8: Integration — skill injection into station.sh
# ============================================================
echo ""
echo "=== T.8: skill injection ==="

# Create a test skill
SKILL_DIR="$INT_PROJECT/.claude/skills/test-skill"
mkdir -p "$SKILL_DIR"
cat > "$SKILL_DIR/SKILL.md" << 'EOF'
---
name: test-skill
description: A test skill for injection
---
# Test skill content
Always use semicolons.
EOF

# Mock claude that captures its system prompt
PROMPT_LOG="$TEST_TMP/system-prompt.log"
cat > "$INT_MOCK_DIR/claude" << MOCK
#!/usr/bin/env bash
# Find --append-system-prompt arg and save it
while [ \$# -gt 0 ]; do
  case "\$1" in
    --append-system-prompt) echo "\$2" > "$PROMPT_LOG"; shift 2 ;;
    *) shift ;;
  esac
done
exit 0
MOCK
chmod +x "$INT_MOCK_DIR/claude"

(
  export PATH="$INT_MOCK_DIR:$PATH"
  export PROJECT_DIR="$INT_PROJECT"
  export HARNESS_SKILLS="test-skill"
  "$RAIL_DIR/station.sh" \
    "int-test" "proposal" "sonnet" "brief" "$INT_LOG_DIR" "" "skill-test" 2>/dev/null || true
)

if [ -f "$PROMPT_LOG" ]; then
  prompt_content=$(cat "$PROMPT_LOG")
  assert_contains "skill content injected into system prompt" "Always use semicolons" "$prompt_content"
  assert_contains "skill section header present" "Project Conventions" "$prompt_content"
else
  echo "  FAIL: system prompt not captured — mock claude issue"
  FAIL=$((FAIL + 1))
fi

# Restore
export PROJECT_DIR="$SAVED_PROJECT_DIR"
export LOG_DIR="$SAVED_LOG_DIR"
export CHANGE_NAME="$SAVED_CHANGE_NAME"
```

**Step 2: Run tests**

Run: `bash tests/test-rail.sh`
Expected: ~90 + ~10 = ~100 tests pass

**Step 3: Commit**

```bash
git add tests/test-rail.sh
git commit -m "test: replace integration placeholders with mock claude tests (T.6-T.8)"
```

---

## Task Group 5: Evaluate→Fix pipeline tests

### Task 5.1: Test the evaluate→fix loop logic

**Files:**
- Modify: `tests/test-rail.sh` (append after integration tests)

**Step 1: Add test suite**

```bash
# ============================================================
# T.19: Evaluate→Fix pipeline logic
# ============================================================
echo ""
echo "=== T.19: Evaluate→Fix pipeline ==="

# Test: multiple FAIL rows counted correctly
MULTI_FAIL="$TEST_TMP/multi-fail-report.md"
cat > "$MULTI_FAIL" << 'EOF'
| AC-1.1: login | FAIL | wrong status |
| AC-1.2: auth | PASS | ok |
| AC-1.3: register | FAIL | timeout |
| AC-2.1: dashboard | FAIL | missing component |

## Overall Verdict: **FAIL**
EOF
fail_count=$(grep -c '| FAIL |' "$MULTI_FAIL" 2>/dev/null || true)
assert_eq "multiple FAIL rows counted" "3" "$fail_count"

# Test: multiple blocker findings
MULTI_BLOCKER="$TEST_TMP/multi-blocker-report.md"
cat > "$MULTI_BLOCKER" << 'EOF'
## Uncontracted Findings

### Finding: SQL injection in login
- **Severity**: blocker

### Finding: XSS in dashboard
- **Severity**: blocker

### Finding: slow query
- **Severity**: minor

## Overall Verdict: **PASS**
EOF
blocker_count=$(grep -ci '\*\*severity\*\*: blocker' "$MULTI_BLOCKER" 2>/dev/null || true)
assert_eq "multiple blockers counted" "2" "$blocker_count"

# minor severity does NOT override PASS
minor_only="$TEST_TMP/minor-only-report.md"
cat > "$minor_only" << 'EOF'
| AC-1.1: login | PASS | works |

## Uncontracted Findings

### Finding: slow query
- **Severity**: minor

## Overall Verdict: **PASS**
EOF
blocker_count=$(grep -ci '\*\*severity\*\*: blocker' "$minor_only" 2>/dev/null || true)
fail_count=$(grep -c '| FAIL |' "$minor_only" 2>/dev/null || true)
if grep -qi "overall verdict" "$minor_only" && grep -qi '\*\*pass\*\*' "$minor_only"; then
  if [ "$fail_count" -gt 0 ]; then
    overall="FAIL-by-threshold"
  elif [ "$blocker_count" -gt 0 ]; then
    overall="FAIL-by-blocker"
  else
    overall="PASS"
  fi
fi
assert_eq "minor severity does NOT override PASS" "PASS" "$overall"

# Test: verdict with different casing
CASE_REPORT="$TEST_TMP/case-report.md"
printf '## overall verdict: **Pass**\n' > "$CASE_REPORT"
if grep -qi "overall verdict" "$CASE_REPORT" && grep -qi '\*\*pass\*\*' "$CASE_REPORT"; then
  echo "  PASS: case-insensitive verdict matching"
  PASS=$((PASS + 1))
else
  echo "  FAIL: verdict matching should be case-insensitive"
  FAIL=$((FAIL + 1))
fi

# Test: report with no verdict line at all
NO_VERDICT="$TEST_TMP/no-verdict-report.md"
cat > "$NO_VERDICT" << 'EOF'
| AC-1.1: login | PASS | works |
EOF
if grep -qi "overall verdict" "$NO_VERDICT"; then
  echo "  FAIL: should not find verdict in report without one"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: no verdict detected in report without verdict line"
  PASS=$((PASS + 1))
fi

# Test: stale report cleanup (verify_report.md deleted before evaluate)
STALE_REPORT="$TEST_TMP/stale-verify-report.md"
echo "stale content" > "$STALE_REPORT"
rm -f "$STALE_REPORT"
if [ ! -f "$STALE_REPORT" ]; then
  echo "  PASS: stale report cleanup works"
  PASS=$((PASS + 1))
else
  echo "  FAIL: stale report should be deleted"
  FAIL=$((FAIL + 1))
fi

# Test: awk extraction with Uncontracted but no Failures section
UNCONTRACTED_ONLY="$TEST_TMP/uncontracted-only-report.md"
cat > "$UNCONTRACTED_ONLY" << 'EOF'
## Acceptance Criteria Verdicts
| AC-1.1: login | PASS | works |

## Uncontracted Findings

### Finding: race condition in session handler
- **Severity**: blocker
- **Root cause**: src/session.ts:42

## Overall Verdict: **FAIL**
EOF
fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1; next} p && /^## /{exit} p' "$UNCONTRACTED_ONLY" | head -200)
assert_contains "uncontracted-only report extracts findings" "race condition" "$fix_context"
assert_contains "uncontracted-only includes root cause" "src/session.ts:42" "$fix_context"
assert_not_contains "uncontracted-only excludes verdict" "Overall Verdict" "$fix_context"
```

**Step 2: Run tests**

Run: `bash tests/test-rail.sh`
Expected: ~100 + ~10 = ~110 tests pass

**Step 3: Commit**

```bash
git add tests/test-rail.sh
git commit -m "test: add evaluate→fix pipeline logic tests (T.19)"
```

---

## Summary

| Task Group | Tests added | Cumulative |
|---|---|---|
| 1. Checkpoint functions (T.13) | ~6 | ~60 |
| 2. Git safety functions (T.14) | ~8 | ~68 |
| 3. Edge cases (T.15-T.18) | ~22 | ~90 |
| 4. Integration tests (T.6-T.8) | ~10 | ~100 |
| 5. Evaluate→Fix pipeline (T.19) | ~10 | ~110 |

Total: from **54 → ~110 tests**, covering all 14 functions in rail.sh.

---

## Review Addendum (post-review fixes)

Reviewed by: Quality Reviewer, Architect, Test Engineer. All critical/high issues addressed below.

### Fix 1: awk pattern must match production (T.12 existing + T.19)

The production awk at `rail.sh:537` is:
```
awk '/^## (Failures|Uncontracted)/{p=1} p && /^## Overall/{exit} p'
```
All test awk patterns must use this exact pattern, NOT the divergent `{p=1; next} p && /^## /{exit}` version.

Update existing T.12 (lines 650, 668) and all T.19 awk calls to match production.

### Fix 2: Add `run_session_if_needed` tests (new T.13b)

Add to Task Group 1 after T.13. Three branches:
1. Checkpoint already done → skip
2. Artifact file exists and non-empty → auto-save checkpoint, skip
3. Neither → calls `run_session`

### Fix 3: Replace tautological stale-report test (T.19)

Remove the `rm -f` test (plan lines 712-722). Replace with: verify that reading a stale report with `**PASS**` after a FAIL evaluate doesn't produce a false positive (i.e., test that the verdict-check code requires BOTH "overall verdict" AND `**pass**` on the same grep pass).

### Fix 4: Fix `git_rollback` nonexistent-tag test (T.14)

Replace unconditional PASS with:
```bash
git_rollback "nonexistent-tag" && rc=0 || rc=$?
assert_eq "git_rollback with missing tag exits cleanly" "0" "$rc"
```

### Fix 5: Add `BRIEF` and re-define `log()` in T.6 setup

Before calling `run_session` in integration tests:
```bash
export BRIEF="test brief"
log() { echo "[TEST] $*" >> "$INT_LOG_DIR/rail.log"; }
```

### Fix 6: Add `detect_skills "evaluate"` test (T.5b)

```bash
result=$(detect_skills "evaluate" "")
assert_contains "evaluate default → testing" "testing" "$result"
assert_contains "evaluate default → agent-browser" "agent-browser" "$result"
```

### Fix 7: Add MAX_EVAL_ITERATIONS boundary test (T.19)

Test that with `MAX_EVAL_ITERATIONS=0`, the loop body never executes and `verify_passed` stays false. Test via:
```bash
# seq 1 0 produces no output → loop body never runs
iterations=$(seq 1 0 | wc -l | tr -d ' ')
assert_eq "MAX_EVAL_ITERATIONS=0 → zero loop iterations" "0" "$iterations"
```

### Fix 8: Add extraction validation guards

In `extract_functions()`, after each `eval`, add:
```bash
type function_name >/dev/null 2>&1 || { echo "FATAL: extraction of function_name failed"; exit 1; }
```
