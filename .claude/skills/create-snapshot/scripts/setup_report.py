#!/usr/bin/env python3
"""
snapshot-master.json を読み、「どんなテストが作成されたか」の導入完了レポートを
Markdown で書き出す。approve 完了直後にユーザへ「今回何が入ったか」を示すために使う。

使用例:
  python3 tools/snapshot/setup_report.py \
    --master snapshots/snapshot-master.json \
    --output snapshots/setup-report.md

- 実 API / 実 DB は叩かない。JSON を読むだけなので sandbox 内でも動く。
- normalizer_rules.json が隣にあれば skip_body_endpoints 等の特記事項も出す。
"""
from __future__ import annotations
import argparse, json, sys, collections, pathlib

SUITE_LABELS = {
    "normal":      "正常系",
    "auth":        "異常系 (認可)",
    "validation":  "異常系 (バリデーション)",
    "boundary":    "境界値",
    "destructive": "破壊系",
}
SUITE_ORDER = ["normal", "auth", "validation", "boundary", "destructive"]


def load_master(path: pathlib.Path) -> list[dict]:
    with path.open() as fh:
        data = json.load(fh)
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for k in ("entries", "snapshots", "data"):
            if isinstance(data.get(k), list):
                return data[k]
    raise SystemExit(f"Unsupported master format: {path}")


def load_rules(master_path: pathlib.Path) -> dict | None:
    for cand in [
        master_path.parent.parent / "tools" / "snapshot" / "normalizer_rules.json",
        master_path.parent / "normalizer_rules.json",
    ]:
        if cand.exists():
            try:
                return json.loads(cand.read_text())
            except Exception:
                return None
    return None


def short_error_message(entry: dict) -> str:
    body = entry.get("response_body")
    if not isinstance(body, dict):
        return ""
    err = body.get("error") or {}
    prev = err.get("previous") or {}
    msg = err.get("message") or ""
    pmsg = prev.get("message") or ""
    out = msg
    if pmsg and pmsg != msg:
        out = f"{msg} | {pmsg}"
    return (out[:160] + "…") if len(out) > 160 else out


