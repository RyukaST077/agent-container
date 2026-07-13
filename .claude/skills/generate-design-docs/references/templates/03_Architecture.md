# アーキテクチャ設計書

## 0. ドキュメント情報
| 項目 | 内容 |
| -- | -- |
| システム名 | [System Name] |
| 対象スコープ | [対象機能/境界] |
| バージョン | 1.0 |
| 作成日 | YYYY-MM-DD |
| 作成者 | [Name] |
| 承認者 | [Name] |
| 更新方針 | 変更時に必ず更新（設計レビューで確認） |

## 1. アーキテクチャ概要
### 1.1 目的・前提
- **目的**: ビジネス要件・非機能要件を満たすための構成方針を明文化する
- **前提条件**: 利用者数、ピーク負荷、外部依存、データ保持要件を明記

### 1.2 アーキテクチャスタイル
**採用方針**: モノリシック・レイヤードアーキテクチャ（初期フェーズ）

**採用理由**:
- **チーム規模**: 開発チーム5名程度の小〜中規模プロジェクト
- **ビジネス複雑度**: ドメインが明確で境界が曖昧でない
- **デプロイ頻度**: 週次リリースで十分（初期は品質重視）
- **運用コスト**: マイクロサービスの分散システム運用のオーバーヘッドを避ける
- **開発速度**: 初期の市場投入スピードを優先

**将来展望**: ユーザー数が10万人を超え、機能ドメインが明確に分離できる段階でマイクロサービス化を検討

### 1.3 要件トレーサビリティ（Business/NFR → Architecture）
| 要件ID | 要件 | 影響する設計要素 | 根拠/測定方法 |
| -- | -- | -- | -- |
| NFR-001 | P95 500ms | キャッシュ戦略、DB接続プール | APM計測、負荷試験 |
| NFR-002 | 可用性 99.9% | Multi-AZ、ヘルスチェック | 稼働率計測 |
| NFR-003 | 個人情報保護 | 暗号化、マスキング | 監査ログ、スキャン |

### 1.4 アーキテクチャ決定記録（ADR）
すべてのアーキテクチャ上の重要な意思決定は、以下の形式でドキュメント化し、`docs/adr/`ディレクトリで管理します。

**ADRテンプレート**:
```markdown
# ADR-001: [タイトル]
* Status: Accepted / Superseded / Deprecated
* Date: YYYY-MM-DD
* Decision Makers: [名前]

## Context
[意思決定が必要になった背景]

## Decision
[採用した方針]

## Consequences
[この決定による影響（良い点・悪い点）]
```

**既存ADR**:
- [ADR-001: PostgreSQL採用](../adr/001-postgresql.md)
- [ADR-002: React + TypeScript採用](../adr/002-react-typescript.md)
- [ADR-003: モノリシックアーキテクチャ採用](../adr/003-monolithic-architecture.md)

## 2. 技術スタック
### 2.1 クライアントサイド
| カテゴリ | 技術・ツール | バージョン | 選定理由 | 更新方針 |
| -- | -- | -- | -- | -- |
| 言語 | TypeScript | 5.x | 型安全性確保のため | LTS/安定版を追従 |
| フレームワーク | React | 18.x | 開発効率とパフォーマンス | 四半期ごとに追随可否を判断 |

### 2.2 サーバーサイド
| カテゴリ | 技術・ツール | バージョン | 選定理由 | 更新方針 |
| -- | -- | -- | -- | -- |
| 言語 | Go | 1.21 | 高速な実行速度 | 1年以内に最新安定版へ |
| フレームワーク | Gin | 1.9 | 軽量・高速 | マイナー更新を随時 |

### 2.3 データベース・ストレージ
| カテゴリ | 技術・ツール | バージョン | 選定理由 | 更新方針 |
| -- | -- | -- | -- | -- |
| RDBMS | PostgreSQL | 15.x | 信頼性と機能性 | メジャー更新前に互換性検証 |
| Cache | Redis | 7.x | セッション管理高速化 | 互換性のある更新のみ |

### 2.4 インフラ・環境
| カテゴリ | サービス・ツール | 用途 | 管理主体 |
| -- | -- | -- | -- |
| Cloud Provider | AWS | インフラ基盤 | Platform Team |
| Container | Docker | 開発・実行環境の統一 | Dev Team |
| IaC | Terraform / CloudFormation | インフラ定義 | Platform Team |

