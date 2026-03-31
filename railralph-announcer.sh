#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:?Usage: railralph-announcer.sh <log-file-path>}"

# Wait for log file to exist
while [ ! -f "$LOG_FILE" ]; do sleep 1; done

# Use a named pipe so we can kill tail -f cleanly on exit
FIFO="$(mktemp -u).railralph-announcer"
mkfifo "$FIFO"

tail -f "$LOG_FILE" > "$FIFO" &
TAIL_PID=$!
trap 'kill $TAIL_PID 2>/dev/null; wait $TAIL_PID 2>/dev/null || true; rm -f "$FIFO"' EXIT

while IFS= read -r line; do
  echo "🚂 $line"
  case "$line" in
    *"ARRIVED"*|*"INTERRUPTED"*) exit 0 ;;
  esac
done < "$FIFO"
