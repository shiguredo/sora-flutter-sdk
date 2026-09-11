# 公開 API メソッドの dartdoc に「throw する例外」と「事前条件」を追記する

- Created: 2026-08-27
- Completed: 2026-09-11
- Branch: feature/doc-add-public-api-throws-dartdoc
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`SoraConnection` の主要な公開メソッドや `SoraConnectionConfig.toMap`、`rpc(...)` などが投げる例外の種類・条件が dartdoc に書かれていないため、利用者が例外ハンドリングを設計できない。dartdoc に例外 / 事前条件を追記する。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection` の以下の公開メソッドは例外や事前条件の告知が不足している:

- `connect(...)` — `_validateConnectStream` 経由で 9 箇所の `StateError` (`sora_connection.dart` 1600〜1649)。`connect` 全体では disposed 時の `StateError`、`TimeoutException`、取消系 `StateError` も伝播する。
- `disconnect()` — `_ensureNotDisposed` を呼ばない (disposed 後に投げない)。`_disconnectWithTimeout` による `TimeoutException` へのラップがある。
- `replaceAudioTrack(...)` — `_validateReplaceAudioTrack` の直接 3 条件に加え、委譲先 `_validateAttachedStream` の 2 条件と `ensureNotDisposed` 由来の `StateError` が伝播する。
- `replaceVideoTrack(...)` / `removeAudioTrack(...)` / `removeVideoTrack(...)` — audio / video の有効条件がメソッドごとに異なるため一括りにはできない。
- `setAudioEnabled(...)` / `setVideoEnabled(...)` — `_ensureNotDisposed` のみであり、disposed 時の `StateError` のみ投げる。上記 validate 系とは別扱いとする。
- `getStats()` — `_ensureNotDisposed` 由来の `StateError`、`WebrtcClient.getStats` の 5 秒 `TimeoutException` を投げうる。`_pcRef == null` の場合は例外ではなく `null` を返す。
- `rpc(...)` — `_ensureNotDisposed` 由来の `StateError`、`SoraRpcError`、`TimeoutException` (`timeoutMs` 指定時のみ) を投げうる。`notification` 時は応答を待たず `null` を返す。

`lib/src/sora_connection_config.dart` の `SoraConnectionConfig.toMap()` は `RangeError`（`validateAudioBitRate` / `validateVideoBitRate` 経由）を伝搬するが、dartdoc は「connect メッセージの payload へ変換する」だけ。`toMap()` は接続生成時 (`Sora.createConnection` → `internalCreate` / `_createWithOnEvent`) に呼ばれるため、利用者が `RangeError` に遭遇するのは生成時である。`0091-add-connection-config-validation` で const 維持・`toMap()` 検証が決着済みであり、同 issue の完了後は `signalingUrls` / `channelId` 空検証の `ArgumentError` が追加される。

## 設計方針

- 対象は現状列挙の 10 メソッド + `SoraConnectionConfig.toMap` に確定する。それ以外の公開メソッド (`sendDataChannelMessage`、`dispose` 等) は扱わない。
- 各公開メソッドに例外と事前条件を追記する。AGENTS.md「コメントは全て日本語にすること」に従い日本語で記載し、例外型は `[StateError]` のような参照形式で示す。各例外の発生条件を 1 行で書く。件数の断定は行わず、条件ごとに列挙する。
- `SoraConnectionConfig.toMap()` の dartdoc に「validation は toMap() 実行時 (接続生成時) に走る。bit rate 範囲外は `RangeError`、`signalingUrls` / `channelId` 空は `ArgumentError`」を明示する。`SoraConnectionConfig` コンストラクタの dartdoc からも参照する。
- `0091-add-connection-config-validation` は const 維持・`toMap()` 検証で決着済みのため、その前提で記載する。本 issue は `0091` の完了後に着手する。
- `getStats()` 前の dartdoc は `0095-fix-dartdoc-broken-by-line-comment` の `///` 統一範囲と重なるため、`0095` 側の修正を優先し、本 issue は例外追記のみ行う。
- 挙動を変更しない。ドキュメントのみの修正。

## 完了条件

- [ ] 対象 10 メソッドと `SoraConnectionConfig.toMap` の dartdoc に例外 / 事前条件が追記されている。
- [ ] `SoraConnectionConfig.toMap()` の生成時検証 (`RangeError` + `ArgumentError`) が dartdoc に明記されている。
- [ ] `flutter analyze` が成功する。ドキュメントのみの変更のため専用の関連テストはなし。

## 解決方法

- `lib/src/sora_connection.dart` の公開メソッド 10 件 (`connect` / `disconnect` / `replaceAudioTrack` / `replaceVideoTrack` / `removeAudioTrack` / `removeVideoTrack` / `setAudioEnabled` / `setVideoEnabled` / `getStats` / `rpc`) に、投げる例外と発火条件を条件ごとに追記した。
- 例外型は `[StateError]` のような参照形式で示し、件数は断定しなかった。`disconnect()` が dispose 済みでも例外を投げないこと、`getStats()` が PeerConnection 未生成で上限未達の場合に `null` を返すこと、`rpc()` が `notification` 指定時に `null` を返すことも明記した。
- `lib/src/sora_connection_config.dart` の `toMap()` に、検証が接続生成時に走ることと `ArgumentError` / `RangeError` の条件を明記し、クラスドキュメントから `toMap()` を参照するようにした。
