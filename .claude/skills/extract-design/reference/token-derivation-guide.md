# トークン導出ガイド — 観測値から M3 トークンへ

インベントリ（頻度表）から Material Design 3 トークン一式を導く際の規則集。
**優先順位は常に「意味的な証拠 > 統計的な推定 > 機械的な導出」**。

## 1. 色の役割推定

### 証拠の優先順位

1. **CSS カスタムプロパティの名前**：`--primary` `--accent` `--brand-*` `--bg` `--text` `--error` 等の
   意味的な名前が付いた変数は最優先の証拠。`--md-sys-color-*` があればほぼそのまま採用できる
2. **プロパティ別頻度**：
   - `background(-color)` で最頻出の明色（または暗色）→ `surface` / `background` 候補
   - `color` で最頻出 → `on-surface` / `on-background` 候補
   - ボタン・リンク文脈（`a`, `.btn`, `button` セレクタ近傍）の彩度が高い色 → `primary` 候補
   - 低頻度だが彩度が最も高い色（CTA・バッジ・強調） → `tertiary`（アクセント）候補
   - `border(-color)` の最頻出グレー → `outline` / `outline-variant` 候補
   - 赤系（hue 0±25°）でバリデーション文脈 → `error`
3. **スクリーンショット**（あれば）：ヒーロー・ナビ・CTA ボタンの実際の見た目で上記を裏取りする

### 前処理（Tailwind 等のユーティリティ CSS で特に重要）

- `var(--xxx)` 参照はインベントリの `css_variables` セクションで実値に解決してから数える
- alpha 付き 8 桁 hex（`#ffffff1a` 等）や `rgba()` は、その要素の下地（通常 surface）と合成した
  6 桁 hex に焼き込む。`合成 = 前景*alpha + 下地*(1-alpha)`
- `transparent` `inherit` `currentcolor` `#0000` はトークン候補から除外する

### 判定のヒント

- primary と tertiary の区別：**面積が広く反復的に使われる方が primary**、局所的な強調が tertiary
- secondary が観測できないサイトは多い。その場合は on-surface-variant 相当の
  **低彩度ニュートラル（primary と同系の hue に寄せたグレー）** を secondary として合成する
- モノトーン主体のサイトでは `primary: '#000000'` のような無彩色 primary も正しい（完成例参照）

## 2. 観測できない M3 トークンの導出規則

`mix(A, B, p%)` は sRGB 直線補間（各チャンネルを `A*(1-p) + B*p`）とする。

### surface 階段（ライトテーマ前提）

| トークン | 導出 |
|----------|------|
| surface / background | 観測した基調背景色 |
| surface-container-lowest | `#ffffff`（または surface より明るい観測値） |
| surface-container-low | `mix(surface, surface-tint, 5%)` |
| surface-container | `mix(surface, surface-tint, 8%)` |
| surface-container-high | `mix(surface, surface-tint, 11%)` |
| surface-container-highest | `mix(surface, surface-tint, 14%)` |
| surface-dim | `mix(surface, surface-tint, 20%)` 程度に暗色化 |
| surface-bright | surface と同値でよい（ライトテーマ） |
| surface-variant | surface-container-highest と同値でよい |
| surface-tint | primary が有彩色ならその低彩度版、無彩色 primary なら基調 hue のミッドトーン |

※ サイトにカード背景・帯背景など**実測の階調があるなら必ずそちらを優先**し、
  階段の抜けだけを mix で埋める。

### on-* 色（コントラスト規則）

- 背景の相対輝度から `#ffffff` か暗色（on-surface）かを選ぶ。**目標コントラスト比 4.5:1 以上**
- `on-<x>-container` は `<x>` の hue を保ったまま濃度を振って 4.5:1 を確保する

### inverse 系

- `inverse-surface` = on-surface を少し明るくした暗色（`mix(on-surface, surface, 15%)` 程度）
- `inverse-on-surface` = surface を少し沈めた明色
- `inverse-primary` = primary の明度を上げたパステル版（暗背景上で読める明るさ）

### fixed 系

- `<x>-fixed` = `<x>-container` 相当の明トーン（`mix(#ffffff, <x>, 20〜25%)`）
- `<x>-fixed-dim` = fixed を一段濃くしたもの（`mix(#ffffff, <x>, 35〜40%)`）
- `on-<x>-fixed` = `<x>` の最暗トーン、`on-<x>-fixed-variant` = その中間トーン

### error 系（サイトに赤が無い場合の既定値）

M3 標準をそのまま使う：

```yaml
error: '#ba1a1a'
on-error: '#ffffff'
error-container: '#ffdad6'
on-error-container: '#93000a'
```

## 3. タイポグラフィ

1. 観測した `font-size` を頻度付きで降順に並べ、クラスタリングする
2. ロール割り当ての目安：
   - 40px 以上 → `display-*`（最大値を display-lg に。モバイル用メディアクエリ内の縮小値があれば `display-lg-mobile`）
   - 24〜39px → `headline-*`
   - 15〜19px → `body-lg` / `body-md`（本文の最頻出サイズを body-md に）
   - 14px 以下 → `label-*`（等幅フォントが使われていれば `label-mono`）
3. 各ロールの `fontWeight` `lineHeight` `letterSpacing` は、そのサイズと同時に宣言されている値を対応付ける
4. フォント名は `font-family` スタックの**第一候補**（クォート除去）。Google Fonts の
   `<link>`（`fonts.googleapis.com/css2?family=...`）はフォント特定の確実な証拠
5. システムフォントスタック（`-apple-system` 始まり等）の場合は `fontFamily` を
   代表名（例 `system-ui`）で記す

## 4. rounded（角丸）

1. 観測した `border-radius` を頻度順に並べる（`50%` / `9999px` はピル・円として除外して考える）
2. 最頻出値を `DEFAULT` に据え、観測値を sm < DEFAULT < md < lg < xl に昇順で割り当てる
3. 観測値が 5 種未満なら Tailwind 標準（0.125 / 0.25 / 0.375 / 0.5 / 0.75rem）の
   比率でスケールを補間する。`full: 9999px` は常に固定

## 5. spacing

1. `padding` `margin` `gap` の観測値（px）を集め、**最大公約数**を基本単位候補にする
   （実務上は 4px か 8px に丸める。10px 系サイトなら 10px と正直に書く）
2. `container-max`：`max-width` の最頻出値（コンテンツラッパー文脈のもの）。
   72〜80rem（1152〜1280px）帯が典型
3. `gutter`：カラム間 `gap` またはコンテナの左右 `padding` の代表値
4. `section-gap-desktop / mobile`：セクション要素の上下 `padding/margin` の大きい方の代表値。
   モバイル値はメディアクエリ内の対応値（無ければデスクトップの 1/2）

## 6. Elevation（本文用の観測メモ）

frontmatter には入らないが、本文 `## Elevation & Depth` のために必ず記録する：

- `box-shadow` の代表値（offset / blur / spread / 色と opacity）
- 階層表現の主手段はどれか：シャドウ／1px ボーダー／背景トーン差
- `:hover` ブロック内の `transform` `box-shadow` 変化（あれば）
