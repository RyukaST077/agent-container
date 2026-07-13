#!/usr/bin/env python3
"""
汎用 API スナップショット比較ツール

Usage:
  python3 snapshot_comparator.py <current.json> [master.json] [--rules rules.json]

入力形式 (JSON 配列、1 要素 = 1 API コール):
  必須: endpoint, http_code
  任意: method, suite, url, response_body, result, expected, timestamp

出力:
  - Markdown 差分レポート (<current>-report.md)
  - 標準出力にも同内容
  - 差分または契約エラーがあれば exit 1
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


DEFAULT_RULES: Dict[str, Any] = {
    "match_keys": ["endpoint", "method"],
    "compare_fields": ["http_code", "response_body"],
    "skip_body_endpoints": [],
    "key_rules": [],
    "value_rules": [],
    # ---- 組み込み機能 ----
    "compare_headers": [],          # compare_fields に "response_headers" を含めた場合に比較するヘッダ名
    "diff_max_lines": 20,           # ボディ diff の表示行上限
    "list_sort": {},                # {endpoint: {"path": "data.items", "key": "id"}} で配列安定ソート
    "idempotent_methods": ["GET"],  # idempotency check 対象メソッド (capture 側で2回叩く必要あり)
    "severity_overrides": {},       # rule名 → severity の上書き。例: {"field_added": "compatible"}
    "cluster_min_count": 2,         # 差分クラスタリングの最小件数
}

# 各 rule のデフォルト severity
#   breaking      : 明らかに破壊的 (人間レビュー必須)
#   compatible    : 破壊的でない変更 (approve を軽量化してよい)
#   informational : 情報のみ (無視してよい可能性が高い)
DEFAULT_SEVERITY: Dict[str, str] = {
    "field_added":                "compatible",
    "field_removed":              "breaking",
    "type_changed":               "breaking",
    "value_changed":              "breaking",
    "array_length_changed":       "breaking",
    "http_code_same_class":       "compatible",
    "http_code_class_changed":    "breaking",
    "http_code_error_introduced": "breaking",
    "type_signature_changed":     "breaking",
    "endpoint_added":             "compatible",
    "endpoint_removed":           "breaking",
}
SEVERITY_ORDER = {"informational": 1, "compatible": 2, "breaking": 3}


class RuleSet:
    def __init__(self, rules: Optional[Dict[str, Any]]):
        merged = dict(DEFAULT_RULES)
        if rules:
            merged.update(rules)
        self.match_keys: List[str] = list(merged["match_keys"])
        self.compare_fields: List[str] = list(merged["compare_fields"])
        self.skip_body_endpoints = set(merged["skip_body_endpoints"])
        self.key_rules: List[Dict[str, Any]] = [
            self._compile_key_rule(r) for r in merged["key_rules"]
        ]
        self.value_rules: List[Tuple[re.Pattern, str]] = [
            (re.compile(r["regex"]), r["token"]) for r in merged["value_rules"]
        ]
        self.compare_headers: List[str] = [h.lower() for h in merged["compare_headers"]]
        self.diff_max_lines: int = int(merged["diff_max_lines"])
        self.list_sort: Dict[str, Dict[str, str]] = dict(merged["list_sort"])
        self.idempotent_methods: set = {m.upper() for m in merged["idempotent_methods"]}
        self.severity_overrides: Dict[str, str] = dict(merged["severity_overrides"])
        self.cluster_min_count: int = int(merged["cluster_min_count"])

    def severity_of(self, rule: str) -> str:
        return self.severity_overrides.get(rule, DEFAULT_SEVERITY.get(rule, "breaking"))

    @staticmethod
    def _compile_key_rule(rule: Dict[str, Any]) -> Dict[str, Any]:
        out = dict(rule)
        if out.get("value_regex"):
            out["_value_re"] = re.compile(out["value_regex"])
        return out

    def normalize(self, value: Any, key: Optional[str] = None) -> Any:
        key_name = (key or "").lower()

        if isinstance(value, str):
            for rule in self.key_rules:
                if self._key_rule_matches(rule, key_name, value):
                    return rule["token"]
            for pattern, token in self.value_rules:
                if pattern.match(value):
                    return token
            return value

        if isinstance(value, int) and not isinstance(value, bool):
            for rule in self.key_rules:
                if rule.get("applies_to_int") and self._key_rule_matches(rule, key_name, str(value)):
                    return rule["token"]
            return value

        return value

    @staticmethod
    def _key_rule_matches(rule: Dict[str, Any], key_name: str, value_str: str) -> bool:
        mtype = rule.get("type", "exact")
        keys = [k.lower() for k in rule.get("keys", [])]
        value_re = rule.get("_value_re")
        if value_re is not None and not value_re.match(value_str):
            return False
        if not keys:
            return value_re is not None
        if mtype == "exact":
            return key_name in keys
        if mtype == "suffix":
            return any(key_name.endswith(k) for k in keys)
        if mtype == "prefix":
            return any(key_name.startswith(k) for k in keys)
        if mtype == "contains":
            return any(k in key_name for k in keys)
        if mtype == "regex":
            return any(re.search(k, key_name) for k in keys)
        return False


class DiffClassifier:
    """CHANGED 差分を path / rule / severity に分解する。"""

    @staticmethod
    def _type_name(v: Any) -> str:
        if v is None:
            return "null"
        if isinstance(v, bool):
            return "bool"
        if isinstance(v, int):
            return "int"
        if isinstance(v, float):
            return "float"
        if isinstance(v, str):
            return "str"
        if isinstance(v, list):
            return "list"
        if isinstance(v, dict):
            return "dict"
        return type(v).__name__

    @staticmethod
    def _short(v: Any, limit: int = 80) -> str:
        try:
            s = json.dumps(v, ensure_ascii=False, default=str)
        except Exception:
            s = str(v)
        return s if len(s) <= limit else s[:limit - 3] + "..."

    @classmethod
    def classify_http_code(cls, rules: RuleSet, old: Any, new: Any) -> Dict[str, Any]:
        try:
            o_class = int(str(old)) // 100
            n_class = int(str(new)) // 100
        except (ValueError, TypeError):
            rule = "http_code_class_changed"
            return {"path": "http_code", "rule": rule, "severity": rules.severity_of(rule), "old": old, "new": new}

        if o_class == n_class:
            rule = "http_code_same_class"
        elif o_class < 4 and n_class >= 4:
            rule = "http_code_error_introduced"
        else:
            rule = "http_code_class_changed"
        return {"path": "http_code", "rule": rule, "severity": rules.severity_of(rule), "old": old, "new": new}

    @classmethod
    def classify_tree(cls, rules: RuleSet, path: str, old: Any, new: Any, is_type_mode: bool = False) -> List[Dict[str, Any]]:
        if old == new:
            return []
        old_t, new_t = cls._type_name(old), cls._type_name(new)
        if old_t != new_t:
            rule = "type_changed"
            return [{
                "path": path or "(root)", "rule": rule, "severity": rules.severity_of(rule),
                "old": f"{old_t}: {cls._short(old)}",
                "new": f"{new_t}: {cls._short(new)}",
            }]
        if isinstance(old, dict):
            results = []
            for k in sorted(set(old.keys()) | set(new.keys())):
                child = f"{path}.{k}" if path else k
                if k in old and k not in new:
                    rule = "field_removed"
                    results.append({"path": child, "rule": rule, "severity": rules.severity_of(rule),
                                    "old": cls._short(old[k]), "new": None})
                elif k not in old and k in new:
                    rule = "field_added"
                    results.append({"path": child, "rule": rule, "severity": rules.severity_of(rule),
                                    "old": None, "new": cls._short(new[k])})
                elif old[k] != new[k]:
                    results.extend(cls.classify_tree(rules, child, old[k], new[k], is_type_mode))
            return results
        if isinstance(old, list):
            if len(old) != len(new):
                rule = "array_length_changed"
                return [{
                    "path": f"{path}[*]" if path else "[*]",
                    "rule": rule, "severity": rules.severity_of(rule),
                    "old": f"length={len(old)}", "new": f"length={len(new)}",
                }]
            results = []
            for i, (o, n) in enumerate(zip(old, new)):
                if o != n:
                    results.extend(cls.classify_tree(rules, f"{path}[{i}]", o, n, is_type_mode))
            return results
        # scalar
        rule = "type_signature_changed" if is_type_mode else "value_changed"
        return [{
            "path": path or "(root)", "rule": rule, "severity": rules.severity_of(rule),
            "old": cls._short(old), "new": cls._short(new),
        }]


def max_severity(items: List[Dict[str, Any]], default: str = "breaking") -> str:
    if not items:
        return default
    return max(
        (i.get("severity", default) for i in items),
        key=lambda s: SEVERITY_ORDER.get(s, 0),
    )


class SnapshotComparator:
    def __init__(self, current_file: str, master_file: Optional[str], rules: RuleSet):
        self.current_file = current_file
        self.master_file = master_file
        self.rules = rules
        self.current: List[Dict[str, Any]] = self._load(current_file) or []
        self.master: List[Dict[str, Any]] = self._load(master_file) if master_file else []
        self.diffs: List[Dict[str, Any]] = []
        self.contract_errors: List[Dict[str, Any]] = []

    @staticmethod
    def _load(path: Optional[str]) -> List[Dict[str, Any]]:
        if not path:
            return []
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
            if not isinstance(data, list):
                print(f"Warning: {path} is not a JSON array", file=sys.stderr)
                return []
            return data
        except FileNotFoundError:
            print(f"Warning: file not found: {path}", file=sys.stderr)
            return []
        except Exception as e:
            print(f"Warning: load failed {path}: {e}", file=sys.stderr)
            return []

    def _key(self, entry: Dict[str, Any]) -> Tuple:
        return tuple(str(entry.get(k, "-")) for k in self.rules.match_keys)

    def _validate(self, entries: List[Dict[str, Any]], source: str) -> None:
        for i, e in enumerate(entries, 1):
            if not isinstance(e, dict):
                self.contract_errors.append({"source": source, "index": i, "message": "entry is not an object"})
                continue
            missing = [k for k in self.rules.match_keys if k not in e]
            if missing:
                self.contract_errors.append({"source": source, "index": i, "message": f"missing match keys: {missing}"})
            if "http_code" not in e:
                self.contract_errors.append({"source": source, "index": i, "message": "missing http_code"})

    def _normalize_any(self, value: Any, key: Optional[str] = None) -> Any:
        if isinstance(value, dict):
            return {k: self._normalize_any(v, k) for k, v in value.items()}
        if isinstance(value, list):
            return [self._normalize_any(v, key) for v in value]
        return self.rules.normalize(value, key)

    def _raw_body(self, entry: Dict[str, Any]) -> Any:
        body = entry.get("response_body")
        if isinstance(body, str):
            try:
                return json.loads(body)
            except Exception:
                return body
        return body

    def _apply_list_sort(self, body: Any, endpoint: Optional[str]) -> Any:
        if not endpoint or endpoint not in self.rules.list_sort:
            return body
        cfg = self.rules.list_sort[endpoint]
        path = [p for p in cfg.get("path", "").split(".") if p]
        sort_key = cfg["key"]
        body_copy = json.loads(json.dumps(body))  # deep copy
        target = body_copy
        for p in path:
            if isinstance(target, dict) and p in target:
                target = target[p]
            else:
                return body_copy
        if isinstance(target, list):
            try:
                target.sort(key=lambda x: (x.get(sort_key) if isinstance(x, dict) else x))
            except TypeError:
                pass
        return body_copy

    def _normalize_body(self, entry: Dict[str, Any]) -> Any:
        body = self._raw_body(entry)
        body = self._apply_list_sort(body, entry.get("endpoint"))
        if isinstance(body, (dict, list)):
            return self._normalize_any(body, "response_body")
        if isinstance(body, str):
            return self.rules.normalize(body, "response_body")
        return body

    def _type_signature(self, value: Any) -> Any:
        if value is None:
            return "null"
        if isinstance(value, bool):
            return "bool"
        if isinstance(value, int):
            return "int"
        if isinstance(value, float):
            return "float"
        if isinstance(value, str):
            try:
                parsed = json.loads(value)
                if isinstance(parsed, (dict, list)):
                    return self._type_signature(parsed)
            except Exception:
                pass
            return "str"
        if isinstance(value, list):
            if not value:
                return []
            types = []
            for item in value:
                t = self._type_signature(item)
                if t not in types:
                    types.append(t)
            return [types[0]] if len(types) == 1 else sorted(types, key=lambda x: json.dumps(x, sort_keys=True))
        if isinstance(value, dict):
            return {k: self._type_signature(v) for k, v in sorted(value.items())}
        return type(value).__name__

    def _pick_headers(self, headers: Any) -> Dict[str, Any]:
        if not isinstance(headers, dict) or not self.rules.compare_headers:
            return {}
        lower = {k.lower(): v for k, v in headers.items()}
        picked = {}
        for name in self.rules.compare_headers:
            if name in lower:
                picked[name] = self.rules.normalize(lower[name], name)
        return picked

    def compare(self) -> None:
        self._validate(self.current, "current")
        if self.master:
            self._validate(self.master, "master")

        if not self.master:
            self.diffs = [
                {"type": "SUMMARY", "key": self._key(e), "current": e, "master": None}
                for e in self.current
            ]
            return

        cmap = {self._key(e): e for e in self.current}
        mmap = {self._key(e): e for e in self.master}

        for key in sorted(set(cmap) | set(mmap)):
            cur = cmap.get(key)
            mas = mmap.get(key)
            if cur is not None and mas is None:
                self.diffs.append({
                    "type": "NEW", "key": key, "current": cur, "master": None,
                    "severity": self.rules.severity_of("endpoint_added"),
                })
            elif mas is not None and cur is None:
                self.diffs.append({
                    "type": "REMOVED", "key": key, "current": None, "master": mas,
                    "severity": self.rules.severity_of("endpoint_removed"),
                })
            else:
                diff = self._compare_pair(cur, mas)
                if diff:
                    self.diffs.append(diff)

    def _compare_pair(self, cur: Dict[str, Any], mas: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        changes = []
        endpoint = cur.get("endpoint") or mas.get("endpoint")
        for field in self.rules.compare_fields:
            detail: List[Dict[str, Any]] = []
            old_val: Any = None
            new_val: Any = None
            hit = False

            if field == "response_body":
                if endpoint in self.rules.skip_body_endpoints:
                    continue
                c = self._normalize_body(cur)
                m = self._normalize_body(mas)
                if json.dumps(c, sort_keys=True, ensure_ascii=False) != json.dumps(m, sort_keys=True, ensure_ascii=False):
                    hit, old_val, new_val = True, m, c
                    detail = DiffClassifier.classify_tree(self.rules, "", m, c)
            elif field == "type_signature":
                if endpoint in self.rules.skip_body_endpoints:
                    continue
                c_types = self._type_signature(self._raw_body(cur))
                m_types = self._type_signature(self._raw_body(mas))
                if json.dumps(c_types, sort_keys=True) != json.dumps(m_types, sort_keys=True):
                    hit, old_val, new_val = True, m_types, c_types
                    detail = DiffClassifier.classify_tree(self.rules, "", m_types, c_types, is_type_mode=True)
            elif field == "response_headers":
                c_h = self._pick_headers(cur.get("response_headers") or {})
                m_h = self._pick_headers(mas.get("response_headers") or {})
                if c_h != m_h:
                    hit, old_val, new_val = True, m_h, c_h
                    detail = DiffClassifier.classify_tree(self.rules, "", m_h, c_h)
            elif field == "http_code":
                if str(cur.get(field)) != str(mas.get(field)):
                    hit, old_val, new_val = True, mas.get(field), cur.get(field)
                    detail = [DiffClassifier.classify_http_code(self.rules, old_val, new_val)]
            else:
                if cur.get(field) != mas.get(field):
                    hit, old_val, new_val = True, mas.get(field), cur.get(field)
                    detail = [{
                        "path": field, "rule": "value_changed",
                        "severity": self.rules.severity_of("value_changed"),
                        "old": DiffClassifier._short(old_val),
                        "new": DiffClassifier._short(new_val),
                    }]

            if hit:
                changes.append({
                    "field": field, "old": old_val, "new": new_val,
                    "detail": detail,
                    "severity": max_severity(detail),
                })

        if not changes:
            return None
        return {
            "type": "CHANGED",
            "key": self._key(cur),
            "current": cur,
            "master": mas,
            "changes": changes,
            "severity": max_severity(changes),
        }

    def filtered_failures(self, min_severity: str) -> List[Dict[str, Any]]:
        """指定 severity 以上の diff と全 NEW/REMOVED/CHANGED を返す"""
        min_order = SEVERITY_ORDER.get(min_severity, 1)
        out = []
        for d in self.diffs:
            if d["type"] not in ("NEW", "REMOVED", "CHANGED"):
                continue
            sev = d.get("severity", "breaking")
            if SEVERITY_ORDER.get(sev, 3) >= min_order:
                out.append(d)
        return out

    def cluster_details(self) -> List[Dict[str, Any]]:
        """全 CHANGED.detail を path 正規化してグルーピングする"""
        from collections import OrderedDict
        bucket: "OrderedDict[Tuple[str, str, str, str], Dict[str, Any]]" = OrderedDict()
        for d in self.diffs:
            if d["type"] != "CHANGED":
                continue
            endpoint_key = " / ".join(str(x) for x in d["key"])
            for change in d.get("changes", []):
                for det in change.get("detail", []):
                    path_norm = re.sub(r"\[\d+\]", "[*]", det.get("path", ""))
                    key = (change["field"], path_norm, det.get("rule", ""), det.get("severity", "breaking"))
                    if key not in bucket:
                        bucket[key] = {
                            "field": change["field"],
                            "path": path_norm,
                            "rule": det.get("rule", ""),
                            "severity": det.get("severity", "breaking"),
                            "endpoints": [],
                        }
                    if endpoint_key not in bucket[key]["endpoints"]:
                        bucket[key]["endpoints"].append(endpoint_key)
        clusters = [b for b in bucket.values() if len(b["endpoints"]) >= self.rules.cluster_min_count]
        clusters.sort(key=lambda x: (-len(x["endpoints"]), x["field"], x["path"]))
        return clusters

    def generate_report(self, output_file: Optional[str] = None) -> str:
        lines: List[str] = ["# API スナップショット比較レポート", ""]

        if self.master_file:
            lines += [
                f"- **現在**: {Path(self.current_file).name}",
                f"- **マスター**: {Path(self.master_file).name}",
                "",
            ]
        else:
            lines += [
                f"- **スナップショット**: {Path(self.current_file).name}",
                "- **マスター**: なし (初回記録)",
                "",
            ]

        counts = {"SUMMARY": 0, "NEW": 0, "REMOVED": 0, "CHANGED": 0}
        for d in self.diffs:
            counts[d["type"]] = counts.get(d["type"], 0) + 1
        counts["CONTRACT_ERROR"] = len(self.contract_errors)

        sev_counts = {"breaking": 0, "compatible": 0, "informational": 0}
        for d in self.diffs:
            if d["type"] in ("NEW", "REMOVED", "CHANGED"):
                sev_counts[d.get("severity", "breaking")] += 1

        lines += ["## 統計", "| 項目 | 数 |", "|---|---:|"]
        for k in ("SUMMARY", "NEW", "REMOVED", "CHANGED", "CONTRACT_ERROR"):
            label = "APIエンドポイント数" if k == "SUMMARY" else k
            lines.append(f"| {label} | {counts[k]} |")
        if any(sev_counts.values()):
            lines += [
                "",
                "### 破壊性サマリー",
                "| severity | 件数 |",
                "|---|---:|",
                f"| 🔴 breaking | {sev_counts['breaking']} |",
                f"| 🟢 compatible | {sev_counts['compatible']} |",
                f"| ⚪ informational | {sev_counts['informational']} |",
            ]
        lines.append("")

        clusters = self.cluster_details()
        if clusters:
            lines += [
                "## 🔗 差分クラスタ（共通パターン集約）",
                "",
                "| severity | field | path | rule | 件数 | 代表 endpoint |",
                "|---|---|---|---|---:|---|",
            ]
            for c in clusters:
                sev_icon = {"breaking": "🔴", "compatible": "🟢", "informational": "⚪"}.get(c["severity"], "")
                sample = ", ".join(c["endpoints"][:3])
                if len(c["endpoints"]) > 3:
                    sample += f" (+{len(c['endpoints']) - 3})"
                lines.append(f"| {sev_icon} {c['severity']} | {c['field']} | `{c['path'] or '(root)'}` | {c['rule']} | {len(c['endpoints'])} | {sample} |")
            lines.append("")

        if counts["CHANGED"] > 0:
            lines.append("## 🔴 変更検出")
            for d in self.diffs:
                if d["type"] == "CHANGED":
                    lines += self._format_changed(d)
        if counts["NEW"] > 0:
            lines.append("## 🟡 新規エンドポイント")
            for d in self.diffs:
                if d["type"] == "NEW":
                    lines += self._format_entry(d)
        if counts["REMOVED"] > 0:
            lines.append("## 🔵 削除エンドポイント")
            for d in self.diffs:
                if d["type"] == "REMOVED":
                    lines += self._format_entry(d)
        if counts["SUMMARY"] > 0 and not self.master_file:
            lines.append("## 📋 スナップショット一覧")
            lines += ["", "| No | Key | HTTP |", "|---:|---|---:|"]
            for i, d in enumerate(self.diffs, 1):
                if d["type"] == "SUMMARY":
                    key_display = " / ".join(d["key"])
                    http_code = d["current"].get("http_code", "-")
                    lines.append(f"| {i} | {key_display} | {http_code} |")
        if self.contract_errors:
            lines.append("## ⚠ 契約エラー")
            lines += ["", "| Source | Index | Message |", "|---|---:|---|"]
            for e in self.contract_errors:
                lines.append(f"| {e['source']} | {e['index']} | {e['message']} |")

        lines.append("")
        report = "\n".join(lines)

        if output_file:
            Path(output_file).write_text(report, encoding="utf-8")
            print(f"Report saved: {output_file}", file=sys.stderr)
        return report

    def _key_header(self, entry: Dict[str, Any]) -> str:
        parts = []
        for k in self.rules.match_keys:
            v = entry.get(k)
            if v:
                parts.append(f"{k}={v}")
        return " ".join(parts) if parts else "(unknown)"

    def _format_changed(self, diff: Dict[str, Any]) -> List[str]:
        entry = diff["current"]
        sev = diff.get("severity", "breaking")
        sev_icon = {"breaking": "🔴", "compatible": "🟢", "informational": "⚪"}.get(sev, "")
        lines = ["", f"### {sev_icon} [{sev}] {self._key_header(entry)}"]
        suite = entry.get("suite")
        url = entry.get("url")
        if suite:
            lines.append(f"- **Suite**: {suite}")
        if url:
            lines.append(f"- **URL**: `{url}`")
        lines.append("")

        for change in diff["changes"]:
            field = change["field"]
            change_sev = change.get("severity", "breaking")
            change_icon = {"breaking": "🔴", "compatible": "🟢", "informational": "⚪"}.get(change_sev, "")
            title = {
                "http_code": "HTTP コード",
                "response_body": "レスポンスボディ",
                "type_signature": "型シグネチャ",
                "response_headers": "レスポンスヘッダ",
            }.get(field, field)
            lines.append(f"#### {change_icon} [{change_sev}] {title}")

            detail = change.get("detail") or []
            if detail:
                lines += ["", "| severity | path | rule | old → new |", "|---|---|---|---|"]
                for d in detail:
                    d_sev = d.get("severity", "breaking")
                    d_icon = {"breaking": "🔴", "compatible": "🟢", "informational": "⚪"}.get(d_sev, "")
                    old_s = "—" if d.get("old") is None else f"`{d['old']}`"
                    new_s = "—" if d.get("new") is None else f"`{d['new']}`"
                    lines.append(f"| {d_icon} {d_sev} | `{d.get('path') or '(root)'}` | {d.get('rule','')} | {old_s} → {new_s} |")
                lines.append("")

            if field == "http_code":
                lines += [
                    "```diff",
                    f"- {change['old']}",
                    f"+ {change['new']}",
                    "```",
                    "",
                ]
            elif field in ("response_body", "type_signature", "response_headers"):
                old_json = json.dumps(change["old"], ensure_ascii=False, indent=2, sort_keys=True)
                new_json = json.dumps(change["new"], ensure_ascii=False, indent=2, sort_keys=True)
                diff_lines = list(
                    difflib.unified_diff(
                        old_json.splitlines(keepends=True),
                        new_json.splitlines(keepends=True),
                        fromfile="Master",
                        tofile="Current",
                        lineterm="",
                    )
                )
                if diff_lines:
                    lines.append("```diff")
                    limit = self.rules.diff_max_lines
                    shown = diff_lines[:limit]
                    lines += [ln.rstrip("\n") for ln in shown]
                    if len(diff_lines) > limit:
                        lines.append(f"... ({len(diff_lines) - limit} 行省略)")
                    lines.append("```")
                lines.append("")
            else:
                lines += [
                    "```diff",
                    f"- {change['old']}",
                    f"+ {change['new']}",
                    "```",
                    "",
                ]
        return lines

    def _format_entry(self, diff: Dict[str, Any]) -> List[str]:
        entry = diff["current"] or diff["master"]
        lines = ["", f"### {self._key_header(entry)}"]
        suite = entry.get("suite")
        url = entry.get("url")
        http_code = entry.get("http_code", "-")
        if suite:
            lines.append(f"- **Suite**: {suite}")
        if url:
            lines.append(f"- **URL**: `{url}`")
        lines.append(f"- **HTTP**: {http_code}")
        body = entry.get("response_body")
        if body is not None:
            body_str = json.dumps(body, ensure_ascii=False, indent=2)[:500]
            lines += ["- **Preview**:", "```json", body_str, "```"]
        lines.append("")
        return lines


def load_rules(path: Optional[str]) -> RuleSet:
    if not path:
        return RuleSet(None)
    p = Path(path)
    if not p.exists():
        print(f"Warning: rules file not found: {path} (using defaults)", file=sys.stderr)
        return RuleSet(None)
    try:
        return RuleSet(json.loads(p.read_text(encoding="utf-8")))
    except Exception as e:
        print(f"Warning: rules load failed: {e} (using defaults)", file=sys.stderr)
        return RuleSet(None)


def main() -> None:
    parser = argparse.ArgumentParser(description="汎用 API スナップショット比較ツール")
    parser.add_argument("current", help="現在のスナップショット JSON")
    parser.add_argument("master", nargs="?", default=None, help="マスタースナップショット JSON (省略時はサマリーのみ)")
    parser.add_argument("--rules", default=None, help="正規化ルール JSON ファイル")
    parser.add_argument("--severity", default="informational",
                        choices=["informational", "compatible", "breaking"],
                        help="この severity 以上のみ失敗扱い (default: informational = 全 diff で失敗)")
    args = parser.parse_args()

    if not Path(args.current).exists():
        print(f"Error: current snapshot not found: {args.current}", file=sys.stderr)
        sys.exit(2)

    rules = load_rules(args.rules)
    comparator = SnapshotComparator(args.current, args.master, rules)
    comparator.compare()

    report_file = args.current.replace(".json", "-report.md")
    report = comparator.generate_report(report_file)
    print(report)

    failures = comparator.filtered_failures(args.severity)
    failure_count = len(failures) + len(comparator.contract_errors)
    if args.severity != "informational":
        print(f"[severity filter: {args.severity}+] failing diffs: {len(failures)}", file=sys.stderr)
    sys.exit(1 if failure_count > 0 else 0)


if __name__ == "__main__":
    main()
