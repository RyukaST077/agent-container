# Discovery Checklist — 導入前の必須調査

`reset-db.sh` と `capture.sh` を書く**前**に、必ずこのチェックリストを上から順に埋めること。
ここを飛ばすと「シーダーが FK 違反で落ちる」「全エンドポイントが 403」「リクエストボディが 400 Bad Request」など、
あとで何往復もデバッグすることになる既知の失敗パターンにほぼ確実にハマる。

目安: **小〜中規模プロジェクトで 30 分〜1 時間**。この時間を惜しむと後工程で 3〜5 時間飛ぶ。

---

## 0. 全体像の把握

- [ ] 対象 API の Laravel / Rails / Django 等のフレームワークとメジャーバージョン
- [ ] API が参照する DB は 1 つか複数か (マルチ DB 構成なら接続名を列挙)
- [ ] Docker コンテナ名 (`docker ps --format '{{.Names}}'`)
- [ ] 対象 API の公開ポート (`docker port <container>`)
- [ ] **BASE_URL の到達確認 (ホスト → コンテナの疎通)**:
  ```bash
  curl -sS -o /dev/null -w "HTTP %{http_code}\n" $BASE_URL/v1/<軽い GET>
  ```
  200 / 401 / 403 のいずれかが返らないなら、port / コンテナ名 / docker ネットワーク (WSL ↔ Windows のポートフォワード含む) を先に解決する。これを飛ばすと後工程で **全エンドポイントが `http_code=000000`** になる。
- [ ] 既存の開発環境構築ドキュメント (`docs/dev/*.md`, `README.md` 等) の有無 — **API キー登録手順など金脈情報あり**

---

## 1. DB スキーマ調査

### 1-1. マイグレーション配置

- [ ] マイグレーションファイルの配置パス
  ```bash
  ls -la database/migrations/
  # → サブディレクトリがあるか?
  #    例: cms/, app/ に分かれている場合は --path 指定が必須
  ```
- [ ] **`migrate:fresh --path=<サブディレクトリ>` が必要か、デフォルトで良いか**

### 1-2. シーダーの実行順序と FK 依存

- [ ] シーダーファイル一覧: `ls database/seeds/ || ls database/seeders/`
- [ ] 各シーダーが INSERT するテーブル:
  ```bash
  grep -HE "DB::table|->insert|::create" database/seeds/*.php
  ```
- [ ] **FK 制約の有無** (これで順序が決まる):
  ```bash
  grep -rE "foreign\(|references\(" database/migrations/
  ```
- [ ] シーダー間の依存関係を紙に図示: 「A は B の INSERT 後でないと動かない」

> **よくある罠**: `SampleDataSeeder` が `areas` に `default_lang_code = 'ja'` を入れるが、
> `LanguageSeeder` が先に走っていないと `languages` テーブルが空で FK 違反になる。

### 1-3. 認証・API キー関連テーブルのスキーマ

- [ ] API キーを保持するテーブル名 (候補: `api_keys`, `application_api_keys`, `access_tokens`)
- [ ] **そのテーブルに `id` カラムがあるか** (プライマリキーが `api_key` 自体のケースあり)
- [ ] `DESCRIBE <table>;` の結果をメモ (カラム名・NOT NULL・DEFAULT)

```bash
docker exec <db-container> mysql -uroot -p<password> <db> -e "DESCRIBE <table>;"
```

- [ ] **シーダーが API キーを固定値で INSERT するか、ランダム生成するか**:
  ```bash
  grep -rnE "api_key|generateApiKey|uniqid|random_bytes|Str::random" database/seeds/ database/seeders/
  ```
  - **固定値 INSERT** → そのまま FIXTURE_API_KEY として使う
  - **ランダム生成 (`ApplicationApiKey::generateApiKey()` / `uniqid()` / `Str::random()` 等)** →
    reset-db.sh で `DELETE FROM <keys_table> WHERE <条件>; INSERT ... VALUES ('test-api-key-local', ...)` で上書き。
    **`INSERT IGNORE` では既存ランダム値が UNIQUE 制約を握り続けるので失敗する**。