## 3. システム構成図
### 3.1 C4 Model - Level 1 (Context)
```mermaid
C4Context
    title System Context for [System Name]

    Person(user, "User", "Webブラウザを利用")
    System(system, "[System Name]", "提供サービス")
    System_Ext(payment, "Payment Provider", "決済サービス")
    System_Ext(erp, "ERP", "売上連携")

    Rel(user, system, "Uses")
    Rel(system, payment, "Charges", "HTTPS")
    Rel(system, erp, "Sends sales", "SFTP")
```

### 3.2 C4 Model - Level 2 (Container)
```mermaid
C4Container
    title Container Diagram for [System Name]

    Person(user, "User", "Webブラウザを利用")
    Container(spa, "SPA", "React, TypeScript", "フロントエンドアプリ")
    Container(api, "API Application", "Go, Gin", "ビジネスロジック")
    ContainerDb(db, "Database", "PostgreSQL", "メインデータストア")
    ContainerDb(cache, "Cache", "Redis", "セッション/キャッシュ")

    Rel(user, spa, "HTTPS", "Uses")
    Rel(spa, api, "HTTPS/JSON", "API Calls")
    Rel(api, db, "TCP", "Reads/Writes")
    Rel(api, cache, "TCP", "Reads/Writes")
```

### 3.3 ソフトウェア構成図
```mermaid
graph TB
    subgraph "Application Server (ECS on Fargate)"
        ALB[Application Load Balancer]
        APP1[App Instance 1<br/>Go + Gin]
        APP2[App Instance 2<br/>Go + Gin]
        ALB --> APP1
        ALB --> APP2
    end

    subgraph "Data Layer"
        RDS_M[(PostgreSQL<br/>Primary)]
        RDS_S[(PostgreSQL<br/>Standby)]
        REDIS[(Redis Cluster)]
        S3[S3 Bucket<br/>Static Assets]
    end

    subgraph "External Services"
        CW[CloudWatch Logs/Metrics]
        DD[Datadog]
    end

    APP1 --> RDS_M
    APP2 --> RDS_M
    RDS_M -.replication.-> RDS_S
    APP1 --> REDIS
    APP2 --> REDIS
    APP1 --> S3
    APP1 --> CW
    CW --> DD
```

### 3.4 データフロー/信頼境界
- **信頼境界**: Internet → ALB → App → DB/Cache
- **機密データ経路**: ユーザー情報、決済関連情報は暗号化経路のみ通過
- **データ分類**: PII / Transaction / Public の3分類（詳細はデータ設計書）

## 4. API Gateway 構成
**採用**: Application Load Balancer (ALB)

**機能**:
- パスベースルーティング（`/api/v1/*` → Backend Service）
- ヘルスチェック（`GET /health`）
- TLS終端（証明書はACMで管理）

**レート制限**:
- **実装場所**: AWS WAF または アプリケーションレイヤーのレートリミッター
- **初期値**: 1 IP あたり 100 req/min（要検証）

**将来的な検討事項**:
- API Gateway（AWS）への移行: 認証・認可、スロットリング、APIキー管理が複雑化した場合

## 5. Documentation as Code
- **管理方法**: 設計書はMarkdownで記述し、`docs/`配下で管理する。
- **図の描画**: Mermaid.jsを使用し、修正が容易な状態を維持する。
- **更新フロー**: コード変更PRには対応ドキュメント更新を必須化。

## 6. 非機能要件の実装方式
### 6.1 可用性設計
**目標値**:
- **稼働率（Availability）**: 99.9%（年間ダウンタイム: 8.76時間以内）
- **RTO**: 30分以内
- **RPO**: 5分以内（WALアーカイブ間隔）

**実装方式**:
- **Webサーバー**: Multi-AZ構成、ALBによる負荷分散、最小2インスタンス
- **DBサーバー**: マスタ・スタンバイ構成（自動フェイルオーバー有効）
- **キャッシュサーバー**: Redis Cluster（3ノード、レプリカ有効）
- **ヘルスチェック**:
  - ALB → Backend: `/health`エンドポイント（10秒間隔）
  - 異常検知後の自動切り離し: 連続3回失敗時

**障害分離・サーキットブレーカー**:
- 外部API呼び出しに対してサーキットブレーカーパターンを適用
- 閾値: 10秒以内に50%以上の失敗 → Open状態（30秒間）
- ライブラリ: `sony/gobreaker`（Go実装）
- フォールバック戦略: キャッシュデータ返却 or デフォルト値返却

### 6.2 性能・拡張性設計
**目標値**:
- **レスポンスタイム**: P95 500ms以内（API呼び出し）/ P99 1秒以内
- **スループット**: 1,000 req/sec（ピーク時）
- **同時接続数**: 10,000セッション

