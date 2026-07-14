# Common functions for the feature-implement skill (PowerShell port of common.sh)
#
# This is a focused port: it provides ONLY the functions that
# check-prerequisites.ps1 needs (feature-path resolution + doc checks).
# The template-composition helpers from common.sh (resolve_template*,
# format_speckit_command, get_invoke_separator) are intentionally NOT ported
# because check-prerequisites does not use them.
#
# Targets Windows PowerShell 5.1 (no ternary / ?? / -AsHashtable).

# Find repository root by searching upward for a .specify directory.
function Find-SpecifyRoot {
    param([string]$StartDir = (Get-Location).Path)

    $dir = $null
    try {
        $dir = (Resolve-Path -LiteralPath $StartDir -ErrorAction Stop).Path
    } catch {
        return $null
    }

    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $dir '.specify') -PathType Container) {
            return $dir
        }
        $parent = Split-Path -LiteralPath $dir -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $dir) {
            break
        }
        $dir = $parent
    }
    return $null
}

# Resolve an explicit SPECIFY_INIT_DIR project override (the directory that
# contains .specify/). Strict by design: the path must exist and contain
# .specify/, with no silent fallback. Returns $null on failure (and writes an
# error), so callers can bail out.
function Resolve-SpecifyInitDir {
    if ([string]::IsNullOrEmpty($env:SPECIFY_INIT_DIR)) {
        return $null
    }

    $initRoot = $null
    try {
        $initRoot = (Resolve-Path -LiteralPath $env:SPECIFY_INIT_DIR -ErrorAction Stop).Path
    } catch {
        Write-Error "ERROR: SPECIFY_INIT_DIR does not point to an existing directory: $($env:SPECIFY_INIT_DIR)"
        return $null
    }

    if (-not (Test-Path -LiteralPath (Join-Path $initRoot '.specify') -PathType Container)) {
        Write-Error "ERROR: SPECIFY_INIT_DIR is not a Spec Kit project (no .specify/ directory): $initRoot"
        return $null
    }
    return $initRoot
}

# Get repository root, prioritizing the .specify directory over the git root.
function Get-RepoRoot {
    # Explicit project override wins.
    if (-not [string]::IsNullOrEmpty($env:SPECIFY_INIT_DIR)) {
        return (Resolve-SpecifyInitDir)
    }

    # First, look for a .specify directory (spec-kit's own marker).
    $specifyRoot = Find-SpecifyRoot
    if ($specifyRoot) {
        return $specifyRoot
    }

    # Final fallback: git repo root, else current directory.
    $gitRoot = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrEmpty($gitRoot)) {
        return $gitRoot.Trim()
    }
    return (Get-Location).Path
}

# Current feature name from explicit state only, or empty string.
function Get-CurrentBranch {
    if (-not [string]::IsNullOrEmpty($env:SPECIFY_FEATURE)) {
        return $env:SPECIFY_FEATURE
    }
    return ''
}

# Safely read .specify/feature.json's "feature_directory" value.
# Returns the raw value (possibly relative) or '' when missing/unparseable.
function Read-FeatureJsonFeatureDirectory {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $fj = Join-Path $RepoRoot '.specify\feature.json'
    if (-not (Test-Path -LiteralPath $fj -PathType Leaf)) {
        return ''
    }

    try {
        $data = Get-Content -LiteralPath $fj -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($data -and ($data.PSObject.Properties.Name -contains 'feature_directory') -and $data.feature_directory) {
            return [string]$data.feature_directory
        }
    } catch {
        return ''
    }
    return ''
}

# Persist a feature_directory value to .specify/feature.json.
# Writes only when the file is missing or the value differs.
function Persist-FeatureJson {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [Parameter(Mandatory = $true)][string]$FeatureDirValue
    )

    $fj = Join-Path $RepoRoot '.specify\feature.json'

    # Strip repo_root prefix if the value is absolute and under repo_root.
    if ($FeatureDirValue.StartsWith($RepoRoot + '\') -or $FeatureDirValue.StartsWith($RepoRoot + '/')) {
        $FeatureDirValue = $FeatureDirValue.Substring($RepoRoot.Length + 1)
    }

    $current = Read-FeatureJsonFeatureDirectory -RepoRoot $RepoRoot
    if ($current -eq $FeatureDirValue) {
        return
    }

    $specifyDir = Join-Path $RepoRoot '.specify'
    if (-not (Test-Path -LiteralPath $specifyDir -PathType Container)) {
        New-Item -ItemType Directory -Path $specifyDir -Force | Out-Null
    }

    ([pscustomobject]@{ feature_directory = $FeatureDirValue }) |
        ConvertTo-Json -Compress |
        Set-Content -LiteralPath $fj -Encoding UTF8
}