### 1-4. fixture 投入先テーブル

スナップショットで叩くエンドポイント (QR コード / シリアルコード / 注文 / 在庫等) が参照するテーブル:

- [ ] テーブル名を曖昧検索: `SHOW TABLES LIKE '%qr%';`
- [ ] 中間テーブルのカラム名 (`group_id` なのか `serial_code_group_id` なのか等)
- [ ] 各テーブルの必須カラム

---

## 2. API エンドポイント調査

### 2-1. ルートファイルと認証

- [ ] ルートファイル (`routes/api.php`, `routes/api_v1.php` 等)
- [ ] 全エンドポイント共通ミドルウェア (`api`, `api.v1`, `auth:api` 等)
- [ ] ミドルウェアの実装を読み、**どのヘッダが必須か**を確認:
  ```bash
  grep -HrE "header\(|hasHeader\(|->getHeader" app/Http/Middleware/
  ```
- [ ] よくある必須ヘッダ: `x-api-key`, `Authorization`, `x-os-type`, `x-app-version`, `x-lang-code`

### 2-2. OS / プラットフォーム別分岐

- [ ] **iOS/Android で別ルート** になっているか (`/ios/*`, `/android/*` 等)
- [ ] 別ルートがある場合、ヘッダ (`x-os-type`) でバリデーションしているか
  ```bash
  grep -rE "getOSTypeHeader|x-os-type|platform" app/Http/
  ```
- [ ] 別ルートのヘッダ要件をメモ (例: `/payments/android/*` → `x-os-type: android` 必須)

### 2-3. ID エンコーディング

- [ ] リクエストパス / クエリで受け取る ID の形式 (`id-N` / UUID / 暗号化文字列 / 連番)
- [ ] デバッグモードの有無 (`ID_ENCRYPT_DEBUG=true` 等) と形式
- [ ] レスポンスに返る ID の形式 (リクエストと同形式か別形式か)
- [ ] `IdConverter::fromApi()` 等の変換関数の存在

### 2-4. 非決定的レスポンスを返すエンドポイントの洗い出し

**これを埋めないと初回 approve 後の compare で必ず diff が出て、CI が即日壊れる。**

診断系エンドポイントは `REQUEST_TIME` / opcache 統計 / プロセス PID / uptime などを含みやすく、
2 回叩けば必ず差分が出る。初回 `approve` の **前** に `normalizer_rules.json` の
`skip_body_endpoints` に登録する必要がある。

調査方法:

```bash
# phpinfo() を返す実装を検索
grep -rnE "phpinfo\(|PhpInfoController" app/ routes/ 2>/dev/null

# サーバ情報系・ヘルスチェック系のルート
grep -rnE "server-info|server-status|/health|/metrics|/debug" routes/ 2>/dev/null
```

- [ ] **phpinfo を返すエンドポイント** (Laravel 系なら `DebugController@info` などが典型)
- [ ] ヘルスチェック系 (現在時刻 / uptime / キュー統計などを含む場合)
- [ ] ログビュアー・メトリクス系 (動的カウンタ / アクセス数)
- [ ] サーバ情報系 (`/server-info`, `/phpmyinfo` 等)
- [ ] Laravel `/v1/sleep1` `/v1/headers` `/v1/logging` 等の動作確認用 stub endpoints

洗い出した論理名を `skip_body_endpoints` に登録する:
```json
"skip_body_endpoints": ["info", "debug.sleep1", "debug.headers", "debug.logging", "admin.metrics"]
```

比較は `http_code` と (有効化していれば) `response_headers` でのみ行われる。
body diff の誤検知を防ぎつつ、ステータスコードの退行は検知し続けられる。

---

## 3. リクエストバリデーション調査

