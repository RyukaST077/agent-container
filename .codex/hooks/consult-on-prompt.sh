#!/usr/bin/env bash
#
# UserPromptSubmit hook: remind Codex to consult knowledge/ when a prompt looks
# like a development trouble report.
#
set -euo pipefail

input="$(cat)"

prompt="$(printf '%s' "$input" | jq -r '.prompt // .user_prompt // .message // empty' 2>/dev/null || true)"
[ -z "$prompt" ] && exit 0

pattern='error|errors|exception|traceback|stack ?trace|fail|failed|failing|cannot|can'\''t|unable|crash|broken|not work|does ?n'\''t work|won'\''t start|refused|timeout|エラー|失敗|落ちる|起動しない|動かない|繋がら|つながら|例外|タイムアウト|権限|アクセスできない|ビルド'

if printf '%s' "$prompt" | grep -iqE "$pattern"; then
  msg='The user seems to be reporting a development trouble. Before investigating from scratch, use the consult-knowledge skill to check knowledge/ for a previously recorded fix. Treat any hit as a strong hint and verify before applying.'
  jq -nc --arg c "$msg" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$c}, additionalContext:$c}'
fi

exit 0
