# [物理テーブル名] ([論理テーブル名])

## 1. 概要
<!-- テーブルの用途、格納するデータの内容 -->
[ここに記述]

## 2. テーブル定義
| カラム名 | 論理名 | 型 | 長さ/精度 | NULL | PK | FK | Default | 備考 |
| -- | -- | -- | -- | -- | -- | -- | -- | -- |
| id | ID | BIGINT | - | No | Yes | - | AUTO_INCREMENT | |
| [col_name] | [論理名] | VARCHAR | 255 | No | - | - | - | |
| group_id | グループID | BIGINT | - | No | - | Yes | - | groups.id |
| created_at | 作成日時 | DATETIME | - | No | - | - | CURRENT_TIMESTAMP | 共通カラム |
| updated_at | 更新日時 | DATETIME | - | No | - | - | CURRENT_TIMESTAMP | 共通カラム |

## 3. インデックス定義
| インデックス名 | 種類 | 対象カラム | 備考 |
| -- | -- | -- | -- |
| PRIMARY | Primary | id | |
| idx_[table]_[col] | Normal | [col_name] | 検索用 |
| uniq_[table]_[col] | Unique | [col_name] | |

## 4. 制約・トリガー
- [制約名]: [内容]
- [トリガー名]: [内容] (例: 更新時にupdated_atを更新)

## 5. 備考
- データ量の想定: 月間xx件増加
- パーティショニング: なし
