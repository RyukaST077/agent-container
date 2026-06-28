# save-nudge-on-stop.ps1  —  Stop hook (PowerShell port of save-nudge-on-stop.sh)
#
#   When Claude finishes a turn, if a real command failure happened earlier in THIS
#   session (left by consult-on-failure.ps1) and hasn't been recorded yet, show the
#   user a gentle, visible reminder to capture it with the `save-knowledge` skill.
#
#   - Fires at most once per trouble episode (the marker is cleared on the first nudge).
#   - Session-id matched, so a stale marker from a previous session is cleared silently.
#   Pure PowerShell — no external dependencies. Always exits 0 (allow the stop).
#
# I/O contract (Claude Code hooks):
#   - stdin : JSON { session_id, stop_hook_active }
#   - stdout: JSON { systemMessage } -> shown to the user
$ErrorActionPreference = 'SilentlyContinue'
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $data = $raw | ConvertFrom-Json

    # If we're already in a hook-triggered continuation, do nothing (prevents loops).
    if ("$($data.stop_hook_active)" -eq 'True' -or "$($data.stop_hook_active)" -eq 'true') { exit 0 }

    $session = [string]$data.session_id
    $root = $env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    $marker = Join-Path $root '.claude/.cache/knowledge/pending-trouble'

    if (-not (Test-Path $marker)) { exit 0 }

    $saved = ([System.IO.File]::ReadAllText($marker)).Trim()
    # Clear unconditionally: nudge at most once per trouble episode.
    Remove-Item $marker -Force -ErrorAction SilentlyContinue

    # Only nudge when the failure belongs to the current session.
    if (-not [string]::IsNullOrWhiteSpace($session) -and $saved -eq $session) {
        $msg = '💡 A command failed during this session. Once the trouble is resolved, consider recording it with the save-knowledge skill (just say "save it") so the fix is reusable next time.'
        $out = [ordered]@{ systemMessage = $msg }
        $json = $out | ConvertTo-Json -Compress -Depth 6
        $stdout = [Console]::OpenStandardOutput()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
    }
} catch { }
exit 0
