#!/usr/bin/env python3
"""
世代履歴レポート: 過去のマスタースナップショットと現マスターの規模推移を出力

Usage:
  python3 history_report.py <history_dir> <current_master>

出力:
  - 全体サマリー (世代ごとの endpoint 数 / 総フィールド数 / 総バイト数)
  - endpoint 別フィールド数の上位変動
  - 閾値超過の肥大化警告

環境変数:
  HISTORY_ALERT_FIELD_INCREASE  endpoint 単体のフィールド数増加率 (比率) の警告閾値 (default: 1.5)
  HISTORY_ALERT_BYTES_INCREASE  同、バイト数の警告閾値                      (default: 2.0)
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple


def count_fields(obj: Any) -> int:
    if isinstance(obj, dict):
        return len(obj) + sum(count_fields(v) for v in obj.values())
    if isinstance(obj, list):
        return sum(count_fields(v) for v in obj)
    return 0


def bytes_size(obj: Any) -> int:
    try:
        return len(json.dumps(obj, ensure_ascii=False, default=str))
    except Exception:
        return 0


def load_snapshot(path: Path) -> List[Dict[str, Any]]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except Exception as e:
        print(f"Warning: failed to load {path}: {e}", file=sys.stderr)
        return []


def metrics(entries: List[Dict[str, Any]]) -> Dict[str, Dict[str, int]]:
    out: Dict[str, Dict[str, int]] = {}
    for e in entries:
        key = f"{e.get('endpoint', '-')}|{e.get('method', '-')}"
        body = e.get("response_body")
        out[key] = {
            "fields": count_fields(body) if body is not None else 0,
            "bytes": bytes_size(body) if body is not None else 0,
        }
    return out


def main() -> None:
    if len(sys.argv) < 3:
        print("Usage: history_report.py <history_dir> <current_master>", file=sys.stderr)
        sys.exit(2)

    history_dir = Path(sys.argv[1])
    current_master = Path(sys.argv[2])

    series: List[Tuple[str, Path]] = []
    if history_dir.exists():
        for f in sorted(history_dir.glob("master-*.json")):
            series.append((f.stem.replace("master-", ""), f))
    if current_master.exists():
        series.append(("current", current_master))

    if not series:
        print("履歴もマスターもありません。approve を実行してください。")
        return

    per_gen = [(label, metrics(load_snapshot(f))) for label, f in series]

    print("# 世代履歴レポート")
    print()
    print(f"- 世代数: {len(series)}")
    all_ep = set()
    for _, m in per_gen:
        all_ep.update(m.keys())
    print(f"- endpoint 種類数 (全世代 union): {len(all_ep)}")
    print()

    # ---- 全体サマリー ----
    print("## 全体サマリー")
    print()
    print("| 世代 | endpoints | 総 fields | 総 bytes |")
    print("|---|---:|---:|---:|")
    for label, m in per_gen:
        total_f = sum(v["fields"] for v in m.values())
        total_b = sum(v["bytes"] for v in m.values())
        print(f"| {label} | {len(m)} | {total_f} | {total_b} |")
    print()

    # ---- endpoint 別の変動 ----
    if len(per_gen) >= 2:
        first_label, first = per_gen[0]
        last_label, last = per_gen[-1]

        diffs: List[Tuple[int, str, int, int, int, int]] = []
        for ep in all_ep:
            f0 = first.get(ep, {}).get("fields", 0)
            b0 = first.get(ep, {}).get("bytes", 0)
            f1 = last.get(ep, {}).get("fields", 0)
            b1 = last.get(ep, {}).get("bytes", 0)
            if f0 == 0 and f1 == 0 and b0 == 0 and b1 == 0:
                continue
            diffs.append((abs(f1 - f0), ep, f0, f1, b0, b1))
        diffs.sort(reverse=True)

        print(f"## endpoint 別フィールド数推移 ({first_label} → {last_label}, 上位 20 件)")
        print()
        print("| endpoint | 最古 fields | 最新 fields | Δ fields | 最古 bytes | 最新 bytes | Δ bytes |")
        print("|---|---:|---:|---:|---:|---:|---:|")
        for _, ep, f0, f1, b0, b1 in diffs[:20]:
            f_arrow = "📈" if f1 > f0 else ("📉" if f1 < f0 else "→")
            b_arrow = "📈" if b1 > b0 else ("📉" if b1 < b0 else "→")
            print(f"| `{ep}` | {f0} | {f1} | {f_arrow} {f1 - f0:+d} | {b0} | {b1} | {b_arrow} {b1 - b0:+d} |")
        print()

        # ---- 肥大化警告 ----
        f_th = float(os.environ.get("HISTORY_ALERT_FIELD_INCREASE", "1.5"))
        b_th = float(os.environ.get("HISTORY_ALERT_BYTES_INCREASE", "2.0"))
        alerts: List[str] = []
        for _, ep, f0, f1, b0, b1 in diffs:
            if f0 > 0 and f1 / f0 >= f_th:
                pct = (f1 / f0 - 1) * 100
                alerts.append(f"- ⚠ `{ep}` フィールド数 {f0} → {f1} ({pct:+.0f}%)")
            if b0 > 0 and b1 / b0 >= b_th:
                pct = (b1 / b0 - 1) * 100
                alerts.append(f"- ⚠ `{ep}` バイト数 {b0} → {b1} ({pct:+.0f}%)")

        if alerts:
            print("## ⚠ 肥大化警告")
            print()
            print(f"(閾値: fields x{f_th} 以上 / bytes x{b_th} 以上)")
            print()
            for a in alerts:
                print(a)


if __name__ == "__main__":
    main()
