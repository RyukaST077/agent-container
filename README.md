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

カレントディレクトリに Claude Code 用の設定（`.claude/`）と、共通の `knowledge/` `.devcontainer/` が展開されます。
**既存ファイルは保持**され、`.claude/settings.json` は可能な範囲で**安全マージ**します。

### オプション

| オプション | 説明 |
|------------|------|
| `--shell <name>` | フックのシェルを `bash` / `powershell` から指定（既定: Windows は `powershell`、その他は `bash`） |
| `--powershell`, `--bash` | `--shell` の短縮指定 |
| `--dry-run`, `-n` | 実際には書き込まず、変更内容だけ表示 |
| `--force`, `-f`   | 既存ファイルも上書きする |
| `--quiet`, `-q`   | ログを抑制 |
| `--no-docs`       | `CLAUDE.md` の生成・更新を行わない |
| `--help`, `-h`    | ヘルプを表示 |

導入前に差分を確認したいときは:

```bash
npx github:RyukaST077/agent-container --dry-run
```

## Windows / PowerShell 対応

フックは **bash 版（`.sh`）と PowerShell 版（`.ps1`）の両方**を同梱しています。
どちらも同じ挙動で、PowerShell 版は `jq` / `grep` などの外部コマンドに依存しません
（Windows PowerShell 5.1 / PowerShell 7+ で動作）。

インストール時に環境を判定し、設定ファイル（`.claude/settings.json`）の
フック呼び出しを選択シェル向けに自動で書き換えます。

- **Windows**: 既定で PowerShell 版を使う設定を書き込みます。
- **macOS / Linux**: 既定で bash 版を使います。
- 明示する場合は `--powershell` / `--bash`（または `--shell <name>`）を指定します。

```bash
npx github:RyukaST077/agent-container --powershell   # Windows 想定
```

シェルを切り替えて再実行しても二重登録にはならず、選択したシェルの呼び出しに更新されます
（ユーザが自分で追加したフックは保持されます）。

> 注: Windows の Claude Code は Git for Windows があると bash、無いと PowerShell でフックを実行します。
> bash 経路でも Git Bash には `jq` が同梱されないため、Windows では PowerShell 版の利用を推奨します。

## 動作要件

- Node.js >= 16（`npx` 同梱）
- 追加の npm 依存はありません（Node 標準モジュールのみ）
- フック実行時のシェル: bash 経路は `bash` / `jq` / `grep`、PowerShell 経路は追加依存なし

## 導入後

1. VS Code / Cursor で導入先プロジェクトを開く
2. コマンドパレットから `Dev Containers: Reopen in Container` を実行して DevContainer を起動する
3. トラブルに当たると `consult-knowledge` が `knowledge/` を検索して過去の修正を提案
4. 解決後に `save-knowledge` で記録 → 次回からヒットするようループが閉じる

DevContainer の設定は `.devcontainer/devcontainer.json`。
Claude Code の設定は `.claude/settings.json`、Skills は `.claude/skills/`、hooks は `.claude/hooks/` に入ります。
フックがうるさい場合は `.claude/settings.json` の当該エントリを外せば無効化できます。

## ライセンス

[MIT](LICENSE)
