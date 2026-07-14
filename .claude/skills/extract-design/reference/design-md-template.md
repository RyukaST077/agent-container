# DESIGN.md テンプレート（完全準拠すること）

生成する DESIGN.md は、以下の frontmatter スキーマと本文構成に**完全に**従う。
キーの追加・削除・改名は禁止（typography のロール名と各ロール内の任意キーを除く）。

## frontmatter スキーマ

```yaml
---
name: <テーマ名。デザインの人格を要約した 2〜4 語の英語名。例 "Precision & Clarity">
colors:
  # ---- surface 系（全キー必須） ----
  surface: '#rrggbb'
  surface-dim: '#rrggbb'
  surface-bright: '#rrggbb'
  surface-container-lowest: '#rrggbb'
  surface-container-low: '#rrggbb'
  surface-container: '#rrggbb'
  surface-container-high: '#rrggbb'
  surface-container-highest: '#rrggbb'
  on-surface: '#rrggbb'
  on-surface-variant: '#rrggbb'
  inverse-surface: '#rrggbb'
  inverse-on-surface: '#rrggbb'
  outline: '#rrggbb'
  outline-variant: '#rrggbb'
  surface-tint: '#rrggbb'
  # ---- primary / secondary / tertiary / error（全キー必須） ----
  primary: '#rrggbb'
  on-primary: '#rrggbb'
  primary-container: '#rrggbb'
  on-primary-container: '#rrggbb'
  inverse-primary: '#rrggbb'
  secondary: '#rrggbb'
  on-secondary: '#rrggbb'
  secondary-container: '#rrggbb'
  on-secondary-container: '#rrggbb'
  tertiary: '#rrggbb'
  on-tertiary: '#rrggbb'
  tertiary-container: '#rrggbb'
  on-tertiary-container: '#rrggbb'
  error: '#rrggbb'
  on-error: '#rrggbb'
  error-container: '#rrggbb'
  on-error-container: '#rrggbb'
  # ---- fixed 系（全キー必須） ----
  primary-fixed: '#rrggbb'
  primary-fixed-dim: '#rrggbb'
  on-primary-fixed: '#rrggbb'
  on-primary-fixed-variant: '#rrggbb'
  secondary-fixed: '#rrggbb'
  secondary-fixed-dim: '#rrggbb'
  on-secondary-fixed: '#rrggbb'
  on-secondary-fixed-variant: '#rrggbb'
  tertiary-fixed: '#rrggbb'
  tertiary-fixed-dim: '#rrggbb'
  on-tertiary-fixed: '#rrggbb'
  on-tertiary-fixed-variant: '#rrggbb'
  # ---- background / variant（全キー必須） ----
  background: '#rrggbb'
  on-background: '#rrggbb'
  surface-variant: '#rrggbb'
typography:
  # ロール名は観測結果に応じて命名する（display-lg / headline-md / body-lg / body-md / label-mono など）。
  # 最低限 display 系 1 つ・headline 系 1 つ・body 系 2 つを含めること。
  <role-name>:
    fontFamily: <フォント名>
    fontSize: <NNpx>
    fontWeight: '<100-900>'          # 文字列としてクォート
    lineHeight: '<数値>'              # 文字列としてクォート
    letterSpacing: <±N.NNem>          # 任意（観測できた場合のみ）
rounded:
  sm: <rem 値>
  DEFAULT: <rem 値>
  md: <rem 値>
  lg: <rem 値>
  xl: <rem 値>
  full: 9999px
spacing:
  unit: <Npx>                        # 基本単位（4px / 8px 等）
  container-max: <NNNNpx>            # コンテンツ最大幅
  gutter: <NNpx>                     # カラム間・左右余白
  section-gap-desktop: <NNNpx>       # セクション間（デスクトップ）
  section-gap-mobile: <NNpx>         # セクション間（モバイル）
---
```

### 記法ルール

- 色は**すべて小文字 6 桁 hex** をシングルクォートで囲む（`'#f8f9ff'`）。alpha 付きの観測値は白/黒/背景色との合成結果を 6 桁 hex に焼き込む
- `fontWeight` と `lineHeight` は文字列（クォート必須）。`fontSize` `letterSpacing` は素の値
- `rounded` は rem 単位に正規化する（観測が px なら 16 で割る）。`full: 9999px` は固定

## 本文構成（7 セクション必須・この順）

```markdown
## Brand & Style

<誰に向けた・どんな人格のデザインか。スタイル分類（例: Modern Professional Minimalism）と、
それを支える視覚的手段（余白・タイポ・深度など）。観測事実から言えることのみ。2 段落程度>

## Colors

<パレットの構成論理。primary / secondary / tertiary それぞれの色に説明的な名前を付け
（例: **Deep Slate (Primary)**）、どこに・どう使い分けるかを書く。2 段落程度>

## Typography

<採用フォントとその選定意図の推定、ロールごとの使い方。箇条書きで
Headlines / Body / Labels 等の運用ルールを含める>

## Layout & Spacing

<グリッド体系（カラム数・最大幅）、セクション間隔の思想、
モバイル時の変化、spacing スケール（基本単位と系列）。2 段落程度>

## Elevation & Depth

<階層表現の手段（シャドウ／ボーダー／トーン差）。観測したシャドウの実値
（blur・opacity・色）と、ホバー等のインタラクション時の変化>

## Shapes

<角丸の基本方針と、コンポーネント規模ごとの使い分け（ボタン/カード/画像）。箇条書き可>

## Components

### <観測できた主要コンポーネント 3〜5 種。例: Buttons / Cards / Input Fields / Navigation>
<各コンポーネントの様式を、frontmatter のトークン名を参照しながら記述する>
```

## 完成例

ユーザ提示の完成イメージ（このスキルの正解基準）。トーン・粒度・分量の基準としてこれに合わせる：

- frontmatter: テーマ名 "Precision & Clarity"、M3 全色トークン、Inter + JetBrains Mono の 6 ロール、8px ベースの spacing
- 本文: 各セクション 1〜3 段落。色に **Deep Slate** のような固有名を与え、太字で強調。
  Components はサイトで実際に観測できた種類だけを `###` 小見出しで列挙
