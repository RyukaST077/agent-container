# consult-on-failure.ps1 — Codex PostToolUse hook (PowerShell port).
#
#   When a Bash command output looks like a real failure, set a pending-trouble
#   marker and remind Codex to use consult-knowledge once per session.
#   Pure PowerShell — no external dependencies. Always exits 0 (non-blocking).
$ErrorActionPreference = 'SilentlyContinue'
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $data = $raw | ConvertFrom-Json
    $session = [string]$data.session_id
    if (-not $session) { $session = [string]$data.sessionId }
    $cmd = [string]$data.tool_input.command
    if (-not $cmd) { $cmd = [string]$data.toolInput.command }

    # Haystack: the command plus the full raw payload (covers tool_response of any shape).
    $hay = "$cmd`n$raw"

    $fail = 'BUILD FAILURE|BUILD FAILED|npm ERR!|Traceback \(most recent call last\)|Exception in thread|\] ERROR|: error:|fatal:|command not found|No such file or directory|Cannot find|ModuleNotFoundError|ImportError|NoClassDefFoundError|ClassNotFoundException|EADDRINUSE|ECONNREFUSED|ENOENT|Connection refused|Port .* (is )?already in use|Permission denied|Tests run:.*Failures: [1-9]|Tests run:.*Errors: [1-9]|non-zero exit|exit code [1-9]|exit status [1-9]|panic:|segmentation fault'

    if (-not ($hay -imatch $fail)) { exit 0 }

    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    $root = ([string]$root).Trim()
    $cache = Join-Path $root '.codex/.cache/knowledge'
    [System.IO.Directory]::CreateDirectory($cache) | Out-Null

    [System.IO.File]::WriteAllText((Join-Path $cache 'pending-trouble'), $session)

    $consulted = Join-Path $cache 'consulted'
    $already = ''
    if (Test-Path $consulted) { $already = ([System.IO.File]::ReadAllText($consulted)).Trim() }
    if ($already -ne $session -or [string]::IsNullOrWhiteSpace($session)) {
        [System.IO.File]::WriteAllText($consulted, $session)
        $msg = 'A command appears to have failed. If this is a non-trivial trouble, use the consult-knowledge skill to search knowledge/ for a known fix before investigating from scratch. After solving a new one, offer save-knowledge.'
        $out = [ordered]@{
            hookSpecificOutput = [ordered]@{ hookEventName = 'PostToolUse'; additionalContext = $msg }
            additionalContext  = $msg
        }
        $json = $out | ConvertTo-Json -Compress -Depth 6
        $stdout = [Console]::OpenStandardOutput()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
    }
} catch { }
exit 0
