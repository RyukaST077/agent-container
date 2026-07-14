# extract_css_tokens.ps1
# 指定 URL の HTML と全 CSS を取得し、デザイントークンのインベントリ（頻度表）を出力する。
# Windows PowerShell 5.1 互換。
#
# 使い方:
#   .\extract_css_tokens.ps1 -Url https://example.com -OutFile inventory.txt

param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$OutFile = "design-token-inventory.txt"
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

function Fetch-Text([string]$u) {
    try {
        $r = Invoke-WebRequest -Uri $u -UseBasicParsing -UserAgent $UA -TimeoutSec 30
        if ($r.RawContentStream) {
            return [System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
        }
        return [string]$r.Content
    } catch {
        Write-Warning "fetch failed: $u ($($_.Exception.Message))"
        return $null
    }
}

function Resolve-Href([string]$base, [string]$href) {
    try { return ([Uri]::new([Uri]$base, $href)).AbsoluteUri } catch { return $null }
}

# --- 1. HTML 取得 ---
$html = Fetch-Text $Url
if (-not $html) { throw "HTML の取得に失敗しました: $Url" }

# --- 2. CSS 収集（<style> + <link rel=stylesheet> + @import 1段） ---
$cssParts = New-Object System.Collections.Generic.List[string]
$cssSources = New-Object System.Collections.Generic.List[string]

foreach ($m in [regex]::Matches($html, '(?is)<style[^>]*>(.*?)</style>')) {
    $cssParts.Add($m.Groups[1].Value)
    $cssSources.Add('(inline <style>)')
}

$linkHrefs = New-Object System.Collections.Generic.List[string]
foreach ($m in [regex]::Matches($html, '(?is)<link\b[^>]*>')) {
    $tag = $m.Value
    if ($tag -match '(?i)rel\s*=\s*["'']?[^"''>]*stylesheet' -and $tag -match '(?i)href\s*=\s*["'']?([^"''\s>]+)') {
        $linkHrefs.Add($Matches[1])
    }
}
foreach ($href in $linkHrefs) {
    $abs = Resolve-Href $Url $href
    if (-not $abs) { continue }
    $css = Fetch-Text $abs
    if ($css) { $cssParts.Add($css); $cssSources.Add($abs) }
}

# @import を 1 段だけ解決
$importUrls = New-Object System.Collections.Generic.List[string]
foreach ($part in @($cssParts)) {
    foreach ($m in [regex]::Matches($part, '@import\s+(?:url\(\s*)?["'']?([^"''\)\s;]+)')) {
        $importUrls.Add($m.Groups[1].Value)
    }
}
foreach ($imp in $importUrls | Select-Object -Unique) {
    $abs = Resolve-Href $Url $imp
    if (-not $abs) { continue }
    $css = Fetch-Text $abs
    if ($css) { $cssParts.Add($css); $cssSources.Add("(import) $abs") }
}

$allCss = ($cssParts -join "`n")
# style 属性も色・フォントの証拠になるので末尾に足す
foreach ($m in [regex]::Matches($html, '(?is)style\s*=\s*"([^"]+)"')) { $allCss += "`n" + $m.Groups[1].Value + ";" }

# --- 3. 頻度カウントのヘルパ ---
function Count-Values([string]$text, [string]$pattern, [int]$group = 1) {
    $table = @{}
    foreach ($m in [regex]::Matches($text, $pattern, 'IgnoreCase')) {
        $v = $m.Groups[$group].Value.Trim().ToLower()
        if ($v -eq '') { continue }
        if ($table.ContainsKey($v)) { $table[$v] = $table[$v] + 1 } else { $table[$v] = 1 }
    }
    return $table
}

function Format-Table2([hashtable]$table, [int]$top = 40) {
    $lines = @()
    $sorted = $table.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First $top
    foreach ($e in $sorted) { $lines += ("  {0,6} x  {1}" -f $e.Value, $e.Key) }
    if ($lines.Count -eq 0) { $lines = @('  (none)') }
    return $lines -join "`n"
}

$colorToken = '(#[0-9a-fA-F]{3,8}\b|rgba?\([^\)]+\)|hsla?\([^\)]+\)|oklch\([^\)]+\))'

# --- 4. レポート生成 ---
$sb = New-Object System.Text.StringBuilder
$null = $sb.AppendLine("== meta ==")
$null = $sb.AppendLine("url: $Url")
$null = $sb.AppendLine("fetched_at: $(Get-Date -Format s)")
$null = $sb.AppendLine("stylesheets: $($cssSources.Count)")
foreach ($s in $cssSources) { $null = $sb.AppendLine("  - $s") }
$null = $sb.AppendLine("css_bytes: $($allCss.Length)")
if ($allCss.Length -lt 5000) {
    $null = $sb.AppendLine("WARNING: CSS が非常に少ない。JS レンダリング（SPA）の可能性。Playwright フォールバックを検討すること。")
}
$null = $sb.AppendLine()

$null = $sb.AppendLine("== google_fonts (from HTML <link>) ==")
$gf = @{}
foreach ($m in [regex]::Matches($html, 'fonts\.googleapis\.com/css2?\?family=([^&"''\s>]+)')) {
    $fam = [Uri]::UnescapeDataString($m.Groups[1].Value) -replace '\+', ' '
    $gf[$fam] = 1
}
if ($gf.Count -eq 0) { $null = $sb.AppendLine("  (none)") }
foreach ($k in $gf.Keys) { $null = $sb.AppendLine("  - $k") }
$null = $sb.AppendLine()

$null = $sb.AppendLine("== css_variables (--name: value) ==")
$varLines = @()
$varSeen = @{}
foreach ($m in [regex]::Matches($allCss, '(--[\w-]+)\s*:\s*([^;}{]+)')) {
    $k = $m.Groups[1].Value.Trim(); $v = $m.Groups[2].Value.Trim()
    $key = "$k`: $v"
    if (-not $varSeen.ContainsKey($key)) { $varSeen[$key] = 1; $varLines += "  $key" }
}
if ($varLines.Count -eq 0) { $varLines = @('  (none)') }
$null = $sb.AppendLine((($varLines | Select-Object -First 120) -join "`n"))
$null = $sb.AppendLine()

# プロパティ文脈付きの色
$null = $sb.AppendLine("== colors_by_property (property | color x count) ==")
$propColor = @{}
foreach ($m in [regex]::Matches($allCss, '(?i)\b(background(?:-color)?|color|border(?:-\w+)*-color|border|outline|fill|stroke|box-shadow|text-decoration-color|caret-color|accent-color)\s*:\s*([^;}{]+)')) {
    $prop = $m.Groups[1].Value.ToLower()
    if ($prop -match '^border') { $prop = 'border' }
    if ($prop -match '^background') { $prop = 'background' }
    foreach ($cm in [regex]::Matches($m.Groups[2].Value, $colorToken)) {
        $key = "{0,-12} | {1}" -f $prop, $cm.Value.ToLower()
        if ($propColor.ContainsKey($key)) { $propColor[$key] = $propColor[$key] + 1 } else { $propColor[$key] = 1 }
    }
}
$null = $sb.AppendLine((Format-Table2 $propColor 80))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== all_colors ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss $colorToken) 60))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== font_family ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'font-family\s*:\s*([^;}{]+)') 20))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== font_size ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'font-size\s*:\s*([^;}{]+)') 30))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== font_weight ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'font-weight\s*:\s*([^;}{]+)') 15))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== line_height ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'line-height\s*:\s*([^;}{]+)') 20))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== letter_spacing ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'letter-spacing\s*:\s*([^;}{]+)') 15))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== border_radius ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'border-radius\s*:\s*([^;}{]+)') 25))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== box_shadow ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'box-shadow\s*:\s*([^;}{]+)') 20))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== max_width ==")
$null = $sb.AppendLine((Format-Table2 (Count-Values $allCss 'max-width\s*:\s*([^;}{]+)') 20))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== spacing_values (padding/margin/gap) ==")
$spacing = @{}
foreach ($m in [regex]::Matches($allCss, '(?i)\b(padding|margin|gap|row-gap|column-gap)(?:-\w+)?\s*:\s*([^;}{]+)')) {
    foreach ($vm in [regex]::Matches($m.Groups[2].Value, '\b\d+(?:\.\d+)?(?:px|rem|em)\b')) {
        $v = $vm.Value.ToLower()
        if ($spacing.ContainsKey($v)) { $spacing[$v] = $spacing[$v] + 1 } else { $spacing[$v] = 1 }
    }
}
$null = $sb.AppendLine((Format-Table2 $spacing 40))
$null = $sb.AppendLine()

$null = $sb.AppendLine("== hover_effects (transform/shadow near :hover) ==")
$hoverLines = @()
foreach ($m in [regex]::Matches($allCss, '(?is):hover[^{]*\{([^}]*)\}')) {
    $body = $m.Groups[1].Value
    if ($body -match '(?i)(transform|box-shadow|translate)') {
        $one = ($body -replace '\s+', ' ').Trim()
        if ($one.Length -gt 160) { $one = $one.Substring(0, 160) + '...' }
        $hoverLines += "  $one"
    }
}
if ($hoverLines.Count -eq 0) { $hoverLines = @('  (none)') }
$null = $sb.AppendLine((($hoverLines | Select-Object -First 15) -join "`n"))

$sb.ToString() | Out-File -FilePath $OutFile -Encoding utf8
Write-Host "inventory written: $OutFile ($($allCss.Length) bytes of CSS from $($cssSources.Count) sources)"
