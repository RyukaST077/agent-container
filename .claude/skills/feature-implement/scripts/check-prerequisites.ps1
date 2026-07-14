#!/usr/bin/env pwsh
# Consolidated prerequisite checking script (PowerShell port of check-prerequisites.sh).
#
# Provides unified prerequisite checking for the Spec-Driven Development workflow
# on PowerShell (Windows-first), mirroring the bash script's JSON output so the
# feature-implement skill can consume either one interchangeably.
#
# Usage: .\check-prerequisites.ps1 [OPTIONS]
#
# OPTIONS:
#   -Json           Output in JSON format
#   -RequireTasks   Require tasks.md to exist (for the implementation phase)
#   -IncludeTasks   Include tasks.md in the AVAILABLE_DOCS list
#   -PathsOnly      Only output path variables (no validation)
#   -Help           Show this help message
#
# OUTPUTS:
#   JSON mode: {"FEATURE_DIR":"...","AVAILABLE_DOCS":["..."]}
#   Text mode: FEATURE_DIR:... \n AVAILABLE_DOCS: \n check/cross file.md
#   Paths only: REPO_ROOT: ... \n BRANCH: ... \n FEATURE_DIR: ... etc.

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

Consolidated prerequisite checking for the Spec-Driven Development workflow.

OPTIONS:
  -Json           Output in JSON format
  -RequireTasks   Require tasks.md to exist (for the implementation phase)
  -IncludeTasks   Include tasks.md in the AVAILABLE_DOCS list
  -PathsOnly      Only output path variables (no prerequisite validation)
  -Help           Show this help message

EXAMPLES:
  # Check task prerequisites (plan.md required)
  .\check-prerequisites.ps1 -Json

  # Check implementation prerequisites (plan.md + tasks.md required)
  .\check-prerequisites.ps1 -Json -RequireTasks -IncludeTasks

  # Get feature paths only (no validation)
  .\check-prerequisites.ps1 -PathsOnly
'@
    exit 0
}

# Dot-source common functions (resolved relative to this script).
. (Join-Path $PSScriptRoot 'common.ps1')

# Resolve feature paths.
# In -PathsOnly mode this is pure resolution, so pass -NoPersist to opt out of
# the feature.json write side effect.
try {
    if ($PathsOnly) {
        $paths = Get-FeaturePaths -NoPersist
    } else {
        $paths = Get-FeaturePaths
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

# Paths-only mode: output paths and exit (no validation).
if ($PathsOnly) {
    if ($Json) {
        $sb = @(
            '"REPO_ROOT":'    + (ConvertTo-JsonStringValue $paths.REPO_ROOT)
            '"BRANCH":'       + (ConvertTo-JsonStringValue $paths.CURRENT_BRANCH)
            '"FEATURE_DIR":'  + (ConvertTo-JsonStringValue $paths.FEATURE_DIR)
            '"FEATURE_SPEC":' + (ConvertTo-JsonStringValue $paths.FEATURE_SPEC)
            '"IMPL_PLAN":'    + (ConvertTo-JsonStringValue $paths.IMPL_PLAN)
            '"TASKS":'        + (ConvertTo-JsonStringValue $paths.TASKS)
        ) -join ','
        '{' + $sb + '}'
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

# Validate required directories and files.
if (-not (Test-Path -LiteralPath $paths.FEATURE_DIR -PathType Container)) {
    Write-Error "ERROR: Feature directory not found: $($paths.FEATURE_DIR)`nRun /feature-specify first to create the feature structure."
    exit 1
}

if (-not (Test-Path -LiteralPath $paths.IMPL_PLAN -PathType Leaf)) {
    Write-Error "ERROR: plan.md not found in $($paths.FEATURE_DIR)`nRun /feature-plan first to create the implementation plan."
    exit 1
}

if ($RequireTasks -and -not (Test-Path -LiteralPath $paths.TASKS -PathType Leaf)) {
    Write-Error "ERROR: tasks.md not found in $($paths.FEATURE_DIR)`nRun /feature-tasks first to create the task list."
    exit 1
}

# Build list of available documents.
$docs = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $paths.RESEARCH -PathType Leaf)   { $docs.Add('research.md') }
if (Test-Path -LiteralPath $paths.DATA_MODEL -PathType Leaf) { $docs.Add('data-model.md') }
if ((Test-Path -LiteralPath $paths.CONTRACTS_DIR -PathType Container) -and
    ($null -ne (Get-ChildItem -LiteralPath $paths.CONTRACTS_DIR -Force -ErrorAction SilentlyContinue | Select-Object -First 1))) {
    $docs.Add('contracts/')
}
if (Test-Path -LiteralPath $paths.QUICKSTART -PathType Leaf) { $docs.Add('quickstart.md') }
if ($IncludeTasks -and (Test-Path -LiteralPath $paths.TASKS -PathType Leaf)) { $docs.Add('tasks.md') }

# Output results.
if ($Json) {
    # Build the array manually so a single-element list is not unwrapped into a
    # scalar (a known ConvertTo-Json quirk on Windows PowerShell 5.1), and so
    # backslashes in Windows paths are correctly escaped.
    $items = @($docs | ForEach-Object { ConvertTo-JsonStringValue $_ })
    $jsonDocs = '[' + ($items -join ',') + ']'
    '{"FEATURE_DIR":' + (ConvertTo-JsonStringValue $paths.FEATURE_DIR) + ',"AVAILABLE_DOCS":' + $jsonDocs + '}'
} else {
    "FEATURE_DIR:$($paths.FEATURE_DIR)"
    "AVAILABLE_DOCS:"
    Test-DocFile $paths.RESEARCH 'research.md'
    Test-DocFile $paths.DATA_MODEL 'data-model.md'
    Test-DocDir  $paths.CONTRACTS_DIR 'contracts/'
    Test-DocFile $paths.QUICKSTART 'quickstart.md'
    if ($IncludeTasks) { Test-DocFile $paths.TASKS 'tasks.md' }
}
