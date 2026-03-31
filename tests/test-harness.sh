#!/usr/bin/env bash
set -euo pipefail

#
# Unit tests for long-running harness functions
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
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
# We need to source just the functions from run.sh without executing the main script.
# Extract function definitions into a sourceable file.

extract_functions() {
  # Source required variables
  export HARNESS_DIR
  export PROJECT_DIR
  export LOG_DIR="$TEST_TMP/logs"
  export CHANGE_DIR="$TEST_TMP/change"
  export CHANGE_NAME="test-change"
  mkdir -p "$LOG_DIR" "$CHANGE_DIR"

  # Define log function
  log() { echo "[TEST] $*" >> "$LOG_DIR/harness.log"; }

  # Source get_section_content and get_section_unchecked
  eval "$(sed -n '/^get_section_content()/,/^}/p' "$HARNESS_DIR/run.sh")"
  eval "$(sed -n '/^get_section_unchecked()/,/^}/p' "$HARNESS_DIR/run.sh")"

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
  eval "$(sed -n '/^run_tsc_gate()/,/^}/p' "$HARNESS_DIR/run.sh")"

  # Source detect_skills and its dependencies
  eval "$(sed -n '/^SKILL_KEYWORDS=.*{SKILL_KEYWORDS/p' "$HARNESS_DIR/run.sh")"
  eval "$(sed -n '/^detect_skills()/,/^}/p' "$HARNESS_DIR/run.sh")"
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
sed "s|\"\$PROJECT_DIR/.claude/skills\"|\"$FIXTURE_SKILLS\"|;s|\"\$HOME/.claude/skills\"|\"$FIXTURE_USER_SKILLS\"|" "$HARNESS_DIR/match-skills.sh" > "$FIXTURE_MATCH"
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
MATCH_SKILLS="$HARNESS_DIR/match-skills.sh"

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

# ============================================================
# T.6-T.8: Integration tests (placeholders)
# ============================================================
echo ""
echo "=== T.6-T.8: Integration tests (placeholders) ==="
echo "  SKIP: T.6 — dry-run apply loop requires full harness"
echo "  SKIP: T.7 — dry-run review-response requires gh CLI + PR"
echo "  SKIP: T.8 — dry-run skill injection requires claude CLI"

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
# T.10: ALLOWED_TOOLS passthrough to session.sh
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
    # Extract only the --allowed-tools value (the space-separated list after the flag)
    allowed_tools_value=$(echo "$args" | grep -oE '\-\-allowed-tools [A-Za-z ]+' | sed 's/--allowed-tools //')
    assert_not_contains "evaluate excludes Write from --allowed-tools" "Write" "$allowed_tools_value"
    assert_not_contains "evaluate excludes Edit from --allowed-tools" "Edit" "$allowed_tools_value"
    assert_contains "evaluate includes Bash in --allowed-tools" "Bash" "$allowed_tools_value"
    assert_contains "evaluate includes Read in --allowed-tools" "Read" "$allowed_tools_value"
  else
    echo "  FAIL: claude was not invoked — check session.sh path"
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

fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1; next} p && /^## /{exit} p' "$FULL_REPORT" | head -200)
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
fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1; next} p && /^## /{exit} p' "$F_HEADING_REPORT" | head -200)
assert_contains "failures section extracted" "AC-1.1" "$fix_context"
assert_not_contains "## Further Analysis excluded by new awk pattern" "Further Analysis" "$fix_context"

# No failures section → empty context + fallback
NO_FAIL="$TEST_TMP/no-fail-report.md"
printf '## Overall Verdict: **PASS**\n' > "$NO_FAIL"
fix_context=$(awk '/^## (Failures|Uncontracted)/{p=1; next} p && /^## /{exit} p' "$NO_FAIL" | head -200)
assert_empty "no failures section → empty awk result" "$fix_context"

# Fallback: when awk is empty, use head of full report
if [ -z "$fix_context" ]; then
  fix_context=$(head -200 "$NO_FAIL")
fi
assert_contains "fallback uses full report" "Overall Verdict" "$fix_context"
