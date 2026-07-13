# Test Case Matrix — 異常値・境界値を含むテストケース設計

`capture.sh` に並べるテストケースを**エンドポイント型ごとの観点表**として定義する。
「何を書けばいいか分からない」状態を構造的に解消するためのチェックリスト。

---

## なぜこの表が必要か

スナップショットテストは **正常系だけ並べても 30% しか仕事をしない**。
PHP / Rails / Django のバージョンアップで壊れるのは、むしろ以下のような経路:

- バリデーション実装の微妙な挙動差（型キャスト、空文字の扱い）
- 認証ミドルウェアのヘッダ欠落時の挙動
- 境界値での丸め・オーバーフロー
- エラーレスポンスの body 構造
- 多言語 / locale / タイムゾーンでの分岐

**正常系と異常系と境界値の3レイヤーを面で押さえる** のが本テストの目標。
この表はそのための網羅チェックリスト。

---

## 全体観: 4 レイヤーでテストを書く

1. **正常系** (suite: `normal`) — 期待する入力で 2xx が返ることを固定化
2. **認可** (suite: `auth`) — ヘッダ欠落・不正ヘッダ・他人リソースで 401/403 を固定化
3. **バリデーション** (suite: `validation`) — 必須欠落・型違反・enum 外・フォーマット違反で 400/422 を固定化
4. **境界値** (suite: `boundary`) — min-1 / min / max / max+1、空・大量、locale などで挙動を固定化

`suite` ラベルは `capture.sh` の `call` / `call_json` の第1引数でそのまま付ける。
これにより `coverage_report.py` で「エンドポイントごとに各 suite が揃っているか」をレポートできる。

---

## エンドポイント型別テストケース表

### 型 A: GET 一覧 (`/resources?langCode=ja&page=1`)

| suite | 観点 | 代表ケース |
|---|---|---|
| normal | 既定クエリで 200 | `?langCode=ja` |
| normal | 検索クエリあり | `?keyword=東京` |
| auth | API キー欠落 | ヘッダなしで 401 |
| auth | API キー不正 | `x-api-key: invalid` で 401 |
| validation | 必須クエリ欠落 | `langCode` なしで 400 |
| validation | enum 外の値 | `langCode=xx` で 400 |
| boundary | 多言語 | `langCode=en` / `ko` / `zh` |
| boundary | 件数ゼロ | 絶対にヒットしない `keyword` |
| boundary | 大量件数 | `page=1&limit=MAX` |
| boundary | ページング境界 | `page=0` / 存在しないページ |

### 型 B: GET 単体 (`/resources/{id}`)

| suite | 観点 | 代表ケース |
|---|---|---|
| normal | 存在する ID | `FIXTURE_RESOURCE_ID` |
| auth | API キー欠落 | 401 |
| validation | 不正な ID 形式 | 英字禁止のプロジェクトなら `abc` で 400 |
| boundary | 存在しない ID | `id-9999` / 範囲外で 404 |
| boundary | SoftDeleted な ID | deleted_at が設定済みで 404 |
| boundary | 非公開状態の ID | `publish_scope=private` で 404 |

### 型 C: POST 作成 (`/resources`, ボディあり)

| suite | 観点 | 代表ケース |
|---|---|---|
| normal | 完全な正常ボディ | 全フィールド埋めて 201 |
| normal | 任意フィールド省略 | `nullable` のみ省略で 201 |
| auth | API キー欠落 | 401 |
| auth | 認証済みユーザー必要な場合、user-id 欠落 | 401 |
| validation | 必須欠落 × フィールド数分 | `nick_name` 欠落、`birth_year` 欠落、... (フィールドごとに1本) |
| validation | 型違反 | `gender` に `"0"` (文字列) / `birth_year` に `"abc"` |
| validation | enum 外 | `gender=3` / `address_status=99` |
| validation | 相関バリデーション違反 | `address_status=1` だが `address_code` 未指定 |
| boundary | 文字列長 min-1 | `nick_name=""` (最小1文字なら) |
| boundary | 文字列長 max | `nick_name=` ちょうど最大長 |
| boundary | 文字列長 max+1 | `nick_name=` 最大+1 |
| boundary | 数値下限 | `birth_year=1900` (最小) |
| boundary | 数値下限-1 | `birth_year=1899` で 400 |
| boundary | 数値上限 | `birth_year=2100` |
| boundary | 数値上限+1 | `birth_year=2101` で 400 |
| boundary | マルチバイト | `nick_name="テスト🔥"` |
| boundary | 空文字 / null | `nick_name=""` / `nick_name=null` (型違反かどうか) |

### 型 D: PUT / PATCH 更新 (`/resources/{id}`, 自分のリソース)

型 C に加えて:

| suite | 観点 | 代表ケース |
|---|---|---|
| auth | 他人のリソース更新 | `x-user-id` を別人にして 403 |
| boundary | 不変フィールド更新 | `id` / `created_at` を渡して無視されるか |
| boundary | 空ボディ | `{}` で 400 or 200 (仕様確認) |
| boundary | 二重更新 | 同じ内容を2回 → 冪等か |

### 型 E: DELETE 破壊 (`/resources/{id}`)

