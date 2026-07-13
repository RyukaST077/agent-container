#!/usr/bin/env bash
# 汎用 API スナップショット回帰テスト CLI
#
# Usage:
#   bash snapshot.sh [action]
#
# action:
#   record   - キャプチャを実行してスナップショットを記録
#   test     - record + マスターとの差分検出 (差分あれば exit 1)
#   compare  - 最新スナップショットとマスターを比較してレポート表示
#   approve  - 最新スナップショットをマスターとして承認 (旧 master は履歴へ退避)
#   history  - マスター履歴のメトリクス推移を表示 (世代比較)
#   reset    - マスターを削除 (対話)
#
# SEVERITY=breaking     # breaking な diff だけで失敗扱いにする (approve 疲労軽減)
# SEVERITY=compatible   # compatible と breaking で失敗
# SEVERITY=informational (default) # どの diff でも失敗
#
# 必須環境変数:
#   CAPTURE_CMD       キャプチャスクリプトの実行コマンド
#                     実行中に環境変数 SNAPSHOT_CAPTURE_FILE が渡されるので
#                     そのパスに JSONL 形式で 1 API コール = 1 行を追記すること
#                     例: export CAPTURE_CMD="bash tools/snapshot/capture.sh"
#
# 任意環境変数:
#   SEED_CMD          record/test 前に実行する DB リセットコマンド (未設定ならスキップ)
#                     例: export SEED_CMD="bash tools/snapshot/reset-db.sh"
#                     reset-db.sh は DB を既知状態に戻し fixture.env を生成する。
#                     capture.sh が fixture.env を読み込んでフィクスチャ ID を使用する。
#   SNAPSHOT_DIR      スナップショット保存先        (default: ./snapshots)
#   LOG_DIR           ログ保存先                    (default: ./logs)
#   MASTER_FILE       マスターファイル              (default: $SNAPSHOT_DIR/snapshot-master.json)
#   NORMALIZER_RULES  正規化ルール JSON             (default: <script_dir>/normalizer_rules.json)
#   COMPARATOR        比較スクリプト                (default: <script_dir>/snapshot_comparator.py)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_DIR="${SNAPSHOT_DIR:-./snapshots}"
LOG_DIR="${LOG_DIR:-./logs}"
MASTER_FILE="${MASTER_FILE:-${SNAPSHOT_DIR}/snapshot-master.json}"
HISTORY_DIR="${HISTORY_DIR:-${SNAPSHOT_DIR}/history}"
HISTORY_MAX_GENERATIONS="${HISTORY_MAX_GENERATIONS:-20}"
NORMALIZER_RULES="${NORMALIZER_RULES:-${SCRIPT_DIR}/normalizer_rules.json}"
COMPARATOR="${COMPARATOR:-${SCRIPT_DIR}/snapshot_comparator.py}"
HISTORY_REPORTER="${HISTORY_REPORTER:-${SCRIPT_DIR}/history_report.py}"
SEVERITY="${SEVERITY:-informational}"  # informational|compatible|breaking

mkdir -p "$SNAPSHOT_DIR" "$LOG_DIR"
ACTION="${1:-help}"

usage() {
  sed -n '2,33p' "$0"
}

require_capture_cmd() {
  if [[ -z "${CAPTURE_CMD:-}" ]]; then
    echo "❌ CAPTURE_CMD が未設定です。" >&2
    echo "   例: export CAPTURE_CMD=\"bash tools/snapshot/capture.sh\"" >&2
    exit 2
  fi
}

