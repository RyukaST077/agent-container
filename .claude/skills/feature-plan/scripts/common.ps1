#!/usr/bin/env pwsh
# Common functions for setup-plan (PowerShell port of common.sh).
# Ports the subset setup-plan.ps1 needs: path/feature resolution and template
# resolution. Template *composition* helpers (resolve_template_content) from
# common.sh are intentionally omitted — setup-plan does not use them.

# Find repository root by searching upward for a .specify directory.
function Find-SpecifyRoot {
    param([string]$StartDir = (Get-Location).Path)
    try { $dir = (Resolve-Path -LiteralPath $StartDir -ErrorAction Stop).Path } catch { return $null }
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $dir '.specify') -PathType Container) { return $dir }
        $parent = Split-Path -Parent $dir
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) { break }
        $dir = $parent
    }
    return $null
}

# Resolve an explicit SPECIFY_INIT_DIR override (must exist and contain .specify/).
function Resolve-SpecifyInitDir {
    $initDir = $env:SPECIFY_INIT_DIR
    try { $initRoot = (Resolve-Path -LiteralPath $initDir -ErrorAction Stop).Path }
    catch { throw "ERROR: SPECIFY_INIT_DIR does not point to an existing directory: $initDir" }
    if (-not (Test-Path -LiteralPath (Join-Path $initRoot '.specify') -PathType Container)) {
        throw "ERROR: SPECIFY_INIT_DIR is not a Spec Kit project (no .specify/ directory): $initRoot"
    }
    return $initRoot
}

# Repo root: SPECIFY_INIT_DIR override -> nearest .specify/ -> git root -> cwd.
function Get-RepoRoot {
    if (-not [string]::IsNullOrEmpty($env:SPECIFY_INIT_DIR)) { return Resolve-SpecifyInitDir }
    $specifyRoot = Find-SpecifyRoot
    if ($specifyRoot) { return $specifyRoot }
    $gitRoot = & git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitRoot) { return $gitRoot.Trim() }
    return (Get-Location).Path
}

# Explicit feature name from SPECIFY_FEATURE only (empty otherwise).
function Get-CurrentBranch {
    if (-not [string]::IsNullOrEmpty($env:SPECIFY_FEATURE)) { return $env:SPECIFY_FEATURE }
    return ''
}

# Read .specify/feature.json's feature_directory value ('' if missing/unparseable).
function Read-FeatureJsonFeatureDirectory {
    param([string]$RepoRoot)
    $fj = Join-Path $RepoRoot '.specify/feature.json'
    if (-not (Test-Path -LiteralPath $fj -PathType Leaf)) { return '' }
    try { $data = Get-Content -LiteralPath $fj -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return '' }
    $val = $data.feature_directory
    if ($null -eq $val) { return '' }
    return [string]$val
}

