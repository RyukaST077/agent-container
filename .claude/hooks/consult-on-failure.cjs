#!/usr/bin/env node
// consult-on-failure.js  —  PostToolUse hook (matcher: Bash) — cross-platform Node port
//
//   After a Bash command runs, inspect its result. If it looks like a real failure:
//     1. drop a "pending-trouble" marker (so the Stop hook can later offer save-knowledge)
//     2. once per session, inject a reminder to use the `consult-knowledge` skill
//
//   Matching is intentionally high-precision to avoid nagging during normal iteration.
//   Pure Node.js — no external dependencies. Always exits 0 (non-blocking).
//
// I/O contract (Claude Code hooks):
//   - stdin : JSON { session_id, tool_input:{command}, tool_response:{...} }
//   - stdout: JSON { hookSpecificOutput: { additionalContext } } -> added to context

'use strict';

const fs = require('fs');
const path = require('path');

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

    const session = typeof data.session_id === 'string' ? data.session_id : '';
    const cmd = (data.tool_input && typeof data.tool_input.command === 'string')
      ? data.tool_input.command : '';

    // Haystack: the command plus the full raw payload (covers tool_response of any shape).
    const hay = cmd + '\n' + raw;

    // High-precision failure signatures (Maven / npm / Java / Python / Docker / shell).
    const fail = /BUILD FAILURE|BUILD FAILED|npm ERR!|Traceback \(most recent call last\)|Exception in thread|\] ERROR|: error:|fatal:|command not found|No such file or directory|Cannot find|ModuleNotFoundError|ImportError|NoClassDefFoundError|ClassNotFoundException|EADDRINUSE|ECONNREFUSED|ENOENT|Connection refused|Port .* (is )?already in use|Permission denied|Tests run:.*Failures: [1-9]|Tests run:.*Errors: [1-9]|non-zero exit|exit code [1-9]|exit status [1-9]|panic:|segmentation fault/i;

    if (!fail.test(hay)) return;

    const root = process.env.CLAUDE_PROJECT_DIR && process.env.CLAUDE_PROJECT_DIR.trim()
      ? process.env.CLAUDE_PROJECT_DIR
      : process.cwd();
    const cache = path.join(root, '.claude', '.cache', 'knowledge');
    fs.mkdirSync(cache, { recursive: true });

    // Record an unsaved trouble for this session (Stop hook reads this).
    fs.writeFileSync(path.join(cache, 'pending-trouble'), session);

    // Nudge consult-knowledge at most once per session (avoid spam while iterating).
    const consulted = path.join(cache, 'consulted');
    let already = '';
    try { already = fs.readFileSync(consulted, 'utf8').trim(); } catch { /* no prior marker */ }

    if (already !== session || !session.trim()) {
      fs.writeFileSync(consulted, session);
      const msg = '⚠️ A command appears to have failed. If this is a non-trivial trouble, use the **consult-knowledge** skill to search knowledge/ for a known fix before investigating from scratch. After you solve a new (unrecorded) one, offer the **save-knowledge** skill so the next occurrence is an instant hit.';
      const out = { hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: msg } };
      process.stdout.write(JSON.stringify(out));
    }
  } catch {
    // Never block on hook failure.
  }
})();
