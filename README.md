# agent-container

Claude Code の **「ナレッジループ」一式**を、任意のプロジェクトに `npx` 一発で導入するインストーラです。

- **skills** … `consult-knowledge`（過去トラブルを検索して再利用）/ `save-knowledge`（トラブルを構造化記録）/ `update-skill`（既存 Skill の安全更新）
- **hooks** … スキルの発火を取りこぼさないよう後押しする3つのフック
- **knowledge/** … 「1トラブル = 1ファイル」で知見を貯め、grep で再利用する雛形
- **.devcontainer/** … 開発コンテナ定義

> 仕組みの詳細は [`knowledge/README.md`](knowledge/README.md) を参照してください。

## インストール

導入したいプロジェクトのルートで実行します（GitHub から直接、インストール不要）:

```bash
npx github:RyukaST077/agent-container
```

カレントディレクトリに `.claude/` `knowledge/` `.devcontainer/` が展開されます。
**既存ファイルは保持**され、`.claude/settings.json` だけは `hooks` / `permissions` / `env` を**安全マージ**します。

### オプション

| オプション | 説明 |
|------------|------|
| `--dry-run`, `-n` | 実際には書き込まず、変更内容だけ表示 |
| `--force`, `-f`   | 既存ファイルも上書きする |
| `--quiet`, `-q`   | ログを抑制 |
| `--help`, `-h`    | ヘルプを表示 |

導入前に差分を確認したいときは:

```bash
npx github:RyukaST077/agent-container --dry-run
```

## 動作要件

- Node.js >= 16（`npx` 同梱）
- 追加の npm 依存はありません（Node 標準モジュールのみ）

## 導入後

1. Claude Code をプロジェクトで起動する
2. トラブルに当たると `consult-knowledge` が `knowledge/` を検索して過去の修正を提案
3. 解決後に `save-knowledge` で記録 → 次回からヒットするようループが閉じる

設定は `.claude/settings.json`。フックがうるさい場合は当該エントリを外せば無効化できます。

## ライセンス

[MIT](LICENSE)
