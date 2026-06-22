#!/usr/bin/env bash
#
# save-nudge-on-stop.sh  —  Stop hook
#
#   When Claude finishes a turn, if a real command failure happened earlier in THIS
#   session (left by consult-on-failure.sh) and hasn't been recorded yet, show the
#   user a gentle, visible reminder to capture it with the `save-knowledge` skill.
#
#   - Fires at most once per trouble episode (the marker is cleared on the first nudge).
#   - Session-id matched, so a stale marker from a previous session is cleared silently.
#   - Uses `systemMessage` (visible to the user) instead of forcing another turn, so it
#     is never intrusive — the user opts in by saying "save it".
#
# I/O contract (Claude Code hooks):
#   - stdin : JSON { session_id, stop_hook_active }
#   - stdout: JSON { systemMessage } -> shown to the user
#   - exit 0 always (allow the stop; never loop)
#
set -euo pipefail

input="$(cat)"

# If we're already in a hook-triggered continuation, do nothing (prevents loops).
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$active" = "true" ] && exit 0

session="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
cache="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/.cache/knowledge"
marker="$cache/pending-trouble"

[ -f "$marker" ] || exit 0

saved_session="$(cat "$marker" 2>/dev/null || true)"
# Clear unconditionally: nudge at most once per trouble episode.
rm -f "$marker"

# Only nudge when the failure belongs to the current session.
if [ -n "$session" ] && [ "$saved_session" = "$session" ]; then
  jq -nc '{systemMessage:"💡 A command failed during this session. Once the trouble is resolved, consider recording it with the save-knowledge skill (just say \"save it\") so the fix is reusable next time."}'
fi

exit 0
