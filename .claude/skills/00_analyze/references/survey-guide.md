# 調査ガイド（survey-guide）

各フェーズの調査手順・言語/FW 別の手掛かり・証拠記法。フェーズは順番に実行する。

---

## 共通：証拠記法と AS-Is ヘッダ

### 証拠記法

すべての記述の末尾または「根拠」列に、次のいずれかを付ける：

- ファイル根拠: `根拠: composer.json:15`／`根拠: app/Http/Kernel.php`
- コマンド根拠: `根拠: \`git log --oneline | head -1\` → abc1234`
- 信頼度: `[確認済]` `[推定 → ASM-xxx]` `[不明 → UNK-xxx]`

### AS-Is ヘッダ（全成果物の冒頭に必ず挿入）

```markdown
> **本書はコードベース調査から生成された AS-IS ドキュメントです（00_analyze）**
>
> | 項目 | 内容 |
> | -- | -- |
> | 生成日 | YYYY-MM-DD |
> | 対象コミット | `git rev-parse --short HEAD` の結果 |
> | 対象ブランチ | ブランチ名 |
> | 信頼度凡例 | [確認済] = コードで裏取り済 / [推定] = 状況証拠から推測（ASM 台帳参照） / [不明] = 要確認（UNK 台帳参照） |
```

- 生成日・コミットはコマンドで実際に取得する（`git rev-parse --short HEAD`、`git branch --show-current`）。

---

## フェーズ 0：セットアップ

1. リポジトリ直下を一覧し、モノレポか単一サービスかを判定する
2. README・既存ドキュメント（`docs/`、Wiki 参照等）の有無を確認する
3. `git log --oneline | head -20` で直近の開発活動を把握する
4. AskUserQuestion で **ゲート 0**（SKILL.md 記載の 4 項目）を確認する

---

## フェーズ 1：全体像 → 01_System_Overview / 02_Tech_Stack / 03_Code_Structure

### 技術スタックの手掛かり（マニフェストファイル）

| ファイル | 言語/エコシステム | 読み取れること |
| -- | -- | -- |
| `package.json` / `package-lock.json` | Node.js / フロントエンド | 依存・スクリプト（build/test/start）・エンジン指定 |
| `composer.json` / `composer.lock` | PHP | FW（laravel/framework 等）と依存バージョン |
| `pom.xml` / `build.gradle(.kts)` | Java / Kotlin | FW・Java バージョン・モジュール構成 |
| `requirements.txt` / `pyproject.toml` / `Pipfile` | Python | 依存・ツールチェーン |
| `go.mod` | Go | モジュール名・依存 |
| `Gemfile` | Ruby | Rails 等の FW と依存 |
| `*.csproj` / `*.sln` | .NET | ターゲットフレームワーク・依存 |
| `Dockerfile` / `docker-compose.yml` | — | ランタイムバージョン・ミドルウェア（DB/Redis/MQ）・起動方法 |
| `.github/workflows/` / `Jenkinsfile` / `.gitlab-ci.yml` | — | ビルド/テスト/デプロイの実手順（**最も信頼できる起動手順の証拠**） |
| `.env.example` / `config/` | — | 必要な環境変数・接続先の種類 |

### バージョンの EOL 確認

主要ランタイム・FW のバージョンを特定したら、知識の範囲で EOL（サポート終了）状況を記載する。
自信がなければ `[推定]` を付け、正確な確認が必要なものは UNK に落とす（Web 検索可能な環境なら確認してよい）。

### コード構成

1. ディレクトリツリーを深さ 2〜3 で取得（vendor / node_modules / 自動生成物は除外）
2. レイヤ構成を判定する（MVC / レイヤード / クリーンアーキテクチャ / 特に無し）— 判定根拠となるディレクトリ・基底クラスを記録
3. モジュール間依存の概要を Mermaid で図示（厳密な全依存でなく、主要な流れで良い）
4. 観察できた規約（命名・ファイル配置・エラー処理パターン）をメモする — `feature-constitution` の入力になる

---

## フェーズ 2：エントリポイント棚卸し → 04_Entry_Points

「外部から本システムの処理を起動できる口」をすべて列挙し、`EP-001` から採番する。

### 種別と手掛かり

