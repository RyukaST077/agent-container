#!/usr/bin/env python3
"""
スナップショット網羅率レポートツール

用途:
  - 対象 API 仕様 (OpenAPI/Swagger YAML or JSON) と、
    現行のマスタースナップショット JSON を突合し、
    どのエンドポイントにどの suite (normal/auth/validation/boundary) が
    揃っているかを表にする。
  - 「どこが不足しているか」「何を足すべきか」を定量化するのが目的。

Usage:
  python3 coverage_report.py \
    --spec path/to/swagger.yaml \
    --master snapshots/snapshot-master.json \
    [--format markdown|text|json] \
    [--output report.md]

仕様ファイル形式:
  - OpenAPI 3.x / Swagger 2.x の YAML または JSON
  - paths の下の各 method (get/post/put/patch/delete) を拾う
  - responses のステータスコードも集計

スナップショット形式:
  - JSON 配列。各要素は少なくとも endpoint / method / http_code / suite を持つ
    (capture.sh.example / snapshot_comparator.py と同じスキーマ)

依存: Python 3.8+。PyYAML が入っていれば YAML を読める。
      入っていない場合は JSON 仕様ファイルのみ対応。
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

KNOWN_SUITES = ["normal", "auth", "validation", "boundary", "destructive"]
HTTP_METHODS = ["get", "post", "put", "patch", "delete", "head", "options"]


def load_spec(path: str) -> Dict[str, Any]:
    """OpenAPI/Swagger YAML or JSON を dict として読む"""
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"spec not found: {path}")
    text = p.read_text(encoding="utf-8")
    if path.endswith((".yaml", ".yml")):
        try:
            import yaml  # type: ignore
        except ImportError:
            raise ImportError(
                "YAML 仕様ファイルを読むには PyYAML が必要です: pip install pyyaml"
            )
        return yaml.safe_load(text)
    return json.loads(text)


def load_snapshot(path: str) -> List[Dict[str, Any]]:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"snapshot not found: {path}")
    data = json.loads(p.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"snapshot is not a JSON array: {path}")
    return data


def extract_spec_endpoints(spec: Dict[str, Any]) -> List[Tuple[str, str, Set[str]]]:
    """
    spec から (path, method, {status_code, ...}) のリストを返す。
    基準パス (servers[0].url や basePath) は適用しない (スナップショット側は
    フルパスを持つので、スナップショットの endpoint 論理名とマッチさせるのは
    呼び出し側の責任)。
    """
    out = []
    paths = spec.get("paths") or {}
    for path_str, path_item in paths.items():
        if not isinstance(path_item, dict):
            continue
        for method, op in path_item.items():
            m = method.lower()
            if m not in HTTP_METHODS:
                continue
            if not isinstance(op, dict):
                continue
            responses = op.get("responses") or {}
            status_codes: Set[str] = set()
            for code in responses.keys():
                code_s = str(code)
                if code_s.lower() != "default":
                    status_codes.add(code_s)
            out.append((path_str, m.upper(), status_codes))
    return out


def base_endpoint_name(endpoint: str) -> str:
    """
    auth/validation/boundary のサフィックスを剥がし、論理ベース名を返す。
    例: users.register.missing_nick → users.register
        users.register.bad_api_key  → users.register
        areas.list.lang_en          → areas.list
    """
    if not endpoint:
        return endpoint
    # 既知サフィックスパターン (完全一致ではなく末尾マッチ)
    # 複数階層のサフィックスに対応するため、繰り返し剥がす。
    suffix_patterns = [
        r"\.no_api_key$",
        r"\.bad_api_key$",
        r"\.no_user_id$",
        r"\.other_user$",
        r"\.missing_[a-z0-9_]+$",
        r"\.bad_[a-z0-9_]+$",
        r"\.invalid_[a-z0-9_]+$",
        r"\.notfound$",
        r"\.not_found$",
    ]
    # boundary 系は多様なので、最後のセグメントが英数のみかつ既知キーワードを含むなら剥がす
    boundary_keywords = (
        "min", "max", "over", "under", "zero", "empty", "lang_", "page_",
        "multibyte", "nohit", "no_hit",
    )

    name = endpoint
    changed = True
    while changed:
        changed = False
        for pat in suffix_patterns:
            new = re.sub(pat, "", name)
            if new != name:
                name = new
                changed = True
                break
        # boundary heuristic
        if not changed and "." in name:
            last = name.rsplit(".", 1)[1]
            if any(kw in last for kw in boundary_keywords):
                name = name.rsplit(".", 1)[0]
                changed = True
    return name


def collect_snapshot_coverage(entries: List[Dict[str, Any]]) -> Dict[Tuple[str, str], Dict[str, Any]]:
    """
    スナップショットを (base_endpoint, method) 単位に集約:
      {(base, method): {
         "suites": {suite_name: [case endpoint, ...]},
         "status_codes": {"200", "400", ...},
         "urls": ["/v1/...", ...],
      }}
    """
    bucket: Dict[Tuple[str, str], Dict[str, Any]] = defaultdict(
        lambda: {"suites": defaultdict(list), "status_codes": set(), "urls": set()}
    )
    for e in entries:
        endpoint = e.get("endpoint") or ""
        method = (e.get("method") or "").upper()
        if not endpoint or not method:
            continue
        base = base_endpoint_name(endpoint)
        key = (base, method)
        suite = e.get("suite") or "normal"
        bucket[key]["suites"][suite].append(endpoint)
        http_code = str(e.get("http_code") or "")
        if http_code:
            bucket[key]["status_codes"].add(http_code)
        url = e.get("url") or ""
        if url:
            bucket[key]["urls"].add(url)
    return bucket


def match_spec_to_snapshot(
    spec_endpoints: List[Tuple[str, str, Set[str]]],
    snapshot_coverage: Dict[Tuple[str, str], Dict[str, Any]],
) -> List[Dict[str, Any]]:
    """
    spec の各エンドポイントを、スナップショットの URL / endpoint 論理名と照合。
    マッチング戦略:
      1. URL に spec の path テンプレ (例: /users/{id}) の正規表現を当てる
      2. マッチした (base, method) を採用
    """
    # spec path → regex
    def path_to_regex(path: str) -> re.Pattern:
        # {id} → [^/]+
        escaped = re.escape(path)
        # re.escape は {...} をエスケープするので戻す
        escaped = re.sub(r"\\\{[^}]+\\\}", r"[^/]+", escaped)
        return re.compile(f"^.*{escaped}(\\?.*)?$")

    result = []
    used_keys: Set[Tuple[str, str]] = set()
    for spec_path, method, statuses in spec_endpoints:
        regex = path_to_regex(spec_path)
        matched_key: Optional[Tuple[str, str]] = None
        for key, cov in snapshot_coverage.items():
            if key[1] != method:
                continue
            if any(regex.match(u) for u in cov["urls"]):
                matched_key = key
                break
        result.append({
            "spec_path": spec_path,
            "method": method,
            "spec_status_codes": sorted(statuses),
            "matched_snapshot_key": matched_key,
            "snapshot_coverage": snapshot_coverage.get(matched_key) if matched_key else None,
        })
        if matched_key:
            used_keys.add(matched_key)

    # spec に無いが snapshot にある = 未記載 or debug
    extras = []
    for key, cov in snapshot_coverage.items():
        if key in used_keys:
            continue
        extras.append({
            "spec_path": None,
            "method": key[1],
            "spec_status_codes": [],
            "matched_snapshot_key": key,
            "snapshot_coverage": cov,
        })

    return result + extras


def summarize(rows: List[Dict[str, Any]]) -> Dict[str, Any]:
    covered = sum(1 for r in rows if r["matched_snapshot_key"] is not None and r["spec_path"] is not None)
    total_spec = sum(1 for r in rows if r["spec_path"] is not None)
    extras = sum(1 for r in rows if r["spec_path"] is None)

    suite_counts = {s: 0 for s in KNOWN_SUITES}
    status_counts: Dict[str, int] = defaultdict(int)
    missing_auth: List[str] = []
    missing_validation: List[str] = []
    missing_boundary: List[str] = []
    status_gaps: List[Dict[str, Any]] = []

    for r in rows:
        cov = r.get("snapshot_coverage")
        if not cov:
            if r["spec_path"]:
                missing_auth.append(f"{r['method']} {r['spec_path']}")
                missing_validation.append(f"{r['method']} {r['spec_path']}")
                missing_boundary.append(f"{r['method']} {r['spec_path']}")
            continue
        for suite in cov["suites"]:
            if suite in suite_counts:
                suite_counts[suite] += 1
        for sc in cov["status_codes"]:
            status_counts[sc] += 1

        if r["spec_path"]:
            label = f"{r['method']} {r['spec_path']}"
            if "auth" not in cov["suites"]:
                missing_auth.append(label)
            if "validation" not in cov["suites"]:
                missing_validation.append(label)
            if "boundary" not in cov["suites"]:
                missing_boundary.append(label)

            covered_statuses = cov["status_codes"]
            spec_statuses = set(r["spec_status_codes"])
            missing_status = spec_statuses - covered_statuses
            if missing_status:
                status_gaps.append({
                    "endpoint": label,
                    "spec": sorted(spec_statuses),
                    "covered": sorted(covered_statuses),
                    "missing": sorted(missing_status),
                })

    return {
        "total_spec_endpoints": total_spec,
        "covered_endpoints": covered,
        "extras_endpoints": extras,
        "suite_counts": suite_counts,
        "status_counts": dict(status_counts),
        "missing_auth": missing_auth,
        "missing_validation": missing_validation,
        "missing_boundary": missing_boundary,
        "status_gaps": status_gaps,
    }


def render_markdown(rows: List[Dict[str, Any]], summary: Dict[str, Any], limit: int = 30) -> str:
    L: List[str] = ["# スナップショット網羅率レポート", ""]

    total = summary["total_spec_endpoints"]
    covered = summary["covered_endpoints"]
    pct = (covered / total * 100) if total else 0.0
    L += [
        "## エンドポイント網羅率",
        "",
        f"- 仕様定義: **{total}** 件",
        f"- カバー済み: **{covered}** 件 ({pct:.1f}%)",
        f"- 未カバー: **{total - covered}** 件",
        f"- 仕様外 (debug/Web 等): {summary['extras_endpoints']} 件",
        "",
    ]

    L += [
        "## suite 別 スナップショット数",
        "",
        "| suite | エンドポイント数 |",
        "|---|---:|",
    ]
    for s in KNOWN_SUITES:
        L.append(f"| {s} | {summary['suite_counts'].get(s, 0)} |")
    L.append("")

    if summary["status_counts"]:
        L += ["## ステータスコード分布", "", "| code | 件数 |", "|---|---:|"]
        for code in sorted(summary["status_counts"].keys()):
            L.append(f"| {code} | {summary['status_counts'][code]} |")
        L.append("")

    L += [
        "## エンドポイント × suite マトリクス",
        "",
        "記号: ✓=あり / ✗=なし / ⚠=仕様未マッチ",
        "",
        "| method | path | normal | auth | validation | boundary | statuses (covered / spec) |",
        "|---|---|:-:|:-:|:-:|:-:|---|",
    ]
    # ソート: spec_path がある → path 順、 spec 外 → method 順
    def sort_key(r):
        if r["spec_path"]:
            return (0, r["spec_path"], r["method"])
        cov = r.get("snapshot_coverage") or {}
        urls = sorted(cov.get("urls") or [""])
        return (1, urls[0] if urls else "", r["method"])
    rows_sorted = sorted(rows, key=sort_key)
    for r in rows_sorted[:limit]:
        cov = r.get("snapshot_coverage")
        if cov:
            has = cov["suites"]
            def mark(s):
                return "✓" if s in has else "✗"
            covered_str = ",".join(sorted(cov["status_codes"])) or "-"
        else:
            has = {}
            def mark(s):
                return "✗"
            covered_str = "-"
        spec_str = ",".join(r["spec_status_codes"]) or "-"
        path_disp = r["spec_path"] or (sorted((cov or {}).get("urls") or [""])[0] or "(unknown)")
        if not r["spec_path"]:
            path_disp = f"⚠ {path_disp}"
        L.append(
            f"| {r['method']} | `{path_disp}` | {mark('normal')} | {mark('auth')} | "
            f"{mark('validation')} | {mark('boundary')} | {covered_str} / {spec_str} |"
        )
    if len(rows_sorted) > limit:
        L.append(f"| ... ({len(rows_sorted) - limit} 件省略) | | | | | | |")
    L.append("")

    def dump_missing(title: str, items: List[str]) -> List[str]:
        if not items:
            return [f"### ✓ {title}", "", "  すべてのエンドポイントで取得済み", ""]
        head = [f"### ⚠ {title} ({len(items)} 件)", ""]
        head += [f"- `{x}`" for x in items[:20]]
        if len(items) > 20:
            head.append(f"- ... 他 {len(items) - 20} 件")
        head.append("")
        return head

    L.append("## 不足している suite")
    L.append("")
    L += dump_missing("auth スナップショット未取得", summary["missing_auth"])
    L += dump_missing("validation スナップショット未取得", summary["missing_validation"])
    L += dump_missing("boundary スナップショット未取得", summary["missing_boundary"])

    if summary["status_gaps"]:
        L += [
            "## ステータスコード ギャップ",
            "",
            "仕様に定義されているが、スナップショットで取れていないレスポンスコード:",
            "",
            "| endpoint | spec | covered | missing |",
            "|---|---|---|---|",
        ]
        for g in summary["status_gaps"][:30]:
            L.append(
                f"| `{g['endpoint']}` | {','.join(g['spec'])} | "
                f"{','.join(g['covered'])} | **{','.join(g['missing'])}** |"
            )
        if len(summary["status_gaps"]) > 30:
            L.append(f"| ... ({len(summary['status_gaps']) - 30} 件省略) | | | |")
        L.append("")

    L += [
        "## 推奨アクション",
        "",
    ]
    recs = []
    if summary["missing_auth"]:
        recs.append(
            f"- **[High]** {len(summary['missing_auth'])} endpoints に auth suite なし → "
            "`call_unauth_no_key` / `call_unauth_bad_key` で最低 1 本ずつ追加"
        )
    if summary["missing_validation"]:
        recs.append(
            f"- **[High]** {len(summary['missing_validation'])} endpoints に validation suite なし → "
            "`reference/discovery-checklist.md §3-5` のバリデーション表を埋めてから "
            "`call_invalid_body` / `call_invalid_query` で追加"
        )
    if summary["missing_boundary"]:
        recs.append(
            f"- **[Mid]** {len(summary['missing_boundary'])} endpoints に boundary suite なし → "
            "`reference/test-case-matrix.md` の型別観点を参照して `call_boundary` で追加"
        )
    if summary["status_gaps"]:
        recs.append(
            f"- **[Mid]** {len(summary['status_gaps'])} endpoints で仕様定義ステータスの一部が未カバー → "
            "上記「ステータスコード ギャップ」の `missing` 列を参考にテストケース追加"
        )
    if not recs:
        recs.append("- すべての観点が最低ラインを満たしています 🎉")
    L += recs
    L.append("")

    return "\n".join(L)


def render_text(rows: List[Dict[str, Any]], summary: Dict[str, Any]) -> str:
    L = []
    total = summary["total_spec_endpoints"]
    covered = summary["covered_endpoints"]
    pct = (covered / total * 100) if total else 0.0
    L.append("=== Snapshot Coverage Report ===")
    L.append(f"Endpoints: {covered}/{total} ({pct:.1f}%)  extras: {summary['extras_endpoints']}")
    L.append("")
    L.append("Suite counts:")
    for s in KNOWN_SUITES:
        L.append(f"  {s:12s} {summary['suite_counts'].get(s, 0)}")
    L.append("")
    L.append("Status distribution:")
    for code in sorted(summary["status_counts"].keys()):
        L.append(f"  {code}  {summary['status_counts'][code]}")
    L.append("")
    if summary["missing_auth"]:
        L.append(f"[High] Missing auth suite ({len(summary['missing_auth'])} endpoints):")
        for x in summary["missing_auth"][:10]:
            L.append(f"  - {x}")
        if len(summary["missing_auth"]) > 10:
            L.append(f"  ... +{len(summary['missing_auth']) - 10} more")
        L.append("")
    if summary["missing_validation"]:
        L.append(f"[High] Missing validation suite ({len(summary['missing_validation'])} endpoints):")
        for x in summary["missing_validation"][:10]:
            L.append(f"  - {x}")
        if len(summary["missing_validation"]) > 10:
            L.append(f"  ... +{len(summary['missing_validation']) - 10} more")
        L.append("")
    if summary["missing_boundary"]:
        L.append(f"[Mid] Missing boundary suite ({len(summary['missing_boundary'])} endpoints):")
        for x in summary["missing_boundary"][:10]:
            L.append(f"  - {x}")
        if len(summary["missing_boundary"]) > 10:
            L.append(f"  ... +{len(summary['missing_boundary']) - 10} more")
        L.append("")
    return "\n".join(L)


def render_json(rows: List[Dict[str, Any]], summary: Dict[str, Any]) -> str:
    def clean(obj):
        if isinstance(obj, set):
            return sorted(obj)
        if isinstance(obj, defaultdict):
            return {k: clean(v) for k, v in obj.items()}
        if isinstance(obj, dict):
            return {k: clean(v) for k, v in obj.items()}
        if isinstance(obj, list):
            return [clean(v) for v in obj]
        if isinstance(obj, tuple):
            return list(obj)
        return obj
    return json.dumps({"rows": clean(rows), "summary": clean(summary)},
                      ensure_ascii=False, indent=2)


def main() -> int:
    ap = argparse.ArgumentParser(description="スナップショット網羅率レポート")
    ap.add_argument("--spec", required=True, help="OpenAPI/Swagger YAML または JSON")
    ap.add_argument("--master", required=True, help="マスタースナップショット JSON")
    ap.add_argument("--format", choices=["markdown", "text", "json"], default="markdown")
    ap.add_argument("--output", default=None, help="出力ファイル (省略時は stdout)")
    ap.add_argument("--limit", type=int, default=100, help="マトリクス表示行数上限 (markdown)")
    ap.add_argument("--fail-on-gap", action="store_true",
                    help="auth/validation/boundary いずれかが不足していれば exit 1")
    args = ap.parse_args()

    try:
        spec = load_spec(args.spec)
    except Exception as e:
        print(f"Error loading spec: {e}", file=sys.stderr)
        return 2
    try:
        entries = load_snapshot(args.master)
    except Exception as e:
        print(f"Error loading snapshot: {e}", file=sys.stderr)
        return 2

    spec_endpoints = extract_spec_endpoints(spec)
    coverage = collect_snapshot_coverage(entries)
    rows = match_spec_to_snapshot(spec_endpoints, coverage)
    summary = summarize(rows)

    if args.format == "markdown":
        output = render_markdown(rows, summary, limit=args.limit)
    elif args.format == "text":
        output = render_text(rows, summary)
    else:
        output = render_json(rows, summary)

    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
        print(f"Report written: {args.output}", file=sys.stderr)
    else:
        print(output)

    if args.fail_on_gap and (
        summary["missing_auth"] or summary["missing_validation"] or summary["missing_boundary"]
    ):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
