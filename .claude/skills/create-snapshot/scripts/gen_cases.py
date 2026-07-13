#!/usr/bin/env python3
"""
テストケース雛形ジェネレータ

OpenAPI/Swagger から `capture.sh` に貼り付けられる call_* 行の雛形を生成する。
生成されたものはあくまで「案」で、人間が精査して採用する前提。
ゼロから書くより 3〜5倍速く異常系・境界値を網羅できる。

Usage:
  python3 gen_cases.py --spec swagger.yaml --endpoint /users/register --method POST
  python3 gen_cases.py --spec swagger.yaml --all                           # 全部出す
  python3 gen_cases.py --spec swagger.yaml --path-filter users             # パスフィルタ

出力例:
  # ---- normal ----
  call_json normal users.register POST "/v1/users/register" \\
    '{"nick_name":"snap","address_status":0,"gender":0,"birth_year":1990}' \\
    "${COMMON_HEADERS_IOS[@]}"

  # ---- auth ----
  call_unauth_no_key users.register POST "/v1/users/register" \\
    -H "x-os-type: ios" -H "x-app-version: 3.3.0"

  # ---- validation ----
  call_invalid_body users.register missing_nick_name POST "/v1/users/register" \\
    '{"address_status":0,"gender":0,"birth_year":1990}' \\
    "${COMMON_HEADERS_IOS[@]}"

  # ---- boundary ----
  call_boundary users.register nick_name_max POST "/v1/users/register" \\
    '{"nick_name":"aaaaaaaaaaaaaaaaaaaa",...}' \\
    "${COMMON_HEADERS_IOS[@]}"

依存: Python 3.8+、YAML 仕様なら PyYAML
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple


HTTP_METHODS = ["get", "post", "put", "patch", "delete"]


def load_spec(path: str) -> Dict[str, Any]:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"spec not found: {path}")
    text = p.read_text(encoding="utf-8")
    if path.endswith((".yaml", ".yml")):
        try:
            import yaml  # type: ignore
        except ImportError:
            raise ImportError("YAML には PyYAML が必要: pip install pyyaml")
        return yaml.safe_load(text)
    return json.loads(text)


def resolve_ref(spec: Dict[str, Any], ref: str) -> Dict[str, Any]:
    """$ref を辿る。#/components/schemas/Foo 等"""
    if not ref.startswith("#/"):
        return {}
    parts = ref[2:].split("/")
    cur: Any = spec
    for p in parts:
        if isinstance(cur, dict) and p in cur:
            cur = cur[p]
        else:
            return {}
    return cur if isinstance(cur, dict) else {}


def get_request_schema(spec: Dict[str, Any], op: Dict[str, Any]) -> Dict[str, Any]:
    """
    OpenAPI 3.x の requestBody.content.application/json.schema を取得。
    Swagger 2.x の parameters[in=body].schema もサポート。
    """
    # OpenAPI 3
    rb = op.get("requestBody") or {}
    if "$ref" in rb:
        rb = resolve_ref(spec, rb["$ref"])
    content = rb.get("content") or {}
    for ct in ("application/json", "application/x-www-form-urlencoded", "*/*"):
        if ct in content:
            s = content[ct].get("schema") or {}
            if "$ref" in s:
                s = resolve_ref(spec, s["$ref"])
            return s
    # Swagger 2
    for p in op.get("parameters") or []:
        if p.get("in") == "body":
            s = p.get("schema") or {}
            if "$ref" in s:
                s = resolve_ref(spec, s["$ref"])
            return s
    return {}


def get_path_parameters(spec: Dict[str, Any], op: Dict[str, Any], path_item: Dict[str, Any]) -> List[Dict[str, Any]]:
    """path / query パラメータを取得 (operation レベルと path レベルをマージ)"""
    params = []
    for src in (path_item.get("parameters") or [], op.get("parameters") or []):
        for p in src:
            if "$ref" in p:
                p = resolve_ref(spec, p["$ref"])
            params.append(p)
    return params


def dummy_value_for(schema: Dict[str, Any], field_name: str = "") -> Any:
    """スキーマから妥当性のあるダミー値を生成"""
    t = schema.get("type")
    enum = schema.get("enum")
    if enum:
        return enum[0]
    fmt = schema.get("format")
    if t == "integer" or t == "number":
        mn = schema.get("minimum")
        mx = schema.get("maximum")
        if mn is not None and mx is not None:
            return mn
        if mn is not None:
            return mn
        return 1
    if t == "boolean":
        return True
    if t == "array":
        item_schema = schema.get("items") or {}
        return [dummy_value_for(item_schema, field_name)]
    if t == "object":
        props = schema.get("properties") or {}
        return {k: dummy_value_for(v, k) for k, v in props.items()}
    # string / unknown
    if fmt == "date":
        return "2026-01-01"
    if fmt == "date-time":
        return "2026-01-01T00:00:00Z"
    if fmt == "email":
        return "snap@example.test"
    if fmt == "uuid":
        return "00000000-0000-0000-0000-000000000000"
    if "nick_name" in field_name.lower() or "name" in field_name.lower():
        return "snap"
    if "code" in field_name.lower():
        return "JPY"
    if "id" in field_name.lower():
        return "id-1"
    return "snap"


