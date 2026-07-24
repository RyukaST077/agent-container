#!/usr/bin/env node
// save-nudge-on-stop.js  —  Stop hook (cross-platform Node port)
//
//   When Claude finishes a turn, if a real command failure happened earlier in THIS
//   session (left by consult-on-failure.js) and hasn't been recorded yet, show the
//   user a gentle, visible reminder to capture it with the `save-knowledge` skill.
//
//   - Fires at most once per trouble episode (the marker is cleared on the first nudge).
//   - Session-id matched, so a stale marker from a previous session is cleared silently.
//   Pure Node.js — no external dependencies. Always exits 0 (allow the stop).
//
// I/O contract (Claude Code hooks):
//   - stdin : JSON { session_id, stop_hook_active }
//   - stdout: JSON { systemMessage } -> shown to the user

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

    // If we're already in a hook-triggered continuation, do nothing (prevents loops).
    if (data.stop_hook_active === true || String(data.stop_hook_active).toLowerCase() === 'true') return;

    const session = typeof data.session_id === 'string' ? data.session_id : '';
    const root = process.env.CLAUDE_PROJECT_DIR && process.env.CLAUDE_PROJECT_DIR.trim()
      ? process.env.CLAUDE_PROJECT_DIR
      : process.cwd();
    const marker = path.join(root, '.claude', '.cache', 'knowledge', 'pending-trouble');

    if (!fs.existsSync(marker)) return;

    let saved = '';
    try { saved = fs.readFileSync(marker, 'utf8').trim(); } catch { /* unreadable */ }
    // Clear unconditionally: nudge at most once per trouble episode.
    try { fs.unlinkSync(marker); } catch { /* already gone */ }

    // Only nudge when the failure belongs to the current session.
    if (session.trim() && saved === session) {
      const msg = '💡 A command failed during this session. Once the trouble is resolved, consider recording it with the save-knowledge skill (just say "save it") so the fix is reusable next time.';
      const out = { systemMessage: msg };
      process.stdout.write(JSON.stringify(out));
    }
  } catch {
    // Never block the stop on hook failure.
  }
})();
