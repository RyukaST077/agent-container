# API スナップショット回帰テスト作成指示書

バージョンアップや大規模リファクタのときに「外から見える API が壊れていないか」を面で保証するための、**プロジェクト横断で使えるスナップショット回帰テスト** の設計指針と実装テンプレートです。

このディレクトリをまるごと対象プロジェクトへコピーし、`capture.sh` の中身だけをそのプロジェクト向けに書けば動きます。

---

## 1. 何を解決するテストか

本テストが保証する命題は 1 つだけです。

> **承認済みマスターと、現在の実装は、同じ入力に対して同じ HTTP ステータスと（正規化後で同一の）レスポンスボディを返す。**

- 保証する: 外部から見た API 契約（HTTP ステータス / レスポンス構造 / 値）の不変性
- 保証しない: 内部実装の正しさ、性能、未呼び出しエンドポイント、非決定ソート順
- 位置づけ: ユニット/結合テストの **下流** に置き、「完成系が承認時から動いてない方向に動いたか」を検知する最後の壁

この割り切りにより、フレームワークのバージョンアップでアプリ内部テストが一時的に不安定になっても、**ユーザー体験の不変性** だけは独立して見続けられます。

---

## 2. 設計原則

### 2.1 キャプチャと比較を分離する

- **キャプチャ（プロジェクト依存）**: 実 API を呼んでレスポンスを JSONL で落とす。プロジェクトごとに書く。
- **比較（汎用）**: JSON 配列を突き合わせて差分を出す。全プロジェクト共通。

分離することで、対象プロジェクトが変わってもテンプレートの 8 割（ランナー・比較器・正規化ルール）はそのまま流用できます。

### 2.2 実 API + 実依存に対して叩く

モックで差し替えると「モックとプロダクション実装のズレ」を検知できなくなります。テスト環境は **本番と同じ構成で起動した API サーバと実データベース** を使ってください（Docker Compose で立ち上げるのが最も楽）。

### 2.3 可変値は正規化ルールで吸収する

タイムスタンプ / ID / URL / シークレットなど、毎回変わる値をそのまま比較すると全件差分になり実質無意味になります。JSON で設定可能な **正規化ルール** で `{{TIMESTAMP}}` 等のトークンに置き換えてから比較します。

### 2.4 マスター更新は人間のレビュー + Git コミット

マスター (`snapshot-master.json`) の上書きは `approve` アクション経由で対話確認つき、かつ **Git にコミットして初めて承認完了** とする運用にします。マスター差分 = 承認された API 変更履歴、という関係を成立させます。

### 2.5 CI と pre-commit / ローカル hook の両方で走らせる

- **CI**: マージゲート。落ちたら PR マージ不可。
- **ローカル自動実行**: 編集 → 保存 → 自動テストのサイクルを短くする。失敗時は人間に見せる。

---

## 3. スナップショットに記録すべきフィールド

1 回のテスト実行で叩いた API コールを JSON 配列として保存します。1 要素は以下の形式。

| フィールド | 必須 | 用途 | 備考 |
|---|:-:|---|---|
| `endpoint` | ○ | マッチングキー | `users/{id}` のような論理識別子。URL に含まれる可変値を入れない |
| `method` | ○ | マッチングキー | `GET` / `POST` 等 |
| `http_code` | ○ | 差分検出 | 文字列でも数値でも可（内部で文字列化して比較） |
| `response_body` | △ | 差分検出 | オブジェクト / 配列 / 文字列(JSON)いずれも可。無ければステータスのみ比較 |
| `suite` | △ | 参考表示 | `normal` / `error_cases` 等のグループ名 |
| `url` | △ | 参考表示 | 実 URL。マッチングキーには使わない |
| `result` | △ | 参考表示 | `OK` / `NG` 等、ランナー側の判定 |
| `expected` | △ | 参考表示 | 期待 HTTP コード |
| `timestamp` | × | 参考表示 | 比較対象外。ランナーが自動付与 |

