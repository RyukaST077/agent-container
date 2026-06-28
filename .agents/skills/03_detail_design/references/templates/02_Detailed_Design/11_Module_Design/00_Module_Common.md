# 詳細設計共通

## 0. ドキュメント情報
| 項目 | 内容 |
| -- | -- |
| システム名 | [System Name] |
| 対象範囲 | サーバーサイド詳細設計 |
| バージョン | 1.0 |
| 作成日 | YYYY-MM-DD |
| 作成者 | [Name] |
| 承認者 | [Name] |

## 1. 設計方針
- **言語/実装方針**: Go (Standard Layout) / Java (Spring Boot) / etc.
- **アーキテクチャ**: Clean Architecture / Layered Architecture
- **エラーハンドリング**: 
  - 独自エラー定義の使用有無
  - エラーログ出力基準
- **トランザクション管理**: 
  - 宣言的トランザクション vs 明示的トランザクション
- **ロギング**:
  - ログレベル基準 (INFO, WARN, ERROR)
  - 構造化ログ (JSON) の採用

## 2. モジュール一覧
| モジュールID | 名称 | 概要 | 責任 | 担当 | パス/パッケージ |
| -- | -- | -- | -- | -- | -- |
| M001 | OrderService | 注文サービス | 注文ドメインロジック | Server | `internal/service/order`  |
| M002 | UserRepository | ユーザーリポジトリ | ユーザーデータの永続化 | Server | `internal/repository/user` |
| M003 | PaymentGateway | 決済GW | 外部決済API連携 | Server | `internal/gateway/payment` |

## 改訂履歴
| バージョン | 日付 | 変更内容 | 承認者 |
| -- | -- | -- | -- |
| 1.0 | 2026-XX-XX | 初版作成 | - |
