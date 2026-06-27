#!/usr/bin/env python3
"""02_plan スキル用トレーサビリティ検証スクリプト。

要件定義（01_Requirements.md）で定義された ID が、設計3点セット
（03_Architecture / 04_Basic_Design / 05_Feature_List）で参照されているかを検証する。

検証内容:
  [ERROR] FR が 05_Feature_List.md で1度も参照されていない
  [ERROR] 設計ドキュメントにプレースホルダID（FR-xxx, FNC-XXX 等）が残っている
  [WARN]  NFR が 03_Architecture.md で1度も参照されていない
  [WARN]  BREQ が設計3点のどこからも参照されていない
  [INFO]  採番済み FNC/SCR/RPT/IF/BAT/ADR の件数

使い方:
  python3 check_traceability.py <docs_dir>
  例: python3 check_traceability.py docs/01_Project_Design

終了コード: ERROR が1件以上あれば 1、なければ 0
"""

import re
import sys
from pathlib import Path

REQ_PREFIXES = ("BREQ", "FR", "NFR", "CON")
DESIGN_PREFIXES = ("FNC", "SCR", "RPT", "IF", "BAT", "ADR", "UC")
ID_RE = re.compile(r"\b([A-Z]{2,4})-(\d{2,4})\b")
PLACEHOLDER_RE = re.compile(r"\b(?:BREQ|FR|NFR|CON|FNC|SCR|RPT|IF|BAT|ADR|UC)-(?:[xX]{2,4}|0[xX]{2}|ID)\b")

REQUIREMENTS = "01_Requirements.md"
ARCHITECTURE = "03_Architecture.md"
BASIC_DESIGN = "04_Basic_Design.md"
FEATURE_LIST = "05_Feature_List.md"
DESIGN_DOCS = (ARCHITECTURE, BASIC_DESIGN, FEATURE_LIST)


def extract_ids(text, prefixes):
    """text 内に出現する prefixes の正規ID（PREFIX-数字）の集合を返す。"""
    return {
        f"{m.group(1)}-{m.group(2)}"
        for m in ID_RE.finditer(text)
        if m.group(1) in prefixes
    }


def find_placeholders(path, text):
    """プレースホルダID の残存を (ファイル名:行番号, マッチ文字列) で列挙する。"""
    hits = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for m in PLACEHOLDER_RE.finditer(line):
            hits.append((f"{path.name}:{lineno}", m.group(0)))
    return hits


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2

    docs_dir = Path(sys.argv[1])
    req_path = docs_dir / REQUIREMENTS
    if not req_path.is_file():
        print(f"[ERROR] 要件定義が見つかりません: {req_path}")
        return 1

    req_text = req_path.read_text(encoding="utf-8")
    defined = {p: sorted(i for i in extract_ids(req_text, (p,))) for p in REQ_PREFIXES}

    texts = {}
    errors, warns = [], []
    for name in DESIGN_DOCS:
        path = docs_dir / name
        if path.is_file():
            texts[name] = path.read_text(encoding="utf-8")
        else:
            errors.append(f"設計ドキュメントが見つかりません: {path}")

    # FR → 機能一覧のカバレッジ
    if FEATURE_LIST in texts:
        referenced = extract_ids(texts[FEATURE_LIST], ("FR",))
        for fr in defined["FR"]:
            if fr not in referenced:
                errors.append(f"{fr} が {FEATURE_LIST} で参照されていません（機能への対応漏れ）")

    # NFR → アーキテクチャ設計のカバレッジ
    if ARCHITECTURE in texts:
        referenced = extract_ids(texts[ARCHITECTURE], ("NFR",))
        for nfr in defined["NFR"]:
            if nfr not in referenced:
                warns.append(f"{nfr} が {ARCHITECTURE} で参照されていません（NFRトレーサビリティ）")

    # BREQ → 設計3点のどこかで参照
    all_design_text = "\n".join(texts.values())
    referenced_breq = extract_ids(all_design_text, ("BREQ",))
    for breq in defined["BREQ"]:
        if breq not in referenced_breq:
            warns.append(f"{breq} が設計ドキュメントのどこからも参照されていません")

    # プレースホルダ残存
    for name, text in texts.items():
        for loc, token in find_placeholders(docs_dir / name, text):
            # テンプレの記入例・凡例の行は対象外にしない（残存は人が判断）
            errors.append(f"プレースホルダID が残っています: {loc} → {token}")

    # レポート
    print("=== 02_plan トレーサビリティチェック ===")
    print(f"docs: {docs_dir}")
    print("\n--- 要件定義の定義済みID ---")
    for p in REQ_PREFIXES:
        print(f"  {p}: {len(defined[p])} 件")

    print("\n--- 設計側の採番状況 ---")
    counts = {p: len(extract_ids(all_design_text, (p,))) for p in DESIGN_PREFIXES}
    for p, n in counts.items():
        print(f"  {p}: {n} 件")

    print(f"\n--- 結果: ERROR {len(errors)} / WARN {len(warns)} ---")
    for e in errors:
        print(f"[ERROR] {e}")
    for w in warns:
        print(f"[WARN]  {w}")
    if not errors and not warns:
        print("OK: トレーサビリティに問題は見つかりませんでした")

    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