**各エンドポイントを叩く前に** Request クラスを全部読むこと。
適当なボディで叩いて「400 で出てから直す」は往復が多すぎる。

### 3-1. Request クラスの rules()

- [ ] 対象エンドポイントの FormRequest クラスの `rules()` を読む
- [ ] 各フィールドの型 (**`integer` 指定なら数値リテラル必須、`"1"` 文字列は NG**)
- [ ] 必須 (`required`) vs 任意 (`nullable`)
- [ ] enum 制約 (`in:0,1,2` 等) の許容値

### 3-2. カスタム Rule クラス

- [ ] `['required', new SomeRule($x, $y)]` のようなカスタム Rule があれば、そのクラスを読む
- [ ] 条件付きバリデーション (例: `address_status=1` なら 7 桁必須、`=2` なら別許容値)

### 3-3. 相関バリデーション

- [ ] 複数フィールドが相互依存していないか (`area_id` + `channel_id` + `spot_id` が DB 上で紐付いていること等)
- [ ] 該当があれば、seeder データでその組み合わせが成立しているかを確認

### 3-4. 日時・数値フォーマット

- [ ] `date_format:Y-m-d\TH:i:s\Z` のような厳格なフォーマット指定
- [ ] 桁数制約 (`max:255`, 郵便番号の 7 桁等)
- [ ] 通貨コードの ISO 形式 (`JPY`, `USD` 等)

### 3-5. バリデーション表の作成（capture.sh 設計入力）

**3-1 〜 3-4 で集めた情報をここで「テストケース設計用の表」に落とし込む**。
この表が埋まっていれば、`reference/test-case-matrix.md` のマトリクスに沿って
`call_invalid_body` / `call_boundary` を機械的に並べられる。

各 POST/PUT エンドポイントについて以下の表を 1 つ埋める:

```
## POST /v1/users/register のバリデーション表

| field          | required | type    | 制約              | 異常系で試す値                    | 境界値                    |
|----------------|----------|---------|-------------------|-----------------------------------|---------------------------|
| nick_name      | ◯        | string  | max:20            | 欠落 / 数値 / ""                   | 20文字 / 21文字 / マルチバイト |
| address_status | ◯        | int     | in:0,1,2          | 欠落 / 3 / -1 / "0" (文字列)       | 0 / 2                     |
| address_code   | 条件付き | string  | address_status=1 のとき 7桁数字 | address_status=1 で欠落 | "1234567"     |
| gender         | ◯        | int     | in:0,1,2          | 欠落 / 3 / "1" (文字列)            | 0 / 2                     |
| birth_year     | ◯        | int     | between:1900,2100 | 欠落 / "1990" (文字列) / "abc"    | 1900 / 2100 / 1899 / 2101 |
```

### 表の列の埋め方

| 列 | 情報源 | 例 |
|---|---|---|
| field | FormRequest の `rules()` | `nick_name` |
| required | `rules()` 内の `required` 有無 | ◯ / ✗ / 条件付き |
| type | `string` / `integer` / `numeric` / `array` / ... | int |
| 制約 | `max:20` / `in:0,1,2` / `between:a,b` / `date_format:...` / カスタム Rule | max:20 |
| 異常系で試す値 | → `call_invalid_body <endpoint> <case_name> ...` で書く | 欠落 / 型違反 / enum外 |
| 境界値 | → `call_boundary <endpoint> <case_name> ...` で書く | min / max / ±1 / マルチバイト |

### テストケース名への変換

表の「異常系で試す値」「境界値」列はそのまま `case_name` になる:

| 表の値 | case_name の例 | 生成される endpoint |
|---|---|---|
| `nick_name` 欠落 | `missing_nick` | `users.register.missing_nick` |
| `gender` が 3 | `bad_gender` | `users.register.bad_gender` |
| `birth_year` に "abc" | `bad_birth_year_type` | `users.register.bad_birth_year_type` |
| `nick_name` 20文字 | `nick_max` | `users.register.nick_max` |
| `nick_name` 21文字 | `nick_over_max` | `users.register.nick_over_max` |
| `birth_year` 1900 | `birth_min` | `users.register.birth_min` |
| `birth_year` 1899 | `birth_under_min` | `users.register.birth_under_min` |

