# agent-container

Claude Code / Codex の **「ナレッジループ」一式**を、任意のプロジェクトに `npx` 一発で導入するインストーラです。

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

TTY で実行すると、導入対象を `Claude Code` / `Codex` / `Both` から選択できます。
非対話環境では後方互換のため `Claude Code` が既定です。

明示する場合:

```bash
npx github:RyukaST077/agent-container --agent claude
npx github:RyukaST077/agent-container --agent codex
npx github:RyukaST077/agent-container --agent both
```

カレントディレクトリに選択したエージェント用の設定と、共通の `knowledge/` `.devcontainer/` が展開されます。
**既存ファイルは保持**され、`.claude/settings.json`、`.codex/config.toml`、`.codex/hooks.json` は可能な範囲で**安全マージ**します。

### オプション

| オプション | 説明 |
|------------|------|
| `--agent <name>` | 導入対象を `claude` / `codex` / `both` から指定 |
| `--claude`, `--codex`, `--both` | `--agent` の短縮指定 |
| `--dry-run`, `-n` | 実際には書き込まず、変更内容だけ表示 |
| `--force`, `-f`   | 既存ファイルも上書きする |
| `--quiet`, `-q`   | ログを抑制 |
| `--help`, `-h`    | ヘルプを表示 |

導入前に差分を確認したいときは:

```bash
npx github:RyukaST077/agent-container --dry-run
```

Codex 用だけ確認する場合:

```bash
npx github:RyukaST077/agent-container --agent codex --dry-run
```

## 動作要件

- Node.js >= 16（`npx` 同梱）
- 追加の npm 依存はありません（Node 標準モジュールのみ）

## 導入後

1. VS Code / Cursor で導入先プロジェクトを開く
2. コマンドパレットから `Dev Containers: Reopen in Container` を実行して DevContainer を起動する
3. トラブルに当たると `consult-knowledge` が `knowledge/` を検索して過去の修正を提案
4. 解決後に `save-knowledge` で記録 → 次回からヒットするようループが閉じる

DevContainer の設定は `.devcontainer/devcontainer.json`。
Claude Code の設定は `.claude/settings.json`。
Codex の設定は `.codex/config.toml`、Skills は `.agents/skills/`、hooks は `.codex/hooks.json` と `.codex/hooks/` に入ります。
`.codex/config.toml` には `.claude/settings.json` 相当の reasoning / memory / permissions 設定を入れています。
Codex では初回起動後に `/hooks` で project-local hooks の信頼確認が必要になる場合があります。
フックがうるさい場合は当該エントリを外せば無効化できます。

## ライセンス

[MIT](LICENSE)
