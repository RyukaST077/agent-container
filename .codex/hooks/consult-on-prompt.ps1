# consult-on-prompt.ps1 — Codex UserPromptSubmit hook (PowerShell port).
#
#   Remind Codex to consult knowledge/ when a prompt looks like a development
#   trouble report. Pure PowerShell — no external dependencies (no jq / grep).
#   Always exits 0 (non-blocking).
$ErrorActionPreference = 'SilentlyContinue'
try {
    $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $data = $raw | ConvertFrom-Json
    $prompt = [string]$data.prompt
    if (-not $prompt) { $prompt = [string]$data.user_prompt }
    if (-not $prompt) { $prompt = [string]$data.message }
    if ([string]::IsNullOrWhiteSpace($prompt)) { exit 0 }

    $pattern = 'error|errors|exception|traceback|stack ?trace|fail|failed|failing|cannot|can''t|unable|crash|broken|not work|does ?n''t work|won''t start|refused|timeout|エラー|失敗|落ちる|起動しない|動かない|繋がら|つながら|例外|タイムアウト|権限|アクセスできない|ビルド'

    if ($prompt -imatch $pattern) {
        $msg = 'The user seems to be reporting a development trouble. Before investigating from scratch, use the consult-knowledge skill to check knowledge/ for a previously recorded fix. Treat any hit as a strong hint and verify before applying.'
        $out = [ordered]@{
            hookSpecificOutput = [ordered]@{ hookEventName = 'UserPromptSubmit'; additionalContext = $msg }
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
