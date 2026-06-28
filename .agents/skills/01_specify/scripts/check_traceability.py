#!/usr/bin/env python3
"""要件定義書のトレーサビリティ・品質チェック。

使い方:
    python3 check_traceability.py <01_Requirements.md> [02_Business_Process.md ...]

チェック内容:
    1. ID種別ごとの出現数（採番の抜け・重複の手がかり）
    2. ACが1つも紐付かないFR（同一行にAC-IDが共起しないFR）
    3. 曖昧語の残存箇所（ファイル:行番号付き）

終了コード: AC未紐付けFRがあれば 1、なければ 0
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

ID_PREFIXES = [
    "BP", "ACT", "BRL", "EX", "BREQ", "FR", "NFR", "CON",
    "AC", "ASM", "DEP", "RSK", "SC",
]
ID_PATTERN = re.compile(r"\b(" + "|".join(ID_PREFIXES) + r")-(\d{1,4})\b")

AMBIGUOUS_WORDS = [
    "適切に", "迅速に", "柔軟に", "ユーザーフレンドリー", "使いやすい",
    "わかりやすい", "分かりやすい", "高速に", "簡単に", "十分な",
    "必要に応じて", "できるだけ", "なるべく", "速やかに", "効率的に",
    "安定して", "直感的に",
]

# 曖昧語チェックの対象外とする行（ガイド文・注記など）
SKIP_LINE_MARKERS = ("> ", "<!--")


def collect(paths):
    ids = defaultdict(set)          # prefix -> {number}
    fr_with_ac = set()              # AC と同一行に共起した FR の完全ID
    ambiguous_hits = []             # (file, lineno, word, line)

    for path in paths:
        text = Path(path).read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), 1):
            found = ID_PATTERN.findall(line)
            for prefix, num in found:
                ids[prefix].add(num)
            prefixes_on_line = {p for p, _ in found}
            if "FR" in prefixes_on_line and "AC" in prefixes_on_line:
                for prefix, num in found:
                    if prefix == "FR":
                        fr_with_ac.add(f"FR-{num}")
            stripped = line.lstrip()
            if not stripped.startswith(SKIP_LINE_MARKERS):
                for word in AMBIGUOUS_WORDS:
                    if word in line:
                        ambiguous_hits.append((path, lineno, word, stripped))
    return ids, fr_with_ac, ambiguous_hits


def main():
    paths = [p for p in sys.argv[1:] if Path(p).is_file()]
    missing = [p for p in sys.argv[1:] if not Path(p).is_file()]
    if not paths:
        print("対象ファイルがありません。", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    for p in missing:
        print(f"[警告] ファイルが見つかりません: {p}", file=sys.stderr)

    ids, fr_with_ac, ambiguous_hits = collect(paths)

    print("== ID種別ごとの件数 ==")
    for prefix in ID_PREFIXES:
        if ids[prefix]:
            nums = sorted(ids[prefix], key=int)
            print(f"  {prefix}: {len(nums)}件 ({prefix}-{nums[0]} 〜 {prefix}-{nums[-1]})")

    all_fr = {f"FR-{n}" for n in ids["FR"]}
    orphan_fr = sorted(all_fr - fr_with_ac)
    print("\n== ACが紐付かないFR ==")
    if orphan_fr:
        for fr in orphan_fr:
            print(f"  [NG] {fr} … 同一行にACが共起していません（トレーサビリティ表で紐付けてください）")
    elif all_fr:
        print("  [OK] すべてのFRにACが紐付いています")
    else:
        print("  [情報] FRがまだ定義されていません")

    print("\n== 曖昧語の残存箇所 ==")
    if ambiguous_hits:
        for path, lineno, word, line in ambiguous_hits:
            print(f"  [警告] {path}:{lineno} 「{word}」 … {line[:60]}")
    else:
        print("  [OK] 曖昧語は検出されませんでした")

    sys.exit(1 if orphan_fr else 0)


if __name__ == "__main__":
    main()
