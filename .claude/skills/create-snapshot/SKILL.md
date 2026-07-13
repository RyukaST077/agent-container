---
name: create-snapshot
description: 対象プロジェクトに「API スナップショット回帰テスト」を新規セットアップするための Skill。実 API + 実 DB を叩いた JSONL レスポンスを正規化済みゴールデンマスターとして固定化し、HTTP コード/ボディ/ヘッダ/型/破壊性分類で差分検知できる仕組みを `tools/snapshot/` 一式として導入する。バージョンアップや大規模リファクタの「外部から見た API 契約の不変性」を面で保証したいときに使う。
---

# 目的

このSkillは、**「承認済みマスターと現行実装が、同じ入力に対して同じ HTTP ステータスと（正規化後で同一の）レスポンスボディを返す」** ことを保証する、汎用スナップショット回帰テスト一式を新規プロジェクトに導入する。

- **保証する**: 外部から見た API 契約（HTTP ステータス / レスポンス構造 / 値）の不変性
- **保証しない**: 内部実装の正しさ、性能、未呼び出しエンドポイント、非決定ソート順
- **位置づけ**: ユニット/結合テストの **下流** に置く「最後の壁」（フレームワーク非依存 = curl + python3 のみ）

設計の根拠と限界の詳細は `reference/design.md` を、テンプレ仕様の全体像は `reference/template-README.md` を参照。

---

# 実行分担（サンドボックス制約）

**Claude の実行環境 (sandbox) は実 API / 実 DB にアクセスできない。** したがって本 Skill では次の分担で進める。

| 担当 | 作業 |
|---|---|
| **Claude** | 事前調査（コード/ドキュメント読解）、テンプレのコピー、`capture.sh` / `reset-db.sh` / `normalizer_rules.json` の編集、ユーザ報告結果の解釈、次に実行すべきコマンドの提示 |
| **ユーザ** | 実 API / 実 DB を叩くすべてのコマンド実行（`reset-db.sh` / `capture.sh` / `snapshot.sh record\|test\|compare\|approve\|history\|reset` / `coverage_report.py` / `gen_cases.py`） |

## Claude → ユーザ へのコマンド提示フォーマット

実行を依頼するときは、以下を 1 ブロックにまとめて提示する:

1. **目的** — なぜこのコマンドが必要か（例: 「初回マスターの候補を作るため」）
2. **前提** — 事前に立ち上げておくべきもの（`docker compose up -d` 済み / 対象ブランチ 等）
3. **コマンド** — コピペ実行できる形（作業ディレクトリも明示）
4. **成功判定** — exit 0 / 特定ファイルが生成される 等
5. **報告してほしいこと** — 後述

## ユーザ → Claude への報告フォーマット

ユーザは **生成物のパスと要点** だけ教える（大きな JSON の貼り付けは不要。Claude が `Read` する）。

```
- exit code: 0 / 非0 (非0 なら末尾のエラー行を貼る)
- 生成/更新されたファイル:
    - snapshots/snapshot-current.json
    - snapshots/compare-reports/2026xxxx-xxxxxx.json
- 標準出力の要点 (数件): "X entries captured" / "Y differences" など
- 気になった表示があればその行だけ
```

Claude はパスを受け取ったら `Read` / `Glob` で中身を確認し、次の指示（承認 or 修正）に進む。

**原則**: ユーザが手で実行した結果は、上記パス経由で Claude が自分で読む。中身をテキストで貼り戻してもらわない。

---

# 起動条件

ユーザが次のいずれかを依頼してきたら本 Skill を呼ぶ:

- 「スナップショットテストを導入したい / 作りたい / 整備したい」
- 「Laravel/Rails/Django などのバージョンアップに備えて API 回帰テストを用意したい」
- 「ゴールデンマスター方式で API レスポンスを固定化したい」
- 「`tools/snapshot/` を作って」

すでに `tools/snapshot/` が存在する場合は **上書きせず**、何が違うか / 不足ファイルだけ補うかをユーザに確認すること。

---

# 提供物（このSkillに同梱されるファイル）

```
skills-bank/create-snapshot/
├── SKILL.md                              # 本書
├── reference/
│   ├── discovery-checklist.md            # 導入前の必須調査チェックリスト (Step 0 で使用)
│   ├── test-case-matrix.md               # 異常系・境界値も含むテストケース観点表 (Step 3 で使用)
│   ├── normalizer-guide.md               # 正規化ルールの過剰マスク回避指針
│   ├── design.md                         # 設計説明 (なぜ機能保証になるか / 限界)
│   ├── template-README.md                # テンプレ全体仕様 (§1〜13)
│   ├── optional-extensions.md            # JSON Schema / 不変条件 / replay / fuzzing / mutation
│   └── operation-guide.md                # 日常運用フロー (record/test/compare/approve)
└── scripts/
    ├── snapshot.sh                       # 汎用 CLI (record/test/compare/approve/history/reset)
    ├── snapshot_comparator.py            # 比較器 (正規化 + 破壊性分類 + クラスタリング)
    ├── history_report.py                 # 世代比較レポート
    ├── coverage_report.py                # 仕様 (OpenAPI/Swagger) vs マスターの網羅率レポート
    ├── setup_report.py                   # 導入完了レポート (master のサマリ / 何を固定したか)
    ├── gen_cases.py                      # 仕様からテストケース雛形を自動生成
    ├── normalizer_rules.json             # 正規化ルールのデフォルト
    ├── capture.sh.example                # キャプチャスクリプトのテンプレ (project 固有)
    └── reset-db.sh.example               # DB リセットスクリプトのテンプレ (project 固有)
```

