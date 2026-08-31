# FFI 依存テストの tearDown で共有 factory / ADM / thread が leak し得る

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-webrtc-client-test-teardown-shared-factory-leak
- Polished: {YYYY-MM-DD}

## 目的

`test/` 配下の FFI 依存テストが `WebrtcClient.dispose()` を tearDownAll で
呼んで後始末しているつもりでも、共有 factory (`_sharedFactoryRef`) / 共有 ADM
(`_sharedAdmRef`) / spawn された thread 群がプロセス寿命まで解放されないため、
テスト実行中の native リソース leak が沈黙する。テスト間汚染の温床になっている
現状を、意図した設計として明文化するか、または実際に解放する API を追加する
かを決める。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient.dispose()` は `_factoryRef`
（per-client の native client）を `null` にするだけで、以下の共有リソースは
解放しない。

- `_sharedFactoryRef` (`webrtc_client.dart` の `sharedFactory` getter で lazy
  初期化される PeerConnectionFactory)
- `_sharedAdmRef` (Audio Device Module。`_ensureSharedFactory` 内で生成される)
- `_ensureSharedFactory` が spawn する native スレッド群 (worker / network /
  signaling threads)

これらは意図的にプロセス寿命まで保持される可能性が高いが、影響として次の 2 点
が観測されている。

- テスト経路で `MediaDevices.createExternalVideoTrack()` などが生成する
  native track を tearDown で解放し忘れると、共有 factory 側に生き残って
  後続テストや以降の group を汚染し得る。
- テスト実装者が「`WebrtcClient.dispose()` を呼べば FFI 経路が全て閉じる」
  と誤解しやすい (`test/sora_media_stream_test.dart` の複数 group で
  `late WebrtcClient wc;` パターンを踏襲している)。docstring や API 名
  だけからはこの限定的な破棄しか行わないことが読み取れない。

## 設計方針

以下の 2 択のどちらを採用するか判断する。

- (a) 現状の「shared リソースはプロセス寿命」の設計を意図として明文化する。
  `WebrtcClient.dispose()` の dartdoc に「per-client のみ解放し、共有
  factory / ADM / thread は解放しない」旨を明記し、テスト側は
  「共有 factory 上に生き残る native track が leak しないよう自前で
  detach + dispose する責任がある」ことを README / テストヘルパで示す。
- (b) テスト向けに `WebrtcClient.disposeSharedForTest()` (仮) のような
  `@visibleForTesting` API を追加し、テスト suite の全 group 完了後 (top-level
  `tearDownAll`) で共有 factory / ADM / thread を明示的に解放する。libwebrtc-c
  側の API と native factory の再生成可否に依存するため、実装可否は要検証。

いずれを選んでも、既存の FFI 依存 group の tearDownAll (`test/sora_media_stream_test.dart`
と `test/sora_connection_test.dart` の複数 group) の意図と整合を取る。

## 完了条件

- [ ] `WebrtcClient.dispose()` の docstring に per-client のみ解放する旨と
      共有リソースの寿命が明記されている。
- [ ] 上記 (a) / (b) いずれかを採用し、テスト suite が期待どおりに汚染
      なく走ることを確認する (可能なら test を追加)。
- [ ] `flutter analyze` と関連テストが成功する。

## 関連

- `issues/closed/0080-bug-fix-local-video-track-dispose-sync-throw.md`
  (本 issue の起点。テスト tearDown での leak リスクをレビューで検出)
