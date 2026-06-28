# consult-on-failure.ps1  —  PostToolUse hook (matcher: Bash) — PowerShell port
#
#   After a Bash command runs, inspect its result. If it looks like a real failure:
#     1. drop a "pending-trouble" marker (so the Stop hook can later offer save-knowledge)
#     2. once per session, inject a reminder to use the `consult-knowledge` skill
#
#   Matching is intentionally high-precision to avoid nagging during normal iteration.
#   Pure PowerShell — no external dependencies. Always exits 0 (non-blocking).
#
# I/O contract (Claude Code hooks):
#   - stdin : JSON { session_id, tool_input:{command}, tool_response:{...} }
#   - stdout: JSON { hookSpecificOutput: { additionalContext } } -> added to context
$ErrorActionPreference = 'SilentlyContinue'
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $data = $raw | ConvertFrom-Json
    $session = [string]$data.session_id
    $cmd = [string]$data.tool_input.command

    # Haystack: the command plus the full raw payload (covers tool_response of any shape).
    $hay = "$cmd`n$raw"

    # High-precision failure signatures (Maven / npm / Java / Python / Docker / shell).
    $fail = 'BUILD FAILURE|BUILD FAILED|npm ERR!|Traceback \(most recent call last\)|Exception in thread|\] ERROR|: error:|fatal:|command not found|No such file or directory|Cannot find|ModuleNotFoundError|ImportError|NoClassDefFoundError|ClassNotFoundException|EADDRINUSE|ECONNREFUSED|ENOENT|Connection refused|Port .* (is )?already in use|Permission denied|Tests run:.*Failures: [1-9]|Tests run:.*Errors: [1-9]|non-zero exit|exit code [1-9]|exit status [1-9]|panic:|segmentation fault'

    if (-not ($hay -imatch $fail)) { exit 0 }

    $root = $env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrWhiteSpace($root)) { $root = (Get-Location).Path }
    $cache = Join-Path $root '.claude/.cache/knowledge'
    [System.IO.Directory]::CreateDirectory($cache) | Out-Null

    # Record an unsaved trouble for this session (Stop hook reads this).
    [System.IO.File]::WriteAllText((Join-Path $cache 'pending-trouble'), $session)

    # Nudge consult-knowledge at most once per session (avoid spam while iterating).
    $consulted = Join-Path $cache 'consulted'
    $already = ''
    if (Test-Path $consulted) { $already = ([System.IO.File]::ReadAllText($consulted)).Trim() }
    if ($already -ne $session -or [string]::IsNullOrWhiteSpace($session)) {
        [System.IO.File]::WriteAllText($consulted, $session)
        $msg = '⚠️ A command appears to have failed. If this is a non-trivial trouble, use the **consult-knowledge** skill to search knowledge/ for a known fix before investigating from scratch. After you solve a new (unrecorded) one, offer the **save-knowledge** skill so the next occurrence is an instant hit.'
        $out = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PostToolUse'; additionalContext = $msg } }
        $json = $out | ConvertTo-Json -Compress -Depth 6
        $stdout = [Console]::OpenStandardOutput()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        $stdout.Write($bytes, 0, $bytes.Length)
        $stdout.Flush()
    }
} catch { }
exit 0