find_latest_snapshot() {
  shopt -s nullglob
  local files=("${SNAPSHOT_DIR}"/snapshot-*.json)
  shopt -u nullglob
  if [[ ${#files[@]} -eq 0 ]]; then
    echo ""
    return 0
  fi
  local master_basename
  master_basename="$(basename "$MASTER_FILE")"
  printf '%s\n' "${files[@]}" \
    | grep -v "/${master_basename}\$" \
    | sort | tail -n 1 || true
}

run_seed() {
  if [[ -n "${SEED_CMD:-}" ]]; then
    echo "🌱 DB リセット実行: ${SEED_CMD}" >&2
    bash -c "$SEED_CMD" >&2 || { echo "❌ SEED_CMD failed" >&2; exit 1; }
    echo "" >&2
  fi
}

run_capture() {
  require_capture_cmd
  run_seed
  local tag; tag="$(date '+%Y%m%d-%H%M%S')"
  local log_file="${LOG_DIR}/snapshot-${tag}.log"
  local capture_file="${LOG_DIR}/snapshot-${tag}.jsonl"
  local snapshot_file="${SNAPSHOT_DIR}/snapshot-${tag}.json"

  : > "$capture_file"

  echo "🔄 キャプチャ実行: ${CAPTURE_CMD}" >&2
  echo "   ログ:   ${log_file}" >&2
  echo "   JSONL:  ${capture_file}" >&2

  SNAPSHOT_CAPTURE_FILE="$capture_file" bash -c "$CAPTURE_CMD" 2>&1 | tee "$log_file" >&2

  python3 - "$capture_file" "$snapshot_file" <<'PY'
import json, sys
from datetime import datetime
from pathlib import Path

capture_file, snapshot_file = sys.argv[1], sys.argv[2]
entries = []
p = Path(capture_file)
if p.exists():
    for line in p.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError as e:
            print(f"Warning: JSONL parse error: {e}: {line[:120]}", file=sys.stderr)
            continue
        entry.setdefault('timestamp', datetime.now().isoformat())
        entries.append(entry)

with open(snapshot_file, 'w', encoding='utf-8') as f:
    json.dump(entries, f, ensure_ascii=False, indent=2)
print(f"Captured {len(entries)} entries -> {snapshot_file}", file=sys.stderr)
PY

  echo "✅ スナップショット作成: ${snapshot_file}" >&2
  echo "$snapshot_file"
}

compare_snapshots() {
  local latest="${1:-}"
  if [[ ! -f "$MASTER_FILE" ]]; then
    echo "❌ マスターが見つかりません: $MASTER_FILE" >&2
    echo "   先に 'record' を実行し 'approve' で承認してください。" >&2
    return 1
  fi
  if [[ -z "$latest" ]]; then
    latest="$(find_latest_snapshot)"
  fi
  if [[ -z "$latest" ]] || [[ ! -f "$latest" ]]; then
    echo "❌ 比較対象のスナップショットが見つかりません。" >&2
    return 1
  fi

  echo "比較中:" >&2
  echo "  Master: $MASTER_FILE" >&2
  echo "  Latest: $latest" >&2
  echo "" >&2

  local rules_arg=()
  if [[ -f "$NORMALIZER_RULES" ]]; then
    rules_arg=(--rules "$NORMALIZER_RULES")
  fi

  python3 "$COMPARATOR" "$latest" "$MASTER_FILE" "${rules_arg[@]}" --severity "$SEVERITY"
  local ec=$?

  local report="${latest%.json}-report.md"
  if [[ -f "$report" ]]; then
    echo "" >&2
    echo "📄 差分レポート (先頭 50 行):" >&2
    head -50 "$report" >&2
  fi

  return $ec
}

approve_snapshot() {
  local latest; latest="$(find_latest_snapshot)"
  if [[ -z "$latest" ]] || [[ ! -f "$latest" ]]; then
    echo "❌ 承認対象のスナップショットが見つかりません。" >&2
    echo "   先に実行: bash $0 record" >&2
    exit 1
  fi

  echo "承認候補:" >&2
  echo "  $latest" >&2

  local rules_arg=()
  if [[ -f "$NORMALIZER_RULES" ]]; then
    rules_arg=(--rules "$NORMALIZER_RULES")
  fi
  python3 "$COMPARATOR" "$latest" "${rules_arg[@]}" 2>/dev/null || true

  read -rp "このスナップショットをマスターとして承認しますか？ (yes/no): " confirm
  if [[ "$confirm" == "yes" ]]; then
    rotate_master_to_history
    cp "$latest" "$MASTER_FILE"
    echo "✅ マスター更新: $MASTER_FILE"
    echo ""
    echo "Git に追加してください:"
    echo "  git add $MASTER_FILE $HISTORY_DIR"
    echo "  git commit -m 'Update master snapshot'"
  else
    echo "キャンセルしました。"
  fi
}

# 承認時に旧マスターを history/ にローテート
rotate_master_to_history() {
  [[ -f "$MASTER_FILE" ]] || return 0
  mkdir -p "$HISTORY_DIR"
  local ts; ts="$(date '+%Y%m%d-%H%M%S')"
  local dest="${HISTORY_DIR}/master-${ts}.json"
  cp "$MASTER_FILE" "$dest"
  echo "📦 旧マスターを履歴に保存: $dest" >&2
  # 保持世代数を超えた古いファイルを削除
  local keep="$HISTORY_MAX_GENERATIONS"
  local total
  total=$(ls -1 "${HISTORY_DIR}"/master-*.json 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$total" -gt "$keep" ]]; then
    local remove=$((total - keep))
    ls -1t "${HISTORY_DIR}"/master-*.json | tail -n "$remove" | xargs rm -f
    echo "🗑  古い履歴を $remove 件削除 (保持: $keep 世代)" >&2
  fi
}

history_report() {
  if [[ ! -d "$HISTORY_DIR" ]] && [[ ! -f "$MASTER_FILE" ]]; then
    echo "履歴もマスターも存在しません。"
    return 0
  fi
  python3 "$HISTORY_REPORTER" "$HISTORY_DIR" "$MASTER_FILE"
}

reset_master() {
  if [[ ! -f "$MASTER_FILE" ]]; then
    echo "マスターは存在しません: $MASTER_FILE"
    return 0
  fi
  read -rp "マスターを削除しますか？ ($MASTER_FILE) (yes/no): " confirm
  if [[ "$confirm" == "yes" ]]; then
    rm "$MASTER_FILE"
    echo "✅ 削除しました。"
  else
    echo "キャンセルしました。"
  fi
}

case "$ACTION" in
  record)
    latest="$(run_capture)"
    echo ""
    echo "次のステップ:"
    echo "  1. ログ確認: less ${LOG_DIR}/snapshot-*.log"
    echo "  2. 承認:     bash $0 approve"
    ;;
  test)
    set +e
    latest="$(run_capture)"
    compare_snapshots "$latest"
    ec=$?
    set -e
    if [[ $ec -eq 0 ]]; then
      echo "✅ マスターと一致"
      exit 0
    else
      echo "❌ マスターと差分あり (exit $ec)"
      exit 1
    fi
    ;;
  compare)
    compare_snapshots || true
    ;;
  approve)
    approve_snapshot
    ;;
  reset)
    reset_master
    ;;
  history)
    history_report
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    usage
    exit 1
    ;;
esac