# Resolve all feature paths. Returns a PSCustomObject; throws on failure.
# Priority for the feature directory:
#   1. SPECIFY_FEATURE_DIRECTORY env var (explicit override)
#   2. .specify/feature.json "feature_directory" key
#   3. Error
function Get-FeaturePaths {
    param([switch]$NoPersist)

    $repoRoot = Get-RepoRoot
    if ([string]::IsNullOrEmpty($repoRoot)) {
        throw 'ERROR: Failed to resolve repository root'
    }
    $currentBranch = Get-CurrentBranch

    $featureDir = $null
    if (-not [string]::IsNullOrEmpty($env:SPECIFY_FEATURE_DIRECTORY)) {
        $featureDir = $env:SPECIFY_FEATURE_DIRECTORY
        if (-not [System.IO.Path]::IsPathRooted($featureDir)) {
            $featureDir = Join-Path $repoRoot $featureDir
        }
        # Persist so future sessions without the env var still work, unless the
        # caller opted out for read-only resolution.
        if (-not $NoPersist) {
            Persist-FeatureJson -RepoRoot $repoRoot -FeatureDirValue $env:SPECIFY_FEATURE_DIRECTORY
        }
    }
    elseif (Test-Path -LiteralPath (Join-Path $repoRoot '.specify\feature.json') -PathType Leaf) {
        $fd = Read-FeatureJsonFeatureDirectory -RepoRoot $repoRoot
        if (-not [string]::IsNullOrEmpty($fd)) {
            $featureDir = $fd
            if (-not [System.IO.Path]::IsPathRooted($featureDir)) {
                $featureDir = Join-Path $repoRoot $featureDir
            }
        } else {
            throw 'ERROR: Feature directory not found. Set SPECIFY_FEATURE_DIRECTORY or ensure .specify/feature.json contains feature_directory.'
        }
    }
    else {
        throw 'ERROR: Feature directory not found. Set SPECIFY_FEATURE_DIRECTORY or run the specify command to create .specify/feature.json.'
    }

    # When no branch context exists, fall back to the feature directory basename.
    if ([string]::IsNullOrEmpty($currentBranch)) {
        $currentBranch = Split-Path -Leaf ($featureDir.TrimEnd('\', '/'))
    }

    return [pscustomobject]@{
        REPO_ROOT      = $repoRoot
        CURRENT_BRANCH = $currentBranch
        FEATURE_DIR    = $featureDir
        FEATURE_SPEC   = (Join-Path $featureDir 'spec.md')
        IMPL_PLAN      = (Join-Path $featureDir 'plan.md')
        TASKS          = (Join-Path $featureDir 'tasks.md')
        RESEARCH       = (Join-Path $featureDir 'research.md')
        DATA_MODEL     = (Join-Path $featureDir 'data-model.md')
        QUICKSTART     = (Join-Path $featureDir 'quickstart.md')
        CONTRACTS_DIR  = (Join-Path $featureDir 'contracts')
    }
}

# Human-readable doc presence markers (mirror common.sh check_file/check_dir).
# [char] is used instead of the `u{...} escape so this works on Windows
# PowerShell 5.1 (which does not support the `u{...} syntax).
$script:CheckMark = [char]0x2713  # U+2713 CHECK MARK
$script:CrossMark = [char]0x2717  # U+2717 BALLOT X

function Test-DocFile {
    param([string]$Path, [string]$Label)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { "  $script:CheckMark $Label" } else { "  $script:CrossMark $Label" }
}

function Test-DocDir {
    param([string]$Path, [string]$Label)
    $hasContent = (Test-Path -LiteralPath $Path -PathType Container) -and
        ($null -ne (Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue | Select-Object -First 1))
    if ($hasContent) { "  $script:CheckMark $Label" } else { "  $script:CrossMark $Label" }
}

# Escape a string as a JSON string value (RFC 8259 minimal set).
# Critical on Windows: backslashes in paths (C:\...) must become C:\\...
function ConvertTo-JsonStringValue {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    # NOTE: in a .NET regex replacement string only `$` is special; backslashes
    # are literal. So the replacement for one backslash must be exactly two
    # literal backslash characters ('\\'), not four.
    $s = $Value
    $s = $s -replace '\\', '\\'     # backslash first: one -> two (JSON escape)
    $s = $s -replace '"', '\"'
    $s = $s -replace "`r", '\r'
    $s = $s -replace "`n", '\n'
    $s = $s -replace "`t", '\t'
    return '"' + $s + '"'
}