`scripts/` 配下は **そのまま `tools/snapshot/` にコピー** すれば動く。`reference/` は読み物。
プロジェクト固有の編集が必要なのは `capture.sh` と `reset-db.sh` の 2 ファイル。

---

# 導入手順（Skill が実行すべき作業）

## 🚨 よくある初回の落とし穴 TOP 3

過去の導入で実際に踏んだ地雷。**capture.sh に手を付ける前に必ず潰す**こと。放置すると初回 record 後に作業がまるごと無駄になる。

1. **BASE_URL / port が推測値のまま** — docs に書かれた値を信じて capture.sh の `BASE_URL` を決めると、実環境と port が違って **全件 `http_code=000000`** で record し直しになる（過去実績: 90 エントリ全滅）。
   - 対策: Step 1 冒頭で `docker ps --format '{{.Names}}\t{{.Ports}}'` + `curl -I $BASE_URL/v1/<軽い GET>` を実行し、**ユーザに実ポートを確認してから** テンプレ編集を始める。

2. **phpinfo / debug 系が非決定 HTML を返す** — `/v1/info` のように PHP の `phpinfo()` を返すエンドポイントがあると、`REQUEST_TIME` / opcache 統計 / プロセス PID が毎回変動し、**初回 approve 後の compare で毎回大量 diff**が出て CI が壊れる。
   - 対策: `reference/discovery-checklist.md §2-4` で洗い出し、**初回 approve 前に** `normalizer_rules.json` の `skip_body_endpoints` に登録する（Step 4 参照）。

3. **シーダーが API キーをランダム生成している** — `ApplicationApiKey::generateApiKey()` のように uniqid/random 系で生成する実装の場合、固定の `test-api-key-local` を使いたくても `INSERT IGNORE` では **既存レコードが残って UNIQUE 制約を食う**。
   - 対策: reset-db.sh は `DELETE FROM <key_table> WHERE <条件>; INSERT ...` で上書き。`discovery-checklist §1-3` でシーダーを `grep generateApiKey` して確認する。

この 3 つを事前に潰すと、初回 record → approve まで 1 ラウンドで通る。

---

## 0. 事前調査（**スキップすると必ず後戻りする**）

`reset-db.sh` と `capture.sh` を書き始める前に、`reference/discovery-checklist.md` に沿って
プロジェクトの DB スキーマ / API バリデーション / ID エンコーディング / 既存ドキュメントを調査する。

**最低限、以下 8 項目が埋まるまでテンプレ編集を始めない** (詳細は `reference/discovery-checklist.md`):

1. マイグレーションパス（`--path` 指定が要るサブディレクトリ構成か）
2. シーダー順序（FK 依存関係の解決済み）
3. API キーテーブルのカラム構造（`id` カラムがあるか、PK は何か）
4. API キーの取得方法（固定値 vs ランダム生成）
5. 対象 API の必須ヘッダ一覧（`x-api-key` / `x-os-type` / `Authorization` 等）
6. ID エンコーディング形式（連番 / `id-N` / UUID / 暗号化）
7. 登録系エンドポイントのレスポンス ID キー名（`id` / `user_id` / `data.id`）
8. **OpenAPI / Swagger 仕様ファイルの有無と所在**（`docs/swagger.yaml` / `docs/openapi.yaml` / `storage/api-docs/` / `public/api-docs/` / `app/*/Swagger/` 等） — 見つかれば Step 3 で `gen_cases.py` / §5.5 の `coverage_report.py` の `--spec` 起点にできる。`l5-swagger` / `swagger-php` 等アノテーション型で YAML 未生成なら、先に生成コマンド (`php artisan l5-swagger:generate` 等) をユーザに依頼する

**既存ドキュメント (`docs/dev/*.md`, `README.md`) のテスト用 API キー登録手順は必ず読む** — 固定値が既に運用されていれば、それを `FIXTURE_API_KEY` のデフォルトに採用して fixture.env 依存を消せる。

## 1. プロジェクト構成の確認

ユーザに以下を確認する（既知ならスキップ）:

| 項目 | 例 |
|---|---|
| 配置先パス | `tools/snapshot/`（推奨）/ `test/snapshot/` 等 |
| API ベース URL | `http://localhost:8080`、`http://api:80` 等 |
| 認証方式 | 不要 / Bearer トークン / Cookie / API Key |
| OS 別分岐の有無 | モバイル API で `x-os-type: ios/android` による別ルートがあるか |
| 起動方法 | `docker compose up`、`bin/rails s` 等（CI で再利用するため） |
| 初期に叩く代表エンドポイント | `GET /v1/health` 等 5〜20 個 |

### ⚡ テンプレ編集前の接続 pre-check (**省略不可**)

API ベース URL は docs を信じず、ユーザ環境で以下 2 コマンドを実行して実ポートを確認してもらう:

```bash
# 1) コンテナ名とポートマッピング
docker ps --format 'table {{.Names}}\t{{.Ports}}' | grep -E "<project keyword>"
# 期待例: sarf-api-develop-api-1   0.0.0.0:8082->80/tcp

# 2) BASE_URL 到達確認 (認証不要 or 軽い GET を 1 本)
curl -sS -o /dev/null -w "HTTP %{http_code}\n" ${BASE_URL}/v1/<info や health 等>
# 200 / 401 / 403 のいずれかが返れば OK
# 000 / Connection refused なら port / コンテナ起動状態を見直す (先に進まない)
```

**これをやらずに推測 port でテンプレを書くと、初回 record で 全件 `http_code=000000` になり、90 本以上やり直しになる**（過去実績）。
ユーザから「ポートはXXXX」と回答をもらうまで Step 2 (コピー) に進まない。

## 2. テンプレ一式をコピー

```bash
mkdir -p <PROJECT_ROOT>/tools/snapshot
cp skills-bank/create-snapshot/scripts/* <PROJECT_ROOT>/tools/snapshot/
chmod +x <PROJECT_ROOT>/tools/snapshot/snapshot.sh
mv <PROJECT_ROOT>/tools/snapshot/capture.sh.example <PROJECT_ROOT>/tools/snapshot/capture.sh
mv <PROJECT_ROOT>/tools/snapshot/reset-db.sh.example <PROJECT_ROOT>/tools/snapshot/reset-db.sh
chmod +x <PROJECT_ROOT>/tools/snapshot/capture.sh <PROJECT_ROOT>/tools/snapshot/reset-db.sh
```

## 2.5. DB 環境の調査と `reset-db.sh` の作成

スナップショットの再現性を保証するには、record のたびに DB を既知状態に戻す仕組みが必要。以下を調査してから `reset-db.sh` をプロジェクト向けに編集する。

### 調査項目

| 項目 | 確認方法の例 | なぜ必要か |
|---|---|---|
| DB 接続情報 | `.env` / `docker-compose.yml` / `config/database.php` 等 | reset-db.sh のコンテナ名・認証情報に使う |
| マイグレーション方式 | Laravel: `migrate:fresh`, Rails: `db:reset`, Django: `flush` | DB リセットコマンドの選択 |
| シーダーの内容と順序 | `database/seeds/` 等を読む。どのテーブルに何が入るか | 投入順序の決定、フィクスチャ ID の把握 |
| **ビジネスロジック上の制約** | Action / Usecase クラスを読む | **最重要。以下のような罠を事前に回避する** |

### ビジネスロジック調査のチェックリスト

シーダーでデータが入っても、API から見えないケースが頻出する。以下を必ず確認
(より網羅的なチェックリストは `reference/discovery-checklist.md` §5 参照):

- [ ] **公開状態** — `publish_scope` / `enabled` / `status` / `is_active` 等のフラグ。シーダーのデフォルトが「非公開」の場合、API は 404 を返す。公開状態のレコードをフィクスチャ SQL で明示的に用意するか、公開済みの既存レコード ID を使う
- [ ] **SoftDeletes** — `deleted_at` カラムがあるモデルは DELETE 後に Eloquent/ActiveRecord の通常クエリから消える。capture.sh で DELETE を叩くなら最後尾に配置する
- [ ] **認証・認可** — API キー / Bearer トークン / セッション Cookie / カスタムヘッダ（`x-user-id` 等）。必要なら reset-db.sh でテスト用キー・ユーザーを登録する
- [ ] **API キーの生成方式** — シーダーのコードを `grep -rE "api_key|generateApiKey|uniqid|random_bytes" database/` で確認
    - **固定値を INSERT するシーダー** → そのまま使える
    - **ランダム生成 (`ApplicationApiKey::generateApiKey()` / `uniqid()` / `Str::random()` 等)** → reset-db.sh では `DELETE FROM <keys_table> WHERE <条件>; INSERT ...` で上書きする。**`INSERT IGNORE` ではランダム生成された既存レコードが残って UNIQUE 制約違反になり失敗する**