**キー設計のコツ**:
- `endpoint` は「このエンドポイントが何か」を一意に識別できる論理名にする。`users/123`（実 ID 入り）ではなく `users/{id}` や `users.show` のようにする。
- 同じエンドポイントで正常系と異常系の両方を叩く場合は `suite` で分ける（`normal` vs `error`）。ただしマッチングキーは `(endpoint, method)` 固定がデフォルト。正常系と異常系でキーが衝突する場合はマッチングキーに `suite` を足す。

---

## 4. テンプレート構成

```
snapshot-regression-template/
├── README.md                 # 本書(指示書)
├── snapshot.sh               # 汎用 CLI (record/test/compare/approve/reset)
├── snapshot_comparator.py    # 汎用比較ツール (正規化 + 差分検出 + レポート)
├── normalizer_rules.json     # 正規化ルールのデフォルト設定
└── capture.sh.example        # キャプチャスクリプトのテンプレ(これだけプロジェクト固有)
```

他プロジェクトへの導入手順:

```bash
# 1. テンプレート一式をコピー
cp -r docs/guides/snapshot-regression-template /path/to/your-project/tools/snapshot

# 2. キャプチャスクリプトをプロジェクト向けに書き換える
cd /path/to/your-project
cp tools/snapshot/capture.sh.example tools/snapshot/capture.sh
$EDITOR tools/snapshot/capture.sh

# 3. 実行権限を付与
chmod +x tools/snapshot/snapshot.sh tools/snapshot/capture.sh

# 4. 初回スナップショットを記録してマスターに承認
export CAPTURE_CMD="bash tools/snapshot/capture.sh"
bash tools/snapshot/snapshot.sh record
bash tools/snapshot/snapshot.sh approve

# 5. Git に追加
git add snapshots/snapshot-master.json tools/snapshot
git commit -m "Add snapshot regression test"
```

---

## 5. `capture.sh` の書き方（唯一のプロジェクト固有部分）

キャプチャスクリプトは **JSONL を 1 行 1 コール分、`$SNAPSHOT_CAPTURE_FILE` に追記する** ことだけが契約です。

最小実装:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${SNAPSHOT_CAPTURE_FILE:?SNAPSHOT_CAPTURE_FILE is required}"
: "${BASE_URL:=http://localhost:8080}"

emit() {
  # $1: suite, $2: endpoint(論理名), $3: method, $4: url, $5: http_code, $6: body(JSON文字列)
  python3 - "$@" <<'PY' >> "$SNAPSHOT_CAPTURE_FILE"
import json, sys
suite, endpoint, method, url, code, body = sys.argv[1:7]
try:
    body_obj = json.loads(body) if body else None
except Exception:
    body_obj = body
print(json.dumps({
  "suite": suite, "endpoint": endpoint, "method": method,
  "url": url, "http_code": code, "response_body": body_obj
}, ensure_ascii=False))
PY
}

call() {
  local suite="$1" endpoint="$2" method="$3" path="$4"; shift 4
  local url="${BASE_URL}${path}"
  local tmp; tmp=$(mktemp)
  local code
  code=$(curl -s -o "$tmp" -w '%{http_code}' -X "$method" "$url" "$@" || echo "000")
  emit "$suite" "$endpoint" "$method" "$url" "$code" "$(cat "$tmp")"
  rm -f "$tmp"
}

