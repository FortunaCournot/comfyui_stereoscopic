# Issue 1: Forward Progress Display Breaks In-Place Rendering

Status: Open
Priority: Medium
Scope: Forward progress output in terminal mode

## Summary

During forward processing, progress entries such as `[#######-----------------------] pad-16-9-sbs` are printed as separate lines instead of updating a single terminal line in place.

## Expected Behavior

The forward progress bar should redraw on the same terminal line by using carriage-return based output. A newline should only be emitted when the progress step completes or when output intentionally transitions to a different status line.

## Observed Behavior

Each progress update appears on its own line. This causes the terminal output to scroll and makes the progress display much harder to read during longer runs.

## Known Context

- The likely rendering path is in [api/lib_forward.sh](../../api/lib_forward.sh), especially `render_progress_bar()` and the callers around it.
- The renderer itself is suspected to already use carriage-return style output.
- The bug is therefore likely caused by surrounding code that emits newlines, wraps the renderer in a pipeline, or flushes a final newline too early.

## Impact

- Forward progress output becomes noisy and difficult to monitor.
- Users cannot rely on a stable single-line progress display.
- Repeated line output can hide more important warnings or state transitions in the terminal log.

## Suggested Investigation

1. Inspect [api/lib_forward.sh](../../api/lib_forward.sh) for how `render_progress_bar()` writes the progress line.
2. Trace all callers in [api/forward.sh](../../api/forward.sh) and related shell helpers to find where newline-producing output is mixed into the same display flow.
3. Check whether the progress renderer is executed inside command substitution, pipelines, subshells, or logging wrappers that convert carriage returns into visible line breaks.
4. Verify that completion handling emits exactly one newline after the final progress update, not one newline per intermediate update.

## Acceptance Criteria

- Intermediate forward progress updates reuse a single terminal line.
- A newline is emitted only when the progress sequence finishes or intentionally changes to another message.
- The fix does not suppress legitimate log output from unrelated steps.
