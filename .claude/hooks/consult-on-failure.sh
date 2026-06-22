#!/usr/bin/env bash
#
# consult-on-failure.sh  —  PostToolUse hook (matcher: Bash)
#
#   After a Bash command runs, inspect its result. If it looks like a real failure
#   (build/test failure, stack trace, "command not found", connection refused ...):
#     1. drop a "pending-trouble" marker (so the Stop hook can later offer save-knowledge)
#     2. once per session, inject a reminder to use the `consult-knowledge` skill
#
#   Matching is intentionally high-precision (it does NOT fire on a bare "error"
#   substring) to avoid nagging during normal iteration.
#
# I/O contract (Claude Code hooks):
#   - stdin : JSON { session_id, tool_input:{command}, tool_response:{...} }
#   - stdout: JSON { hookSpecificOutput: { additionalContext } } -> added to context
#   - exit 0 always (non-blocking)
#
set -euo pipefail

input="$(cat)"

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
# Pull every string value out of tool_response, whatever its shape.
resp="$(printf '%s' "$input" | jq -r '[.tool_response | .. | strings] | join("\n")' 2>/dev/null || true)"

hay="${cmd}"$'\n'"${resp}"

# High-precision failure signatures (Maven / npm / Java / Python / Docker / shell).
fail='BUILD FAILURE|BUILD FAILED|npm ERR!|Traceback \(most recent call last\)|Exception in thread|\] ERROR|: error:|fatal:|command not found|No such file or directory|Cannot find|ModuleNotFoundError|ImportError|NoClassDefFoundError|ClassNotFoundException|EADDRINUSE|ECONNREFUSED|ENOENT|Connection refused|Port .* (is )?already in use|Permission denied|Tests run:.*Failures: [1-9]|Tests run:.*Errors: [1-9]|non-zero exit|exit code [1-9]|exit status [1-9]|panic:|segmentation fault'

if ! printf '%s' "$hay" | grep -iqE "$fail"; then
  exit 0
fi

cache="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.cache/knowledge"
mkdir -p "$cache"

# Record an unsaved trouble for this session (Stop hook reads this).
printf '%s\n' "$session" > "$cache/pending-trouble"

# Nudge consult-knowledge at most once per session (avoid spam while iterating).
already=""
[ -f "$cache/consulted" ] && already="$(cat "$cache/consulted" 2>/dev/null || true)"
if [ "$already" != "$session" ] || [ -z "$session" ]; then
  printf '%s\n' "$session" > "$cache/consulted"
  msg='⚠️ A command appears to have failed. If this is a non-trivial trouble, use the **consult-knowledge** skill to search knowledge/ for a known fix before investigating from scratch. After you solve a new (unrecorded) one, offer the **save-knowledge** skill so the next occurrence is an instant hit.'
  jq -nc --arg c "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
fi

exit 0
