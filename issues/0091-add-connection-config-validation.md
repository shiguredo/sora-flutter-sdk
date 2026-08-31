# `SoraConnectionConfig` の `signalingUrls` / `channelId` 空検証を早期化する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-connection-config-validation
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`SoraConnectionConfig` が `signalingUrls: []` / `channelId: ''` を受け入れ、`connect()` の実行時に素の `Exception('No signaling URLs configured')` で失敗する現状を、`toMap()` の段階で `ArgumentError` として fail-fast する形に修正する。

## 現状

`lib/src/sora_connection_config.dart` の `SoraConnectionConfig` のコンストラクタは `signalingUrls` / `channelId` の空検証を行わない。`toMap()` は `validateAudioBitRate` / `validateVideoBitRate` を呼んで bit rate を検証するが、URL / channelId の空検証は含まない。

- `SoraConnection.connect` 経由の `_connectWebSocket` で全 URL を舐めた後、`throw lastError ?? Exception('No signaling URLs configured')` に到達する。この Exception は `ArgumentError` ではなく素の `Exception` で、呼び出し側は型で判別しにくい。
- `channelId: ''` は connect メッセージに空文字列が入り、Sora 側で reject されるまで気付かない。

## 設計方針

- 検証場所は `toMap()` に統一する。`SoraConnectionConfig` は const コンストラクタ（`sora_connection_config.dart` の 10 行）を持ち、const コンストラクタはボディを持てないため throw を伴う検証を書けない。コンストラクタ検証には const の廃止（factory 化）が必要になり、既存テスト（`test/sora_connection_config_test.dart` の「const コンストラクターでビットレート未指定の設定を作成できる」）とユーザーコードへの破壊的変更になるため採用しない。
- 既存の `toMap()` は 146 行に「const コンストラクターを維持するため、接続設定の利用時に検証する。」と設計判断を明記しており、本 issue はこの判断を踏襲する。
- `toMap()` で以下を validate する:
  - `signalingUrls.isNotEmpty` を要求。`ArgumentError.value(signalingUrls, 'signalingUrls', ...)` で拒否する。
  - `channelId.isNotEmpty` を要求。同様に `ArgumentError.value` で拒否する。
- 既存の bit rate 検証（`validateAudioBitRate` / `validateVideoBitRate`）との責務分担を dartdoc に明記する。検証責務の分担は次のとおり: フィールドの空検証は `toMap()`、各 URL 要素の形式検証は既存の `_connectWebSocket` 内（`ArgumentError.value(urlString, 'signalingUrls', 'Invalid signaling URL')`）のまま変更しない。
- 0059（サイマルキャストマルチコーデック）は `SoraConnectionConfig` のコンストラクタで `ArgumentError` を送出する方針を既定としている。本 issue で検証場所を `toMap()` に統一する場合、0059 の設計方針を `toMap()` 側に合わせて修正する必要があることを明記する。

## 完了条件

- [ ] `SoraConnectionConfig(signalingUrls: [], ...).toMap()` および `signalingUrls: ['ws://...']` かつ `channelId: ''` の `toMap()` が `ArgumentError` で拒否される。
- [ ] 上記シナリオを exercise するユニットテストを追加する。
- [ ] 既存の bit rate 検証との検証責務分担が dartdoc に明記される。
- [ ] 0059 の設計方針（コンストラクタ検証）が本 issue の決定（`toMap()` 検証）と整合するよう更新される。
- [ ] `flutter analyze` と関連テストが成功する。
