#!/usr/bin/env bash
set -euo pipefail

#
# Unit tests for RailRalph Announcer
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RAIL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ANNOUNCER="$RAIL_DIR/railralph-announcer.sh"
TEST_TMP="$(mktemp -d)"
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

# Helper: run announcer in background, write lines, collect output
# Usage: run_announcer <log_file> <output_file> <lines...> — then "STOP" to send terminal line
run_announcer() {
  local log_file="$1" out_file="$2"
  shift 2
  touch "$log_file"
  "$ANNOUNCER" "$log_file" > "$out_file" 2>/dev/null &
  local pid=$!
  sleep 0.5
  for line in "$@"; do
    echo "$line" >> "$log_file"
  done
  # Wait for process to exit (max 3s)
  local waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 6 ]; do
    sleep 0.5
    waited=$((waited + 1))
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "$pid"
}

cleanup() {
  # Kill any leftover announcer processes
  pkill -f "railralph-announcer.*$TEST_TMP" 2>/dev/null || true
  rm -rf "$TEST_TMP"
  echo ""
  echo "================================"
  echo "Results: $PASS passed, $FAIL failed"
  echo "================================"
  [ "$FAIL" -eq 0 ]
}
trap cleanup EXIT

# ============================================================
echo "=== Announcer Tests ==="
# ============================================================

# --- A.1: Announcer prefixes lines with train emoji ---
echo "A.1: Prefixes lines with 🚂"
LOG="$TEST_TMP/a1.log"
OUT="$TEST_TMP/a1.out"
run_announcer "$LOG" "$OUT" \
  '[00:00:01] test line one' \
  '[00:00:02] RAILRALPH ARRIVED'
assert_contains "A.1a first line prefixed" "🚂 [00:00:01] test line one" "$(cat "$OUT")"
assert_contains "A.1b arrived line prefixed" "🚂 [00:00:02] RAILRALPH ARRIVED" "$(cat "$OUT")"

# --- A.2: Announcer exits on ARRIVED ---
echo "A.2: Exits on ARRIVED"
LOG="$TEST_TMP/a2.log"
OUT="$TEST_TMP/a2.out"
touch "$LOG"
"$ANNOUNCER" "$LOG" > "$OUT" 2>/dev/null &
PID=$!
sleep 0.5
echo '[00:00:01] RAILRALPH ARRIVED' >> "$LOG"
# Wait up to 3s for exit
waited=0
while kill -0 "$PID" 2>/dev/null && [ "$waited" -lt 6 ]; do
  sleep 0.5
  waited=$((waited + 1))
done
if ! kill -0 "$PID" 2>/dev/null; then
  echo "  PASS: A.2 — process exited after ARRIVED"
  PASS=$((PASS + 1))
else
  echo "  FAIL: A.2 — process still running after ARRIVED"
  FAIL=$((FAIL + 1))
  kill "$PID" 2>/dev/null || true
fi
wait "$PID" 2>/dev/null || true

# --- A.3: Announcer exits on INTERRUPTED ---
echo "A.3: Exits on INTERRUPTED"
LOG="$TEST_TMP/a3.log"
OUT="$TEST_TMP/a3.out"
touch "$LOG"
"$ANNOUNCER" "$LOG" > "$OUT" 2>/dev/null &
PID=$!
sleep 0.5
echo '[00:00:01] INTERRUPTED — cleaning up...' >> "$LOG"
waited=0
while kill -0 "$PID" 2>/dev/null && [ "$waited" -lt 6 ]; do
  sleep 0.5
  waited=$((waited + 1))
done
if ! kill -0 "$PID" 2>/dev/null; then
  echo "  PASS: A.3 — process exited after INTERRUPTED"
  PASS=$((PASS + 1))
else
  echo "  FAIL: A.3 — process still running after INTERRUPTED"
  FAIL=$((FAIL + 1))
  kill "$PID" 2>/dev/null || true
fi
wait "$PID" 2>/dev/null || true

# --- A.4: Announcer waits for log file to exist ---
echo "A.4: Waits for log file"
LOG="$TEST_TMP/a4.log"
OUT="$TEST_TMP/a4.out"
# Do NOT create log file yet
"$ANNOUNCER" "$LOG" > "$OUT" 2>/dev/null &
PID=$!
sleep 1.5
# Announcer should still be running (waiting for file)
if kill -0 "$PID" 2>/dev/null; then
  echo "  PASS: A.4a — process waiting for log file"
  PASS=$((PASS + 1))
else
  echo "  FAIL: A.4a — process exited before log file created"
  FAIL=$((FAIL + 1))
fi
# Now create the log and write lines
echo '[00:00:01] hello' > "$LOG"
sleep 0.5
echo '[00:00:02] RAILRALPH ARRIVED' >> "$LOG"
waited=0
while kill -0 "$PID" 2>/dev/null && [ "$waited" -lt 6 ]; do
  sleep 0.5
  waited=$((waited + 1))
done
assert_contains "A.4b picked up line" "🚂 [00:00:01] hello" "$(cat "$OUT")"
wait "$PID" 2>/dev/null || true

# --- A.5: Multiple lines forwarded in order ---
echo "A.5: Multiple lines in order"
LOG="$TEST_TMP/a5.log"
OUT="$TEST_TMP/a5.out"
run_announcer "$LOG" "$OUT" \
  '[00:00:01] line one' \
  '[00:00:02] line two' \
  '[00:00:03] line three' \
  '[00:00:04] RAILRALPH ARRIVED'
LINE_COUNT=$(wc -l < "$OUT" | tr -d ' ')
assert_eq "A.5a — 4 lines output" "4" "$LINE_COUNT"
FIRST_LINE=$(head -1 "$OUT")
LAST_LINE=$(tail -1 "$OUT")
assert_contains "A.5b — first is line one" "line one" "$FIRST_LINE"
assert_contains "A.5c — last is ARRIVED" "ARRIVED" "$LAST_LINE"

# --- A.6: Announcer is killable (simulates pipeline cleanup) ---
echo "A.6: Killable by signal"
LOG="$TEST_TMP/a6.log"
OUT="$TEST_TMP/a6.out"
touch "$LOG"
"$ANNOUNCER" "$LOG" > "$OUT" 2>/dev/null &
PID=$!
sleep 0.5
echo '[00:00:01] some log line' >> "$LOG"
sleep 0.5
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
sleep 0.5
if ! kill -0 "$PID" 2>/dev/null; then
  echo "  PASS: A.6 — process terminated by kill"
  PASS=$((PASS + 1))
else
  echo "  FAIL: A.6 — process survived kill"
  FAIL=$((FAIL + 1))
fi