### この表を埋めたあとに行うこと

1. **`reference/test-case-matrix.md`** を開いて、このエンドポイントが型 A〜G のどれか分類する
2. マトリクスの観点列を見ながら表の「異常系」「境界値」列を追記・調整（抜けがあれば FormRequest に戻って確認）
3. `capture.sh` の **3. バリデーション系** セクションに `call_invalid_body` を並べる
4. `capture.sh` の **4. 境界値系** セクションに `call_boundary` を並べる
5. `bash tools/snapshot/snapshot.sh record` でキャプチャ
6. `python3 tools/snapshot/coverage_report.py` で網羅率を確認

**重要**: バリデーション表を埋めずに capture.sh を書くと、必ず「何が不足しているか分からない」状態になる。先に表を埋めること。

---

## 4. レスポンス形式調査

### 4-1. 成功レスポンスの構造

- [ ] 登録系の返却 ID のキー名:
  - `{"id":"..."}` か
  - `{"user_id":"..."}` か
  - `{"data":{"id":"..."}}` か
  - その他カスタム
- [ ] `capture.sh` の `SNAPSHOT_USER_ID` 抽出コードの候補リストを準備

### 4-2. エラーレスポンスの構造

- [ ] エラーペイロードの形式 (`{"error":{"message":"...", "code":"...", "previous":{...}}}` 等)
- [ ] スタックトレースが含まれるか (正規化対象になる)

### 4-3. 外部サービス連携エンドポイント

- [ ] Apple IAP / Google Play / SMS / 決済 ゲートウェイ等、**ローカルでは必ずエラーが返るエンドポイント**
- [ ] 500 になる (JWS 検証失敗等) vs 400 になる (検証前のバリデーション落ち) の区別
- [ ] これらは **ベースラインとしてエラーを固定化** する方針でよいか

---

## 5. ビジネスロジック上の可視性制約

**「DB に入っているが API から見えない」罠**を事前に潰す。

- [ ] `publish_scope` / `enabled` / `status` / `is_active` 等の**公開状態フラグ**
  - シーダーのデフォルトが「非公開」だと、API は 404 を返す
- [ ] **SoftDeletes** (`deleted_at`) の有無 — capture.sh で DELETE を先に叩くと後続が全滅する
- [ ] **ユーザー×エリアの紐付け** (`user_organization`, `user_area` 等) — 未紐付けだと 403
- [ ] **キャッシュの存在** (`config:cache`, Redis 等) — DB リセット後の stale cache で API が古い値を返す

---

## 6. 既存開発ドキュメントの参照

**金脈情報**: プロジェクト内に既に開発環境構築手順があれば、**先に読む**。

- [ ] `README.md`, `docs/dev/*.md`, `CONTRIBUTING.md` 等
- [ ] **特に「テスト用 API キー登録」「初期ユーザー登録」「シーダー順序」「DB リセット手順」** の章
- [ ] ドキュメントに固定 API キー (`test-api-key-local` 等) があれば、それを `FIXTURE_API_KEY` のデフォルト値に採用する
  - → これで fixture.env が無くても capture.sh が動く
- [ ] **OpenAPI / Swagger 仕様ファイルの有無と所在**:
  ```bash
  # よくある配置を一通り見る
  ls docs/swagger.yaml docs/swagger.yml docs/openapi.yaml docs/openapi.yml 2>/dev/null
  ls storage/api-docs/ public/api-docs/ 2>/dev/null
  find . -maxdepth 5 -type f \( -iname "swagger.*" -o -iname "openapi.*" \) \
    -not -path "*/node_modules/*" -not -path "*/vendor/*" 2>/dev/null
  # Laravel l5-swagger / swagger-php アノテーション型
  grep -rlE "@OA\\\\|@SWG\\\\" app/ 2>/dev/null | head -5
  ```
  - 見つかれば `gen_cases.py` / `coverage_report.py` の `--spec` にそのまま渡せる
  - アノテーション型で YAML 未生成なら、**先に生成コマンド** (`php artisan l5-swagger:generate` 等) を流す手順をユーザに依頼する
  - 見つからなければ SKILL.md Step 3 を手書き起点で進める（`gen_cases.py` は使えない）