def fmt_matrix(entries: list[dict]) -> str:
    mtx = collections.defaultdict(collections.Counter)
    for e in entries:
        mtx[e.get("suite", "?")][str(e.get("http_code", "?"))] += 1
    codes = sorted({code for row in mtx.values() for code in row})
    header = "| suite | " + " | ".join(codes) + " | 合計 |"
    sep = "|---" * (len(codes) + 2) + "|"
    rows = [header, sep]
    for suite in SUITE_ORDER:
        if suite not in mtx:
            continue
        row = mtx[suite]
        cells = [str(row.get(c, 0)) for c in codes]
        total = sum(row.values())
        rows.append(
            f"| {suite} ({SUITE_LABELS.get(suite, suite)}) | "
            + " | ".join(cells)
            + f" | {total} |"
        )
    return "\n".join(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--master", required=True, type=pathlib.Path)
    ap.add_argument("--output", required=True, type=pathlib.Path)
    args = ap.parse_args()

    entries = load_master(args.master)
    rules = load_rules(args.master)

    suites = collections.Counter(e.get("suite", "?") for e in entries)

    bad_conn = [e for e in entries if str(e.get("http_code", "")) in ("000", "000000", "0", "")]
    fivexx = [e for e in entries if str(e.get("http_code", "")).startswith("5")]
    normal_non2 = [
        e for e in entries
        if e.get("suite") == "normal"
        and not str(e.get("http_code", "")).startswith("2")
    ]

    lines: list[str] = []
    lines.append("# スナップショット導入完了レポート")
    lines.append("")
    lines.append(f"- master: `{args.master}`")
    lines.append(f"- 総エントリ数: **{len(entries)}**")
    lines.append("")

    lines.append("## suite 別件数")
    lines.append("")
    lines.append("| 区分 | suite | 件数 |")
    lines.append("|---|---|---:|")
    for suite in SUITE_ORDER:
        if suite in suites:
            lines.append(f"| {SUITE_LABELS[suite]} | `{suite}` | {suites[suite]} |")
    lines.append(f"| **合計** |  | **{len(entries)}** |")
    lines.append("")

    lines.append("## suite × HTTP code マトリクス")
    lines.append("")
    lines.append(fmt_matrix(entries))
    lines.append("")

    lines.append("## 健全性チェック")
    lines.append("")
    lines.append(f"- 接続失敗 (000/000000): **{len(bad_conn)}** {'✅' if not bad_conn else '❌'}")
    lines.append(f"- 5xx: **{len(fivexx)}** {'(後述で原因確認)' if fivexx else ''}")
    lines.append(f"- normal suite の非 2xx: **{len(normal_non2)}** {'(後述で個別確認)' if normal_non2 else ''}")
    lines.append("")

    if fivexx:
        lines.append("## 5xx エントリ一覧")
        lines.append("")
        lines.append("> ローカルで外部サービス連携 (Apple/Google 決済, メール, SMS 等) が 500 になるのは想定内。")
        lines.append("> ベースラインとして固定化する対象。http_code が変わったら検知される。")
        lines.append("")
        lines.append("| suite | endpoint | code | error 要約 |")
        lines.append("|---|---|---|---|")
        for e in fivexx:
            lines.append(
                f"| {e.get('suite')} | `{e.get('endpoint')}` | "
                f"{e.get('http_code')} | {short_error_message(e)} |"
            )
        lines.append("")

    if normal_non2:
        lines.append("## normal suite で 2xx にならなかったエントリ")
        lines.append("")
        lines.append("> 「正常系なのに 4xx/5xx」は以下いずれか:")
        lines.append("> (a) seed にデータが無い, (b) テスト body が実仕様を満たしていない, (c) 外部依存, (d) 業務ロジック上の期待挙動。")
        lines.append("> 現状挙動を **マスターとして固定化** する方針で問題ない（バージョンアップで挙動が変わったら検知される）。")
        lines.append("")
        lines.append("| endpoint | code | error 要約 |")
        lines.append("|---|---|---|")
        for e in normal_non2:
            lines.append(
                f"| `{e.get('endpoint')}` | {e.get('http_code')} | {short_error_message(e)} |"
            )
        lines.append("")

    if rules:
        skip = rules.get("skip_body_endpoints") or []
        cmp_fields = rules.get("compare_fields") or []
        lines.append("## 正規化・比較ルールの特記事項")
        lines.append("")
        lines.append(
            f"- `compare_fields`: {', '.join(f'`{x}`' for x in cmp_fields) or '(未設定)'}"
        )
        lines.append(
            f"- `skip_body_endpoints`: {', '.join(f'`{x}`' for x in skip) or '(なし)'}"
        )
        key_rules = rules.get("key_rules") or []
        debug_rule = [
            r for r in key_rules
            if "file" in (r.get("keys") or []) or "trace" in (r.get("keys") or [])
        ]
        if debug_rule:
            lines.append(
                "- APP_DEBUG 由来の stack trace (`file`/`line`/`trace`) を mask 済み "
                "(framework バージョンアップで false-positive にならない)"
            )
        lines.append("")

    lines.append("## 何を固定化したか (要約)")
    lines.append("")
    lines.append(f"この master は、現時点の API が **{len(entries)} パターンの入力に対して返すレスポンス**を")
    lines.append("正規化後のゴールデンとして固定化しています。以降の `snapshot.sh test` で:")
    lines.append("")
    lines.append("- HTTP ステータスが変化した場合")
    lines.append("- レスポンスボディの構造・値が変化した場合 (正規化でマスクしたもの除く)")
    lines.append("- (設定していれば) レスポンスヘッダが変化した場合")
    lines.append("")
    lines.append("に回帰として検出されます。PHP/Laravel のバージョンアップ、ライブラリ更新、")
    lines.append("リファクタ前後で走らせ、差分の有無で「外から見た API 契約」の保全を確認してください。")
    lines.append("")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(f"[setup_report] wrote {args.output} ({len(entries)} entries)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
