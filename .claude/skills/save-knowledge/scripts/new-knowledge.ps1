# new-knowledge.ps1  (PowerShell port of new-knowledge.sh)
#   Deterministically generate the save path for a knowledge file.
#   - Create knowledge/ under the project root (if absent)
#   - Print a unique path knowledge/YYYY-MM-DD-<slug>.md to stdout (appends -2, -3 ... on collision)
#   - Does NOT touch INDEX (INDEX update is handled by the SKILL.md flow)
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File new-knowledge.ps1 "<slug>" [<project-root>]
#
# Output:
#   Relative path of the file to create (one line). The caller writes to this path.
#
# Pure PowerShell — no external dependencies. PS 5.1 and 7+.
$ErrorActionPreference = 'Stop'

$slug = if ($args.Count -ge 1) { [string]$args[0] } else { '' }
$root = if ($args.Count -ge 2 -and $args[1]) { [string]$args[1] } else { (Get-Location).Path }

if ([string]::IsNullOrEmpty($slug)) {
    [Console]::Error.WriteLine("ERROR: slug is required. usage: new-knowledge.ps1 <slug> [project-root]")
    exit 2
}

# Sanitize slug: lowercase, non-alnum -> hyphen, collapse repeats, trim leading/trailing hyphens.
$safe = $slug.ToLowerInvariant()
$safe = [regex]::Replace($safe, '[^a-z0-9]+', '-')
$safe = [regex]::Replace($safe, '-+', '-')
$safe = $safe.Trim('-')
if ([string]::IsNullOrEmpty($safe)) { $safe = 'knowledge' }

$date = (Get-Date).ToString('yyyy-MM-dd')   # YYYY-MM-DD
$kdir = Join-Path $root 'knowledge'
[System.IO.Directory]::CreateDirectory($kdir) | Out-Null

$base = "$date-$safe"
$target = Join-Path $kdir "$base.md"

# Avoid filename collisions.
if (Test-Path -LiteralPath $target) {
    $i = 2
    while (Test-Path -LiteralPath (Join-Path $kdir "$base-$i.md")) { $i++ }
    $target = Join-Path $kdir "$base-$i.md"
}

# Return a path relative to ROOT (forward slash, LF only).
$name = [System.IO.Path]::GetFileName($target)
$bytes = [System.Text.Encoding]::UTF8.GetBytes("knowledge/$name`n")
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
exit 0