# --- ここから各プロジェクトのテストケース ---
call normal  languages     GET "/v1/languages"
call normal  terms.version GET "/v1/terms/version"
call error   users.show    GET "/v1/users/0"
# ...
```

**書くときのチェックリスト**:
- [ ] 実行中はテスト用 DB / スタブに切り替わっている（本番 DB を叩かない）
- [ ] 認証トークンを取得する正常系パスを最初に叩く
- [ ] 正常系 → 副作用が残る作成系 → 参照系 → 更新系 → 削除系 の順で並べる
- [ ] フィクスチャのユニーク名は実行タグ (例: `$(date +%Y%m%d-%H%M%S)`) で作り、正規化ルール側で `{{TEST_FIXTURE}}` に吸収する
- [ ] 失敗しても後続を止めないようにする（`set -e` は使わず、`|| true` で握る）
- [ ] テスト後にフィクスチャをクリーンアップする（残すとスナップショットが汚れる）

---

### §5.5 DB リセットとフィクスチャ管理

スナップショットの再現性を保証するには、record のたびに DB を既知状態に戻す仕組みが必要。

#### reset-db.sh テンプレートの構成

`scripts/reset-db.sh.example` を `reset-db.sh` にコピーして編集する。6 ステップ構成:

| Step | 処理 | 例 |
|---|---|---|
| 1 | DB リセット | `php artisan migrate:fresh` / `rails db:reset` / `python manage.py flush` |
| 2 | シーダー実行 | `php artisan db:seed --class=YourSeeder` |
| 3 | 共通フィクスチャ | テスト用 API キーの INSERT |
| 4 | プロジェクト固有フィクスチャ | QR コード、シリアルコード等 |
| 5 | テストユーザー登録 | API 経由で user_id を取得 |
| 6 | fixture.env 書き出し | capture.sh が参照する ID を出力 |

#### fixture.env の仕様

`reset-db.sh` が `tools/snapshot/fixture.env` を自動生成する。`capture.sh` は起動時にこれを source する。

```bash
# fixture.env の例
FIXTURE_AREA_ID=id-5
FIXTURE_USER_ID=123456789012
FIXTURE_SERIAL_CODE=SNP000000001
```

capture.sh での使用例:
```bash
call normal areas.show GET "/v1/areas/${FIXTURE_AREA_ID}"
call normal users.me   GET "/v1/users/me"  # x-user-id: ${FIXTURE_USER_ID} がヘッダに入る
```

#### SEED_CMD による snapshot.sh との統合

`SEED_CMD` 環境変数を設定すると `record` / `test` 前に自動実行される:

```bash
export SEED_CMD="bash tools/snapshot/reset-db.sh"
export CAPTURE_CMD="bash tools/snapshot/capture.sh"
bash tools/snapshot/snapshot.sh test   # reset-db.sh → capture.sh → 比較
```

#### ビジネスロジック調査チェックリスト

reset-db.sh を書く前に以下を確認する:

- [ ] 公開状態 (`publish_scope` / `enabled` / `status`): シーダーのデフォルトが非公開なら公開レコードをフィクスチャで用意
- [ ] SoftDeletes (`deleted_at`): capture.sh で DELETE を叩くなら最後尾に配置
- [ ] 認証方式: API キー / Bearer / カスタムヘッダ。reset-db.sh でテスト用を登録
- [ ] ID エンコーディング: 連番 / 暗号化 / UUID。API が受け付ける形式で fixture.env に書き出す
- [ ] 必須クエリパラメータ: `langCode` 等。capture.sh で共通付与する
- [ ] 外部サービス連携: 決済等はローカルで 500 が正常。ベースラインとして固定化

#### .gitignore への追加

fixture.env と中間スナップショットは Git 管理外にする:

```
tools/snapshot/fixture.env
snapshots/snapshot-*.json
!snapshots/snapshot-master.json
logs/snapshot-*
```

---

## 6. 正規化ルールのカスタマイズ

`normalizer_rules.json` を編集することで、プロジェクト固有の可変値を吸収できます。設定できるのは以下。

```jsonc
{
  "match_keys": ["endpoint", "method"],           // 突合キー
  "compare_fields": ["http_code", "response_body"], // 差分を見るフィールド
  "skip_body_endpoints": ["info", "health"],       // ボディ比較を飛ばすエンドポイント
  "key_rules": [
    // キー名で判定して置換
    {"type": "exact",    "keys": ["id"],         "token": "{{ID}}"},
    {"type": "suffix",   "keys": ["_id"],        "token": "{{ID}}"},
    {"type": "suffix",   "keys": ["_at"],        "token": "{{TIMESTAMP}}"},
    {"type": "contains", "keys": ["token","secret","password"], "token": "{{SECRET}}"},
    // value_regex を付けると「キー名条件 AND 値条件」の AND マッチになる
    {"type": "contains", "keys": ["url","image","avatar"], "value_regex": "^https?://", "token": "{{URL}}"}
  ],
  "value_rules": [
    // 値の形だけで判定して置換 (キー名不問)
    {"regex": "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2}", "token": "{{TIMESTAMP}}"},
    {"regex": "^\\d{4}-\\d{2}-\\d{2}$",                         "token": "{{DATE}}"},
    {"regex": "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", "token": "{{UUID}}"},
    {"regex": "^[0-9a-fA-F]{32,64}$",                           "token": "{{HEX_DIGEST}}"},
    {"regex": "^\\d{8,}$",                                       "token": "{{NUMERIC_ID}}"},
    {"regex": "^https?://",                                      "token": "{{URL}}"}
  ]
}
```

**追加パターンの作り方**:
1. `compare` を実行して、差分レポート (`snapshots/snapshot-*-report.md`) を見る
2. 「毎回変わるだけで意味が無い差分」を見つける
3. その値のキー名 / 値パターンを `key_rules` か `value_rules` に 1 行追加
4. `compare` で差分が消えることを確認

**`key_rules` と `value_rules` の使い分け**:
- キー名が意味を決める場合 (`created_at`, `user_id`) → `key_rules`
- 値の形だけで十分な場合 (UUID, ISO8601) → `value_rules`
- 誤爆が怖い場合 (例: `description` 欄に URL っぽい文字列) → `key_rules` + `value_regex` で AND 条件化

---

## 7. 運用ワークフロー

### 7.1 初回セットアップ

```bash
export CAPTURE_CMD="bash tools/snapshot/capture.sh"
bash tools/snapshot/snapshot.sh record     # キャプチャしてスナップショット生成
bash tools/snapshot/snapshot.sh approve    # マスターとして承認(対話)
git add snapshots/snapshot-master.json
git commit -m "Register golden master snapshot"
```

### 7.2 日常の回帰チェック

```bash
bash tools/snapshot/snapshot.sh test
# ✅ マスターと一致 → OK
# ❌ マスターと差分あり → レポート確認
```

### 7.3 仕様変更を承認する

```bash
bash tools/snapshot/snapshot.sh compare     # 差分を確認
less snapshots/snapshot-*-report.md
bash tools/snapshot/snapshot.sh approve     # 納得できたら承認
git add snapshots/snapshot-master.json
git commit -m "Update master: [変更理由]"
```

### 7.4 CI への組み込み

GitHub Actions の例:

```yaml
- name: Snapshot regression test
  env:
    CAPTURE_CMD: bash tools/snapshot/capture.sh
  run: |
    docker compose up -d
    ./tools/snapshot/wait-for-ready.sh
    bash tools/snapshot/snapshot.sh test
