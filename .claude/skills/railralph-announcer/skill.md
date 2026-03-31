---
name: railralph-announcer
description: "Use when the developer asks to run railralph, start railralph, or provides a task for railralph to work on. Monitors pipeline progress and narrates in real-time."
---

# RailRalph Announcer

Start a RailRalph pipeline in the background and narrate its progress to the developer.

## Inputs

Gather from the developer (ask if missing):
- **Project directory**: The git repo to work on
- **Change name**: Lowercase hyphenated identifier (e.g., `admin-review-page`)
- **Brief**: 1-2 sentence description

If the developer provides a GitHub issue URL, fetch it with `gh issue view` and derive the change name and brief.

## Start the Pipeline

```bash
cd "$PROJECT_DIR" && \
  RAILRALPH_PROJECT_DIR="$PROJECT_DIR" \
  bash /Users/bumgeunsong/coding/BashRalph/rail.sh \
  "$CHANGE_NAME" "$BRIEF" \
  > /tmp/railralph-$CHANGE_NAME.log 2>&1
```

**Critical details:**
- `rail.sh` takes TWO positional args: `<change-name> "<brief>"` (NOT flags)
- Set `RAILRALPH_PROJECT_DIR` env var to the target project
- Run with `run_in_background: true` so you can monitor
- Redirect to `/tmp/` (the `.railralph/` dir doesn't exist until rail.sh creates it)

## Find the Log File

After starting, read the output to find `RUN_ID`:

```bash
head -20 /tmp/railralph-$CHANGE_NAME.log
```

Look for `Run ID: YYYYMMDD-HHMMSS`. The log file is:
```
$PROJECT_DIR/.railralph/logs/$RUN_ID/rail.log
```

## Monitor Loop

Repeat until pipeline completes:

1. Read new lines: `tail -n +$LAST_LINE "$LOG_FILE" 2>/dev/null | head -50`
2. Output each line prefixed with `🚂`
3. Update `LAST_LINE` counter
4. If any line contains `ARRIVED` or `INTERRUPTED` → stop
5. Sleep 10 seconds between checks

## Pipeline Phases

What the log lines mean:

| Log pattern | Phase | What's happening |
|---|---|---|
| `PHASE 1: PLANNING` | Planning | 6 sessions: proposal → review → design → review → specs → tasks |
| `PHASE 2: APPLY` | Implementation | One session per task group, with TSC gate + retries |
| `PHASE 3: VERIFICATION` | Verify | Evaluate (opus, read-only) → fix (sonnet) loop, max 3 iterations |
| `Starting session: X` | Session start | A `claude -p` session is running |
| `Completed session: X` | Session end | Duration and exit code shown |
| `TSC GATE: PASS/FAIL` | Type check | TypeScript compilation gate between apply groups |
| `Evaluate PASSED` | Verify pass | All acceptance criteria met |
| `OVERRIDE:` | Verify fail | Individual criteria failed despite overall verdict |
| `RAILRALPH ARRIVED` | Done | Pipeline complete |
| `INTERRUPTED` | Stopped | Pipeline was interrupted |

## Narration Rules

- Prefix every log line with `🚂`
- Do NOT summarize or interpret — forward as-is
- Do NOT add commentary between checks
- On `ARRIVED`: show the summary and ask about artifacts
- On error or no new lines for 5+ minutes: mention it

## On-demand Q&A

If the developer asks a question mid-run, read the relevant artifact from `$PROJECT_DIR/openspec/changes/$CHANGE_NAME/`:
- `verify_report.md` — evaluation results
- `tasks.md` — implementation checklist
- `handoff.md` — last session's handoff notes
- `proposal.md`, `design.md` — planning artifacts
