#!/usr/bin/env bash
#
# consult-on-prompt.sh  —  UserPromptSubmit hook
#
#   When the user's message looks like a development-trouble report (error / build
#   failure / "won't start" / エラー / 失敗 ...), inject a one-line reminder so Claude
#   reaches for the `consult-knowledge` skill BEFORE investigating from scratch.
#
#   This only adds context (a hint). It never blocks the prompt.
#
# I/O contract (Claude Code hooks):
#   - stdin : JSON with at least { "prompt": "<user text>" }
#   - stdout: JSON { hookSpecificOutput: { additionalContext } } -> added to context
#   - exit 0 always (non-blocking)
#
set -euo pipefail

input="$(cat)"

prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
[ -z "$prompt" ] && exit 0

# Trouble vocabulary (English + Japanese). High-signal symptom words only.
pattern='error|errors|exception|traceback|stack ?trace|fail|failed|failing|cannot|can'\''t|unable|crash|broken|not work|does ?n'\''t work|won'\''t start|refused|timeout|エラー|失敗|落ちる|起動しない|動かない|繋がら|つながら|例外|タイムアウト|権限|アクセスできない|ビルド'

if printf '%s' "$prompt" | grep -iqE "$pattern"; then
  msg='💡 The user seems to be reporting a development trouble. Before investigating from scratch, use the **consult-knowledge** skill to check knowledge/ for a previously recorded fix. Treat any hit as a strong hint, not gospel — verify before applying. If knowledge/ has no match and you solve a new one, offer the **save-knowledge** skill afterward.'
  jq -nc --arg c "$msg" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}}'
fi

exit 0