- [ ] **ID エンコーディング** — 内部連番がそのまま API に出るか、暗号化/ハッシュ/UUID に変換されるか。debug モード用のフォーマット（`id-N` 等）があるか
- [ ] **必須クエリパラメータ** — `langCode` / `page` / `limit` 等。省略すると 400 になる
- [ ] **リレーション依存** — `area_application` / `user_organization` 等の中間テーブル。シーダーが作るかどうか。FK 制約で API が 500 になる場合あり
- [ ] **外部サービス連携** — 決済（Apple/Google）/ メール / SMS 等。ローカルでは 500 になるのが正常。ベースラインとして固定化する

### reset-db.sh の編集

`scripts/reset-db.sh.example` をプロジェクト向けに編集する。6 つのステップに分かれている:

1. **DB リセット** — `migrate:fresh` 等（フレームワーク別のコメント例あり）
2. **シーダー実行** — 順序を明記
3. **共通フィクスチャ** — API キー等。**ランダム生成型シーダーの場合は `DELETE → INSERT` で上書き** (下記参照)
4. **プロジェクト固有フィクスチャ** — QR コード、シリアルコード等シーダーに無いもの
5. **テストユーザー登録** — API 経由で user_id を取得
6. **fixture.env 書き出し** — capture.sh が参照するフィクスチャ ID

**API キー登録パターン (ランダム生成型シーダーの場合)**:

```bash
# ApplicationDataSeeder::run() が ApplicationApiKey::generateApiKey() を呼ぶ等、
# シーダー後に application_api_keys テーブルにランダム値が入っている場合:
mysql_exec "$CMS_DB_NAME" -e "
  DELETE FROM application_api_keys WHERE application_id = 1;
  INSERT INTO application_api_keys
    (api_key, application_id, created_by, created_at, updated_by, updated_at)
  VALUES
    ('${FIXTURE_API_KEY}', 1, 'snapshot', NOW(), 'snapshot', NOW());
"
# → 固定値 FIXTURE_API_KEY=test-api-key-local で capture.sh が叩けるようになる

# API キーキャッシュのクリア (Cache::remember 経由の実装なら必須)
docker exec "$APP_CONTAINER" php artisan cache:clear
```

**よくあるミス**: `INSERT IGNORE INTO application_api_keys (api_key, application_id, ...) VALUES ('test-api-key-local', 1, ...)` としても、**既に別の api_key 値で application_id=1 のレコードがある**ので、`UNIQUE(application_id)` や複合 PK で衝突する。必ず先に `DELETE` してから `INSERT`。

### fixture.env の役割

`reset-db.sh` が `tools/snapshot/fixture.env` を自動生成し、`capture.sh` が起動時に source する。これにより seed 結果の動的 ID（テストユーザー ID 等）がキャプチャスクリプトに連携される。

```
# fixture.env の例
FIXTURE_AREA_ID=id-5
FIXTURE_USER_ID=123456789012
FIXTURE_SERIAL_CODE=SNP000000001
```

## 3. `capture.sh` をプロジェクト向けに編集

`capture.sh` と `reset-db.sh` がプロジェクト固有の 2 ファイル。`capture.sh.example` の冒頭〜ヘルパ (`emit` / `call` / `call_json` / `call_idempotent` / `call_unauth_*` / `call_invalid_body` / `call_boundary` 等) は触らない。末尾の「テストケース」以下に対象 API のコールを並べる。`fixture.env` から読み込んだ ID を使ってリクエストパスや JSON ボディを構築する。

### ヘッダセットの使い分け

`capture.sh.example` は最初から 4 種類のヘッダ配列を用意している:

| 配列 | 用途 |
|---|---|
| `COMMON_HEADERS` | OS 非依存の共通ヘッダ (Bearer トークン / API キーのみの API 向け) |
| `COMMON_HEADERS_IOS` | `x-os-type: ios` を含む (モバイル API の iOS ルート / OS 非依存ルート) |
| `COMMON_HEADERS_ANDROID` | `x-os-type: android` を含む (`/payments/android/*` 等 Android 専用ルート向け) |
| `USER_HEADERS_IOS` / `USER_HEADERS_ANDROID` | 上記に `x-user-id` を足したもの (登録後に `rebuild_user_headers` で再構築) |

**OS 別ルートがあるプロジェクトでは `COMMON_HEADERS_IOS` で全部叩くと Android ルートが全滅する**。
`/payments/ios/*` には `*_IOS`、`/payments/android/*` には `*_ANDROID` を必ず使い分けること。

OS 非依存の API しか無い場合は `COMMON_HEADERS_ANDROID` を削除して良い。

### 3-a. 正常系 (suite=normal)

全エンドポイントについて代表ケースを並べる。登録系は最初の方に置き、`SNAPSHOT_USER_ID` を抽出して以降の認証ヘッダに連携する。DELETE 等の破壊系はこの時点では書かず、後の 3-e に回す。

### 3-b. 認可系 (suite=auth)

`reference/test-case-matrix.md` の「型別」表で対象エンドポイントの型を決定 → 下記ヘルパで必要なケースを追加する:

