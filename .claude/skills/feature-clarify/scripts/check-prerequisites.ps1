#!/usr/bin/env pwsh
# Consolidated prerequisite checking (PowerShell port of check-prerequisites.sh).
#
# OPTIONS:
#   -Json           Output in JSON format
#   -RequireTasks   Require tasks.md to exist (implementation phase)
#   -IncludeTasks   Include tasks.md in AVAILABLE_DOCS
#   -PathsOnly      Only output path variables (no validation; no feature.json write)
#   -Help           Show help
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$RequireTasks,
    [switch]$IncludeTasks,
    [switch]$PathsOnly,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
@'
Usage: check-prerequisites.ps1 [OPTIONS]

Consolidated prerequisite checking for Spec-Driven Development workflow.

OPTIONS:
  -Json           Output in JSON format
  -RequireTasks   Require tasks.md to exist (for implementation phase)
  -IncludeTasks   Include tasks.md in AVAILABLE_DOCS list
  -PathsOnly      Only output path variables (no prerequisite validation)
  -Help           Show this help message

EXAMPLES:
  ./check-prerequisites.ps1 -Json
  ./check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks
  ./check-prerequisites.ps1 -PathsOnly
'@
    exit 0
}

. (Join-Path $PSScriptRoot 'common.ps1')

# In -PathsOnly mode this is pure resolution: opt out of the feature.json write.
try { $paths = Get-FeaturePathsEnv -NoPersist:$PathsOnly }
catch { Write-Error $_.Exception.Message; exit 1 }

if ($PathsOnly) {
    if ($Json) {
        [PSCustomObject]@{
            REPO_ROOT    = $paths.REPO_ROOT
            BRANCH       = $paths.CURRENT_BRANCH
            FEATURE_DIR  = $paths.FEATURE_DIR
            FEATURE_SPEC = $paths.FEATURE_SPEC
            IMPL_PLAN    = $paths.IMPL_PLAN
            TASKS        = $paths.TASKS
        } | ConvertTo-Json -Compress
    } else {
        "REPO_ROOT: $($paths.REPO_ROOT)"
        "BRANCH: $($paths.CURRENT_BRANCH)"
        "FEATURE_DIR: $($paths.FEATURE_DIR)"
        "FEATURE_SPEC: $($paths.FEATURE_SPEC)"
        "IMPL_PLAN: $($paths.IMPL_PLAN)"
        "TASKS: $($paths.TASKS)"
    }
    exit 0
}

# Validate required directories and files
if (-not (Test-Path -LiteralPath $paths.FEATURE_DIR -PathType Container)) {
    Write-Error "Feature directory not found: $($paths.FEATURE_DIR)`nRun /feature-specify first to create the feature structure."
    exit 1
}
if (-not (Test-Path -LiteralPath $paths.IMPL_PLAN -PathType Leaf)) {
    Write-Error "plan.md not found in $($paths.FEATURE_DIR)`nRun /feature-plan first to create the implementation plan."
    exit 1
}
if ($RequireTasks -and -not (Test-Path -LiteralPath $paths.TASKS -PathType Leaf)) {
    Write-Error "tasks.md not found in $($paths.FEATURE_DIR)`nRun /feature-tasks first to create the task list."
    exit 1
}

# Build list of available documents
$docs = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $paths.RESEARCH -PathType Leaf)   { $docs.Add('research.md') }
if (Test-Path -LiteralPath $paths.DATA_MODEL -PathType Leaf) { $docs.Add('data-model.md') }
if ((Test-Path -LiteralPath $paths.CONTRACTS_DIR -PathType Container) -and
    (Get-ChildItem -LiteralPath $paths.CONTRACTS_DIR -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    $docs.Add('contracts/')
}
if (Test-Path -LiteralPath $paths.QUICKSTART -PathType Leaf) { $docs.Add('quickstart.md') }
if ($IncludeTasks -and (Test-Path -LiteralPath $paths.TASKS -PathType Leaf)) { $docs.Add('tasks.md') }

if ($Json) {
    # Build the array manually so a single-element list is not collapsed to a
    # scalar by Windows PowerShell 5.1's ConvertTo-Json.
    $docsJson = '[' + (($docs | ForEach-Object { ConvertTo-Json $_ -Compress }) -join ',') + ']'
    '{"FEATURE_DIR":' + (ConvertTo-Json $paths.FEATURE_DIR -Compress) + ',"AVAILABLE_DOCS":' + $docsJson + '}'
} else {
    "FEATURE_DIR:$($paths.FEATURE_DIR)"
    "AVAILABLE_DOCS:"
    Test-FileMark -Path $paths.RESEARCH   -Label 'research.md'
    Test-FileMark -Path $paths.DATA_MODEL -Label 'data-model.md'
    Test-DirMark  -Path $paths.CONTRACTS_DIR -Label 'contracts/'
    Test-FileMark -Path $paths.QUICKSTART -Label 'quickstart.md'
    if ($IncludeTasks) { Test-FileMark -Path $paths.TASKS -Label 'tasks.md' }
}