| 種別 | 手掛かり |
| -- | -- |
| 画面（サーバレンダリング/SPA ルート） | ルーティング定義（`routes/web.php`、`urls.py`、React Router / Vue Router 定義等）、テンプレート/ページディレクトリ |
| API | `routes/api.php`、`@RestController` / `@RequestMapping`、`urls.py` + DRF、OpenAPI 定義（`openapi.yml` / `swagger.json`） |
| バッチ / CLI | `routes/console.php`、`artisan` コマンド、`management/commands/`、`main()` を持つ CLI、シェルスクリプト |
| スケジュール | crontab、`Kernel.php` の `schedule()`、`@Scheduled`、CloudWatch Events / cron 系 IaC 定義 |
| キュー / イベント購読 | ジョブ/リスナークラス、Kafka/SQS/RabbitMQ のコンシューマ定義 |
| その他 | Webhook 受け口、SFTP 取り込み、ファイル監視 |

- **PHP / Laravel の場合は `check-endpoints` スキルの手順をそのまま使い**、結果をテンプレートの表形式に転記する。
- 正規化ルール: パスパラメータ違い・クエリ違いは同一 EP に統合する。
- 動的に組み立てられるルートやプラグイン経由のルートは「未確定候補」として別表に残す（消さない）。

---

## フェーズ 3：データ → 05_Data_Overview

### 手掛かり（信頼度の高い順）

1. **マイグレーション / DDL**：`migrations/`、`db/migrate/`、`schema.rb`、`*.sql` — テーブル定義の一次証拠
2. **ORM モデル**：Eloquent モデル、JPA `@Entity`、Django モデル等 — リレーションとビジネス上の意味
3. **実 DB スキーマ**：ローカル/開発 DB に接続できる場合のみ、読み取り専用で情報スキーマを参照してよい（**ゲート 0 で許可を得た場合のみ。本番接続は禁止**）

### 記載すること

- テーブル一覧（名前・役割 1 行・主キー・主要な外部キー・定義根拠）
- 主要エンティティ（10〜20 個目安）の ER 概要を Mermaid `erDiagram` で図示
- 論理削除・監査列・マルチテナント列などの横断パターン
- スキーマとモデルの食い違いがあれば DEBT として記録

---

## フェーズ 4：外部連携 → 06_External_Interfaces

1. HTTP クライアント呼び出し（`Guzzle`、`HttpClient`、`axios`、`requests` 等）の呼び出し先を洗い出す
2. SDK 依存（AWS SDK、決済 SDK、メール送信 SDK 等）から連携先を推定する
3. 設定ファイル・環境変数のエンドポイント URL / API キー名から連携先を裏取りする
4. ファイル連携（SFTP/S3 取り込み・出力）、メッセージング（キュー間連携）も含める
5. `EXT-001` から採番し、方向（送信/受信/双方向）・方式・認証・実装位置を表にする

---

## フェーズ 5：品質・負債 → 07_Quality_Assessment

### テスト状況

- テストディレクトリとテスト件数（`find tests -name "*Test*" | wc -l` 等）
- テストの種類（単体/結合/E2E）と実行方法（CI 定義が一次証拠）
- 実行してよい環境なら実際にテストを流し、結果（成功/失敗数）を記録する

### 静的シグナル

- 巨大ファイル: `git ls-files '*.<ext>' | xargs wc -l | sort -rn | head -20`
- TODO/FIXME/HACK 件数: `grep -rn "TODO\|FIXME\|HACK" --include="*.<ext>" | wc -l`
- 変更ホットスポット（直近 1〜2 年で変更頻度が高いファイル）:
  `git log --since="2 years ago" --format= --name-only | sort | uniq -c | sort -rn | head -20`
  → 変更頻度が高い × 行数が多いファイルは、追加開発時の高リスク箇所として DEBT に記録

### 依存リスク

- EOL 済み / メジャーバージョンが大きく遅れている依存
- ロックファイルと宣言の乖離、fork されたままの依存

### 台帳の整理

- `DEBT-xxx`：負債・リスク（影響度 高/中/低 と、追加開発時の注意を 1 行で）
- `ASM-xxx`：推定した事項（本文の `[推定]` をすべて集約）
- `UNK-xxx`：不明・要確認事項（**誰に/どこで確認すべきかの見当**も書く）

---

## フェーズ 6：サマリと最終レビュー

1. `01_System_Overview.md` の冒頭サマリ（システムの目的・規模感・主要リスク 3 点）を完成させる
2. 全成果物の相互参照（EP ↔ EXT ↔ DEBT の ID 参照）が壊れていないか確認する
3. AskUserQuestion で **最終ゲート**：
   - [ ] UNK（不明点）の一覧を提示し、ユーザが回答できるものを回収したか
   - [ ] 調査スコープ外とした範囲に合意したか
   - [ ] 次のステップ（`generate-design-docs` / `feature-constitution`）を選んだか