```

落ちたらジョブ失敗 → PR マージ不可 とするのが推奨。

### 7.5 Claude Code / pre-commit hook への組み込み

Claude Code の Stop hook（会話終了時に自動実行）:

```bash
# .claude/hooks/snapshot-check.sh
#!/usr/bin/env bash
set -uo pipefail
input=$(cat)
if echo "$input" | python3 -c "import json,sys;d=json.load(sys.stdin);sys.exit(0 if d.get('stop_hook_active') else 1)" 2>/dev/null; then
  exit 0
fi
cd /path/to/project || exit 0
export CAPTURE_CMD="bash tools/snapshot/capture.sh"
output=$(bash tools/snapshot/snapshot.sh test 2>&1)
ec=$?
if [ "$ec" -ne 0 ]; then
  python3 -c "
import json, sys
msg = sys.stdin.read()
print(json.dumps({'decision':'block','reason':'スナップショット検証失敗:\n'+msg}, ensure_ascii=False))" <<< "$output"
else
  echo '{"systemMessage":"✅ スナップショット検証OK"}'
fi
```

---

## 8. 差分種別の読み方

| 種別 | 意味 | 典型的な原因 | 対応 |
|---|---|---|---|
| `NEW` | 現行にだけ存在 | 新規エンドポイント追加 | 意図通りなら `approve` |
| `REMOVED` | マスターにだけ存在 | エンドポイント削除 / 未呼び出しに退行 | 退行なら修正、廃止なら `approve` |
| `CHANGED` | 同キーで `http_code` か body が変化 | 仕様変更 or バグ | レポート精査 → 判断 |
| `CONTRACT_ERROR` | エントリ形式が契約違反 | `capture.sh` のバグ | 必ず修正（握り潰さない） |

`CHANGED` のボディ差分は Markdown レポートに unified diff で記録されます。先頭 20 行まで表示、超過分は省略。

---

## 9. やらない/避けるべきこと

- **毎回 `approve` で黙殺する**: 差分が出たら必ず原因を説明できる状態にする。黙殺はマスターの価値を壊す。
- **正規化ルールを広げすぎる**: 「とりあえず `*` を `{{ANY}}` に」は検知能力を消す。追加は必要最小限。
- **マッチングキーに URL を入れる**: クエリ順序のゆらぎで同一エンドポイントが別扱いされる。`endpoint` は論理名で固定する。
- **本番環境で record する**: テスト用フィクスチャが残る。
- **マスターを個別ブランチで長期分岐させる**: マージ時に大量差分になる。仕様変更は小刻みに承認コミットする。

---

## 10. 組み込み機能（全プロジェクトで最初から有効）

基本の HTTP コード + 正規化済みボディ比較に加えて、以下の機能は **どのプロジェクトでも価値があり** 、コピーしただけで自動で動きます。ルール追加だけで効くもの、capture.sh に書き込む定型パターン、そしてテンプレ側が自動でやる運用機能の 3 種類です。

### 10.1 正規化で吸収する揺らぎ（ルール追加）

| 機能 | 埋める穴 | 有効化 |
|---|---|---|
| 型シグネチャ比較 | `"id": 123` → `"id": "123"` のような型変化。値正規化では `{{ID}}` vs `{{ID}}` で消える | `compare_fields` に `"type_signature"` を追加 |
| レスポンスヘッダ比較 | Content-Type / Cache-Control / CORS の壊れ | `compare_fields` に `"response_headers"` 追加 + `compare_headers` でホワイトリスト指定 |
| 配列の安定ソート | 順序が意味を持たない list の揺らぎ | `list_sort` に `{"endpoint名": {"path": "data", "key": "id"}}` |
| diff 表示行数の制御 | 大きな body 差分が切れる | `diff_max_lines` を増やす |

設定例:
```json
{
  "compare_fields": ["http_code", "type_signature", "response_headers", "response_body"],
  "compare_headers": ["content-type", "cache-control"],
  "diff_max_lines": 100,
  "list_sort": {"users.list": {"path": "data", "key": "id"}}
}
```

> 型シグネチャは **値を正規化する前の生ボディから計算** するため、`{{ID}}` マスクに邪魔されず型退化を検知できる。

### 10.2 差分の破壊性分類（approve 疲労の解消）

すべての `CHANGED` / `NEW` / `REMOVED` に `breaking` / `compatible` / `informational` の severity ラベルが付与されます。デフォルト分類は以下:

| rule | 例 | severity |
|---|---|---|
| `field_added` | レスポンスに optional フィールドが増えた | 🟢 compatible |
| `field_removed` | フィールドが消えた | 🔴 breaking |
| `type_changed` | 型が変わった | 🔴 breaking |
| `value_changed` | 値が変わった | 🔴 breaking |
| `array_length_changed` | 配列長が変わった | 🔴 breaking |
| `http_code_same_class` | 200 → 201 | 🟢 compatible |
| `http_code_error_introduced` | 2xx → 4xx/5xx | 🔴 breaking |
| `http_code_class_changed` | 4xx → 2xx 等 | 🔴 breaking |
| `endpoint_added` (NEW) | エンドポイント追加 | 🟢 compatible |
| `endpoint_removed` (REMOVED) | エンドポイント削除 | 🔴 breaking |

**SEVERITY 環境変数で失敗判定のしきい値を変える**:

```bash
bash snapshot.sh test                        # デフォルト: どの差分でも失敗 (厳格)
SEVERITY=breaking bash snapshot.sh test      # breaking のみで失敗 (compatible は通す)
SEVERITY=compatible bash snapshot.sh test    # breaking + compatible で失敗
```

推奨運用: **CI は `SEVERITY=informational` (厳格)、ローカル hook は `SEVERITY=breaking` (作業中は軽く)**。

プロジェクト固有の分類ポリシーは `normalizer_rules.json` の `severity_overrides` で上書きできます:
```json
{
  "severity_overrides": {
    "field_added": "breaking",          // 厳格にしたい
    "array_length_changed": "compatible" // このプロジェクトでは許容
  }
}
```

### 10.3 差分クラスタリング（大量 diff のレビュー負荷軽減）

同じパターンの変更（例: `data[*].created_at` の形式変更）が複数 endpoint で発生した場合、レポート冒頭に自動で集約表示されます:

```
## 🔗 差分クラスタ（共通パターン集約）
| severity | field | path | rule | 件数 | 代表 endpoint |
|---|---|---|---|---:|---|
| 🟢 compatible | response_body | `data[*].meta` | field_added | 45 | users.list, posts.list, orders.list (+42) |
```

- path は `[0]` / `[1]` などの配列インデックスを `[*]` に正規化して集約
- `cluster_min_count`（デフォルト 2）以上同じパターンが出たら集約
- 100 件の個別 diff が 3 クラスタに集約される、といったレビュー体験

### 10.4 世代比較（緩やかな退行の検知）

`approve` のたびに旧マスターが `snapshots/history/master-YYYYMMDD-HHMMSS.json` に自動退避されます。**初日から履歴が溜まっていないと後から再構築できない** ため、最初から回っているのが重要です。

```bash
bash snapshot.sh history  # 履歴の推移をレポート
```

出力例:
```
## 全体サマリー
| 世代             | endpoints | 総 fields | 総 bytes |
| 20260101-100000  |       47  |       340 |     12800 |
| 20260201-100000  |       47  |       355 |     13200 |
| 20260301-100000  |       48  |       420 |     16800 |
| current          |       48  |       510 |     21400 |

