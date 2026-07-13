# v1 API スナップショットテスト運用ガイド

## ⚡ クイックスタート（セットアップ済み）

> このガイドのスナップショットテストは「回帰検知」の1レイヤーです。  
> バージョンアップ後も安定運用するには、下の「🧱 バージョンアップ耐性を高める運用」も必ず併用してください。

### 日常的なテスト実行

マスタースナップショット（`snapshots/responses-master.json`）がすでに確定している場合、以下を実行してください。

```bash
cd /home/kamayama/02_work/001_hakuhodo

# ✅ 推奨：マスター比較テスト（差分を検出）
bash tools/v1-test/v1_test_with_snapshot.sh test

# または従来型：テストのみ実行
bash tools/v1-test/v1_test_runner.sh 2>&1 | tee logs/v1-test-$(date +%Y%m%d-%H%M%S).log
```

**結果:**
- `✅ All API responses match master` → OK（差分なし）
- `❌ API response mismatch detected` → NG（変化あり：差分レポート確認）

---

## 📋 実運用フロー

### フロー 1：通常のテスト実行（推奨）

```bash
# マスターとの差分を自動検出・レポート
bash tools/v1-test/v1_test_with_snapshot.sh test

# ✅ 差分がなければ OK
# ❌ 差分があれば logs/*.md を確認
```

補足: `test` は毎回最新テストを実行してから比較します。

### フロー 2：差分を確認・承認（マスター更新時）

変更が仕様通りの場合、新しいマスターに更新：

```bash
# 1. テスト実行して差分を確認
bash tools/v1-test/v1_test_with_snapshot.sh compare
less logs/v1-snapshot-diff-*.md

# 2. OK なら新しいマスターとして承認
bash tools/v1-test/v1_test_with_snapshot.sh approve

# 3. Git に提交
git add snapshots/responses-master.json
git commit -m "Update v1 API master snapshot: [変更理由]"
```

### フロー 3：全詳細を確認したい場合

```bash
# 最新スナップショットを明示的に作成
bash tools/v1-test/v1_test_with_snapshot.sh record

# 詳細レポート生成
python3 tools/v1-test/v1_snapshot_comparator.py snapshots/responses-*.json snapshots/responses-master.json

# ログ確認
tail -100 logs/v1-summary-*.md
```

---

## 📚 セットアップ済みの確認

```bash
# マスタースナップショットが存在するか確認
ls -la snapshots/responses-master.json

# 内容確認（エンドポイント数）
cat snapshots/responses-master.json | grep endpoint | wc -l
```

---

## 🔄 初期セットアップ（新規プロジェクト用）

### 1. スナップショットをマスターとして記録

```bash
cd /home/kamayama/02_work/001_hakuhodo

# v1テストを実行（スナップショット記録）
bash tools/v1-test/v1_test_with_snapshot.sh record
```

### 2. マスタースナップショットを固定化

```bash
# テスト内容を確認
bash tools/v1-test/v1_test_with_snapshot.sh compare

# OK なら承認
bash tools/v1-test/v1_test_with_snapshot.sh approve

# Git に提交
git add snapshots/responses-master.json
git commit -m "Register golden master snapshot for v1 API"
```

---

## DB リセット付きワークフロー (SEED_CMD)

### 概要

`SEED_CMD` は、`record` / `test` の実行前に DB リセットを自動実行する仕組みです。
スナップショットテストは DB の状態に依存するため、テスト前に DB を既知の初期状態へ戻すことで、データ差分による偽陽性を防ぎます。

`SEED_CMD` が設定されている場合、`snapshot.sh` は以下の順序で処理を行います:

1. **SEED_CMD 実行** -- DB を初期状態にリセット
2. **CAPTURE_CMD 実行** -- 全 API エンドポイントを叩いてレスポンスを取得
3. **比較** (`test` モード時) -- マスタースナップショットと差分を検出

### セットアップ

```bash
# reset-db.sh を編集済みであること
export SEED_CMD="bash tools/snapshot/reset-db.sh"
export CAPTURE_CMD="bash tools/snapshot/capture.sh"
```

### 日常の回帰テスト

```bash
bash tools/snapshot/snapshot.sh test
# → reset-db.sh (DB初期化) → capture.sh (API叩く) → compare (マスターと比較)
```

### DB リセットなしで実行したい場合

`SEED_CMD` を未設定 (unset) にすれば、DB リセットをスキップして従来通り動作します。

```bash
unset SEED_CMD
bash tools/snapshot/snapshot.sh test
# → capture.sh (API叩く) → compare (マスターと比較)
```

### CI での使い方

```yaml
env:
  SEED_CMD: bash tools/snapshot/reset-db.sh
  CAPTURE_CMD: bash tools/snapshot/capture.sh
run: |
  docker compose up -d
  bash tools/snapshot/snapshot.sh test
```

---

## CI/CD 統合

### 推奨: 3層テスト（バージョンアップ耐性）

バージョンアップ時の破損を減らすため、CI は次の3層で運用してください。  
Layer 1・3 は curl ベースのため、フレームワークのバージョンアップに影響されません。

| Layer | 内容 | 実装 | 依存 |
|-------|------|------|------|
| 1 | **値・型アサーション**（レスポンスの中身を検証） | `tools/v1-test/lib/assert.sh` (v1_test_runner.sh に組込み済) | curl + python3 |
| 2 | アプリテスト（ユニット/結合） | PHPUnit / Laravel Test | フレームワーク依存 |
| 3 | **スナップショット比較**（回帰検知） | `tools/v1-test/v1_test_with_snapshot.sh` | curl + python3 |

