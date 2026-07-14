#!/usr/bin/env bash
# extract_css_tokens.sh
# 指定 URL の HTML と全 CSS を取得し、デザイントークンのインベントリ（頻度表）を出力する。
# 依存: curl, grep, sed, sort, uniq（POSIX 環境標準のみ）
#
# 使い方:
#   ./extract_css_tokens.sh https://example.com inventory.txt

set -u

URL="${1:?usage: extract_css_tokens.sh <URL> [outfile]}"
OUT="${2:-design-token-inventory.txt}"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'

TMPDIR_X="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_X"' EXIT
HTML="$TMPDIR_X/page.html"
CSS="$TMPDIR_X/all.css"
SOURCES="$TMPDIR_X/sources.txt"
: > "$CSS"; : > "$SOURCES"

fetch() { curl -fsSL -A "$UA" --max-time 30 "$1" 2>/dev/null; }

resolve_url() {
  # $1=base $2=href → 絶対 URL
  case "$2" in
    http://*|https://*) printf '%s' "$2" ;;
    //*)  printf 'https:%s' "$2" ;;
    /*)   printf '%s%s' "$(printf '%s' "$1" | grep -oE '^https?://[^/]+')" "$2" ;;
    *)    printf '%s/%s' "$(printf '%s' "$1" | sed 's|/[^/]*$||')" "$2" ;;
  esac
}

# --- 1. HTML 取得 ---
if ! fetch "$URL" > "$HTML" || [ ! -s "$HTML" ]; then
  echo "ERROR: HTML の取得に失敗しました: $URL" >&2; exit 1
fi

# --- 2. CSS 収集（<style> + <link rel=stylesheet> + @import 1段） ---
# inline <style>
tr '\n' ' ' < "$HTML" | grep -oiE '<style[^>]*>[^<]*</style>' | sed -E 's/<[^>]*>//g' >> "$CSS" || true
echo "(inline <style>)" >> "$SOURCES"

# <link rel=stylesheet>
tr '\n' ' ' < "$HTML" | grep -oiE '<link[^>]+>' | grep -iE 'rel *= *["'\'']?[^"'\''>]*stylesheet' \
  | grep -oiE 'href *= *["'\'']?[^"'\'' >]+' | sed -E 's/^href *= *["'\'']?//i' | sort -u \
  | while read -r href; do
      abs="$(resolve_url "$URL" "$href")"
      if fetch "$abs" >> "$CSS"; then echo "$abs" >> "$SOURCES"; fi
      echo >> "$CSS"
    done

# @import を 1 段だけ解決
grep -oE '@import +(url\()?["'\'']?[^"'\'')  ;]+' "$CSS" | sed -E 's/@import +(url\()?["'\'']?//' | sort -u \
  | while read -r imp; do
      abs="$(resolve_url "$URL" "$imp")"
      if fetch "$abs" >> "$CSS"; then echo "(import) $abs" >> "$SOURCES"; fi
      echo >> "$CSS"
    done

# style 属性
grep -oE 'style="[^"]+"' "$HTML" | sed -E 's/^style="//; s/"$/;/' >> "$CSS" || true

CSS_BYTES=$(wc -c < "$CSS" | tr -d ' ')

count_prop() {
  # $1=プロパティ名の正規表現 → 値の頻度表
  grep -oiE "$1[[:space:]]*:[[:space:]]*[^;}{]+" "$CSS" \
    | sed -E "s/^[^:]+:[[:space:]]*//" | tr 'A-Z' 'a-z' | sed -E 's/[[:space:]]+$//' \
    | sort | uniq -c | sort -rn | head -n "${2:-30}" | sed 's/^/  /'
}

COLOR_RE='#[0-9a-fA-F]{3,8}|rgba?[(][^)]+[)]|hsla?[(][^)]+[)]|oklch[(][^)]+[)]'

