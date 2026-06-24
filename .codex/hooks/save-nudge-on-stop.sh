#!/usr/bin/env bash
#
# Stop hook: if a command failed during the session, remind the user that the
# resolved trouble can be saved with save-knowledge.
#
set -euo pipefail

input="$(cat)"

active="$(printf '%s' "$input" | jq -r '.stop_hook_active // .stopHookActive // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)"
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cache="$root/.codex/.cache/knowledge"
marker="$cache/pending-trouble"

[ -f "$marker" ] || exit 0

saved_session="$(cat "$marker" 2>/dev/null || true)"
rm -f "$marker"

if [ -n "$session" ] && [ "$saved_session" = "$session" ]; then
  msg='A command failed during this session. Once the trouble is resolved, consider recording it with the save-knowledge skill so the fix is reusable next time.'
  jq -nc --arg c "$msg" '{systemMessage:$c}'
fi

exit 0
