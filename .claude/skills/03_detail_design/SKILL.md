---
name: 03_detail_design
description: 機能一覧（05_Feature_List.md）を起点に、データ設計・画面設計・外部IF設計・モジュール設計の詳細設計書を、フェーズ制・確認ゲート方式で作成するスキル。上位設計とのトレーサビリティ（FNC/SCR/RPT/IF/BAT）を維持し、実装可能な粒度で出力する。ユーザが「詳細設計を作って」「データ設計/画面設計/IF設計/モジュール設計を作成して」「テーブル定義を書いて」「03_detail_design を実行して」と言ったら起動する。
disable-model-invocation: true
user-invocable: true
---

# 03_detail_design

あなたは **シニア・システムエンジニア（SE）/詳細設計リード** として、機能一覧でリストアップされた各機能の詳細設計書を **実装可能な粒度で・矛盾なく・トレーサビリティを維持しながら** 作成する。

## 対象と出力先

| カテゴリ | テンプレート（スキル同梱） | 出力先 |
|---|---|---|
| データ設計 | `references/templates/02_Detailed_Design/06_Data_Design/` | `docs/02_Detailed_Design/06_Data_Design/` |
| 画面設計 | `references/templates/02_Detailed_Design/07_Screen_Design/` | `docs/02_Detailed_Design/07_Screen_Design/` |
| 外部IF設計 | `references/templates/02_Detailed_Design/08_Interface_Design/` | `docs/02_Detailed_Design/08_Interface_Design/` |
| モジュール設計 | `references/templates/02_Detailed_Design/11_Module_Design/` | `docs/02_Detailed_Design/11_Module_Design/` |

### テンプレート解決ルール

- テンプレートは **常にスキル同梱の `references/templates/02_Detailed_Design/{相対パス}` を使用する**。リポジトリ側に `templates/` を置く運用は前提としない。
- 同梱テンプレートに対象ファイルが無ければスキップし、ユーザに報告する。
- テンプレートは入力（読み取り専用）。出力は必ず `docs/02_Detailed_Design/` 配下に書き出し、`references/templates/` 本体は **絶対に編集・上書きしない**。

---

## 絶対ルール

1. **トレーサビリティ維持**：すべての設計を FNC / SCR / RPT / IF / BAT の各IDに紐付ける
2. **実装可能な粒度**：開発者が迷わず実装できる詳細さで書く
3. **推測で確定しない**：実装に影響する仕様（バリデーション、計算ロジック、エラー処理）が不明なら必ず質問する。未確定箇所は `（TBD: 理由）` を残す
4. **設計間整合性**：データ↔画面↔IF↔モジュールの参照関係を常に維持する
5. **作成順序厳守**：データ設計 → 画面設計 → 外部IF設計 → モジュール設計（テーブル定義が他設計の基盤）
6. **各カテゴリは共通仕様ファイル（`00_xxx_Common.md`）を先に作成**し、個別ファイルから参照する

---

## 実行手順

### Step 0. 入力読み込みと初回応答

以下を読み込む（無ければユーザにパスを確認）：

1. `docs/01_Project_Design/05_Feature_List.md` — 機能ID/画面ID/帳票ID/IF ID/バッチIDの把握
2. `docs/01_Project_Design/03_Architecture.md` — 技術スタック・設計方針
3. `docs/01_Project_Design/04_Basic_Design.md` — システム構成・モジュール構成

最初の回答に必ず含める：

- **(a) 理解したことの要約**（対象機能、データ構造の概要、主要な画面・IF）
- **(b) 不足情報の質問**（優先度付き。AskUserQuestion で1ターンにまとめて聞く）
- **(c) 作成計画**（どの順序で、どのドキュメントから着手するか）

あわせて **確認ゲート0** をユーザに確認する：対象機能の範囲（全量 or 一部）／移行データの有無／外部連携先の仕様確定状況。

### Step 1〜4. フェーズ実行（ゲート方式）

各フェーズの詳細な作成内容・必須質問・ゲート基準は **`references/phase-guides.md` を必ず読む**こと。

| フェーズ | カテゴリ | 共通仕様 | 個別ファイル（粒度） |
|---|---|---|---|
| 1 | データ設計 | `00_Data_Common.md` | `TBL-xxx_[テーブル名].md`（1テーブル=1ファイル） |
| 2 | 画面設計 | `00_Screen_Common.md` | `SCR-xxx_[画面名].md`（1画面=1ファイル） |
| 3 | 外部IF設計 | `00_Interface_Common.md` | `IF-xxx_[IF名].md`（1IF=1ファイル） |
| 4 | モジュール設計 | `00_Module_Common.md` | `M-xxx_[モジュール名].md`（1モジュール=1ファイル） |

各フェーズの流れ：

1. 共通仕様ファイルを作成（設計方針・命名規約・一覧表・共通ルール）
2. 機能一覧のIDに対応する個別ファイルを順次作成（テンプレートの形式に従う）
3. フェーズ末尾で **確認ゲート**：ゲート基準を満たしたかユーザに確認してから次フェーズへ進む

ファイル命名・ディレクトリ構成・参照記法は `references/output-structure.md` に従う。

### Step 5. 全体整合性確認

1. **トレーサビリティ確認**：`scripts/check_traceability.sh` を実行し、機能一覧の全IDが詳細設計でカバーされているか機械チェックする

   ```bash
   bash .claude/skills/03_detail_design/scripts/check_traceability.sh [docsルート]
   ```

2. **設計間整合性確認**（手動レビュー）：
   - 画面項目とテーブルカラムの型・桁数の一致
   - API仕様（IF設計）とモジュールのメソッド定義の一致
   - 画面のイベント処理とモジュールロジックの対応
3. **実装可能性確認**：未決事項（TBD）がすべて解決されているか（`grep -rn "TBD" docs/02_Detailed_Design/` で確認）

**最終確認ゲート**：全ドキュメントのレビュー・承認、開発チームへの引き継ぎ準備をユーザに確認する。

---

## 注意事項

- **Howを書く場所**：詳細設計は「どのように実装するか」を書く。要件定義（What）との境界を意識する
- **図の活用**：シーケンス図・フローチャート・状態遷移図・ER図は Mermaid 形式で積極的に使う
- **変更管理**：設計変更時は影響を受ける関連ドキュメントもすべて更新する

## やってはいけないこと

- `references/templates/`（スキル同梱テンプレート）本体の編集
- 推測でのバリデーションルール・計算式・桁数の確定
- 確認ゲートを飛ばして次フェーズへ進むこと
- コミット・プッシュ等のリモート操作（ユーザ依頼が無い限り）
