# 公開 API メソッドの dartdoc に「throw する例外」と「事前条件」を追記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-public-api-throws-dartdoc
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`SoraConnection` の主要な公開メソッドや `SoraConnectionConfig.toMap`、`SoraRpc` などが投げる例外の種類・条件が dartdoc に書かれていないため、利用者が例外ハンドリングを設計できない。dartdoc に throws / 事前条件を追記する。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection` の以下の公開メソッドは 1 行 dartdoc に留まり、実際に投げる例外や事前条件を利用者に告知していない:

- `connect(...)` — `_validateConnectStream` 経由で 8 種類の `StateError`
- `disconnect()` — `_disconnectBody` 経由の例外
- `replaceAudioTrack(...)` — `_validateReplaceAudioTrack` 経由で 4 種類の `StateError`
- `replaceVideoTrack(...)` — 同種
- `removeAudioTrack(...)` / `removeVideoTrack(...)` — 同種
- `setAudioEnabled(...)` / `setVideoEnabled(...)` — 同種
- `getStats()` — 例外条件不明
- `rpc(...)` — `SoraRpcError` と `TimeoutException`

`lib/src/sora_connection_config.dart` の `SoraConnectionConfig.toMap()` は `RangeError`（`validateAudioBitRate` / `validateVideoBitRate` 経由）を伝搬するが、dartdoc は「connect メッセージの payload へ変換する」だけ。const constructor 側で検証しないため、`connect()` 経由で初めて `RangeError` が伝播する非対称構造。

## 設計方針

- 各公開メソッドに「Throws:」節を追加する。以下を統一書式で記載:
  - 事前条件（例: 接続確立後に呼ぶこと、`LocalMediaStream` は attach 済み等）
  - 投げる例外の種類（`StateError`, `TimeoutException`, `ArgumentError`, `SoraRpcError`, `PlatformException` 等）
  - 各例外の発生条件を 1 行で
- `SoraConnectionConfig.toMap()` の dartdoc に「validation は toMap() 実行時に走る。bit rate 範囲外は `RangeError`」を明示。連携する `SoraConnectionConfig` コンストラクタの dartdoc からも参照する。
- 別 issue で `SoraConnectionConfig` の検証タイミング（コンストラクタ移行）を扱う場合、そちらの決着に合わせて追記内容を調整する。
- 「Throws:」記法は dart doc の慣習に合わせる（`/// Throws [StateError] if ...`）。

## 完了条件

- [ ] 上記公開メソッドの dartdoc に throws / 事前条件が追記されている。
- [ ] `SoraConnectionConfig.toMap()` の遅延検証が dartdoc に明記されている。
- [ ] `flutter analyze` と関連テストが成功する。
