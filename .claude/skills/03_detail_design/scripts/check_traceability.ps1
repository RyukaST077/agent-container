# check_traceability.ps1  (PowerShell port of check_traceability.sh)
# 詳細設計のトレーサビリティチェック
#
# 機能一覧（05_Feature_List.md）に登場する ID（FNC/SCR/RPT/IF/BAT）が
# docs/02_Detailed_Design/ 配下の詳細設計でカバーされているかを検証する。
#
# 使い方:
#   powershell -NoProfile -ExecutionPolicy Bypass -File check_traceability.ps1 [docsルート]   # デフォルト: ./docs
#
# 終了コード: 0=全カバー, 1=未カバーIDあり, 2=入力ファイル不足
# Pure PowerShell — no external dependencies (no grep / wc). PS 5.1 and 7+.
$ErrorActionPreference = 'Stop'

$docsRoot = if ($args.Count -ge 1 -and $args[0]) { [string]$args[0] } else { './docs' }
$featureList = Join-Path $docsRoot '01_Project_Design/05_Feature_List.md'
$detailDir = Join-Path $docsRoot '02_Detailed_Design'

if (-not (Test-Path -LiteralPath $featureList -PathType Leaf)) {
    [Console]::Error.WriteLine("ERROR: 機能一覧が見つかりません: $featureList")
    exit 2
}
if (-not (Test-Path -LiteralPath $detailDir -PathType Container)) {
    [Console]::Error.WriteLine("ERROR: 詳細設計ディレクトリが見つかりません: $detailDir")
    exit 2
}

$featureText = Get-Content -LiteralPath $featureList -Raw -Encoding UTF8
$detailFiles = @(Get-ChildItem -LiteralPath $detailDir -Recurse -Filter *.md -File -ErrorAction SilentlyContinue)
$allDetailText = (($detailFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 }) -join "`n")
$detailFull = (Resolve-Path -LiteralPath $detailDir).Path

$script:missingTotal = 0
$script:sb = New-Object System.Text.StringBuilder
function Add-Line([string]$s) { [void]$script:sb.AppendLine($s) }

function Get-Ids([string]$prefix) {
    $m = [regex]::Matches($featureText, "$prefix-[0-9]+")
    return @($m | ForEach-Object { $_.Value } | Sort-Object -Unique)
}

# --- 1. ID カバレッジ：機能一覧の各IDが詳細設計のどこかで参照されているか ---
function Check-Coverage([string]$prefix, [string]$label) {
    $ids = Get-Ids $prefix
    if ($ids.Count -eq 0) { return }
    $missing = @()
    foreach ($id in $ids) {
        $pattern = '\b' + [regex]::Escape($id) + '\b'
        if ($allDetailText -notmatch $pattern) { $missing += $id }
    }
    $total = $ids.Count
    if ($missing.Count -eq 0) {
        Add-Line "OK   $label ($prefix): $total/$total カバー済み"
    } else {
        Add-Line "NG   $label ($prefix): $($total - $missing.Count)/$total カバー — 未参照: $($missing -join ' ')"
        $script:missingTotal += $missing.Count
    }
}

Add-Line "=== IDカバレッジ（機能一覧 → 詳細設計） ==="
Check-Coverage 'FNC' '機能'
Check-Coverage 'SCR' '画面'
Check-Coverage 'RPT' '帳票'
Check-Coverage 'IF'  'インターフェース'
Check-Coverage 'BAT' 'バッチ'

# --- 2. 個別ファイル存在チェック：SCR/IF はIDごとに個別ファイルがあるはず ---
Add-Line ''
Add-Line '=== 個別ファイル存在チェック ==='
function Check-Files([string]$prefix, [string]$dir, [string]$label) {
    $ids = Get-Ids $prefix
    if ($ids.Count -eq 0) { return }
    $sub = Join-Path $detailDir $dir
    if (-not (Test-Path -LiteralPath $sub -PathType Container)) {
        Add-Line "WARN ${label}: $sub が存在しません"
        return
    }
    foreach ($id in $ids) {
        $hits = @(Get-ChildItem -LiteralPath $sub -Filter "${id}_*.md" -File -ErrorAction SilentlyContinue)
        if ($hits.Count -eq 0) {
            Add-Line "NG   ${label}: ${id} の個別ファイル（${dir}/${id}_*.md）がありません"
            $script:missingTotal++
        }
    }
    Add-Line "OK   ${label}: 個別ファイルチェック完了"
}
Check-Files 'SCR' '07_Screen_Design'    '画面詳細'
Check-Files 'IF'  '08_Interface_Design' 'IF詳細'

# --- 3. 共通仕様ファイルの存在チェック ---
Add-Line ''
Add-Line '=== 共通仕様ファイル ==='
$common = @(
    '06_Data_Design/00_Data_Common.md',
    '07_Screen_Design/00_Screen_Common.md',
    '08_Interface_Design/00_Interface_Common.md',
    '11_Module_Design/00_Module_Common.md'
)
foreach ($f in $common) {
    if (Test-Path -LiteralPath (Join-Path $detailDir $f) -PathType Leaf) {
        Add-Line "OK   $f"
    } else {
        Add-Line "NG   $f がありません"
        $script:missingTotal++
    }
}

# --- 4. 未決事項（TBD）の検出 ---
Add-Line ''
Add-Line '=== 未決事項（TBD） ==='
$tbd = @()
foreach ($df in $detailFiles) {
    $n = 0
    foreach ($ln in @(Get-Content -LiteralPath $df.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        $n++
        if ($ln -match 'TBD') { $tbd += "$($df.FullName):${n}:$ln" }
    }
}
if ($tbd.Count -gt 0) {
    Add-Line "WARN TBD が $($tbd.Count) 件残っています:"
    foreach ($t in ($tbd | Select-Object -First 20)) { Add-Line $t }
} else {
    Add-Line 'OK   TBD なし'
}

Add-Line ''
if ($script:missingTotal -gt 0) {
    Add-Line "RESULT: NG（未カバー/欠落 $($script:missingTotal) 件）"
} else {
    Add-Line 'RESULT: OK（全IDカバー済み）'
}

$bytes = [System.Text.Encoding]::UTF8.GetBytes($script:sb.ToString())
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()

if ($script:missingTotal -gt 0) { exit 1 }
exit 0