## ⚠ 肥大化警告
(閾値: fields x1.5 以上 / bytes x2.0 以上)
- ⚠ users.show フィールド数 12 → 32 (+167%)
```

保持世代数は `HISTORY_MAX_GENERATIONS` 環境変数（デフォルト 20）で調整。古い世代は自動削除。

### 10.5 キャプチャ側の定型（capture.sh.example 参照）

`capture.sh.example` には以下のヘルパが組み込まれています。必要なものを自分の `capture.sh` に写してください:

- `curl -D` でレスポンスヘッダを自動取得（10.1 のヘッダ比較の前提）
- `call_json` が `request_body` を記録（差分レビュー時の入力追跡）
- `call_idempotent` が同リクエストを 2 回叩いて `__idem2` サフィックスで記録（冪等性チェック）

### 10.6 残る限界（運用で意識する）

- **正規化トークンの相関消失**: 同一レスポンス内で同じ user を指す 2 箇所が別 ID に退化していても、両方 `{{ID}}` になって気付けない。業務上クリティカルなら Layer 2 側で専用アサーションを書く
- **マスターの正しさ**: 本テストの強度はマスターの正しさと等しい。`approve` 前の人間レビューを崩さない
- **環境依存の固定値**: テストデータを毎回新規作成するほど正規化に吸われる面積が増える。本番相当の安定データを使った方が検知能力は上がるが、副作用管理が難しくなる

---

## 11. プロジェクト特性別オプション

§10 までで大半のプロジェクトは 90 点構成になりますが、**プロジェクトの性格によって要否が割れる** 以下の拡張は別ドキュメント [optional-extensions.md](./optional-extensions.md) に設計指示書として切り出しています。

| 拡張 | 向くプロジェクト | 不要 / 代替となるケース |
|---|---|---|
| **A. JSON Schema スナップショット** | 暗黙の API 契約を顕在化したい | OpenAPI / GraphQL Schema を書いているなら不要 |
| **C. エンドポイント横断の不変条件** | リレーショナルドメイン (user/post, order/item) | エンドポイント独立性が高いなら無価値 |
| **E. プロダクショントラフィック replay** | 本番 / QA 乖離事故があった | 本番ログ基盤・PII マスカーが無いと実装不能 |
| **F. Property-Based / Fuzzing 連携** | バリデーションバグが頻発 | schemathesis 等の専用ツール導入が前提 |
| **G. ミューテーションテスト** | 成熟期でテスト自体の信頼性を数値化したい | Stryker / Infection 等の外部ツール依存 |

**導入ルール**: 基本テンプレを運用してから、症状が出たもの**だけ** 追加する。全部は入れない。詳細な設計・データモデル・実装手順は [optional-extensions.md](./optional-extensions.md) を参照。

---

## 12. snapshot 方式で守らない領域（別ツールへ委譲）

以下はスナップショット方式では原理的に届きません。テンプレを肥大化させず専用ツールに任せる判断にしてください。

| 領域 | 適した手段 |
|---|---|
| 負荷下の性能・スループット | k6、Locust、JMeter |
| 並行性・レースコンディション | カオスエンジニアリング、モデル検査 |
| セキュリティ脆弱性 | SAST（Semgrep）、DAST（ZAP） |
| メモリリーク・長期リソース退行 | プロファイラ、longevity テスト |
| デプロイ・インフラの正しさ | synthetic monitoring、smoke test |
| 業務仕様の正しさそのもの | 仕様書 + 人間レビュー + 受け入れテスト |
| DB 状態の変化 | アプリ統合テスト (PHPUnit Feature / pytest 等) |
| 外部連携 (メール/Webhook/キュー) | モック/スタブのコントラクトテスト |

**判断ルール**: **「レスポンスだけ見れば分かるか？」が YES なら snapshot で守れる、NO なら別ツール。**

---

## 13. ファイル一覧（本テンプレート）

- [README.md](./README.md) — 基本テンプレの指示書（本書）
- [optional-extensions.md](./optional-extensions.md) — プロジェクト特性別オプションの設計指示書
- [snapshot.sh](./snapshot.sh) — 汎用 CLI（record/test/compare/approve/history/reset）
- [snapshot_comparator.py](./snapshot_comparator.py) — 汎用比較ツール（型/ヘッダ/ソート/diff 制御/破壊性分類/クラスタリング対応）
- [history_report.py](./history_report.py) — 世代比較レポート
- [normalizer_rules.json](./normalizer_rules.json) — 正規化 + severity + クラスタ設定
- [capture.sh.example](./capture.sh.example) — キャプチャスクリプトのテンプレ（ヘッダ取得・冪等性チェック・request_body 記録付き）
