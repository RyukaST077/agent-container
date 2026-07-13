# Normalizer Guide — 正規化ルールの設計指針

`normalizer_rules.json` は「毎回変わる値」をトークン化して比較器の偽陽性を減らすための仕組み。
だが、**広げすぎると偽陰性（本来検知すべき差分を見逃す）** が増える。
この文書は過剰マスクを避けるための指針をまとめる。

---

## 判断の原則: 「これは差分検知したい値か？」

正規化は**差分検知を諦める**宣言と同じ。各フィールドについて以下を問う:

| 質問 | Yes なら | No なら |
|---|---|---|
| 毎回の record で値が変わるか？ | 正規化候補 | 正規化不要 |
| 値が変わっても API 契約は壊れないか？ | 正規化して良い | **正規化してはいけない** |
| バージョンアップで値が変わったら気付きたいか？ | **正規化してはいけない** | 正規化して良い |

### 典型例

| フィールド | 判断 | 理由 |
|---|---|---|
| `id`, `user_id`, `area_id` | ✓ 正規化 | テスト実行ごとに変わる、値に業務意味なし |
| `created_at`, `updated_at` | ✓ 正規化 | タイムスタンプは毎回変わる |
| `uuid`, 認証トークン | ✓ 正規化 | ランダム生成 |
| `lang_code` (`ja`/`en`/`ko`) | ✗ **正規化禁止** | 値が業務ロジックを決定する |
| `currency_code` (`JPY`/`USD`) | ✗ **正規化禁止** | 通貨は契約の一部 |
| `transfer_code` | ✓ 正規化 | ランダム発行のワンタイムコード |
| `serial_code` | 文脈次第 | マスター値なら残す、発行値なら正規化 |
| `status`, `enabled` | ✗ **正規化禁止** | 業務状態 |
| `price_amount`, `price_amount_micros` | ✗ **正規化禁止** | 金額は契約の一部 |
| `purchaseTime` (epoch ms) | 文脈次第 | テストフィクスチャで固定できるなら残す |

---

## デフォルトルールの危険箇所

`scripts/normalizer_rules.json` の初期設定には**過剰マスクになりがちなルール**が含まれる。
新規プロジェクトに導入後、必ず見直す:

### 危険 1: `suffix "_code"` → `{{CODE}}`

```json
{"type": "suffix", "keys": ["_code"], "token": "{{CODE}}"}
```

- 潰すもの: `transfer_code`, `verification_code`, `serial_code` (発行されたもの) ← OK
- **潰してはいけないもの**: `lang_code`, `currency_code`, `country_code`, `category_code`, `error_code`

**推奨対応**: suffix ルールを削除し、`exact` リスト化する:

```json
{"type": "exact", "keys": ["transfer_code", "verification_code"], "token": "{{CODE}}"}
```

あるいは `lang_code` 等を「除外リスト」として扱うサポートが入るまでは、
`_code` suffix ルール自体を削除するのが最も安全。

### 危険 2: `value_rules` の `^\d{10,}$` → `{{NUMERIC_ID}}`

```json
{"regex": "^\\d{10,}$", "token": "{{NUMERIC_ID}}"}
```

- 潰すもの: ユーザー ID の連番 12 桁 ← OK
- **潰してはいけないもの**: epoch ミリ秒 (`purchaseTime: 1700000000000`)、金額 (`price_amount_micros`)

**推奨対応**: このルールは残してよいが、以下のフィールドが存在するなら key 指定で除外する:

```json
{"type": "exact", "keys": ["purchasetime", "price_amount_micros"], "token": null}
```

(※ 現在の実装では `token: null` で除外する仕様ではない。必要なら比較器側を拡張する
か、事前に該当フィールドをフィクスチャで固定値にしておくこと)

### 危険 3: `contains "image" / "thumbnail"` → `{{URL}}`

```json
{"type": "contains", "keys": ["image","thumbnail","avatar","icon"], "value_regex": "^https?://", "token": "{{URL}}"}
```

URL がドメイン丸ごと変わる想定ならよいが、`/` 以下のパスが契約の一部なら
`{{URL}}` で全部潰れると「404 画像パスに差し替わった」ことを検知できない。

**推奨対応**: CDN ホストだけを正規化し、path は残す工夫。
もしくは key 指定で外す。ケースバイケース。

---

## プロジェクト固有ルールの追加手順

