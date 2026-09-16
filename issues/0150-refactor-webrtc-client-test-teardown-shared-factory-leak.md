# `WebrtcClient.dispose()` の共有リソース非解放を意図として明文化する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-webrtc-client-test-teardown-shared-factory-leak
- Polished: 2026-09-07

## 目的

`test/` 配下の FFI 依存テストが `WebrtcClient.dispose()` を tearDownAll で
呼んで後始末しているつもりでも、共有 factory (`_sharedFactoryRef`) / 共有 ADM
(`_sharedAdmRef`) / 共有 simulcast factory / spawn された thread 群がプロセス寿命まで解放されない。
テスト実装者が「`WebrtcClient.dispose()` を呼べば FFI 経路が全て閉じる」
と誤解しやすい状態を、`dispose()` の dartdoc 明文化で解消する。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient.dispose()` は per-client の
`_factoryRef` を `null` にするだけで、以下の共有リソースは解放しない (成功系に解放経路は無い。解放は失敗時の `_releaseSharedFactoryResources` のみ)。

- `_sharedFactoryRef` (`sharedFactory` getter で lazy 初期化される PeerConnectionFactory)
- `_sharedAdmRef` (Audio Device Module。`_ensureSharedFactory` 内で生成される)
- `_sharedSimulcastVideoEncoderFactory` (`_ensureSharedFactory` 内で生成される)
- `_ensureSharedFactory` が spawn する native スレッド群 (worker / network /
  signaling threads)

`disconnect()` の docstring は共有リソース残存を明記しているが、`dispose()` の
docstring は「`disconnect()` 相当の片付け」と書くのみで限定破棄が読み取れない。

未 dispose の native track が生き残ると後続テストを汚染し得る懸念がある
(観測事実ではなく懸念である)。`test/sora_media_stream_test.dart` と
`test/sora_connection_test.dart` の複数 group が `late WebrtcClient wc;`
パターンで `tearDownAll` に `wc.dispose()` を呼んでいる。

## 設計方針

- (a) 現状の「shared リソースはプロセス寿命」の設計を意図として明文化する案を採用する。
  `WebrtcClient.dispose()` の dartdoc に「per-client のみ解放し、共有
  factory / ADM / simulcast factory / thread は解放しない」旨を明記する。
- (b) 共有 dispose API 追加案は取らない。成功系の解放・再生成の安全性が未検証であり、
  失敗経路の cleanup (`_releaseSharedFactoryResources`) が既存のためである。
  leak が実測された場合は別 issue で再検討する。
- テスト側の helper 整備 (detach + dispose 責任の示し方) は `0151` が所有するため、
  本 issue では `dispose()` の dartdoc 明文化のみ行う。
- 挙動変更なし。ドキュメントのみ。

## 完了条件

- [ ] `WebrtcClient.dispose()` の docstring に per-client のみ解放する旨と
      共有リソース 4 点の寿命が明記されている。
- [ ] `flutter analyze` と `flutter test test/webrtc_client_test.dart` が成功する。