- `call_unauth_no_key <endpoint> <method> <path> <min_headers>` — x-api-key 欠落
- `call_unauth_bad_key <endpoint> <method> <path> <min_headers>` — 不正 x-api-key
- `call_unauth_no_user <endpoint> <method> <path> <headers>` — x-user-id 欠落
- `call_unauth_other_user <endpoint> <method> <path> <headers>` — 他人の user_id
- `call_unauth_other_user_json ... <body> <headers>` — 上記のボディ付き版

**最低ライン: 保護エンドポイント "全件" に 1 本ずつ** (`call_unauth_no_key`)。

> ⚠️ **「代表エンドポイントで 1 本」では coverage_report が通らない**。
> `coverage_report.py --fail-on-gap` は各エンドポイントの auth 有無を個別に見るため、
> `languages` と `areas.list` だけ取って「ApiKey middleware は全体共通だから他は省略」と
> するのは NG（過去実績: 17/22 未取得で再 record になった）。
>
> ApiKey middleware は body / path 検証より先に動くため、POST/PUT/DELETE でも
> **body 無し・`Content-Type` 無し** で `call_unauth_no_key` を並べるだけで成立する:
>
> ```bash
> NO_KEY_HEADERS=(-H "x-os-type: ios" -H "x-app-version: ${FIXTURE_APP_VERSION}")
> call_unauth_no_key users.register     POST "/v1/users/register"          "${NO_KEY_HEADERS[@]}"
> call_unauth_no_key users.me.update    PUT  "/v1/users/me"                "${NO_KEY_HEADERS[@]}"
> call_unauth_no_key users.destroy      DELETE "/v1/users"                 "${NO_KEY_HEADERS[@]}"
> # ... 以下、保護エンドポイント全件
> ```
>
> `bad_api_key` は任意 (代表 1〜2 本で挙動差 403 を確認)。
> `no_user_id` / `other_user` はユーザ識別が必要な API 限定。

### 3-c. バリデーション系 (suite=validation)

**先に `reference/discovery-checklist.md §3-5` のバリデーション表を埋める**。各 POST/PUT エンドポイントについて:

- `call_invalid_body <endpoint> <case_name> <method> <path> <body> <headers>` — フィールド単位 (`missing_nick`, `bad_gender`, `bad_birth_year`)
- `call_invalid_query <endpoint> <case_name> <method> <path> <headers>` — GET/DELETE の path/query 異常値

最低ライン: 必須フィールド数の 50% を超える個数の `missing_*` + 主要 enum / 型違反 2〜3 本。

### 3-d. 境界値系 (suite=boundary)

- `call_boundary <endpoint> <case_name> <method> <path> <body> <headers>` — 文字列長 / 数値境界
- `call_boundary_query <endpoint> <case_name> <method> <path> <headers>` — 多言語・件数ゼロ等

最低ライン: 主要フィールド 2 つの min/max ±1 + 多言語 (langCode) バリアントがあれば en/ko/zh 1 本ずつ。

### 3-e. 破壊系 (suite=destructive)

DELETE や状態を変える POST (退会・解約など) はここ。**必ず capture.sh の末尾** に置く。

### ⚡ テストケース雛形の自動生成 (Swagger が見つかった場合はここが起点)

Step 0 #8 で OpenAPI/Swagger 仕様が確認できていれば、**3-a 以下を手書きで並べる前にまず `gen_cases.py` で雛形を生成する**。手書きスタートにすると後から Swagger と突き合わせたときに抜け漏れ / enum 取り違えが大量発生するため、「Swagger があるなら gen_cases 起点、手書きはフォールバック」をデフォルトにする。

```bash
# 単一エンドポイントの雛形を生成
python3 tools/snapshot/gen_cases.py --spec docs/swagger.yaml \
  --endpoint /users/register --method POST --base-url-prefix /v1

# 全エンドポイント
python3 tools/snapshot/gen_cases.py --spec docs/swagger.yaml --all \
  --base-url-prefix /v1 --output /tmp/skeleton.sh
```

**生成結果は「案」**。各ケースは FormRequest の実際の制約 (enum 値、相関バリデーション、DB 前提) を確認してから採用・編集する。Step 0 #8 で Swagger が見つからなかったプロジェクトに限り、3-a 以下を手書き起点で進める。

### 書くときのチェックリスト

- [ ] テスト用 DB / スタブに切り替わっている（本番 DB を叩かない）
- [ ] 認証トークン取得を最初に叩く
- [ ] 3-a (normal) → 3-b (auth) → 3-c (validation) → 3-d (boundary) → 3-e (destructive) の順
- [ ] フィクスチャ名は実行タグ（`$(date +%Y%m%d-%H%M%S)`）でユニークにする
- [ ] `set -e` を使わず `|| true` で握って後続を止めない
- [ ] テスト後にフィクスチャをクリーンアップする
- [ ] `endpoint` は `users/{id}` の論理名（実 ID を入れない）
- [ ] 同じエンドポイントの異常系は `.missing_<field>` / `.bad_<field>` / `.nick_max` 等のサフィックスで衝突回避
- [ ] `reference/test-case-matrix.md` の「エンドポイント型別」表を参照しながら書いている