---

## 7. 調査結果の書き出し

以下を `reset-db.sh` の先頭コメント or プロジェクトの `docs/snapshot-setup.md` にメモしておく:

```
## 調査結果 (snapshot 導入前)

### DB
- コンテナ名: <name>
- マイグレーションパス: database/migrations/<subdirs>
- シーダー順序: <seeder1> → <seeder2> → ...
- API キーテーブル: <table>, PK=<column>

### API
- ベース URL: <url>
- 共通ヘッダ: x-api-key, x-os-type (ios/android), x-app-version
- ID 形式: id-N (デバッグモード)
- 登録レスポンス: {"id": "..."}

### バリデーション要点
- POST /v1/users/register
  - address_status=1 のとき address_code は 7 桁数字
  - gender/birth_year は integer 必須
- POST /v1/users/history
  - area_id + channel_id + spot_id が紐付きである必要 (HistorySpotRule)

### 既知のベースライン (エラーが正しい)
- /v1/payments/ios/* → 500 (JWS 検証失敗)
- /v1/payments/android/* → 400 (Account required)

### skip_body_endpoints 候補 (非決定的 HTML を返すため body 比較を外す)
- info             (phpinfo — REQUEST_TIME / opcache 統計)
- debug.sleep1     (診断 stub)
- debug.headers    (リクエストヘッダエコー)
- debug.logging    (ログ系診断)
```

---

## チェックリスト通過の最低ライン

このチェックリストのうち、**以下の 9 項目が埋まるまでは `capture.sh` を書き始めない**:

1. [ ] マイグレーションパス (`--path` が要るか)
2. [ ] シーダー順序 (FK 依存の解決済み)
3. [ ] API キーテーブルのカラム構造
4. [ ] API キーの取得方法 (固定値 vs ランダム生成) + **ランダム生成なら DELETE→INSERT 方針を確定**
5. [ ] 対象 API の必須ヘッダ一覧
6. [ ] ID エンコーディング形式
7. [ ] 登録系エンドポイントのレスポンス ID キー名
8. [ ] **BASE_URL の到達確認** (§0 の curl が 200/401/403 を返す) — ここが通らないと record が全件 `000000` で無駄になる
9. [ ] **非決定的レスポンスを返すエンドポイントのリスト** (§2-4) を作り、`skip_body_endpoints` に登録する候補を確定

この 9 つさえ押さえれば、初回 record → approve まで 1 ラウンドで通る。
8 と 9 は過去の導入で実際に踏んで大幅手戻りになった項目なので、必ず潰してから次に進む。

### 異常系・境界値も取る場合の追加 4 項目

正常系だけでなく異常系・境界値スナップショット（`reference/test-case-matrix.md` 参照）も
導入する場合は、さらに以下 4 項目を埋めてから capture.sh を書く:

10. [ ] **§3-5 のバリデーション表** を対象 POST/PUT エンドポイント全件ぶん埋めた
11. [ ] **もう1人のテストユーザー** を作る（`FIXTURE_USER_ID_OTHER`）— 権限分離 auth テスト用。`reset-db.sh` の「5. テストユーザー登録」を2回実行して `fixture.env` に書き出す
12. [ ] 認証必須エンドポイントについて、**401/403 を返す最小ヘッダセット**を特定（例: `x-api-key` のみ欠落させた場合の挙動）
13. [ ] `reference/test-case-matrix.md` の型 A〜G に対象エンドポイントを分類した一覧
