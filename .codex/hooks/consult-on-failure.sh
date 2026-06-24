#!/usr/bin/env bash
#
# PostToolUse hook: when a Bash command output looks like a real failure, set a
# pending-trouble marker and remind Codex to use consult-knowledge once.
#
set -euo pipefail

input="$(cat)"

session="$(printf '%s' "$input" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // .toolInput.command // empty' 2>/dev/null || true)"
resp="$(printf '%s' "$input" | jq -r '[.tool_response // .toolResponse // empty | .. | strings] | join("\n")' 2>/dev/null || true)"

hay="${cmd}"$'\n'"${resp}"
fail='BUILD FAILURE|BUILD FAILED|npm ERR!|Traceback \(most recent call last\)|Exception in thread|\] ERROR|: error:|fatal:|command not found|No such file or directory|Cannot find|ModuleNotFoundError|ImportError|NoClassDefFoundError|ClassNotFoundException|EADDRINUSE|ECONNREFUSED|ENOENT|Connection refused|Port .* (is )?already in use|Permission denied|Tests run:.*Failures: [1-9]|Tests run:.*Errors: [1-9]|non-zero exit|exit code [1-9]|exit status [1-9]|panic:|segmentation fault'

if ! printf '%s' "$hay" | grep -iqE "$fail"; then
  exit 0
fi

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cache="$root/.codex/.cache/knowledge"
mkdir -p "$cache"

printf '%s\n' "$session" > "$cache/pending-trouble"

already=""
[ -f "$cache/consulted" ] && already="$(cat "$cache/consulted" 2>/dev/null || true)"
if [ "$already" != "$session" ] || [ -z "$session" ]; then
  printf '%s\n' "$session" > "$cache/consulted"
  msg='A command appears to have failed. If this is a non-trivial trouble, use the consult-knowledge skill to search knowledge/ for a known fix before investigating from scratch. After solving a new one, offer save-knowledge.'
  jq -nc --arg c "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}, additionalContext:$c}'
fi

exit 0