## 4. 正規化ルールの初期化

`scripts/normalizer_rules.json` をそのままコピーすれば一般的な可変値（`{{ID}}` `{{TIMESTAMP}}` `{{UUID}}` `{{URL}}` 等）は吸収される。プロジェクト固有のフィクスチャ書式が出てきたら `key_rules` / `value_rules` に追加する（詳細は `reference/template-README.md` §6 と `reference/normalizer-guide.md`）。

### 4-1. 非決定 HTML を返すエンドポイントを `skip_body_endpoints` に登録する（**初回 approve 前に必須**）

`discovery-checklist §2-4` で洗い出した phpinfo / debug / ヘルスチェック系エンドポイントは、
body に `REQUEST_TIME` / opcache 統計 / プロセス PID が含まれ、**毎回必ず差分が出る**。
初回 record 前に `normalizer_rules.json` の `skip_body_endpoints` に登録すること:

```json
{
  "compare_fields": ["http_code", "response_body", "response_headers"],
  "skip_body_endpoints": ["info", "debug.sleep1", "debug.headers", "debug.logging"]
}
```

これを忘れると、**初回 approve 後に毎回の compare で巨大な HTML diff が出て CI が壊れる**（過去実績: sarf-api で `/v1/info` が phpinfo を返しており、1 度 approve した後の test が必ず失敗）。
`skip_body_endpoints` に入れても `http_code` とヘッダの退行は検知され続けるので、検知能力は落ちない。

### 4-2. `_code` 過剰マスクの回避

デフォルト正規化ルールは `_code` suffix を `{{CODE}}` にマスクするため、
`lang_code` / `currency_code` 等の**業務上変わってはいけない値**まで潰す可能性がある。
初回 record 後に正規化済みマスターを目視し、「本来差分検知したい値が潰れていないか」を
必ず確認すること。必要に応じて `reference/normalizer-guide.md` の手順で exact リスト化に切替える
（`transfer_code` / `serial_code` 等ランダム値のみを exact で `{{CODE}}` にする）。

### 4-3. `response_headers` の比較有効化

デフォルトでは `compare_fields` に `response_headers` が含まれていない。
`content-type` が text/html に化けても検知したいなら、`normalizer_rules.json` の
`compare_fields` に `"response_headers"` を追加し、`compare_headers` に `"content-type"` を
書き込む (`reference/normalizer-guide.md §「ヘッダ比較の有効化」`)。

## 5. 初回マスターの確定（ユーザ実行）

このステップ以降は **実 API / 実 DB を叩くためユーザ実行**。Claude は以下のブロックをユーザに提示し、実行結果（パスと要点）の報告を待つ。

### 5-0. 接続 pre-check (**record 実行前に必ず挟む**)

Step 1 の pre-check とは別に、**実際に capture.sh で使うヘッダ構成** で到達できるか確認する。
ここで失敗すると record が無駄になるので、単発 curl で必ず先に確認する:

```text
【目的】 capture.sh が送るヘッダで API に到達できるか確認 (未到達だと全件 000000 で record 無駄打ち)
【コマンド】
  cd <PROJECT_ROOT>
  # fixture.env 未生成時は FIXTURE_API_KEY をベタで入れる (docs/dev/*.md の値)
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" \
    -H "x-api-key: test-api-key-local" \
    -H "x-os-type: ios" -H "x-app-version: 3.3.0" \
    http://localhost:<PORT>/v1/languages
【成功判定】 HTTP 200 が返る
【失敗時】
  - 000 / Connection refused  → port が違う or api コンテナ未起動 (docker ps で確認)
  - 403                       → API キー値が違う (docs/dev/*.md 再確認)
  - 500                       → app コンテナ内部エラー (docker logs <api container>)
【報告してほしいこと】
  - HTTP コード (200 なら一行 "HTTP 200" だけで OK)
```

**5-0 が 200 で通るまで 5-1 に進まない。** ここで 30 秒使えば record 10 分の往復が省ける。

### 5-1. record の依頼

```text
【目的】 初回マスター候補 (snapshots/snapshot-<timestamp>.json) を作る
【前提】 5-0 で 200 が返っている
【コマンド】
  cd <PROJECT_ROOT>
  export SEED_CMD="bash tools/snapshot/reset-db.sh"
  export CAPTURE_CMD="bash tools/snapshot/capture.sh"
  bash tools/snapshot/snapshot.sh record
【成功判定】 exit 0 かつ snapshots/snapshot-<timestamp>.json が生成される
【報告してほしいこと】
  - exit code
  - 生成ファイルのパス (snapshots/snapshot-<timestamp>.json)
  - 標準出力末尾の "Captured X entries" 付近
  - 異常終了ならそのエラー行
```

