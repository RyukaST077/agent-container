# [IF ID] [インターフェース名称]

## 1. 概要
<!-- 連携の目的、データの内容 -->
[ここに記述]

## 2. 接続情報
- **接続先システム**: [System Name]
- **環境**: [Production / Staging]
- **Endpoint / Host**: `https://api.example.com`
- **Method / Protocol**: [GET/POST / SFTP / gRPC]
- **認証情報**: [API Keyヘッダー名 / Credential ID (値は書かない)]

## 3. リクエスト仕様 (Request)
### ヘッダー / パラメータ
| 項目名 | 必須 | 説明 | 備考 |
| -- | -- | -- | -- |
| Content-Type | 〇 | application/json | |
| Authorization | 〇 | Bearer [Token] | |

### ボディ / ペイロード
<!-- JSONスキーマや項目定義 -->
```json
{
  "order_id": "string",
  "amount": 1000
}
```

| 項目名 | 型 | 必須 | 説明 |
| -- | -- | -- | -- |
| order_id | string | 〇 | 注文ID |

## 4. レスポンス仕様 (Response)
### 正常系 (200 OK)
```json
{
  "status": "success",
  "transaction_id": "tx_12345"
}
```

### エラー系
| Status | Code | 説明 |
| -- | -- | -- |
| 400 | INVALID_REQ | パラメータ不備 |
| 500 | SERVER_ERR | 相手側システムエラー |

## 5. エラー時の挙動・リカバリ
- タイムアウト時: [リトライする/しない]
- 500エラー時: [リトライ/アラート通知]
- データ不整合時: [手動リカバリ手順など]