def build_normal_body(schema: Dict[str, Any]) -> Dict[str, Any]:
    props = schema.get("properties") or {}
    required = set(schema.get("required") or [])
    body = {}
    for name, sub in props.items():
        # 必須 or デフォルト例があるフィールドだけ入れる
        if name in required or "example" in sub or "default" in sub:
            body[name] = sub.get("example", sub.get("default", dummy_value_for(sub, name)))
    # 必須が空でもプロパティあれば最低2つ埋める
    if not body:
        for i, (name, sub) in enumerate(props.items()):
            if i >= 2:
                break
            body[name] = dummy_value_for(sub, name)
    return body


def build_missing_field_bodies(schema: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
    """必須フィールドを1つずつ欠落させたボディのリスト"""
    base = build_normal_body(schema)
    required = list((schema.get("required") or []))
    out = []
    for field in required:
        copy = {k: v for k, v in base.items() if k != field}
        out.append((f"missing_{field}", copy))
    return out


def build_bad_type_bodies(schema: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
    """整数フィールドに文字列を入れる等の型違反ボディ"""
    base = build_normal_body(schema)
    props = schema.get("properties") or {}
    out = []
    for name, sub in props.items():
        if name not in base:
            continue
        t = sub.get("type")
        if t == "integer" or t == "number":
            copy = dict(base)
            copy[name] = "not-a-number"
            out.append((f"bad_{name}_type", copy))
        elif t == "boolean":
            copy = dict(base)
            copy[name] = "not-a-bool"
            out.append((f"bad_{name}_type", copy))
    return out


def build_enum_out_bodies(schema: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
    """enum の範囲外の値を入れたボディ"""
    base = build_normal_body(schema)
    props = schema.get("properties") or {}
    out = []
    for name, sub in props.items():
        if name not in base:
            continue
        enum = sub.get("enum")
        if enum:
            t = sub.get("type")
            # 範囲外の値 (数値なら max+1、文字列なら "__invalid__")
            if t in ("integer", "number"):
                try:
                    bad = max(int(x) for x in enum) + 1
                except Exception:
                    bad = 9999
            else:
                bad = "__invalid__"
            copy = dict(base)
            copy[name] = bad
            out.append((f"bad_{name}_enum", copy))
    return out


def build_boundary_bodies(schema: Dict[str, Any]) -> List[Tuple[str, Dict[str, Any]]]:
    """文字列長 / 数値レンジの境界値ボディ"""
    base = build_normal_body(schema)
    props = schema.get("properties") or {}
    out: List[Tuple[str, Dict[str, Any]]] = []
    for name, sub in props.items():
        t = sub.get("type")
        if t == "string":
            mx = sub.get("maxLength")
            mn = sub.get("minLength")
            if mx is not None:
                b = dict(base)
                b[name] = "a" * mx
                out.append((f"{name}_max", b))
                b = dict(base)
                b[name] = "a" * (mx + 1)
                out.append((f"{name}_over_max", b))
            if mn is not None and mn > 0:
                b = dict(base)
                b[name] = "a" * max(mn - 1, 0)
                out.append((f"{name}_under_min", b))
        elif t in ("integer", "number"):
            mn = sub.get("minimum")
            mx = sub.get("maximum")
            if mn is not None:
                b = dict(base)
                b[name] = mn
                out.append((f"{name}_min", b))
                b = dict(base)
                b[name] = mn - 1
                out.append((f"{name}_under_min", b))
            if mx is not None:
                b = dict(base)
                b[name] = mx
                out.append((f"{name}_max", b))
                b = dict(base)
                b[name] = mx + 1
                out.append((f"{name}_over_max", b))
    # 常に 1〜2 本はマルチバイト境界を追加 (string フィールドがあれば)
    for name, sub in props.items():
        if sub.get("type") == "string":
            b = dict(base)
            b[name] = "テスト🔥"
            out.append((f"{name}_multibyte", b))
            break
    return out


def endpoint_logical_name(path: str) -> str:
    """/v1/users/{id}/history → users.history 風の論理名"""
    parts = [p for p in path.strip("/").split("/") if p and not p.startswith("{")]
    # v1/v2 のようなバージョンプレフィックスは捨てる
    if parts and re.fullmatch(r"v\d+", parts[0]):
        parts = parts[1:]
    return ".".join(parts) or "root"


def fmt_bash_json(body: Any) -> str:
    """JSON をシングルクォートで囲める形にエスケープして返す"""
    s = json.dumps(body, ensure_ascii=False)
    # bash のシングルクォート内に ' が出てくるのを避ける
    # 出てきたら \''\''\' 形式で閉じ直す
    if "'" in s:
        s = s.replace("'", "'\\''")
    return f"'{s}'"


def gen_for_operation(
    spec: Dict[str, Any],
    path: str,
    method: str,
    op: Dict[str, Any],
    path_item: Dict[str, Any],
    base_url_prefix: str = "",
    header_var: str = "COMMON_HEADERS_IOS",
    min_header_var: str = "",
) -> List[str]:
    """path + method の雛形を生成。返り値は行のリスト (bash)"""
    method_u = method.upper()
    logical = endpoint_logical_name(path)
    full_path = base_url_prefix + path

    params = get_path_parameters(spec, op, path_item)
    path_params = [p for p in params if p.get("in") == "path"]
    query_params = [p for p in params if p.get("in") == "query"]

    # path パラメータを fixture に置換
    sample_path = full_path
    for p in path_params:
        name = p.get("name", "")
        var = f"${{FIXTURE_{name.upper()}}}"
        sample_path = sample_path.replace("{" + name + "}", var)

    # query 文字列
    q_parts = []
    for p in query_params:
        name = p.get("name", "")
        schema = p.get("schema") or p  # openapi 3 / swagger 2
        if p.get("required"):
            q_parts.append(f"{name}={dummy_value_for(schema, name)}")
    q_str = ("?" + "&".join(q_parts)) if q_parts else ""
    sample_url = sample_path + q_str

    lines: List[str] = []
    lines.append(f"# ================================================================")
    lines.append(f"# {method_u} {path}   (logical endpoint: {logical})")
    lines.append(f"# ================================================================")

    has_body = method_u in ("POST", "PUT", "PATCH")
    schema = get_request_schema(spec, op) if has_body else {}

    # ---- normal ----
    lines.append("# ---- normal ----")
    if has_body and schema:
        body = build_normal_body(schema)
        lines.append(
            f'call_json normal {logical} {method_u} "{sample_url}" \\\n'
            f'  {fmt_bash_json(body)} \\\n'
            f'  "${{{header_var}[@]}}"'
        )
    else:
        lines.append(f'call normal {logical} {method_u} "{sample_url}" "${{{header_var}[@]}}"')
    lines.append("")

    # ---- auth ----
    lines.append("# ---- auth ----")
    # no_api_key / bad_api_key — call 時に x-api-key は渡さない
    min_headers = ' -H "x-os-type: ios" -H "x-app-version: 3.3.0"'
    if has_body:
        lines.append(
            f'# ※ 認可テストもボディ必須の場合は手動で call_json の "auth" suite 版を書く'
        )
        lines.append(
            f'call_unauth_no_key {logical} {method_u} "{sample_url}"{min_headers}'
        )
        lines.append(
            f'call_unauth_bad_key {logical} {method_u} "{sample_url}"{min_headers}'
        )
    else:
        lines.append(f'call_unauth_no_key {logical} {method_u} "{sample_url}"{min_headers}')
        lines.append(f'call_unauth_bad_key {logical} {method_u} "{sample_url}"{min_headers}')
    lines.append("")

    # ---- validation (has body 限定) ----
    if has_body and schema:
        lines.append("# ---- validation ----")
        for case_name, body in build_missing_field_bodies(schema)[:5]:
            lines.append(
                f'call_invalid_body {logical} {case_name} {method_u} "{sample_url}" \\\n'
                f'  {fmt_bash_json(body)} \\\n'
                f'  "${{{header_var}[@]}}"'
            )
        for case_name, body in build_bad_type_bodies(schema)[:3]:
            lines.append(
                f'call_invalid_body {logical} {case_name} {method_u} "{sample_url}" \\\n'
                f'  {fmt_bash_json(body)} \\\n'
                f'  "${{{header_var}[@]}}"'
            )
        for case_name, body in build_enum_out_bodies(schema)[:3]:
            lines.append(
                f'call_invalid_body {logical} {case_name} {method_u} "{sample_url}" \\\n'
                f'  {fmt_bash_json(body)} \\\n'
                f'  "${{{header_var}[@]}}"'
            )
        lines.append("")

    # ---- validation (GET: 必須 query の欠落) ----
    required_queries = [p for p in query_params if p.get("required")]
    if not has_body and required_queries:
        lines.append("# ---- validation ----")
        for p in required_queries[:3]:
            name = p.get("name", "")
            # name のみ欠落させた URL を作る
            stripped = "&".join(
                f"{q.get('name')}={dummy_value_for(q.get('schema') or q, q.get('name',''))}"
                for q in required_queries
                if q.get("name") != name
            )
            url_no_q = sample_path + (("?" + stripped) if stripped else "")
            lines.append(
                f'call_invalid_query {logical} missing_{name} {method_u} "{url_no_q}" "${{{header_var}[@]}}"'
            )
        lines.append("")

    # ---- boundary ----
    if has_body and schema:
        bseqs = build_boundary_bodies(schema)[:6]
        if bseqs:
            lines.append("# ---- boundary ----")
            for case_name, body in bseqs:
                lines.append(
                    f'call_boundary {logical} {case_name} {method_u} "{sample_url}" \\\n'
                    f'  {fmt_bash_json(body)} \\\n'
                    f'  "${{{header_var}[@]}}"'
                )
            lines.append("")
    else:
        # GET の場合: 存在しない ID / 多言語 / 件数ゼロ
        lines.append("# ---- boundary ----")
        if path_params:
            first = path_params[0].get("name", "id")
            not_found_path = full_path
            for p in path_params:
                name = p.get("name", "")
                not_found_path = not_found_path.replace("{" + name + "}", "id-9999")
            lines.append(
                f'call_boundary_query {logical} not_found {method_u} '
                f'"{not_found_path}{q_str}" "${{{header_var}[@]}}"'
            )
        lang_params = [p for p in query_params if p.get("name") == "langCode"]
        if lang_params:
            for lang in ("en", "ko", "zh"):
                url_lang = sample_path + "?" + "&".join(
                    f"{q.get('name')}={lang if q.get('name')=='langCode' else dummy_value_for(q.get('schema') or q, q.get('name',''))}"
                    for q in query_params if q.get("required") or q.get("name") == "langCode"
                )
                lines.append(
                    f'call_boundary_query {logical} lang_{lang} {method_u} "{url_lang}" "${{{header_var}[@]}}"'
                )
        lines.append("")

    return lines


def iter_operations(spec: Dict[str, Any]):
    for path_str, path_item in (spec.get("paths") or {}).items():
        if not isinstance(path_item, dict):
            continue
        for method, op in path_item.items():
            if method.lower() not in HTTP_METHODS:
                continue
            if not isinstance(op, dict):
                continue
            yield path_str, method.lower(), op, path_item


def main() -> int:
    ap = argparse.ArgumentParser(description="テストケース雛形ジェネレータ")
    ap.add_argument("--spec", required=True, help="OpenAPI/Swagger YAML or JSON")
    ap.add_argument("--endpoint", help="対象 path (例: /users/register)")
    ap.add_argument("--method", help="対象 method (GET/POST...)。省略時は全 method")
    ap.add_argument("--all", action="store_true", help="全 endpoint について生成")
    ap.add_argument("--path-filter", help="path に含む文字列でフィルタ")
    ap.add_argument("--base-url-prefix", default="", help="spec path の前に付けるプレフィックス (/v1 等)")
    ap.add_argument("--header-var", default="COMMON_HEADERS_IOS",
                    help="call 時に使うヘッダ配列の変数名")
    ap.add_argument("--output", help="出力ファイル (省略時は stdout)")
    args = ap.parse_args()

    if not (args.all or args.endpoint or args.path_filter):
        print("--all / --endpoint / --path-filter のいずれかを指定してください", file=sys.stderr)
        return 2

    try:
        spec = load_spec(args.spec)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2

    lines: List[str] = [
        "#!/usr/bin/env bash",
        "# 自動生成されたテストケース雛形 (gen_cases.py)",
        "# このまま使わず、各ケースをプロジェクトに合わせて精査・編集すること。",
        "# - FIXTURE_* は reset-db.sh / fixture.env で用意する",
        "# - 不要なケースは削除、必要なら追加する",
        "# - call 順序は normal → auth → validation → boundary → destructive",
        "",
    ]

    count = 0
    for path_str, method, op, path_item in iter_operations(spec):
        if args.endpoint and args.endpoint != path_str:
            continue
        if args.method and args.method.upper() != method.upper():
            continue
        if args.path_filter and args.path_filter not in path_str:
            continue
        lines.extend(gen_for_operation(
            spec, path_str, method, op, path_item,
            base_url_prefix=args.base_url_prefix,
            header_var=args.header_var,
        ))
        count += 1

    if count == 0:
        print("該当するエンドポイントがありません", file=sys.stderr)
        return 1

    text = "\n".join(lines) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"Wrote {count} operations to {args.output}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