報告を受けたら Claude は snapshot ファイルを `Read` し、エントリ数 / HTTP コード分布 / `000/000000` が混ざっていないこと / 5xx の出方 / 正規化済みボディを確認する。

**⚠ 000/000000 が 1 件でも混ざっていたら 5-0 に戻る** (capture.sh の個別コールで BASE_URL を誤って上書きしている等)。

### 5-2. compare の依頼（全件 NEW の確認）

```text
【コマンド】
  cd <PROJECT_ROOT>
  bash tools/snapshot/snapshot.sh compare
【報告してほしいこと】
  - 生成された compare-report ファイルのパス (snapshots/compare-reports/xxxxx.json)
  - 標準出力の要約 (NEW/REMOVED/CHANGED 件数)
```

Claude は compare-report を `Read` し、差分が全件 NEW（初回ゆえ）であることと、CONTRACT_ERROR が混ざっていないことを確認する。

### 5-3. approve の依頼

```text
【目的】 candidate をマスターに昇格させる
【コマンド】
  cd <PROJECT_ROOT>
  bash tools/snapshot/snapshot.sh approve
【報告してほしいこと】
  - exit code
  - snapshots/snapshot-master.json が更新されたか
```

**重要**: マスター更新は必ず人間がレビューしてから承認する。承認されたマスター diff が「API 変更履歴」になる（`reference/design.md` §5）。Claude が勝手に approve 相当の処理を行わない。

## 5.5. 網羅率の確認 (coverage_report.py)（ユーザ実行）

マスター承認の前に、**異常系・境界値が意図どおり揃っているか**を `coverage_report.py` で確認する。Claude は下記のいずれかを依頼する。

```text
【コマンド (OpenAPI/Swagger がある場合)】
  python3 tools/snapshot/coverage_report.py \
    --spec docs/swagger.yaml \
    --master snapshots/snapshot-master.json \
    --format markdown \
    --output snapshots/coverage-report.md

【コマンド (CI 用: ギャップで exit 1)】
  python3 tools/snapshot/coverage_report.py \
    --spec docs/swagger.yaml \
    --master snapshots/snapshot-master.json \
    --fail-on-gap

【報告してほしいこと】
  - exit code
  - 生成ファイルのパス (snapshots/coverage-report.md)
  - 標準出力の Summary 行 (Endpoint coverage / Suite gaps)
```

Claude は生成された `coverage-report.md` を `Read` し、下記の完了判定を適用する。

**完了判定基準**:
- [ ] エンドポイント網羅率 100%
- [ ] 全保護エンドポイントに `auth` suite がある (最低 `no_api_key` 1 本)
- [ ] 全 POST/PUT エンドポイントに `validation` suite がある
- [ ] 主要エンドポイント (全体の半分以上) に `boundary` suite がある
- [ ] ステータスギャップのうち 401/403/422/404 が未取得ではない

仕様ファイルがないプロジェクトでは `coverage_report.py` は使えないが、Claude が `snapshots/snapshot-master.json` を直接 `Read` して上記 4 suite のバランスを目視で確認する。

## 5.6. 導入完了レポートの生成（Claude 実行可）

approve が通ったら、どんなテストが入ったか（suite 別件数 / HTTP code 分布 / 5xx の想定範囲 / normal suite の非 2xx 理由）を **1 枚の markdown にまとめる**。ユーザへの最終報告で要点を引用するためと、後から「この時点でどんな契約が固定化されたか」を振り返るために使う。

このスクリプトは JSON を読むだけで実 API / 実 DB を叩かないため、**Claude が sandbox 内で直接実行してよい**（ユーザ実行に回す必要はない）。

```text
【コマンド (Claude 実行可)】
  cd <PROJECT_ROOT>
  python3 tools/snapshot/setup_report.py \
    --master snapshots/snapshot-master.json \
    --output snapshots/setup-report.md
【成功判定】
  - exit 0
  - snapshots/setup-report.md が生成される
【Claude の次アクション】
  - 生成された setup-report.md を Read
  - 以下 4 点をユーザに短く要約:
      1. 総エントリ数 / suite 別件数 (正常系・異常系・境界値・破壊系)
      2. 000/000000 混入の有無 (0 件であるべき)
      3. 5xx 件数 (想定内の外部連携エラーか)
      4. normal suite の非 2xx 件数 (seed 不足 / 外部依存 / 業務バリデで説明できるか)
```

`coverage_report.py` は「OpenAPI と master を突き合わせて未カバーを検出」する **事前チェック** 用、`setup_report.py` は「入ったもののサマリ」を出す **事後レポート** 用で、役割が異なる。両方出すのが望ましいが、OpenAPI が無いプロジェクトでは setup_report.py のみで十分。

# 日常運用（導入後の使い方）

下記コマンドは **すべてユーザ実行**。Claude は目的に応じてコマンドを提示し、生成ファイルのパスを共有してもらって `Read` する。

