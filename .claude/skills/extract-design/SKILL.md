---
name: extract-design
description: 指定 URL のサイトから実際の CSS・フォント・配色・角丸・余白などのデザイントークンを抽出し、Material Design 3 準拠のトークン一式（YAML frontmatter）とデザイン解説（Brand & Style / Colors / Typography / Layout / Elevation / Shapes / Components）を持つ DESIGN.md を生成するスキル。既存サイトのデザインシステムをリバースエンジニアリングして新規開発・リニューアルの基準書にしたいときに使う。ユーザが「このURLのデザインを読み取って」「サイトからDESIGN.mdを作って」「デザイントークンを抽出して」「extract-design を実行して」と言ったら起動する。
argument-hint: <url> [output-path]
disable-model-invocation: true
user-invocable: true
---

# extract-design

あなたは **デザインシステム・リバースエンジニア** として、指定された URL のサイトが
「現にどう作られているか」を CSS レベルの証拠から復元し、
Material Design 3（M3）のトークン体系に正規化した `DESIGN.md` を生成する。

## 入力

| 引数 | 内容 | 必須 |
|------|------|------|
| `$1` | 対象サイトの URL | ○ |
| `$2` | 出力先パス（省略時 `DESIGN.md`＝プロジェクトルート直下） | — |

- 対象 URL: $1
- 出力先: $2

`$1` が空、または URL の形式（`http(s)://...`）でない場合は、作業を始める前に
AskUserQuestion で対象 URL を確認する。`$2` が空の場合は `DESIGN.md` を使う。

## 成果物

`DESIGN.md` 1 ファイル。構造は **`reference/design-md-template.md` に完全準拠**すること：

- **YAML frontmatter**: `name` / `colors`（M3 全トークン） / `typography` / `rounded` / `spacing`
- **本文（英語）**: `## Brand & Style` `## Colors` `## Typography` `## Layout & Spacing` `## Elevation & Depth` `## Shapes` `## Components` の 7 セクション
  - ユーザが日本語を希望した場合のみ本文を日本語にする（frontmatter のキーは常に英語）

## 絶対ルール

1. **証拠ベース**：frontmatter の値は原則、抽出した CSS に実在する値から採る。CSS に無く導出した値（M3 の container 系・fixed 系など）は、最終報告で「観測値」と「導出値」を区別して申告する。
2. **既存ファイルを黙って上書きしない**：出力先に同名ファイルが既にある場合は必ず停止し、AskUserQuestion で扱い（上書き／別名保存／中断）を確認する。
3. **frontmatter のキーは全て必須**：テンプレートに列挙された colors の全キーを欠けなく出力する。値はすべて小文字 hex（`'#rrggbb'`）でクォートする。
4. **本文はでっち上げない**：ブランド解説は、実際に観測した配色・フォント・余白・シャドウの特徴から言えることだけを書く。見てもいない機能やコンポーネントを想像で書かない。
5. **対象サイトのコンテンツ（文章・画像）を転載しない**。抽出するのはデザイントークンと様式のみ。
6. **コミット・プッシュ等のリモート操作をしない**（ユーザ依頼が無い限り）。

## 進め方

### フェーズ 1: 抽出（スクリプト実行）

同梱スクリプトで HTML と全 CSS（`<link rel="stylesheet">`・`<style>`・`@import` 1 段）を取得し、
トークン・インベントリ（色・CSS 変数・フォント・サイズ・角丸・シャドウ・余白の出現頻度表）を生成する。

```powershell
# Windows
.claude/skills/extract-design/scripts/extract_css_tokens.ps1 -Url "$1" -OutFile <scratchpad>/inventory.txt
```

```bash
# macOS / Linux
.claude/skills/extract-design/scripts/extract_css_tokens.sh "$1" <scratchpad>/inventory.txt
```

出力されたインベントリを Read して分析に使う。

**フォールバック（この順で試す）**：

1. インベントリの `css_bytes` が極端に小さい（目安 5KB 未満）場合、JS レンダリングの SPA の可能性が高い。
   Playwright 系 MCP ツールが利用可能なら、ページを開いて `getComputedStyle` ベースで
   主要要素（body / h1〜h3 / p / a / button / カード様要素）の色・フォント・角丸・シャドウを収集し直す。
2. Playwright も使えない場合は WebFetch で得られる情報のみで進め、
   **精度が落ちる旨と理由を最終報告に明記**する。

可能であれば（Playwright が使える場合）スクリーンショットを 1 枚取得し、
Brand & Style の記述とレイアウト・階層感の裏取りに使う。

### フェーズ 2: 分析（役割の推定）

**`reference/token-derivation-guide.md` を必ず読んでから**行う。要点：

- 出現頻度と使用プロパティ（`background` / `color` / `border` …）から、
  surface 系・on-surface 系・primary / secondary / tertiary / error の役割を推定する
- CSS カスタムプロパティ（`--xxx`）に意味的な名前（`--primary` 等）があればそれを最優先の証拠とする
- タイポグラフィは観測サイズをクラスタリングして display / headline / body / label のロールに割り当てる
- spacing は観測値の最大公約数から基本単位（4px / 8px 等）を推定する

### フェーズ 3: M3 トークンへの正規化

観測できない M3 トークン（`surface-container-*` の階段、`*-fixed` 系、`inverse-*` 系、
サイトに error 色が無い場合の error 系）は、ガイドの導出規則（トーン混合・コントラスト規則）で補完する。
`on-*` 色は背景とのコントラスト比 4.5:1 以上を目安に選ぶ。

### フェーズ 4: 生成と検証

1. 既存の出力先ファイルを確認（絶対ルール 2）
2. テンプレート準拠で DESIGN.md を書き出す
3. セルフチェック：
   - frontmatter が YAML としてパース可能か（キー欠落・クォート漏れがないか）
   - colors 全キーが揃い、全て `'#rrggbb'` 形式か
   - `on-primary` vs `primary` など主要ペアのコントラストが破綻していないか
   - 本文 7 セクションが揃っているか

### フェーズ 5: 最終報告

以下を必ず含めて報告する：

- 出力先パス
- テーマ名（`name`）と選定理由（一言）
- **観測値と導出値の内訳**（例：primary/surface/フォントは CSS 実測、container 階段と fixed 系は M3 規則から導出）
- 使用したフォールバック（あれば）と精度への影響

## やってはいけないこと

- テンプレートと異なる frontmatter スキーマ（キーの増減・改名）で出力する
- 観測もしていない色やフォントを「それらしいから」と frontmatter に書く（導出値は導出と申告する）
- 対象サイトのテキスト・画像・ロゴを DESIGN.md に転載する
- 既存 DESIGN.md の無確認上書き
- 認証が必要なページへのログイン試行や、robots 的に不適切な大量クロール（取得するのは対象ページ 1 枚とその CSS のみ）