**負荷モデル**:
- ピークトラフィックの想定、リクエスト比率、外部API比率を明記
- 想定より上振れした場合のスケール上限/抑制策を定義

**実装方式**:
- **スケーリング戦略**: ECS Auto Scaling（CPU 70%でスケールアウト、最小2/最大10）
- **キャッシュ戦略**: マスタデータ1時間、セッション24時間、静的ファイル7日
- **DB接続プール**: 最大100接続、アイドルタイムアウト5分
- **クエリ最適化**: スロークエリログ監視（1秒以上）

### 6.3 セキュリティ設計
**ネットワークセキュリティ**:
- 通信の暗号化（TLS 1.3）
- VPC内でプライベートサブネット配置（DB、Redisは外部アクセス不可）
- Security Group: 最小権限の原則（Whitelist方式）
- WAF: SQLインジェクション、XSS検出ルール

**認証・認可**:
- 認証方式: OAuth 2.0 + JWT（HS256、有効期限1時間）
- リフレッシュトークン: 7日間有効、Redisで管理
- パスワードハッシュ: bcrypt（cost: 12）
- MFA: TOTP方式（オプション）

**データ保護**:
- **保管時暗号化**: RDS (AES-256)、S3 (SSE-S3)
- **転送時暗号化**: すべてHTTPS/TLS
- **PIIマスキング**: ログ出力時に自動マスキング

**脅威分析（必須）**:
- STRIDE/OWASPに基づく脅威リストと対策を記載
- 信頼境界ごとの攻撃面と対策を明文化

**脅威分析テンプレート**:
| 脅威カテゴリ | 対象 | 影響 | 対策 | 検証方法 |
| -- | -- | -- | -- | -- |
| Spoofing | 認証 | なりすまし | MFA / JWT検証 | セキュリティテスト |
| Tampering | API | データ改ざん | 署名検証 / WAF | 侵入テスト |
| Repudiation | 監査 | 否認 | 監査ログ | 監査ログ確認 |

### 6.4 ログ・監視設計
**ログ出力方式**:
- **フォーマット**: JSON構造化ログ
- **出力先**: stdout → CloudWatch Logs
- **保持期間**: アプリ90日、アクセスログ1年、監査ログ7年

**ログレベル定義**:
| Level | 用途 | 例 |
| -- | -- | -- |
| ERROR | システムエラー | DB接続失敗、外部API障害 |
| WARN | 警告 | キャッシュミス、リトライ |
| INFO | 重要な業務処理 | 注文作成、決済完了 |
| DEBUG | 詳細なデバッグ | SQL実行内容（開発環境のみ） |

**監視項目・アラート**:
| 監視項目 | 閾値 | アラート方法 | 対応優先度 |
| -- | -- | -- | -- |
| API Error Rate | 5%以上 | Slack + PagerDuty | P1 |
| Response Time (P95) | 1秒以上 | Slack | P2 |
| CPU使用率 | 80%以上 | Slack | P3 |
| メモリ使用率 | 85%以上 | Slack | P3 |
| DB接続数 | 80%以上 | Slack | P2 |

**トレーシング**:
- 分散トレーシング導入（Datadog APM）
- 重要APIはサンプリング率を100%に引き上げ

### 6.5 バックアップ・リカバリ設計
**バックアップ方針**:
| 対象 | 方式 | 頻度 | 保持期間 | RPO |
| -- | -- | -- | -- | -- |
| RDS | 自動スナップショット + WAL | 日次 + 継続的 | 7日間 | 5分 |
| Redis | RDB + AOF | 6時間ごと | 3日間 | 6時間 |
| S3 | バージョニング | リアルタイム | 30日間 | 0 |

**復旧訓練**:
- 四半期に1回、リストア手順のリハーサルを実施
- 実測RTO/RPOを記録

### 6.6 SLO/エラーバジェット
| SLI | SLO | 計測方法 | アラート閾値 |
| -- | -- | -- | -- |
| 可用性 | 99.9% | 監視ツール | 99.7% |
| レイテンシ(P95) | 500ms | APM | 700ms |

## 7. 運用設計
### 7.1 運用責任分界（RACI）
| 項目 | 開発 | 運用 | セキュリティ |
| -- | -- | -- | -- |
| 障害対応 | R | A | C |
| 監査ログ | C | R | A |
| 脆弱性対応 | R | C | A |

### 7.2 インシデント対応
- 重大度定義（P1〜P3）と対応タイムラインを記載
- ランブック/ポストモーテムの運用を明記

