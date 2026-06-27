#!/usr/bin/env bash
# 詳細設計のトレーサビリティチェック
#
# 機能一覧（05_Feature_List.md）に登場する ID（FNC/SCR/RPT/IF/BAT）が
# docs/02_Detailed_Design/ 配下の詳細設計でカバーされているかを検証する。
#
# 使い方:
#   bash check_traceability.sh [docsルート]   # デフォルト: ./docs
#
# 終了コード: 0=全カバー, 1=未カバーIDあり, 2=入力ファイル不足
set -u

DOCS_ROOT="${1:-./docs}"
FEATURE_LIST="${DOCS_ROOT}/01_Project_Design/05_Feature_List.md"
DETAIL_DIR="${DOCS_ROOT}/02_Detailed_Design"

if [[ ! -f "$FEATURE_LIST" ]]; then
  echo "ERROR: 機能一覧が見つかりません: $FEATURE_LIST" >&2
  exit 2
fi
if [[ ! -d "$DETAIL_DIR" ]]; then
  echo "ERROR: 詳細設計ディレクトリが見つかりません: $DETAIL_DIR" >&2
  exit 2
fi

missing_total=0

# --- 1. ID カバレッジ：機能一覧の各IDが詳細設計のどこかで参照されているか ---
check_coverage() {
  local prefix="$1" label="$2"
  local ids id
  ids=$(grep -oE "${prefix}-[0-9]+" "$FEATURE_LIST" | sort -u)
  [[ -z "$ids" ]] && return 0

  local missing=()
  while IFS= read -r id; do
    if ! grep -rqE "\b${id}\b" "$DETAIL_DIR" --include='*.md'; then
      missing+=("$id")
    fi
  done <<< "$ids"

  local total
  total=$(wc -l <<< "$ids" | tr -d ' ')
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "OK   ${label} (${prefix}): ${total}/${total} カバー済み"
  else
    echo "NG   ${label} (${prefix}): $((total - ${#missing[@]}))/${total} カバー — 未参照: ${missing[*]}"
    missing_total=$((missing_total + ${#missing[@]}))
  fi
}

echo "=== IDカバレッジ（機能一覧 → 詳細設計） ==="
check_coverage "FNC" "機能"
check_coverage "SCR" "画面"
check_coverage "RPT" "帳票"
check_coverage "IF"  "インターフェース"
check_coverage "BAT" "バッチ"

# --- 2. 個別ファイル存在チェック：SCR/IF はIDごとに個別ファイルがあるはず ---
echo ""
echo "=== 個別ファイル存在チェック ==="
check_files() {
  local prefix="$1" dir="$2" label="$3"
  local ids id
  ids=$(grep -oE "${prefix}-[0-9]+" "$FEATURE_LIST" | sort -u)
  [[ -z "$ids" ]] && return 0
  [[ ! -d "${DETAIL_DIR}/${dir}" ]] && { echo "WARN ${label}: ${DETAIL_DIR}/${dir} が存在しません"; return 0; }

  while IFS= read -r id; do
    if ! ls "${DETAIL_DIR}/${dir}/${id}_"*.md >/dev/null 2>&1; then
      echo "NG   ${label}: ${id} の個別ファイル（${dir}/${id}_*.md）がありません"
      missing_total=$((missing_total + 1))
    fi
  done <<< "$ids"
  echo "OK   ${label}: 個別ファイルチェック完了"
}
check_files "SCR" "07_Screen_Design"    "画面詳細"
check_files "IF"  "08_Interface_Design" "IF詳細"

# --- 3. 共通仕様ファイルの存在チェック ---
echo ""
echo "=== 共通仕様ファイル ==="
for f in "06_Data_Design/00_Data_Common.md" \
         "07_Screen_Design/00_Screen_Common.md" \
         "08_Interface_Design/00_Interface_Common.md" \
         "11_Module_Design/00_Module_Common.md"; do
  if [[ -f "${DETAIL_DIR}/${f}" ]]; then
    echo "OK   ${f}"
  else
    echo "NG   ${f} がありません"
    missing_total=$((missing_total + 1))
  fi
done

# --- 4. 未決事項（TBD）の検出 ---
echo ""
echo "=== 未決事項（TBD） ==="
tbd_count=$(grep -rn "TBD" "$DETAIL_DIR" --include='*.md' | wc -l | tr -d ' ')
if [[ "$tbd_count" -gt 0 ]]; then
  echo "WARN TBD が ${tbd_count} 件残っています:"
  grep -rn "TBD" "$DETAIL_DIR" --include='*.md' | head -20
else
  echo "OK   TBD なし"
fi

echo ""
if [[ "$missing_total" -gt 0 ]]; then
  echo "RESULT: NG（未カバー/欠落 ${missing_total} 件）"
  exit 1
fi
echo "RESULT: OK（全IDカバー済み）"
exit 0