| 目的 | コマンド（ユーザ実行） | Claude が読みに行くファイル |
|---|---|---|
| 回帰チェック | `bash tools/snapshot/snapshot.sh test` | `snapshots/compare-reports/最新.json` |
| 差分内容を見るだけ | `bash tools/snapshot/snapshot.sh compare` | `snapshots/compare-reports/最新.json` |
| 仕様変更の承認 | `bash tools/snapshot/snapshot.sh approve` | `snapshots/snapshot-master.json` の diff |
| 過去マスターからの推移 | `bash tools/snapshot/snapshot.sh history` | `snapshots/history/*.json` |
| マスター削除（やり直し） | `bash tools/snapshot/snapshot.sh reset` | （なし。実行完了の報告のみ） |

failure threshold は `SEVERITY` 環境変数で調整:
- `SEVERITY=informational`（デフォルト, CI 推奨）— どの差分でも fail
- `SEVERITY=compatible` — breaking + compatible で fail
- `SEVERITY=breaking`（ローカル hook 推奨）— breaking のみで fail

詳細フローは `reference/operation-guide.md` を参照。

---

# 差分種別の読み方（`reference/template-README.md` §8）

| 種別 | 意味 | 対応 |
|---|---|---|
| `NEW` | 現行にだけ存在 (新規エンドポイント) | 意図通りなら `approve` |
| `REMOVED` | マスターにだけ存在 (削除 or 未呼び出し退行) | 退行なら修正、廃止なら `approve` |
| `CHANGED` | 同キーで `http_code`/body/型/ヘッダが変化 | レポート精査 → 判断 |
| `CONTRACT_ERROR` | エントリ形式が契約違反 | `capture.sh` のバグ → 必ず修正 |

破壊性ラベル: `breaking` / `compatible` / `informational` がレポートに自動付与される（`reference/template-README.md` §10.2）。

---

# やってはいけないこと

- **毎回 approve で黙殺する**: マスターの価値を壊す。差分が出たら必ず原因を説明できる状態にすること
- **正規化ルールを広げすぎる**: 「とりあえず `*` を `{{ANY}}`」は検知能力を消す。最小限の追加に留める（`reference/normalizer-guide.md`）
- **マッチングキーに URL を入れる**: クエリ順のゆらぎで別エンドポイント扱いになる。`endpoint` は論理名固定
- **本番環境で `record` する**: テストフィクスチャが残る
- **マスターを長期分岐させる**: マージ時に大量差分。仕様変更は小刻みに承認コミット
- **`error` suite を万能袋にする**: `auth` / `validation` / `boundary` を区別せず全部 `error` で済ませると、`coverage_report.py` で網羅不足を検知できなくなる。必ず専用ヘルパ (`call_unauth_*` / `call_invalid_body` / `call_boundary`) を使い分ける
- **正常系だけでマスターを確定する**: PHP/Rails のバージョンアップでは認可ミドルウェアやバリデーションの挙動差が最も漏れやすい。`coverage_report.py --fail-on-gap` が通るレベルまで書いてから承認する
- **FormRequest を読まずにバリデーションテストを書く**: `discovery-checklist.md §3-5` のバリデーション表を埋めてからテストケース化する。発想ベースで書くと必ず漏れる
- **Claude が sandbox 内で実 API / 実 DB を叩こうとする**: サンドボックス環境ではネットワーク・DB アクセスができない。`snapshot.sh record|test|compare|approve` / `reset-db.sh` / `capture.sh` / `coverage_report.py` / `gen_cases.py` は **必ずユーザに実行を依頼し、生成物のパスを共有してもらう**。Claude が自分で Bash 実行して失敗を繰り返さない

---

# プロジェクト特性別オプション（必要になったら導入）

基本テンプレで 90 点。以下は症状が出たときだけ追加する（詳細は `reference/optional-extensions.md`）。

| 拡張 | 導入トリガ |
|---|---|
| A. JSON Schema スナップショット | 暗黙契約を顕在化したい（OpenAPI が無いプロジェクト） |
| C. エンドポイント横断の不変条件 | リレーショナルドメインで横断整合性事故が出た |
| E. プロダクショントラフィック replay | QA と本番で挙動乖離事故があった |
| F. Property-Based / Fuzzing 連携 | バリデーションバグが頻発 |
| G. ミューテーションテスト | 成熟期、テスト自体の信頼性を数値化したい |

**全部は入れない。** 基本テンプレを運用してから症状が出たものだけ。

---

# snapshot で守らない領域（別ツールへ委譲）

「**レスポンスだけ見れば分かるか？**」が NO なら snapshot 不適。`reference/template-README.md` §12 を参照。

| 領域 | 適した手段 |
|---|---|
| 性能・スループット | k6, Locust, JMeter |
| セキュリティ脆弱性 | Semgrep (SAST), ZAP (DAST) |
| DB 状態の変化 | アプリ統合テスト (PHPUnit/pytest) |
| 業務仕様の正しさ | 仕様書 + 人間レビュー + 受け入れテスト |