1. **最初は触らない**。デフォルトで record してみる
2. 比較で差分が出続ける値を特定する (`snapshot.sh compare` の diff を読む)
3. 「この値は差分検知対象か？」を上記原則で判断
4. 差分検知対象でないなら `normalizer_rules.json` に最小限のルールを追加
5. 逆に、差分検知すべき値が潰されていたら既存ルールを剥がす

### 正規化追加の粒度指針

| 粒度 | 使うとき | 例 |
|---|---|---|
| `exact` | 特定フィールド1つを潰す | `["transfer_code"]` |
| `contains` | 命名規則ベース (url/link 等) | `["url","link"]` |
| `suffix` | 末尾が共通する場合 | `["_at"]` (timestamp) |
| `prefix` | 先頭が共通する場合 | `["tmp_"]` |
| `regex` (value_rules) | 値パターン全体が揃っているもの | UUID, タイムスタンプ |

**優先度**: `exact` > `prefix`/`suffix` > `contains` > `regex`。
広い粒度ほど誤爆が多くなるので、exact から始めて必要なときだけ広げる。

---

## 過剰マスクの検出方法

正規化が効きすぎているかを確認する 3 つの手段:

### 手段 1: 正規化済みマスターを目視

```bash
python3 -c "
import json
from tools.snapshot.snapshot_comparator import RuleSet, SnapshotComparator
rules = RuleSet(json.load(open('tools/snapshot/normalizer_rules.json')))
sc = SnapshotComparator('snapshots/snapshot-master.json', None, rules)
for e in sc.current[:5]:
    print(json.dumps(sc._normalize_body(e), indent=2, ensure_ascii=False))
"
```

`{{CODE}}` や `{{NUMERIC_ID}}` が想定以上に出ていたら過剰マスク。

### 手段 2: 意図的に破壊して比較

`lang_code` が潰されていないか確認するには、API のレスポンスで `lang_code` を
別の値に変えて `snapshot.sh compare` が差分として検知するか確認する。
差分が出ない = 正規化されている = 危険。

### 手段 3: coverage_report とのクロスチェック

`coverage_report.py --format json` でマスターのステータス分布を出し、
**同一エンドポイントの異なる suite (normal vs auth) で body が同一**になっていたら
そのエンドポイントは正規化しすぎている可能性がある。

---

## ヘッダ比較の有効化

デフォルトでは `compare_fields` に `response_headers` が含まれていないため、
**`Content-Type` が `application/json` → `text/html` に化けても検知できない**。

### 有効化手順

`tools/snapshot/normalizer_rules.json` を以下のように編集:

```json
{
  "compare_fields": ["http_code", "response_body", "response_headers"],
  "compare_headers": ["content-type", "cache-control"],
  ...
}
```

### 推奨する比較対象ヘッダ

| ヘッダ | 比較すべきか | 理由 |
|---|---|---|
| `content-type` | ✓ 必須 | 誤って HTML が返ったら絶対に気付きたい |
| `cache-control` | ✓ 推奨 | キャッシュ戦略は契約の一部 |
| `content-encoding` | 任意 | gzip/br が外れたら性能に影響 |
| `x-ratelimit-*` | ✗ | 動的に変動する値、正規化しても無意味 |
| `date`, `expires` | ✗ | 毎回変わる、デフォルトで `{{HEADER_VOLATILE}}` に正規化済み |
| `set-cookie` | ✗ | セッション固有、デフォルトで正規化済み |
| `x-request-id`, `x-trace-id` | ✗ | デフォルトで `{{TRACE_ID}}` に正規化済み |

---

## URL ホスト名の正規化

キャプチャ時に URL がフルで入る (`http://172.20.0.8:8082/v1/languages` 等)。
CI とローカルでホストが違う場合はノイズになるので正規化対象にする。

`normalizer_rules.json` の `value_rules` に以下を追加:

```json
{"regex": "^https?://[^/]+", "token": "{{BASE_URL}}"}
```

ただし body 内の `url` フィールドも巻き込むので、既存の URL ルールと衝突しないか
目視確認すること。

---

## ルール変更時のワークフロー

正規化ルールを変更したら、必ず以下を実行:

1. `snapshot.sh record` で新しいキャプチャを取る
2. `snapshot.sh compare` で旧マスターとの差分を確認
   - 意図どおり「今まで差分が出ていた値が正規化されて消えた」か
   - 逆に「今まで正規化で消えていた差分が出るようになった」か
3. ルール変更自体をレビュー対象として `snapshot-master.json` と `normalizer_rules.json` を
   同じ PR でコミット

**正規化ルールの変更はマスターの変更と同じくらい慎重に**。
差分検知能力を左右する最重要設定ファイル。