{
  echo "== meta =="
  echo "url: $URL"
  echo "fetched_at: $(date -u +%Y-%m-%dT%H:%M:%S)"
  echo "stylesheets: $(wc -l < "$SOURCES" | tr -d ' ')"
  sed 's/^/  - /' "$SOURCES"
  echo "css_bytes: $CSS_BYTES"
  if [ "$CSS_BYTES" -lt 5000 ]; then
    echo "WARNING: CSS が非常に少ない。JS レンダリング（SPA）の可能性。Playwright フォールバックを検討すること。"
  fi
  echo

  echo "== google_fonts (from HTML <link>) =="
  grep -oE 'fonts\.googleapis\.com/css2?\?family=[^&"'\'' >]+' "$HTML" \
    | sed -E 's/.*family=//; s/\+/ /g; s/%20/ /g' | sort -u | sed 's/^/  - /' || echo "  (none)"
  echo

  echo "== css_variables (--name: value) =="
  grep -oE '\-\-[a-zA-Z0-9_-]+[[:space:]]*:[[:space:]]*[^;}{]+' "$CSS" | sed -E 's/[[:space:]]+/ /g' \
    | sort -u | head -n 120 | sed 's/^/  /' || echo "  (none)"
  echo

  echo "== colors_by_property (property | color x count) =="
  grep -oiE '(background(-color)?|color|border(-[a-z]+)*-color|border|outline|fill|stroke|box-shadow|accent-color)[[:space:]]*:[[:space:]]*[^;}{]+' "$CSS" \
    | tr 'A-Z' 'a-z' \
    | awk -v cre="$COLOR_RE" '{
        split($0, kv, ":"); prop=kv[1]; gsub(/[[:space:]]/, "", prop);
        if (prop ~ /^border/) prop="border";
        if (prop ~ /^background/) prop="background";
        rest=$0; sub(/^[^:]+:/, "", rest);
        while (match(rest, cre)) {
          print prop " | " substr(rest, RSTART, RLENGTH);
          rest = substr(rest, RSTART + RLENGTH);
        }
      }' | sort | uniq -c | sort -rn | head -n 80 | sed 's/^/  /'
  echo

  echo "== all_colors =="
  grep -oE "$COLOR_RE" "$CSS" | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn | head -n 60 | sed 's/^/  /'
  echo

  echo "== font_family ==";    count_prop 'font-family' 20;    echo
  echo "== font_size ==";      count_prop 'font-size' 30;      echo
  echo "== font_weight ==";    count_prop 'font-weight' 15;    echo
  echo "== line_height ==";    count_prop 'line-height' 20;    echo
  echo "== letter_spacing =="; count_prop 'letter-spacing' 15; echo
  echo "== border_radius ==";  count_prop 'border-radius' 25;  echo
  echo "== box_shadow ==";     count_prop 'box-shadow' 20;     echo
  echo "== max_width ==";      count_prop 'max-width' 20;      echo

  echo "== spacing_values (padding/margin/gap) =="
  grep -oiE '(padding|margin|gap|row-gap|column-gap)(-[a-z]+)?[[:space:]]*:[[:space:]]*[^;}{]+' "$CSS" \
    | grep -oE '[0-9]+(\.[0-9]+)?(px|rem|em)' | tr 'A-Z' 'a-z' \
    | sort | uniq -c | sort -rn | head -n 40 | sed 's/^/  /'
  echo

  echo "== hover_effects (transform/shadow near :hover) =="
  tr '\n' ' ' < "$CSS" | grep -oE ':hover[^{]*\{[^}]*\}' | grep -iE 'transform|box-shadow|translate' \
    | sed -E 's/[[:space:]]+/ /g' | cut -c1-160 | head -n 15 | sed 's/^/  /' || echo "  (none)"
} > "$OUT"

echo "inventory written: $OUT ($CSS_BYTES bytes of CSS from $(wc -l < "$SOURCES" | tr -d ' ') sources)"