## 8. 開発・運用環境
### 8.1 環境区分
| 環境名 | 用途 | 構成概要 | アクセス制限 |
| -- | -- | -- | -- |
| Development (Dev) | 開発・単体テスト | ローカル/開発サーバー | 開発者のみ |
| Staging (Stg) | 結合・受入テスト | 本番相当（縮小構成） | 社内限定 |
| Production (Prod) | 実運用 | フル構成 | 制限あり |

### 8.2 運用ルール
- 環境差分はIaCで管理
- 設定値は環境変数/Parameter Storeで分離

## 9. CI/CDパイプライン
**ツール**: GitHub Actions + AWS ECR/ECS

**パイプラインフロー**:
```mermaid
sequenceDiagram
    participant Dev as Developer
    participant Git as GitHub
    participant CI as CI Server (GitHub Actions)
    participant ECR as AWS ECR
    participant Stg as Staging Env
    participant Prod as Production Env

    Dev->>Git: Push Code to branch
    Git->>CI: Trigger Workflow
    CI->>CI: Run Linter
    CI->>CI: Run Unit Tests
    CI->>CI: Run Integration Tests
    CI->>CI: Security Scan
    CI->>CI: Build Docker Image
    CI->>ECR: Push Image (tag: commit-sha)

    alt Branch is main
        CI->>Stg: Deploy to Staging
        Stg->>Stg: Run Smoke Tests
        Note over Stg: Manual Approval Required
        CI->>Prod: Deploy to Production (Blue-Green)
        Prod->>Prod: Health Check
    end
```

**品質ゲート**:
- コードカバレッジ: 80%以上
- 脆弱性: Critical/High 0件
- Linter: エラー 0件

## 10. エラーハンドリング方針
### 10.1 エラー分類と対応
| エラー種別 | HTTPステータス | ユーザー表示 | ログレベル | リトライ可否 |
| -- | -- | -- | -- | -- |
| バリデーションエラー | 400 | 詳細エラーメッセージ | WARN | No |
| 認証エラー | 401 | 認証失敗 | WARN | No |
| 認可エラー | 403 | 権限不足 | WARN | No |
| リソース不存在 | 404 | データが見つかりません | INFO | No |
| ビジネスロジックエラー | 422 | 詳細エラーメッセージ | WARN | No |
| 外部API障害 | 503 | 一時的なエラー | ERROR | Yes |
| DB接続エラー | 503 | 一時的なエラー | ERROR | Yes |
| 予期しないエラー | 500 | システムエラー | ERROR | No |

### 10.2 エラーレスポンス形式（JSON）
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "入力内容に誤りがあります",
    "details": [
      {
        "field": "email",
        "message": "メールアドレスの形式が正しくありません"
      }
    ],
    "request_id": "req_abc123xyz"
  }
}
```

## 11. インフラコスト見積もり
### 11.1 月次コスト試算（Production環境）
| リソース | スペック | 数量 | 単価 | 月額コスト（USD） |
| -- | -- | -- | -- | -- |
| ECS Fargate | 0.5 vCPU, 1GB RAM | 2 tasks | $15/task | $30 |
| ALB | - | 1 | $23 + データ転送 | $50 |
| RDS PostgreSQL | db.t3.medium | 1 Primary + 1 Standby | $70/instance | $140 |
| Redis ElastiCache | cache.t3.small | 3 nodes | $25/node | $75 |
| CloudFront | 1TB転送 | - | - | $85 |
| S3 | 100GB保存 + 転送 | - | - | $15 |
| CloudWatch Logs | 50GB/月 | - | - | $25 |
| Datadog | 5 hosts | - | $15/host | $75 |
| **合計** | | | | **$495/月** |

**注意**: 実際の料金はリージョンと利用量に依存。算出根拠と更新頻度を明記する。

## 12. 制約事項・前提条件
### 12.1 技術的制約
- **Go言語バージョン**: 1.21以降
- **PostgreSQLバージョン**: 15.x
- **ブラウザサポート**: Chrome/Firefox最新-2、Safari最新-1

### 12.2 外部依存サービス
| サービス | 用途 | 障害時の影響 | フォールバック |
| -- | -- | -- | -- |
| 決済代行API | 決済処理 | 決済不可 | 手動決済対応 |
| メール送信API | 通知メール | 送信不可 | キュー蓄積後リトライ |
| 画像変換API | サムネイル生成 | 画像変換不可 | オリジナル画像使用 |

### 12.3 データ保持期限
- トランザクションデータ: 7年間
- ログデータ: 1年間
- セッションデータ: 24時間

---

## 改訂履歴
| バージョン | 日付 | 変更内容 | 承認者 |
| -- | -- | -- | -- |
| 1.0 | 2026-01-08 | 初版作成 | - |
