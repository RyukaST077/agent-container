---
title: "Spring Bootアプリがポート8080競合で起動しない"
date: "2026-06-22"
cause_category: "Resource"
tech: [java, spring-boot, maven]
error_type: [PortInUse, APPLICATION_FAILED_TO_START]
library: [spring-boot, tomcat]
keywords: [port conflict, ポート競合, 8080 already in use, web server failed to start, EADDRINUSE]
status: "resolved"   # resolved | workaround | unresolved
---

# 開発ナレッジ報告書

> **これは初期サンプル（シード）です。** `save-knowledge` / `consult-knowledge` の
> フォーマット例として置いてあります。実エントリが溜まったら削除して構いません。

## タイトル
Spring Bootアプリがポート8080競合で起動しない

## 概要
`mvn spring-boot:run` で起動しようとすると、`Web server failed to start. Port 8080 was already in use.` で APPLICATION FAILED TO START する。前回起動したプロセスが残ってポートを掴んでいたのが原因。残プロセスを停止するか、起動ポートを変えることで解決した。

## 背景
- プロジェクト: workspace（Spring Boot / Maven）
- 機能 / 作業内容: ローカルでアプリを起動して画面確認しようとしていた
- 技術スタック: Java, Spring Boot, Maven, 組み込みTomcat
- 環境: ローカル開発（Docker 併用）
- 発生タイミング: アプリ起動時（`mvn spring-boot:run`）
- 関連ファイル: `src/main/resources/application.properties`
- 関連コマンド: `mvn spring-boot:run`

## 問題
- 期待した挙動: アプリが 8080 番で起動し、ブラウザからアクセスできる。
- 実際の挙動: 起動直後に APPLICATION FAILED TO START で終了する。
- エラーメッセージ:
  ```
  ***************************
  APPLICATION FAILED TO START
  ***************************

  Description:
  Web server failed to start. Port 8080 was already in use.

  Action:
  Identify and stop the process that's listening on port 8080 or configure this
  application to listen on another port.
  ```
- 再現手順:
  1. 一度 `mvn spring-boot:run` で起動する（Ctrl+C で止めずにターミナルを閉じる等で残す）
  2. 再度 `mvn spring-boot:run` を実行する → 上記エラーで起動失敗

## 原因
- 推測した原因: application.properties の設定ミスかと疑った。
- 確定した原因: 前回起動した Java プロセスが終了しておらず、8080 番ポートを掴み続けていた（リソース競合）。
- 原因カテゴリ: Resource
- 根拠: `lsof -i :8080` で前回の java プロセスが LISTEN 中だったことを確認。停止後は正常起動した。

## 解決策
- 試したこと:
  1. application.properties を確認 → 設定に問題なし（誤った仮説）。
  2. `lsof -i :8080` でポート占有プロセスを特定。
- 最終的な修正: 占有プロセスを停止して再起動。恒久対策として開発用ポートを分離。
  ```bash
  # 占有プロセスを特定して停止
  lsof -i :8080
  kill -9 <PID>

  # もしくは別ポートで起動
  mvn spring-boot:run -Dspring-boot.run.arguments=--server.port=8081
  ```
- 変更ファイル: `src/main/resources/application.properties`（任意：`server.port` を明示）
- Before / After:
  ```properties
  # Before（未設定 = デフォルト8080）

  # After（開発用に固定し、競合時に気づきやすくする）
  server.port=8081
  ```

## 検証
- 検証方法: 占有プロセス停止後に `mvn spring-boot:run` を再実行し、起動ログとブラウザアクセスで確認。
- テスト結果: N/A
- ビルド結果: success
- 残課題: なし

## 再発防止
- 防止策: 起動前にポート占有を確認するワンライナーを手順化。開発用に `server.port` を固定。
- 次回チェック手順:
  1. `lsof -i :8080`（または対象ポート）で占有プロセスを確認する。
  2. 残プロセスがあれば停止してから起動する。
- チェックリスト項目:
  - [ ] 起動前に対象ポートが空いているか確認したか
  - [ ] 前回の起動プロセスを確実に停止したか

## 検索タグ
- Tech: java, spring-boot, maven
- Error Type: PortInUse, APPLICATION_FAILED_TO_START
- Library: spring-boot, tomcat
- Keywords: port conflict, ポート競合, 8080 already in use, web server failed to start, EADDRINUSE
