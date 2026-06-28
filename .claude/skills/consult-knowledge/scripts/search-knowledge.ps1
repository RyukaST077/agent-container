# search-knowledge.ps1  (PowerShell port of search-knowledge.sh)
#
#   Search the project's knowledge/ folder for past trouble reports relevant to the
#   current trouble, and print a ranked list of candidate files to stdout.
#
#   Ranking: each search term is matched case-insensitively (fixed string) against every
#   knowledge file; a file's score is the number of *distinct* terms it matches (higher =
#   better), tie-broken by total line-match count. Files matching zero terms are omitted.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File search-knowledge.ps1 "<term1>" ["<term2>" ...] [--root <project-root>]
#
# Exit codes:
#   0  matches found (or no knowledge dir / no matches — see stderr note)
#   2  usage error (no terms given)
#
# Pure PowerShell — no external dependencies (no grep / sed). PS 5.1 and 7+.
$ErrorActionPreference = 'Stop'

$root = (Get-Location).Path
$terms = New-Object System.Collections.Generic.List[string]
$argList = @($args)
for ($i = 0; $i -lt $argList.Count; $i++) {
    if ($argList[$i] -eq '--root') {
        if ($i + 1 -lt $argList.Count) { $root = [string]$argList[$i + 1] }
        $i++
    } else {
        $terms.Add([string]$argList[$i])
    }
}

if ($terms.Count -eq 0) {
    [Console]::Error.WriteLine("ERROR: at least one search term is required. usage: search-knowledge.ps1 <term> [<term> ...] [--root <path>]")
    exit 2
}

$kdir = Join-Path $root 'knowledge'
if (-not (Test-Path -LiteralPath $kdir -PathType Container)) {
    [Console]::Error.WriteLine("NO_KNOWLEDGE_DIR: $kdir does not exist yet (nothing saved). Proceed without past knowledge.")
    exit 0
}

$files = @(Get-ChildItem -LiteralPath $kdir -Filter *.md -File -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) {
    [Console]::Error.WriteLine("NO_KNOWLEDGE_FILES: $kdir has no .md files yet. Proceed without past knowledge.")
    exit 0
}

$totalTerms = $terms.Count
$results = New-Object System.Collections.Generic.List[object]
$cmp = [System.StringComparison]::OrdinalIgnoreCase

foreach ($f in $files) {
    # Skip meta docs that aren't trouble reports (index / folder readme).
    if ($f.Name -eq 'INDEX.md' -or $f.Name -eq 'README.md') { continue }

    $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { continue }

    $distinct = 0
    $total = 0
    $detail = ''
    foreach ($term in $terms) {
        # Count lines containing this term (case-insensitive, fixed-string) — like grep -icF.
        $matched = @($lines | Where-Object { $_.IndexOf($term, $cmp) -ge 0 })
        $cnt = $matched.Count
        if ($cnt -gt 0) {
            $distinct++
            $total += $cnt
            $line = ([string]$matched[0]).Trim()
            if ($line.Length -gt 120) { $line = $line.Substring(0, 120) }
            $detail += "`n    $term | $line"
        }
    }

    if ($distinct -gt 0) {
        $results.Add([pscustomobject]@{ Distinct = $distinct; Total = $total; Base = $f.Name; Detail = $detail })
    }
}

if ($results.Count -eq 0) {
    [Console]::Error.WriteLine("NO_MATCH: no knowledge file matched the given terms. Proceed without past knowledge (consider saving this one afterward).")
    exit 0
}

# Sort by distinct desc, then total desc.
$sorted = $results | Sort-Object -Property @{ Expression = 'Distinct'; Descending = $true }, @{ Expression = 'Total'; Descending = $true }

$sb = New-Object System.Text.StringBuilder
foreach ($r in $sorted) {
    [void]$sb.Append("SCORE=$($r.Distinct)/$totalTerms  HITS=$($r.Total)  knowledge/$($r.Base)$($r.Detail)`n")
}
$bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
exit 0
