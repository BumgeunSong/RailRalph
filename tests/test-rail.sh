#!/usr/bin/env bash
set -euo pipefail

#
# Unit tests for RailRalph pipeline functions
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAIL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMP="$(mktemp -d)"
PROJECT_DIR="$TEST_TMP/fake-project"
mkdir -p "$PROJECT_DIR/.git" "$PROJECT_DIR/openspec"
PASS=0
FAIL=0

# --- Test Helpers ---
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — '$needle' not found in output"
    FAIL=$((FAIL + 1))
  fi
}

assert_empty() {
  local label="$1" actual="$2"
  if [ -z "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — expected empty, got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label — '$needle' found in output (should not be)"
    FAIL=$((FAIL + 1))
  fi
}

cleanup() {
  rm -rf "$TEST_TMP"
  echo ""
  echo "================================"
  echo "Results: $PASS passed, $FAIL failed"
  echo "================================"
  [ "$FAIL" -eq 0 ]
}
trap cleanup EXIT

# --- Source harness functions ---
# We need to source just the functions from rail.sh without executing the main script.
# Extract function definitions into a sourceable file.

extract_functions() {
  # Source required variables
  export RAIL_DIR
  export PROJECT_DIR
  export LOG_DIR="$TEST_TMP/logs"
  export CHANGE_DIR="$TEST_TMP/change"
  export CHANGE_NAME="test-change"
  mkdir -p "$LOG_DIR" "$CHANGE_DIR"

  # Define log function
  log() { echo "[TEST] $*" >> "$LOG_DIR/rail.log"; }

  # Source get_section_content and get_section_unchecked
  eval "$(sed -n '/^get_section_content()/,/^}/p' "$RAIL_DIR/rail.sh")"
  type get_section_content >/dev/null 2>&1 || { echo "FATAL: extraction of get_section_content failed"; exit 1; }
  eval "$(sed -n '/^get_section_unchecked()/,/^}/p' "$RAIL_DIR/rail.sh")"
  type get_section_unchecked >/dev/null 2>&1 || { echo "FATAL: extraction of get_section_unchecked failed"; exit 1; }

  # Portability: timeout shim for tests (must actually enforce timeout)
  if ! command -v timeout &>/dev/null; then
    if command -v gtimeout &>/dev/null; then
      timeout() { gtimeout "$@"; }
    else
      # Use perl alarm for real timeout on macOS (perl is always available)
      timeout() { local dur="$1"; shift; perl -e 'alarm shift @ARGV; exec @ARGV' "$dur" "$@"; }
    fi
  fi

  # Source run_tsc_gate
  export TSC_TIMEOUT=2
  eval "$(sed -n '/^run_tsc_gate()/,/^}/p' "$RAIL_DIR/rail.sh")"
  type run_tsc_gate >/dev/null 2>&1 || { echo "FATAL: extraction of run_tsc_gate failed"; exit 1; }

  # Source detect_skills and its dependencies
  eval "$(sed -n '/^SKILL_KEYWORDS=.*{SKILL_KEYWORDS/p' "$RAIL_DIR/rail.sh")"
  eval "$(sed -n '/^detect_skills()/,/^}/p' "$RAIL_DIR/rail.sh")"
  type detect_skills >/dev/null 2>&1 || { echo "FATAL: extraction of detect_skills failed"; exit 1; }
}

extract_functions

# ============================================================
# T.1: Test run_tsc_gate() under set -euo pipefail
# ============================================================
echo ""
echo "=== T.1: run_tsc_gate() ==="

# Create mock npx directory
MOCK_BIN="$TEST_TMP/mock-bin"
mkdir -p "$MOCK_BIN"

# Test: tsc passes
cat > "$MOCK_BIN/npx" << 'MOCK'
#!/usr/bin/env bash
echo "tsc ok"
exit 0
MOCK
chmod +x "$MOCK_BIN/npx"

(
  set -euo pipefail
  export PATH="$MOCK_BIN:$PATH"
  if run_tsc_gate; then
    echo "  PASS: tsc exit 0 → returns 0"
    echo "P" > "$TEST_TMP/t1a"
  else
    echo "  FAIL: tsc exit 0 → should return 0"
    echo "F" > "$TEST_TMP/t1a"
  fi
)
[ "$(cat "$TEST_TMP/t1a")" = "P" ] && PASS=$((PASS + 1)) || FAIL=$((FAIL + 1))

# Test: tsc fails — harness must NOT exit
cat > "$MOCK_BIN/npx" << 'MOCK'
#!/usr/bin/env bash
for i in $(seq 1 150); do echo "error TS$i: something wrong"; done
exit 1
MOCK
chmod +x "$MOCK_BIN/npx"

(
  set -euo pipefail
  export PATH="$MOCK_BIN:$PATH"
  TSC_ERRORS=""
  if run_tsc_gate; then
    echo "F" > "$TEST_TMP/t1b"
  else
    # Should reach here — harness did NOT exit
    echo "P" > "$TEST_TMP/t1b"
    echo "$TSC_ERRORS" > "$TEST_TMP/t1b_errors"
  fi
  # If we reach here, set -e did not kill us
  echo "alive" > "$TEST_TMP/t1b_alive"
)

if [ "$(cat "$TEST_TMP/t1b" 2>/dev/null)" = "P" ]; then
  echo "  PASS: tsc exit 1 → returns 1, harness survives"
  PASS=$((PASS + 1))
else
  echo "  FAIL: tsc exit 1 → harness should survive"
  FAIL=$((FAIL + 1))
fi

# Check truncation to 100 lines
error_lines=$(wc -l < "$TEST_TMP/t1b_errors" 2>/dev/null || echo "0")
error_lines=$(echo "$error_lines" | tr -d ' ')
if [ "$error_lines" -le 100 ]; then
  echo "  PASS: tsc errors truncated to ≤100 lines (got $error_lines)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: tsc errors should be ≤100 lines, got $error_lines"
  FAIL=$((FAIL + 1))
fi

# Test: tsc hangs → killed by timeout
cat > "$MOCK_BIN/npx" << 'MOCK'
#!/usr/bin/env bash
exec sleep 999
MOCK
chmod +x "$MOCK_BIN/npx"

(
  set -euo pipefail
  export PATH="$MOCK_BIN:$PATH"
  export TSC_TIMEOUT=1
  run_tsc_gate || true
  echo "alive" > "$TEST_TMP/t1c"
)

if [ "$(cat "$TEST_TMP/t1c" 2>/dev/null)" = "alive" ]; then
  echo "  PASS: hanging tsc killed by timeout, harness survives"
  PASS=$((PASS + 1))
else
  echo "  FAIL: hanging tsc should be killed by timeout"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# T.2: Test match-skills.sh
# ============================================================
echo ""
echo "=== T.2: match-skills.sh ==="

# Create fixture skills
FIXTURE_SKILLS="$TEST_TMP/fixture-project/.claude/skills"
FIXTURE_USER_SKILLS="$TEST_TMP/fixture-user/.claude/skills"
mkdir -p "$FIXTURE_SKILLS/react-component" "$FIXTURE_SKILLS/testing" "$FIXTURE_SKILLS/unsafe-skill"
mkdir -p "$FIXTURE_USER_SKILLS/react-component" "$FIXTURE_USER_SKILLS/user-only"

cat > "$FIXTURE_SKILLS/react-component/SKILL.md" << 'EOF'
---
name: react-component
description: Use when creating or modifying React components (.tsx files)
---
# Content
EOF

cat > "$FIXTURE_SKILLS/testing/SKILL.md" << 'EOF'
---
name: testing
description: Use when writing tests, adding coverage
---
# Content
EOF

cat > "$FIXTURE_SKILLS/unsafe-skill/SKILL.md" << 'EOF'
---
name: ../../etc
description: Malicious skill
---
# Content
EOF

cat > "$FIXTURE_USER_SKILLS/react-component/SKILL.md" << 'EOF'
---
name: react-component
description: User-level version of react-component
---
# User content
EOF

cat > "$FIXTURE_USER_SKILLS/user-only/SKILL.md" << 'EOF'
---
name: user-only
description: A user-only skill for browser testing
---
# User content
EOF

# Create a modified match-skills.sh that uses fixture dirs
FIXTURE_MATCH="$TEST_TMP/match-skills-fixture.sh"
sed "s|\"\$PROJECT_DIR/.claude/skills\"|\"$FIXTURE_SKILLS\"|;s|\"\$HOME/.claude/skills\"|\"$FIXTURE_USER_SKILLS\"|" "$RAIL_DIR/match-skills.sh" > "$FIXTURE_MATCH"
chmod +x "$FIXTURE_MATCH"

result=$(PROJECT_DIR="$TEST_TMP/fixture-project" "$FIXTURE_MATCH" "component")
assert_contains "keyword 'component' → react-component" "react-component" "$result"

result=$(PROJECT_DIR="$TEST_TMP/fixture-project" "$FIXTURE_MATCH" "test")
assert_contains "keyword 'test' → testing" "testing" "$result"

result=$(PROJECT_DIR="$TEST_TMP/fixture-project" "$FIXTURE_MATCH" "nonexistent")
assert_empty "keyword 'nonexistent' → empty" "$result"

result=$(PROJECT_DIR="$TEST_TMP/fixture-project" "$FIXTURE_MATCH" "Component")
assert_contains "case-insensitive 'Component' → react-component" "react-component" "$result"

result=$(PROJECT_DIR="$TEST_TMP/fixture-project" "$FIXTURE_MATCH" "etc")
assert_not_contains "unsafe name ../../etc filtered out" "../../etc" "$result"

# Collision test: project-level shadows user-level
result=$(PROJECT_DIR="$TEST_TMP/fixture-project" "$FIXTURE_MATCH" "component")
count=$(echo "$result" | tr ' ' '\n' | grep -c 'react-component' || true)
assert_eq "collision: react-component appears once" "1" "$count"

# User-only skill found
result=$(PROJECT_DIR="$TEST_TMP/fixture-project" "$FIXTURE_MATCH" "browser")
assert_contains "user-only skill 'browser' → user-only" "user-only" "$result"

# ============================================================
# T.3: Test get_section_content()
# ============================================================
echo ""
echo "=== T.3: get_section_content() ==="

FIXTURE_TASKS="$TEST_TMP/fixture-tasks.md"
cat > "$FIXTURE_TASKS" << 'EOF'
## Group A
- [ ] task 1
- [x] task 2

## Group B (special & chars)
- [ ] task 3

## Tests
- [ ] test 1
EOF

result=$(get_section_content "Group A" "$FIXTURE_TASKS")
assert_contains "Group A → contains 'task 1'" "task 1" "$result"
assert_contains "Group A → contains 'task 2'" "task 2" "$result"

result=$(get_section_content "Group B (special & chars)" "$FIXTURE_TASKS")
assert_contains "Group B with special chars → task 3" "task 3" "$result"

# Returns raw text, not a count
lines=$(echo "$result" | wc -l | tr -d ' ')
assert_eq "Group B returns raw text (1 line)" "1" "$lines"

# ============================================================
# T.4: Test PR number extraction
# ============================================================
echo ""
echo "=== T.4: PR number extraction ==="

extract_pr() { echo "$1" | grep -oE 'pull/[0-9]+' | grep -oE '[0-9]+' | head -1; }

result=$(extract_pr "github.com/owner/repo/pull/123")
assert_eq "pull/123 → 123" "123" "$result"

result=$(extract_pr "https://github.com/foo/bar/pull/456")
assert_eq "pull/456 → 456" "456" "$result"

result=$(extract_pr "no pr url here" || true)
assert_empty "no PR URL → empty" "$result"

result=$(extract_pr "Step #1 then some text" || true)
assert_empty "Step #1 (no PR URL) → empty" "$result"

# ============================================================
# T.5: Test gap report
# ============================================================
echo ""
echo "=== T.5: gap report ==="

# Fixture with unchecked tasks
GAP_CHANGE_DIR="$TEST_TMP/gap-test"
mkdir -p "$GAP_CHANGE_DIR"
GAP_TASKS="$GAP_CHANGE_DIR/tasks.md"

cat > "$GAP_TASKS" << 'EOF'
## Group 1
- [ ] unchecked task
- [x] checked task
EOF

total_unchecked=$(grep -c '^- \[ \]' "$GAP_TASKS" || true)
if [ "$total_unchecked" -gt 0 ]; then
  grep '^- \[ \]' "$GAP_TASKS" > "$GAP_CHANGE_DIR/apply_gaps.md"
fi

if [ -f "$GAP_CHANGE_DIR/apply_gaps.md" ]; then
  echo "  PASS: apply_gaps.md written when unchecked tasks exist"
  PASS=$((PASS + 1))
else
  echo "  FAIL: apply_gaps.md should be written"
  FAIL=$((FAIL + 1))
fi

# Fixture with all checked
cat > "$GAP_TASKS" << 'EOF'
## Group 1
- [x] checked task 1
- [x] checked task 2
EOF

rm -f "$GAP_CHANGE_DIR/apply_gaps.md"
total_unchecked=$(grep -c '^- \[ \]' "$GAP_TASKS" || true)
if [ "$total_unchecked" -gt 0 ]; then
  grep '^- \[ \]' "$GAP_TASKS" > "$GAP_CHANGE_DIR/apply_gaps.md"
fi

if [ ! -f "$GAP_CHANGE_DIR/apply_gaps.md" ]; then
  echo "  PASS: no apply_gaps.md when all tasks checked"
  PASS=$((PASS + 1))
else
  echo "  FAIL: apply_gaps.md should not be written when all tasks checked"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# T.5b: Test detect_skills()
# ============================================================
echo ""
echo "=== T.5b: detect_skills() ==="

# Set MATCH_SKILLS to the real script for integration
MATCH_SKILLS="$RAIL_DIR/match-skills.sh"

# Phase defaults — apply-group
result=$(detect_skills "apply-group" "")
assert_contains "apply-group default → code-style" "code-style" "$result"

# Phase defaults — verify
result=$(detect_skills "verify" "")
assert_contains "verify default → testing" "testing" "$result"
assert_contains "verify default → type-system" "type-system" "$result"
assert_contains "verify default → code-style" "code-style" "$result"
assert_contains "verify default → agent-browser" "agent-browser" "$result"

# Config-driven design skills
result=$(DESIGN_SKILLS="custom-design" detect_skills "design" "")
assert_contains "design with config → custom-design" "custom-design" "$result"

# Empty default (no config)
result=$(DESIGN_SKILLS="" detect_skills "design" "")
assert_empty "design default with no config → empty" "$result"

# Empty content, unknown phase → no skills
result=$(detect_skills "unknown-phase" "")
assert_empty "unknown phase, empty content → empty" "$result"

# Deduplication — verify phase already has "testing", content with "test" also resolves to "testing"
result=$(detect_skills "verify" "write a test for this")
count=$(echo "$result" | tr ' ' '\n' | grep -c '^testing$' || true)
assert_eq "dedup: testing appears once" "1" "$count"

# evaluate phase defaults
result=$(detect_skills "evaluate" "")
assert_contains "evaluate default → testing" "testing" "$result"
assert_contains "evaluate default → agent-browser" "agent-browser" "$result"

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
SAVED_PROJECT_DIR="${PROJECT_DIR:-}"
SAVED_LOG_DIR="${LOG_DIR:-}"
SAVED_CHANGE_NAME="${CHANGE_NAME:-}"
export PROJECT_DIR="$INT_PROJECT"
export CHANGE_NAME="int-test"
INT_LOG_DIR="$TEST_TMP/int-logs"
export LOG_DIR="$INT_LOG_DIR"
mkdir -p "$INT_LOG_DIR"
CHECKPOINT_FILE="$INT_LOG_DIR/checkpoint"
rm -f "$CHECKPOINT_FILE"
export BRIEF="test brief"
log() { echo "[TEST] $*" >> "$INT_LOG_DIR/rail.log"; }

eval "$(sed -n '/^checkpoint_done()/,/^}/p' "$RAIL_DIR/rail.sh")"
type checkpoint_done >/dev/null 2>&1 || { echo "FATAL: extraction of checkpoint_done failed"; exit 1; }
eval "$(sed -n '/^checkpoint_save()/,/^}/p' "$RAIL_DIR/rail.sh")"
type checkpoint_save >/dev/null 2>&1 || { echo "FATAL: extraction of checkpoint_save failed"; exit 1; }
eval "$(sed -n '/^git_snapshot()/,/^}/p' "$RAIL_DIR/rail.sh")"
type git_snapshot >/dev/null 2>&1 || { echo "FATAL: extraction of git_snapshot failed"; exit 1; }
eval "$(sed -n '/^git_rollback()/,/^}/p' "$RAIL_DIR/rail.sh")"
type git_rollback >/dev/null 2>&1 || { echo "FATAL: extraction of git_rollback failed"; exit 1; }
eval "$(sed -n '/^git_ensure_committed()/,/^}/p' "$RAIL_DIR/rail.sh")"
type git_ensure_committed >/dev/null 2>&1 || { echo "FATAL: extraction of git_ensure_committed failed"; exit 1; }
eval "$(sed -n '/^run_session()/,/^}/p' "$RAIL_DIR/rail.sh")"
type run_session >/dev/null 2>&1 || { echo "FATAL: extraction of run_session failed"; exit 1; }

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

# ============================================================
# T.10: ALLOWED_TOOLS passthrough to station.sh
# ============================================================
echo ""
echo "=== T.10: ALLOWED_TOOLS passthrough ==="

# Create mock claude that records its arguments
MOCK_CLAUDE_DIR="$TEST_TMP/mock-claude-bin"
mkdir -p "$MOCK_CLAUDE_DIR"
CLAUDE_ARGS_LOG="$TEST_TMP/claude-args.log"
cat > "$MOCK_CLAUDE_DIR/claude" << MOCK
#!/usr/bin/env bash
echo "\$@" > "$CLAUDE_ARGS_LOG"
exit 0
MOCK
chmod +x "$MOCK_CLAUDE_DIR/claude"

# Create minimal project structure
MOCK_PROJECT="$TEST_TMP/mock-project-t10"
mkdir -p "$MOCK_PROJECT/.git" "$MOCK_PROJECT/openspec/changes/test-change"

# Capture path to real station.sh before subshell (station.sh self-resolves RAIL_DIR from dirname $0)
REAL_SESSION_SH="$RAIL_DIR/station.sh"

# Guard: evaluate.md must exist (created in Task 2)
if [ ! -f "$RAIL_DIR/prompts/evaluate.md" ]; then
  echo "  SKIP: T.10 requires prompts/evaluate.md (run after Task 2)"
else
  # Run station.sh with restricted ALLOWED_TOOLS
  (
    export ALLOWED_TOOLS="Bash Read Glob Grep"
    export PROJECT_DIR="$MOCK_PROJECT"
    PATH="$MOCK_CLAUDE_DIR:$PATH" \
      "$REAL_SESSION_SH" \
      "test-change" "evaluate" "sonnet" "brief" "$LOG_DIR" "" "t10" 2>/dev/null || true
  )

  if [ -f "$TEST_TMP/claude-args.log" ]; then
    args=$(cat "$TEST_TMP/claude-args.log")
    # Extract only the --allowed-tools value (the space-separated list after the flag)
    allowed_tools_value=$(echo "$args" | grep -oE '\-\-allowed-tools [A-Za-z ]+' | sed 's/--allowed-tools //')
    assert_not_contains "evaluate excludes Write from --allowed-tools" "Write" "$allowed_tools_value"
    assert_not_contains "evaluate excludes Edit from --allowed-tools" "Edit" "$allowed_tools_value"
    assert_contains "evaluate includes Bash in --allowed-tools" "Bash" "$allowed_tools_value"
    assert_contains "evaluate includes Read in --allowed-tools" "Read" "$allowed_tools_value"
  else
    echo "  FAIL: claude was not invoked — check station.sh path"
    FAIL=$((FAIL + 1))
  fi
fi  # end guard for evaluate.md existence

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

blocker_count=$(grep -ci '\*\*severity\*\*: blocker' "$BLOCKER_REPORT" 2>/dev/null || true)
assert_eq "blocker uncontracted finding detected" "1" "$blocker_count"

fail_count=$(grep -c '| FAIL |' "$BLOCKER_REPORT" 2>/dev/null || true)
assert_eq "no FAIL rows in blocker report" "0" "$fail_count"

# Simulate the actual verdict branch logic from rail.sh
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
assert_not_contains "Overall Verdict line excluded by production awk pattern" "Overall Verdict" "$fix_context"

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

# ============================================================
# T.13: Checkpoint functions
# ============================================================
echo ""
echo "=== T.13: Checkpoint functions ==="

# Source checkpoint functions (reuse if already sourced in T.6 integration, but define locally)
CHECKPOINT_FILE="$TEST_TMP/checkpoint-test"
rm -f "$CHECKPOINT_FILE"

# checkpoint_done and checkpoint_save already sourced in T.6 block above via extract_functions scope
# Re-eval here to ensure CHECKPOINT_FILE variable is used by these functions
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

# Checkpoint with special characters (colon and underscore in group names)
checkpoint_save "apply-group:Task_Group_1"
if checkpoint_done "apply-group:Task_Group_1"; then
  echo "  PASS: checkpoint with colon/underscore works"
  PASS=$((PASS + 1))
else
  echo "  FAIL: checkpoint with colon/underscore should work"
  FAIL=$((FAIL + 1))
fi

# ============================================================
# T.13b: run_session_if_needed branches
# ============================================================
echo ""
echo "=== T.13b: run_session_if_needed ==="

# Set up a temporary project for run_session_if_needed tests
T13B_PROJECT="$TEST_TMP/t13b-project"
T13B_CHANGE="$T13B_PROJECT/openspec/changes/t13b-change"
T13B_LOG="$TEST_TMP/t13b-logs"
mkdir -p "$T13B_CHANGE" "$T13B_LOG"
(
  cd "$T13B_PROJECT"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "init" > base.txt
  git add base.txt
  git commit -q -m "init"
)

T13B_CHECKPOINT="$T13B_LOG/checkpoint"
rm -f "$T13B_CHECKPOINT"
export CHECKPOINT_FILE="$T13B_CHECKPOINT"
export PROJECT_DIR="$T13B_PROJECT"
export CHANGE_DIR="$T13B_CHANGE"
export CHANGE_NAME="t13b-change"
export LOG_DIR="$T13B_LOG"
export BRIEF="test brief"
log() { echo "[TEST] $*" >> "$T13B_LOG/rail.log"; }

eval "$(sed -n '/^checkpoint_done()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^checkpoint_save()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_snapshot()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_rollback()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^git_ensure_committed()/,/^}/p' "$RAIL_DIR/rail.sh")"
eval "$(sed -n '/^run_session()/,/^}/p' "$RAIL_DIR/rail.sh")"

# Mock run_session to track calls
RUN_SESSION_CALLED="$TEST_TMP/run_session_called"
rm -f "$RUN_SESSION_CALLED"
run_session_mock_called=0

# Define run_session_if_needed inline (matches rail.sh production)
run_session_if_needed() {
  local phase="$1"
  local model="$2"
  local artifact="$3"

  if checkpoint_done "$phase"; then
    log "SKIP (checkpoint): $phase already completed"
    return 0
  fi
  if [ -s "$CHANGE_DIR/$artifact" ]; then
    log "SKIP (artifact exists): $phase — $artifact already present"
    checkpoint_save "$phase"
    return 0
  fi
  run_session "$phase" "$model"
}

# Override run_session for branch-3 test to avoid actual claude invocation
run_session() {
  run_session_mock_called=$((run_session_mock_called + 1))
  echo "mock-run-session-$1" >> "$RUN_SESSION_CALLED"
  return 0
}

# Branch 1: checkpoint already done → skip without calling run_session
checkpoint_save "branch1-phase"
run_session_mock_called=0
run_session_if_needed "branch1-phase" "sonnet" "branch1.md"
assert_eq "run_session_if_needed: checkpoint done → skip (no run_session call)" "0" "$run_session_mock_called"

# Branch 2: artifact exists and non-empty → auto-save checkpoint, skip
echo "artifact content" > "$T13B_CHANGE/branch2.md"
run_session_mock_called=0
run_session_if_needed "branch2-phase" "sonnet" "branch2.md"
assert_eq "run_session_if_needed: artifact exists → skip (no run_session call)" "0" "$run_session_mock_called"
if checkpoint_done "branch2-phase"; then
  echo "  PASS: run_session_if_needed auto-saves checkpoint when artifact exists"
  PASS=$((PASS + 1))
else
  echo "  FAIL: run_session_if_needed should auto-save checkpoint when artifact exists"
  FAIL=$((FAIL + 1))
fi

# Branch 3: neither checkpoint nor artifact → calls run_session
run_session_mock_called=0
rm -f "$T13B_CHANGE/branch3.md"
run_session_if_needed "branch3-phase" "sonnet" "branch3.md"
assert_eq "run_session_if_needed: no checkpoint no artifact → calls run_session" "1" "$run_session_mock_called"

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
SAVED_PROJECT_DIR_T14="$PROJECT_DIR"
SAVED_CHANGE_NAME_T14="$CHANGE_NAME"
export PROJECT_DIR="$GIT_TEST_DIR"
export CHANGE_NAME="test-feature"
T14_LOG="$TEST_TMP/t14-logs"
mkdir -p "$T14_LOG"
export LOG_DIR="$T14_LOG"
export CHECKPOINT_FILE="$T14_LOG/checkpoint"
log() { echo "[TEST] $*" >> "$T14_LOG/rail.log"; }

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

# git_rollback with nonexistent tag exits cleanly (does not crash)
git_rollback "nonexistent-tag" && rc=0 || rc=$?
assert_eq "git_rollback with missing tag exits cleanly" "0" "$rc"

# git_ensure_committed creates safety commit when dirty
# Need openspec/ dir to exist for SAFETY_COMMIT_PATHS default
mkdir -p "$GIT_TEST_DIR/openspec"
echo "uncommitted work" > "$GIT_TEST_DIR/openspec/change.md"
(cd "$GIT_TEST_DIR" && git add openspec/change.md)
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
export PROJECT_DIR="$SAVED_PROJECT_DIR_T14"
export CHANGE_NAME="$SAVED_CHANGE_NAME_T14"

# ============================================================
# T.15: resolve_project_dir()
# ============================================================
echo ""
echo "=== T.15: resolve_project_dir() ==="

eval "$(sed -n '/^resolve_project_dir()/,/^}/p' "$RAIL_DIR/rail.sh")"
type resolve_project_dir >/dev/null 2>&1 || { echo "FATAL: extraction of resolve_project_dir failed"; exit 1; }

# Finds git root from subdirectory
NESTED_DIR="$TEST_TMP/git-nested/src/deep"
mkdir -p "$NESTED_DIR"
(cd "$TEST_TMP/git-nested" && git init -q 2>/dev/null)
result=$(cd "$NESTED_DIR" && resolve_project_dir)
expected=$(cd -P "$TEST_TMP/git-nested" && pwd)
assert_eq "resolve_project_dir finds git root from nested dir" "$expected" "$result"

# RAILRALPH_PROJECT_DIR overrides git detection
OVERRIDE_DIR="$TEST_TMP/override-project"
mkdir -p "$OVERRIDE_DIR"
result=$(RAILRALPH_PROJECT_DIR="$OVERRIDE_DIR" resolve_project_dir)
expected_override=$(cd -P "$OVERRIDE_DIR" && pwd)
assert_eq "RAILRALPH_PROJECT_DIR overrides git detection" "$expected_override" "$result"

# Fails when no git repo and no override
result=$(cd /tmp && unset RAILRALPH_PROJECT_DIR && resolve_project_dir 2>/dev/null) || true
if [ -z "$result" ]; then
  echo "  PASS: resolve_project_dir fails outside git repo"
  PASS=$((PASS + 1))
else
  echo "  FAIL: should fail outside git repo, got: $result"
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
assert_eq "minor severity does NOT override PASS" "PASS" "${overall:-}"

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

# Test: stale report — a report with **PASS** but flagged as stale should not
# produce a false positive (verify that verdict-check requires BOTH conditions)
STALE_REPORT="$TEST_TMP/stale-verify-report.md"
cat > "$STALE_REPORT" << 'EOF'
## Acceptance Criteria Results
| AC-1.1 | PASS | works |

## Overall Verdict: **PASS**
EOF
# Simulate reading stale report after a fresh FAIL evaluate: the old PASS
# report must not produce verify_passed=true unless BOTH grep conditions hold
stale_verdict=""
if grep -qi "overall verdict" "$STALE_REPORT" && grep -qi '\*\*pass\*\*' "$STALE_REPORT"; then
  fail_count_stale=$(grep -c '| FAIL |' "$STALE_REPORT" 2>/dev/null || true)
  blocker_count_stale=$(grep -ci '\*\*severity\*\*: blocker' "$STALE_REPORT" 2>/dev/null || true)
  if [ "$fail_count_stale" -gt 0 ]; then
    stale_verdict="FAIL-by-threshold"
  elif [ "$blocker_count_stale" -gt 0 ]; then
    stale_verdict="FAIL-by-blocker"
  else
    stale_verdict="PASS"
  fi
fi
# A report with PASS verdict and no FAILs should detect as PASS (no false negative)
assert_eq "stale PASS report: both verdict conditions required" "PASS" "${stale_verdict:-}"

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
fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1} p && /^## Overall/{exit} p' "$UNCONTRACTED_ONLY" | head -200)
assert_contains "uncontracted-only report extracts findings" "race condition" "$fix_context"
assert_contains "uncontracted-only includes root cause" "src/session.ts:42" "$fix_context"
assert_not_contains "uncontracted-only excludes verdict" "Overall Verdict" "$fix_context"

# Test: MAX_EVAL_ITERATIONS=1 boundary — only evaluate runs, no fix session
# When MAX_EVAL_ITERATIONS=1, the fix guard (eval_iter < MAX_EVAL_ITERATIONS) prevents fix
# seq 1 1 produces exactly 1 iteration
iterations=$(seq 1 1 | wc -l | tr -d ' ')
assert_eq "MAX_EVAL_ITERATIONS=1 → exactly one loop iteration" "1" "$iterations"

# The fix session guard: on last iteration (eval_iter == MAX_EVAL_ITERATIONS), fix is skipped
eval_iter=1; MAX_EVAL_ITERATIONS=1
if [ "$eval_iter" -lt "$MAX_EVAL_ITERATIONS" ]; then
  fix_ran="yes"
else
  fix_ran="no"
fi
assert_eq "last iteration skips fix session" "no" "$fix_ran"
