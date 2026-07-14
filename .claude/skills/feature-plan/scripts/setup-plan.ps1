#!/usr/bin/env pwsh
# PowerShell port of setup-plan.sh — resolve feature paths and seed plan.md from the template.
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
@'
Usage: setup-plan.ps1 [-Json]
  -Json    Output results in JSON format
  -Help    Show this help message
'@
    exit 0
}

. (Join-Path $PSScriptRoot 'common.ps1')

try { $paths = Get-FeaturePathsEnv }
catch { Write-Error $_.Exception.Message; exit 1 }

# Ensure the feature directory exists
if (-not (Test-Path -LiteralPath $paths.FEATURE_DIR -PathType Container)) {
    New-Item -ItemType Directory -Path $paths.FEATURE_DIR -Force | Out-Null
}

# Copy plan template if plan doesn't already exist.
# Informational messages go to stderr in -Json mode so they never corrupt the JSON payload on stdout.
if (Test-Path -LiteralPath $paths.IMPL_PLAN -PathType Leaf) {
    $msg = "Plan already exists at $($paths.IMPL_PLAN), skipping template copy"
    if ($Json) { [Console]::Error.WriteLine($msg) } else { Write-Output $msg }
} else {
    $template = Resolve-Template -TemplateName 'plan-template' -RepoRoot $paths.REPO_ROOT
    if ($template -and (Test-Path -LiteralPath $template -PathType Leaf)) {
        Copy-Item -LiteralPath $template -Destination $paths.IMPL_PLAN -Force
        $msg = "Copied plan template to $($paths.IMPL_PLAN)"
        if ($Json) { [Console]::Error.WriteLine($msg) } else { Write-Output $msg }
    } else {
        $msg = "Warning: Plan template not found"
        if ($Json) { [Console]::Error.WriteLine($msg) } else { Write-Output $msg }
        # Create a basic plan file if the template doesn't exist (mirrors bash `touch`).
        New-Item -ItemType File -Path $paths.IMPL_PLAN -Force | Out-Null
    }
}

# Output results
if ($Json) {
    [PSCustomObject]@{
        FEATURE_SPEC = $paths.FEATURE_SPEC
        IMPL_PLAN    = $paths.IMPL_PLAN
        SPECS_DIR    = $paths.FEATURE_DIR
        BRANCH       = $paths.CURRENT_BRANCH
    } | ConvertTo-Json -Compress
} else {
    "FEATURE_SPEC: $($paths.FEATURE_SPEC)"
    "IMPL_PLAN: $($paths.IMPL_PLAN)"
    "SPECS_DIR: $($paths.FEATURE_DIR)"
    "BRANCH: $($paths.CURRENT_BRANCH)"
}
