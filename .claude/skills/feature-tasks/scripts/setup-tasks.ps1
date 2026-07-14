#!/usr/bin/env pwsh
# Setup for task generation (PowerShell port of setup-tasks.sh).
#
# OPTIONS:
#   -Json    Output results in JSON format
#   -Help    Show help
[CmdletBinding()]
param(
    [switch]$Json,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

if ($Help) {
@'
Usage: setup-tasks.ps1 [-Json]
  -Json    Output results in JSON format
  -Help    Show this help message
'@
    exit 0
}

. (Join-Path $PSScriptRoot 'common.ps1')

# Resolve feature paths
try { $paths = Get-FeaturePathsEnv }
catch { Write-Error $_.Exception.Message; exit 1 }

# Validate required files
if (-not (Test-Path -LiteralPath $paths.IMPL_PLAN -PathType Leaf)) {
    Write-Error "plan.md not found in $($paths.FEATURE_DIR)`nRun /feature-plan first to create the implementation plan."
    exit 1
}
if (-not (Test-Path -LiteralPath $paths.FEATURE_SPEC -PathType Leaf)) {
    Write-Error "spec.md not found in $($paths.FEATURE_DIR)`nRun /feature-specify first to create the feature structure."
    exit 1
}

# Build available docs list
$docs = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $paths.RESEARCH -PathType Leaf)   { $docs.Add('research.md') }
if (Test-Path -LiteralPath $paths.DATA_MODEL -PathType Leaf) { $docs.Add('data-model.md') }
if ((Test-Path -LiteralPath $paths.CONTRACTS_DIR -PathType Container) -and
    (Get-ChildItem -LiteralPath $paths.CONTRACTS_DIR -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
    $docs.Add('contracts/')
}
if (Test-Path -LiteralPath $paths.QUICKSTART -PathType Leaf) { $docs.Add('quickstart.md') }

# Resolve tasks template through the override stack.
# Not fatal when missing: TASKS_TEMPLATE is reported as empty and the caller
# (SKILL.md) falls back to the skill-bundled reference/tasks-template.md.
$tasksTemplate = Resolve-Template -TemplateName 'tasks-template' -RepoRoot $paths.REPO_ROOT
if ([string]::IsNullOrEmpty($tasksTemplate) -or -not (Test-Path -LiteralPath $tasksTemplate -PathType Leaf)) {
    Write-Warning "tasks template not found for $($paths.REPO_ROOT); caller should fall back to the skill-bundled reference/tasks-template.md"
    $tasksTemplate = ''
}

if ($Json) {
    # Build the array manually so a single-element list is not collapsed to a
    # scalar by Windows PowerShell 5.1's ConvertTo-Json.
    $docsJson = '[' + (($docs | ForEach-Object { ConvertTo-Json $_ -Compress }) -join ',') + ']'
    '{"FEATURE_DIR":' + (ConvertTo-Json $paths.FEATURE_DIR -Compress) +
        ',"AVAILABLE_DOCS":' + $docsJson +
        ',"TASKS_TEMPLATE":' + (ConvertTo-Json $tasksTemplate -Compress) + '}'
} else {
    "FEATURE_DIR: $($paths.FEATURE_DIR)"
    if ([string]::IsNullOrEmpty($tasksTemplate)) { "TASKS_TEMPLATE: not found" } else { "TASKS_TEMPLATE: $tasksTemplate" }
    "AVAILABLE_DOCS:"
    Test-FileMark -Path $paths.RESEARCH   -Label 'research.md'
    Test-FileMark -Path $paths.DATA_MODEL -Label 'data-model.md'
    Test-DirMark  -Path $paths.CONTRACTS_DIR -Label 'contracts/'
    Test-FileMark -Path $paths.QUICKSTART -Label 'quickstart.md'
}
