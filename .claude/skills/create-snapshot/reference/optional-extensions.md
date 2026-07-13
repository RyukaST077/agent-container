# プロジェクト特性別オプション拡張指示書

基本テンプレ（[README.md](./README.md) §1〜10）は「どのプロジェクトでも価値がある機能」だけを組み込み済みです。本書は、**プロジェクトの性格によって要否が明確に割れる** 拡張を、将来プロジェクトで実装する前提の **設計指示書** としてまとめたものです。

症状が出てから / 必要になってから導入する方針です。最初から全部は入れません。

---

## 0. 導入判断

| 拡張 | 導入トリガ | 不要になるケース |
|---|---|---|
| [A. JSON Schema スナップショット](#a-json-schema-スナップショット) | 暗黙契約を顕在化したい / 型シグネチャでは粒度不足 | OpenAPI / GraphQL Schema を書いている |
| [C. エンドポイント横断の不変条件](#c-エンドポイント横断の不変条件) | リレーショナルドメイン、横断整合性の事故履歴 | エンドポイント独立性が高い |
| [E. プロダクショントラフィック replay](#e-プロダクショントラフィック-replay) | QA と本番の挙動乖離で事故った | アクセスログ基盤 / PII マスカー未整備 |
| [F. Property-Based / Fuzzing 連携](#f-property-based--fuzzing-連携) | バリデーションバグ頻発 / 境界値の書き漏れ | schemathesis 等の導入が組織的に無理 |
| [G. ミューテーションテスト](#g-ミューテーションテスト-テストのテスト) | テスト自体の信頼性を数値化したい成熟期 | プロジェクト初期・中期 |

これを超える領域（負荷・並行性・脆弱性・業務仕様の正しさ）は snapshot 方式では原理的に届かないので、README §12 の通り別ツールに委譲してください。

---

## A. JSON Schema スナップショット

### 目的
型シグネチャ（README §10.1）より詳細な契約—`required` / `optional`、`enum`、`minLength`、`maxItems`、`format`—を固定化し、**契約破壊的変更だけ** を抽出できるようにする。

### データモデル
- **ファイル**: `snapshots/schema-master.json`（基本 snapshot とは別管理）
- **構造**: `{ <match_key>: <JSON Schema> }`
- **生成**: capture 時に実レスポンスから schema を推論（`genson` ライブラリ、または独自の軽量推論器）

例:
```json
{
  "users.show|GET": {
    "type": "object",
    "required": ["id", "name"],
    "properties": {
      "id":         {"type": "integer"},
      "name":       {"type": "string", "minLength": 1},
      "role":       {"type": "string", "enum": ["admin", "user"]},
      "created_at": {"type": "string", "format": "date-time"}
    }
  }
}
```

### 比較ロジック
新しい比較器 `schema_comparator.py` を追加し、schema diff を **破壊性分類** で出力:

| 種別 | 例 |
|---|---|
| `SCHEMA_BREAKING` | required 削除 / 型変化 / enum 縮小 / format 厳格化 / maxLength 縮小 / 新規 required 追加 |
| `SCHEMA_COMPATIBLE` | optional 追加 / enum 拡張 / format 緩和 / nullable 化 |

既存の severity 分類機構（README §10.2）をそのまま流用可能。

### 実装手順
1. `capture.sh` で各レスポンスから schema を推論し、`$SNAPSHOT_SCHEMA_FILE` に JSONL で追記
2. `snapshot.sh` に新アクション `schema-record` / `schema-test` / `schema-approve` を追加
3. `schema_comparator.py` を新規作成（既存の `snapshot_comparator.py` とは独立）
4. `test` アクションは既存 snapshot 比較 + schema 比較を両方走らせ、`SCHEMA_BREAKING` があれば fail
5. `normalizer_rules.json` の `severity_overrides` を拡張してプロジェクト固有の破壊性定義を上書き可能にする

### OpenAPI を持っているなら
`schemathesis` や `openapi-diff` で代替可能。本機能は **スキーマを持っていない / 書く文化がない** プロジェクトに向けた軽量代替です。

---

## C. エンドポイント横断の不変条件

### 目的
**複数のエンドポイントをまたぐ整合性** を検証する。例: 「POST /users で返った `id` が直後の GET /users/{id} で取得できる」。README §10.6 で残る限界として挙げた **トークン相関消失の一部** をカバーできる。

### 定義ファイル
`invariants.yml` にプロジェクト固有の不変条件を記述:

```yaml
- name: created_user_is_retrievable
  description: POST /users で作成したユーザーが直後の GET /users/{id} で取れる
  chain:
    - capture_from:
        endpoint: users.create
        method: POST
        extract: {user_id: "data.id", user_name: "data.name"}
    - verify_at:
        endpoint: users.show
        method: GET
        path: "data.id"
        equals: "$user_id"
    - verify_at:
        endpoint: users.show
        path: "data.name"
        equals: "$user_name"

- name: list_contains_created
  chain:
    - capture_from: {endpoint: users.create, extract: {user_id: "data.id"}}
    - verify_at:
        endpoint: users.list
        contains_in: "data[].id"
        value: "$user_id"
```

### 実装
1. `invariant_checker.py` を追加: snapshot JSON + invariants.yml を読んで各ルールを評価
2. JSONPath サブセット（`data.id`、`data[].id`、`data[0].id`）を解釈するヘルパを実装
3. `$var_name` で前段 `extract` の値を参照、未定義参照は契約エラー扱い
4. `snapshot.sh invariant` アクションで独立実行、`test` アクションの末尾でも自動実行
5. 破綻時はどのチェーンのどのステップで失敗したかをレポート出力

### 前提条件
- `capture.sh` の呼び出し順序が固定されていて、同じテストスイート内で作成→参照が必ず連鎖する
- `suite` フィールドで論理的なシナリオを分ける

---

## E. プロダクショントラフィック replay

### 目的
`capture.sh` を人間が書く限界—**想像力の網**—を超え、**本番で実際に呼ばれている入力パターン** でカバレッジを担保する。

### 前提
- 本番 API サーバのアクセスログが構造化（JSONL 等）で `(method, path, query, request_body, response_code)` を記録している
- PII（個人情報・認証トークン・実名 ID）を除去する **マスカー** が存在する、もしくは同等のデータ匿名化レイヤーがある
- テスト環境に本番相当のマスク済みフィクスチャをロードできる

### 実装
1. `replay_capture.sh` を追加:
   ```bash
   # 入力: ログから抽出した {method, path, query, body, expected_code} の JSONL
   # 出力: 標準の capture 形式 ($SNAPSHOT_CAPTURE_FILE に追記)
   cat "$REPLAY_INPUT" | while read -r line; do
     method=$(echo "$line" | jq -r .method)
     path_template=$(echo "$line" | jq -r .path_template)  # /users/{id}
     # ... 実行
   done
   ```
2. 本番パスは URL テンプレート化（`/users/123` → `/users/{id}`）して endpoint マッチング
3. `normalizer_rules.json` に `replay` セクションを追加してマスクルール定義
4. `snapshot.sh replay-record` / `replay-test` アクション追加

### 運用
- 本番トラフィックの代表的な 1 時間分をサンプリング → 匿名化 → `replay_inputs/YYYYMMDD.jsonl` として版管理
- 月次でサンプリングを更新
- replay 用の master は基本 snapshot とは別管理（`snapshots/replay-master.json`）

### 限界
- テスト環境のデータ状態と本番 DB は完全一致しないため、**値レベルの完全一致は諦めて型/構造レベルの一致** で妥協する（= A の schema 比較と相性が良い）
- PII 漏洩リスクがゼロではないので、マスク精度の検証プロセスが別途必要

---

## F. Property-Based / Fuzzing 連携

### 目的
入力バリエーションの網羅性を `capture.sh` の手書きから **自動生成** に切り替える。

### アプローチ
- 各 endpoint のスキーマ（A で生成した JSON Schema、もしくは OpenAPI）から **ランダム入力を生成**
- 期待するのは「値の一致」ではなく「**クラッシュしない** / **レスポンスがスキーマを満たす**」こと
- **スナップショット化するのは "失敗パターン"**（= リグレッションテストとして固定化する）

### 既存ツールとの連携
| ツール | 言語 | 連携方法 |
|---|---|---|
| schemathesis | Python | OpenAPI を食わせて自動ファジング。fail ケースを JSONL で export |
| hypothesis | Python | 独自 strategy で入力生成。assertion failure を snapshot 化 |
| fast-check | TypeScript | 同上 |

### データ
- `snapshots/fuzz-master.json` に **既知の失敗ケース** を固定化:
  ```json
  [
    {"endpoint": "users.show", "method": "GET", "input": {"id": ""}, "http_code": "500", "error": "Division by zero"},
    {"endpoint": "users.create", "method": "POST", "input": {"email": "a@b"}, "http_code": "422", "error": "Invalid email"}
  ]
  ```
- 「前回の fuzzing では入力 X で 500 が出た」を固定 → 修正が入ったら消す運用

### 実装
1. `snapshot.sh fuzz-record` / `fuzz-test` アクション追加
2. schemathesis を wrap する `fuzz_runner.sh` を用意（ツール依存はここに閉じる）
3. 実行結果のうち「期待と違う挙動」（5xx / schema 違反 / タイムアウト）を JSONL で emit

---

## G. ミューテーションテスト (テストのテスト)

### 目的
スナップショット自身が機能しているか—**実装にバグが入ったら本当に検知できるか**—を検証する。**テストの信頼性を数値化** する。

### アプローチ
1. プロジェクトに既知のバグパターンを一時注入:
   - ID を hardcoding（always return 1）
   - null 混入（random field → null）
   - 配列の空化
   - 型退化（int → str）
   - 条件反転（`if x` → `if not x`）
2. スナップショットテストを走らせ、**全 mutation で必ず fail することを確認**
3. pass してしまう mutation があれば「そのケースを snapshot が守れていない」 → `capture.sh` を改善

### 既存ツール
| ツール | 対象言語 |
|---|---|
| Stryker | JS/TS、.NET、Scala |
| Infection | PHP |
| mutmut | Python |
| PIT | Java |

### snapshot テンプレとの統合
1. `snapshot.sh mutation-test` アクションで上記ツールを wrap 実行
2. 検知率 = `killed_mutants / total_mutants` を算出
3. `snapshots/mutation-score-master.json` に前回の検知率を記録し、下がったら fail
4. レポートに「検知できなかった mutation 一覧」と「それを検知するには capture に何を足すべきか」のヒントを出す

### 導入タイミング
他のすべての拡張が入った後の最終段階。初期・中期には不要。

---

## 実装時の共通ルール

本書の拡張を実装するときの設計規約:

1. **基本テンプレを壊さない**: 既存の `snapshot.sh test` / `record` / `approve` / `history` の挙動は不変に保つ。拡張はすべて新アクション or オプションで追加
2. **設定はすべて `normalizer_rules.json` に集約**: 新しい JSON ファイルを増やすのは最終手段。`schema_master.json` や `invariants.yml` のような拡張固有データファイルは許容
3. **拡張ごとに独立スクリプト**: `schema_comparator.py` / `invariant_checker.py` のように機能を分ける。`snapshot_comparator.py` を肥大化させない
4. **オプトイン**: すべての拡張はデフォルト OFF。設定 or 専用アクションを叩いて初めて有効化される
5. **ドキュメントと実装を同時更新**: 本書のセクションと実装を必ずペアで PR する
6. **severity 対応**: 拡張が検出する差分にも `breaking` / `compatible` / `informational` を付与する。既存の `--severity` フィルタと自然に接続できるようにする
