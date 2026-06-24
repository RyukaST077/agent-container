# knowledge/ — トラブル知見の蓄積と再利用

開発中に起きたトラブル（エラー / ビルド失敗 / 起動しない / 設定ミス / 依存衝突 …）と
その解決策を、**1トラブル = 1ファイル**で構造化して貯めるフォルダです。
「前に見たことある、けど直し方を忘れた」を**grep一発で再利用できる状態**にするのが目的。

## 中身

```
knowledge/
├── README.md                  ← このファイル
├── INDEX.md                   ← 全エントリの索引（新しい順・save時に自動追記）
└── YYYY-MM-DD-<slug>.md       ← トラブル1件ごとの報告書
```

各報告書は YAML frontmatter（検索タグ）＋ 9セクション（背景 / 問題 / 原因 / 解決策 / 検証 /
再発防止 / 検索タグ …）の固定フォーマット。テンプレートは導入対象に応じて
`.claude/skills/save-knowledge/templates/knowledge-report.md` または
`.agents/skills/save-knowledge/templates/knowledge-report.md`。

> `2026-06-22-spring-boot-port-8080-in-use.md` は**フォーマット例の初期サンプル**です。
> 実エントリが溜まったら削除して構いません。

## 2つのスキルで回す（書く / 読む）

| スキル | 役割 | いつ |
|--------|------|------|
| **save-knowledge** | トラブルを `knowledge/` に書き込む | トラブルを解決したあと「save it」「記録して」 |
| **consult-knowledge** | `knowledge/` を検索して過去の修正を再利用する | トラブルに当たった瞬間（自動 / 「過去に無い?」） |

```
トラブル発生 ──▶ consult-knowledge で検索 ──┬─ ヒット ─▶ 記録された修正を適用・検証
                                            └─ 無し  ─▶ 自力で解決 ─▶ save-knowledge で記録
                                                                          └──▶ 次回はヒットになる（ループが閉じる）
```

## 自動で回す仕組み（hooks）

スキルは本来「エージェントが自発的に気づいたら発火」ですが、それを取りこぼさないよう
Claude Code では `.claude/hooks/`、Codex では `.codex/hooks/` の3つのフックが発火を後押しします。

| hook | イベント | 動き |
|------|----------|------|
| `consult-on-prompt.sh` | UserPromptSubmit | ユーザーがトラブルを記述したら **consult-knowledge** を促すヒントを注入 |
| `consult-on-failure.sh` | PostToolUse (Bash) | コマンドが実際に失敗したら **consult** を促す＋「未保存トラブル」マーカーを設置（セッション単位で1回・連発防止） |
| `save-nudge-on-stop.sh` | Stop | マーカーがあればターン終了時に **save-knowledge** を1回だけ提案（セッションID照合で持ち越し防止） |

- フックは**ヒントを出すだけ**で、作業をブロックしたりループさせたりしません。
- うるさい / 不要なら `.claude/settings.json` または `.codex/hooks.json` の該当エントリを外せば無効化できます。
- Codex の reasoning / memory / permissions は `.codex/config.toml` に入ります。
- マーカーは `.claude/.cache/knowledge/` または `.codex/.cache/knowledge/`（git管理外）に置かれます。

## 手で使うとき

```bash
# 検索（consult-knowledge が内部で使うスクリプト。直接叩いてもよい）
bash .claude/skills/consult-knowledge/scripts/search-knowledge.sh "EADDRINUSE" "port" "ポート競合"

# Codex 用だけ導入した場合
bash .agents/skills/consult-knowledge/scripts/search-knowledge.sh "EADDRINUSE" "port" "ポート競合"

# ざっくりgrep
grep -ri "8080" knowledge/
```

新規記録は `save-knowledge` スキル（「このトラブルを記録して」等）から。
直接ファイルを作るより、テンプレに沿って埋めてくれるスキル経由を推奨します。