最小コマンド例:

```bash
# 1) v1 curl テスト（Layer 1 アサーション + Layer 3 スナップショット）
bash tools/v1-test/v1_test_with_snapshot.sh test
# → HTTPコード検証 + 37個のレスポンス値アサーション + スナップショット比較

# 2) sarf-api の Laravel テスト（Layer 2 ※バージョンアップで壊れる可能性あり）
cd sarf-api
docker compose exec api php artisan test

# 3) sarf-cms-server の PHPUnit（Layer 2）
cd ../sarf-cms-server
./vendor/bin/phpunit tests/Database/
./vendor/bin/phpunit
```

### アサーション設定

```bash
# アサーションを無効化して実行（従来と同じHTTPコード検証のみ）
ASSERT_ENABLED=0 bash tools/v1-test/v1_test_with_snapshot.sh test

# アサーションを有効化して実行（デフォルト）
bash tools/v1-test/v1_test_with_snapshot.sh test
```

### GitHub Actions での使用例

```yaml
name: v1 API Test

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run v1 API snapshot test
        run: |
          cd /path/to/project
          bash tools/v1-test/v1_test_with_snapshot.sh test

      - name: Run sarf-api tests
        run: |
          cd /path/to/project/sarf-api
          docker compose exec -T api php artisan test

      - name: Run sarf-cms-server tests
        run: |
          cd /path/to/project/sarf-cms-server
          ./vendor/bin/phpunit tests/Database/
          ./vendor/bin/phpunit
```

### GitLab CI での使用例

```yaml
v1_api_test:
  script:
    - cd /path/to/project
    - bash tools/v1-test/v1_test_with_snapshot.sh test
  only:
    - merge_requests
```

---

## ✅ 実行結果の読み方

### OK: テスト成功（差分なし・アサーション全パス）

```
=== Assertion Results ===
Total: 37  Pass: 37  Fail: 0
✅ All 37 assertions passed

✅ All API responses match master
```

→ すべてのAPIが期待通りの値を返しています。OK。

### NG: アサーション失敗（レスポンスの値が不正）

```
❌ 3 assertion(s) FAILED
```

→ アサーション詳細レポートで失敗内容を確認：

```bash
less logs/v1-assertions-*.md
```

### NG: スナップショット差分あり（回帰検知）

```
❌ API response mismatch detected
```

→ スナップショット差分で変更内容を確認：

```bash
# 差分レポートを表示
less logs/v1-snapshot-diff-*.md

# または JSON で直接比較
diff snapshots/responses-master.json snapshots/responses-*.json
```

---

## 🔧 トラブルシューティング

### Q: `approve` で `cp` が失敗する

最新スナップショットが無い状態です。まず `record` で作成してください。

```bash
bash tools/v1-test/v1_test_with_snapshot.sh record
bash tools/v1-test/v1_test_with_snapshot.sh approve
```

### Q: マスタースナップショットが見つからない

```bash
# 存在確認
ls -la snapshots/responses-master.json

# ない場合は初期セットアップを実行
bash tools/v1-test/v1_test_with_snapshot.sh record
bash tools/v1-test/v1_test_with_snapshot.sh approve
```

### Q: テストが実行できない

```bash
# 権限確認
ls -la tools/v1-test/v1_test_with_snapshot.sh
chmod +x tools/v1-test/v1_test_with_snapshot.sh

# Docker が起動しているか確認
docker ps | grep sarf
```

### Q: マスターを前のバージョンに戻したい

```bash
# Git 履歴から復元
git log --oneline snapshots/responses-master.json
git show <commit>:snapshots/responses-master.json > snapshots/responses-master.json
git add snapshots/responses-master.json
git commit -m "Revert master snapshot to previous version"
```

### Q: 差分が多すぎて何が変わったか分からない

```bash
# 統計情報を表示
python3 << 'EOF'
import json

with open('snapshots/responses-master.json') as f:
    master = json.load(f)

print(f"Master endpoints: {len(master)}")
print("\nEndpoints:")
for entry in master:
    print(f"  - {entry['endpoint']} ({entry['method']}): HTTP {entry['http_code']}")
EOF
```

### Q: バージョンアップ後に差分が大量発生する

以下を順番に確認してください。

1. 仕様変更か回帰かを契約テストで切り分ける
2. 仕様変更なら `compare` で内容確認後に `approve`
3. 回帰なら修正して再実行

---

## 📖 参考

- [tools/v1-test/v1_test_with_snapshot.sh](../tools/v1-test/v1_test_with_snapshot.sh) - メインスクリプト
- [tools/v1-test/v1_snapshot_comparator.py](../tools/v1-test/v1_snapshot_comparator.py) - 比較ツール
- [tools/v1-test/v1_test_runner.sh](../tools/v1-test/v1_test_runner.sh) - 基本テストスクリプト（アサーション組込み済）
- [tools/v1-test/lib/assert.sh](../tools/v1-test/lib/assert.sh) - アサーション関数ライブラリ（python3ベース、jq不要）
- `snapshots/responses-master.json` - 確定マスター
- `logs/v1-assertions-*.md` - アサーション結果レポート
