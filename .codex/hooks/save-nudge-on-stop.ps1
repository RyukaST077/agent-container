# save-nudge-on-stop.ps1 — Codex Stop hook (PowerShell port).
#
#   If a command failed during the session, remind the user that the resolved
#   trouble can be saved with save-knowledge.
#   Pure PowerShell — no external dependencies. Always exits 0 (allow the stop).
$ErrorActionPreference = 'SilentlyContinue'
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $data = $raw | ConvertFrom-Json
    $active = "$($data.stop_hook_active)$($data.stopHookActive)"
    if ($active -imatch 'true') { exit 0 }

    $session = [string]$data.session_id
    if (-not $session) { $session = [string]$data.sessionId }

    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    $root = ([string]$root).Trim()
    $marker = Join-Path $root '.codex/.cache/knowledge/pending-trouble'

    if (-not (Test-Path $marker)) { exit 0 }

    $saved = ([System.IO.File]::ReadAllText($marker)).Trim()
    Remove-Item $marker -Force -ErrorAction SilentlyContinue

    if (-not [string]::IsNullOrWhiteSpace($session) -and $saved -eq $session) {
        $msg = 'A command failed during this session. Once the trouble is resolved, consider recording it with the save-knowledge skill so the fix is reusable next time.'
        $out = [ordered]@{ systemMessage = $msg }
        $json = $out | ConvertTo-Json -Compress -Depth 6
        $stdout = [Console]::OpenStandardOutput()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
    }
} catch { }
exit 0