# Persist feature_directory to .specify/feature.json (UTF-8, no BOM), only when changed.
function Set-FeatureJson {
    param([string]$RepoRoot, [string]$FeatureDirValue)
    $fj = Join-Path $RepoRoot '.specify/feature.json'
    $rr = $RepoRoot.TrimEnd('/', '\')
    if ($FeatureDirValue.StartsWith("$rr/") -or $FeatureDirValue.StartsWith("$rr\")) {
        $FeatureDirValue = $FeatureDirValue.Substring($rr.Length + 1)
    }
    if ((Read-FeatureJsonFeatureDirectory -RepoRoot $RepoRoot) -eq $FeatureDirValue) { return }
    $specifyDir = Join-Path $RepoRoot '.specify'
    if (-not (Test-Path -LiteralPath $specifyDir -PathType Container)) {
        New-Item -ItemType Directory -Path $specifyDir -Force | Out-Null
    }
    $json = [PSCustomObject]@{ feature_directory = $FeatureDirValue } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($fj, $json + "`n", (New-Object System.Text.UTF8Encoding($false)))
}

# Test whether a path looks absolute (C:\, C:/, \, or /).
function Test-AbsolutePath { param([string]$Path) return $Path -match '^([a-zA-Z]:[\\/]|[\\/])' }

# Resolve all feature-relative paths. Pass -NoPersist for read-only resolution.
function Get-FeaturePathsEnv {
    param([switch]$NoPersist)
    $repoRoot = Get-RepoRoot
    $currentBranch = Get-CurrentBranch

    $featureDir = $null
    if (-not [string]::IsNullOrEmpty($env:SPECIFY_FEATURE_DIRECTORY)) {
        $featureDir = $env:SPECIFY_FEATURE_DIRECTORY
        if (-not (Test-AbsolutePath $featureDir)) { $featureDir = Join-Path $repoRoot $featureDir }
        if (-not $NoPersist) { Set-FeatureJson -RepoRoot $repoRoot -FeatureDirValue $env:SPECIFY_FEATURE_DIRECTORY }
    }
    elseif (Test-Path -LiteralPath (Join-Path $repoRoot '.specify/feature.json') -PathType Leaf) {
        $fd = Read-FeatureJsonFeatureDirectory -RepoRoot $repoRoot
        if (-not [string]::IsNullOrEmpty($fd)) {
            $featureDir = $fd
            if (-not (Test-AbsolutePath $featureDir)) { $featureDir = Join-Path $repoRoot $featureDir }
        } else {
            throw "ERROR: Feature directory not found. Set SPECIFY_FEATURE_DIRECTORY or ensure .specify/feature.json contains feature_directory."
        }
    } else {
        throw "ERROR: Feature directory not found. Set SPECIFY_FEATURE_DIRECTORY or run the specify command to create .specify/feature.json."
    }

    if ([string]::IsNullOrEmpty($currentBranch)) {
        $currentBranch = Split-Path -Leaf ($featureDir.TrimEnd('/', '\'))
    }

    return [PSCustomObject]@{
        REPO_ROOT      = $repoRoot
        CURRENT_BRANCH = $currentBranch
        FEATURE_DIR    = $featureDir
        FEATURE_SPEC   = Join-Path $featureDir 'spec.md'
        IMPL_PLAN      = Join-Path $featureDir 'plan.md'
        TASKS          = Join-Path $featureDir 'tasks.md'
        RESEARCH       = Join-Path $featureDir 'research.md'
        DATA_MODEL     = Join-Path $featureDir 'data-model.md'
        QUICKSTART     = Join-Path $featureDir 'quickstart.md'
        CONTRACTS_DIR  = Join-Path $featureDir 'contracts'
    }
}

# Resolve a template name to a file path (PowerShell port of common.sh resolve_template).
# Priority: overrides -> presets (by .registry priority) -> extensions -> core.
# Returns $null if the template is not found in any location.
function Resolve-Template {
    param([string]$TemplateName, [string]$RepoRoot)
    $base = Join-Path $RepoRoot '.specify/templates'

    # Priority 1: project overrides
    $override = Join-Path $base "overrides/$TemplateName.md"
    if (Test-Path -LiteralPath $override -PathType Leaf) { return $override }

    # Priority 2: installed presets (sorted by priority from .registry; lower = higher precedence)
    $presetsDir = Join-Path $RepoRoot '.specify/presets'
    if (Test-Path -LiteralPath $presetsDir -PathType Container) {
        $ordered = @()
        $registry = Join-Path $presetsDir '.registry'
        if (Test-Path -LiteralPath $registry -PathType Leaf) {
            try {
                $presets = (Get-Content -LiteralPath $registry -Raw | ConvertFrom-Json).presets
                if ($presets) {
                    $ordered = @($presets.PSObject.Properties |
                        Where-Object { $_.Value.enabled -ne $false } |
                        Sort-Object { if ($null -ne $_.Value.priority) { [int]$_.Value.priority } else { 10 } } |
                        ForEach-Object { $_.Name })
                }
            } catch { $ordered = @() }
        }
        # If the registry gave us an order, use it; otherwise fall back to a directory scan.
        $searchList = if ($ordered.Count -gt 0) { $ordered } else {
            @(Get-ChildItem -LiteralPath $presetsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        }
        foreach ($presetId in $searchList) {
            $candidate = Join-Path $presetsDir "$presetId/templates/$TemplateName.md"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }

    # Priority 3: extension-provided templates (skip hidden directories)
    $extDir = Join-Path $RepoRoot '.specify/extensions'
    if (Test-Path -LiteralPath $extDir -PathType Container) {
        foreach ($ext in Get-ChildItem -LiteralPath $extDir -Directory -ErrorAction SilentlyContinue) {
            if ($ext.Name.StartsWith('.')) { continue }
            $candidate = Join-Path $ext.FullName "templates/$TemplateName.md"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }

    # Priority 4: core templates
    $core = Join-Path $base "$TemplateName.md"
    if (Test-Path -LiteralPath $core -PathType Leaf) { return $core }

    # Not found in any location.
    return $null
}