| suite | 観点 | 代表ケース |
|---|---|---|
| normal | 存在する自分のリソース | 204 or 200 |
| auth | 認証なし | 401 |
| auth | 他人のリソース削除 | 403 |
| boundary | 存在しない ID | 404 (仕様確認) |
| boundary | 二重削除 (冪等性) | 削除直後にもう1回 → 404 or 204 |
| boundary | SoftDelete と併用 | 論理削除済みを再 DELETE |

> ⚠️ **capture.sh 内での配置順**: DELETE 系は最後尾。後続テストが同じリソースを参照できなくなるため。

### 型 F: 外部サービス連携 (`/payments/ios/*`, `/notifications/sms/*` 等)

ローカルでは外部連携が通らないのが前提。

| suite | 観点 | 代表ケース |
|---|---|---|
| auth | API キー欠落 | 401 |
| validation | 必須欠落 | body の `purchases` 欠落で 400 |
| validation | 型違反 / 形式違反 | `price_amount` に文字列 |
| boundary | 外部連携失敗をベースライン化 | 無効 JWS / 無効レシートで 500 を固定化 |

正常系は取れないので、**「壊れているのが正しい」ベースライン** を作る。

### 型 G: OS 分岐ルート (`/payments/ios/*` vs `/payments/android/*`)

| suite | 観点 | 代表ケース |
|---|---|---|
| normal/error | iOS 用ルートに iOS ヘッダ | `x-os-type: ios` |
| normal/error | Android 用ルートに Android ヘッダ | `x-os-type: android` |
| auth | OS ヘッダ欠落 | `x-os-type` なしで 400 |
| auth | OS 不一致 | iOS ルートに `x-os-type: android` で 400 |

---

## endpoint 名の付け方（衝突回避）

`snapshot_comparator.py` のデフォルト `match_keys` は `["endpoint", "method"]`。
**同じ `endpoint` 文字列でメソッドが同じなら衝突する** ので、以下のサフィックスで分ける:

| suite | endpoint サフィックス例 |
|---|---|
| normal | `users.register` (素) |
| auth | `users.register.no_api_key` / `users.register.bad_api_key` / `users.register.other_user` |
| validation | `users.register.missing_nick` / `users.register.bad_gender` / `users.register.bad_birth_year` |
| boundary | `users.register.nick_max` / `users.register.nick_over_max` / `users.register.birth_min` / `users.register.birth_under_min` |

サフィックス命名規則:
- 何をテストしているかが一目で分かる短い英小文字
- `.` 区切りで階層化
- 末尾に `.invalid` を多用しない (何が invalid か分からなくなる)

---

## 対象エンドポイントごとの最低ライン

**基本 4 観点は全エンドポイントで取る**:

- `normal` × 1 (代表ケース)
- `auth` × 1〜2 (API キー欠落は必須、ユーザー認証ありなら user-id 系も)
- `validation` × フィールド数の半分 (必須欠落を中心に)
- `boundary` × 2〜3 (主要な数値・文字列フィールドの境界)

小規模な GET 一覧でも **4〜5 本**、POST/PUT なら **8〜15 本** のテストケースになる想定。

カバレッジ目安:
- 小規模 API (20 endpoints) → 80〜120 ケース
- 中規模 API (50 endpoints) → 200〜400 ケース

---

## このマトリクスの使い方（capture.sh に書く前に）

1. プロジェクトの全エンドポイントをリストアップ（routes ファイル / swagger から）
2. 各エンドポイントを型 A〜G のいずれに分類するかメモ
3. 対応する列の観点を `reference/discovery-checklist.md §3-5` のバリデーション表と照合
4. エンドポイントごとに「正常系 / auth / validation / boundary」の **最低1本ずつ**を決める
5. `capture.sh` の各セクションに `call` / `call_json` / `call_unauth_*` / `call_invalid_body` / `call_boundary` で並べる
6. `bash tools/snapshot/snapshot.sh record` で初回マスター作成
7. `python3 tools/snapshot/coverage_report.py` でカバレッジ自動チェック
8. 不足があれば 5 に戻る

---

## よくある抜け漏れパターン

| 症状 | 原因 | 対策 |
|---|---|---|
| 認可スナップショットが `/languages` だけ | 最初のサンプルをコピペで終わらせている | 全 endpoint × 最低 1 auth を必須化 |
| POST の validation が全部 `{}` で統一 | 「空ボディ = バリデーションエラー」で満足している | フィールド単位で `missing_<field>` を書く |
| 境界値 0 件 | FormRequest を読まずに書いた | `discovery-checklist.md §3-5` で表を作ってから書く |
| 多言語カバレッジなし | `langCode=ja` 固定 | 1 endpoint あたり最低 `ja` + 1 他言語 |
| `compare_headers` 未有効化 | デフォルト設定のまま | 少なくとも `content-type` は比較対象に |

---

## 参考: `create-snapshot` Skill 内での位置づけ

- `reference/discovery-checklist.md` — **調査** (必須ヘッダ、FormRequest rules, 公開状態)
- `reference/test-case-matrix.md` — **設計** ← 本書
- `scripts/capture.sh.example` — **実装** (このマトリクスに沿って call_* を並べる)
- `scripts/coverage_report.py` — **検証** (マトリクスどおり埋まっているか)
- `scripts/gen_cases.py` — **加速** (swagger から雛形生成)
