#!/usr/bin/env node
// consult-on-prompt.js  —  UserPromptSubmit hook (cross-platform Node port)
//
//   When the user's message looks like a development-trouble report, inject a one-line
//   reminder so Claude reaches for the `consult-knowledge` skill BEFORE investigating
//   from scratch. Only adds context (a hint); never blocks the prompt.
//
//   Pure Node.js — no external dependencies. Runs identically on Windows / macOS /
//   Linux because the hook command (`node .claude/hooks/consult-on-prompt.js`) contains
//   no shell-specific syntax. Always exits 0 (non-blocking).
//
// I/O contract (Claude Code hooks):
//   - stdin : JSON with at least { "prompt": "<user text>" }
//   - stdout: JSON { hookSpecificOutput: { additionalContext } } -> added to context

'use strict';

function readStdin() {
  return new Promise((resolve) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', () => resolve(data));
  });
}

(async () => {
  try {
    const raw = await readStdin();
    if (!raw || !raw.trim()) return;

    let data;
    try { data = JSON.parse(raw); } catch { return; }

    const prompt = typeof data.prompt === 'string' ? data.prompt : '';
    if (!prompt.trim()) return;

    // Trouble vocabulary (English + Japanese). High-signal symptom words only.
    const pattern = /error|errors|exception|traceback|stack ?trace|fail|failed|failing|cannot|can't|unable|crash|broken|not work|does ?n't work|won't start|refused|timeout|エラー|失敗|落ちる|起動しない|動かない|繋がら|つながら|例外|タイムアウト|権限|アクセスできない|ビルド/i;

    if (pattern.test(prompt)) {
      const msg = '💡 The user seems to be reporting a development trouble. Before investigating from scratch, use the **consult-knowledge** skill to check knowledge/ for a previously recorded fix. Treat any hit as a strong hint, not gospel — verify before applying. If knowledge/ has no match and you solve a new one, offer the **save-knowledge** skill afterward.';
      const out = { hookSpecificOutput: { hookEventName: 'UserPromptSubmit', additionalContext: msg } };
      process.stdout.write(JSON.stringify(out));
    }
  } catch {
    // Never block the prompt on hook failure.
  }
})();
