# FFI 依存テスト group の `late WebrtcClient wc;` 冗長パターンを削除する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-test-shared-webrtc-client-boilerplate
- Polished: 2026-09-07

## 目的

FFI 依存テスト group が繰り返している `late WebrtcClient wc; setUpAll(() {
wc = WebrtcClient.create(...); }); tearDownAll(() { wc.dispose(); });`
パターンが、共有 factory の事前用意という意図に対して効果が無い状態を整理する。
`WebrtcClient.create` は Dart ラッパーの生成のみで共有 factory を初期化せず
(共有 dylib ロードの副作用はある)、`wc` はテスト本体で参照されず、`wc.dispose()`
は per-client のみ解放する。意図がコードで正しく伝わるようにする。

## 現状

以下の 7 group で同型の boilerplate が繰り返されている:

- `test/sora_media_stream_test.dart`: `LocalMediaStream track cache の参照管理 (FFI)`、`LocalVideoTrack.dispose の非同期契約 (FFI)`
- `test/sora_connection_test.dart`: `SoraConnection._handleWebrtcEvent の想定外イベント処理`、`SoraConnection.disconnect の _disconnecting / _abnormalTerminationStarted の finally リセット`、`SoraConnection._handleRedirectMessage の異常終了処理`、`SoraConnection WebSocket シグナリングメッセージ順序`、`SoraConnection._emitLocalVideo の null スキップ`

コメントの状況は group ごとに異なる。`共有 factory が必要なため事前に生成して初期化する` 旨の誤ったコメントの group と、`LocalVideoTrack.dispose の非同期契約 (FFI)` group のように lazy 生成を正しく説明しながら冗長コードが残る group が混在する。

共有 factory は `MediaDevices.createExternalVideoTrack()` などの初回呼び出しで lazy 生成される。`0150` は polished 済み ((a) 明文化案採用) のため前提は満たされている。

## 設計方針

- (a) `late WebrtcClient wc;` パターンを 7 group から削除し、共有 factory が lazy 生成される事実を setUp コメントに 1 行残す。誤ったコメントは正しい記述に直し、正しいコメントは維持する。
- (b) `sharedFactory` 事前初期化案は取らない (eager 化による初期化タイミングの変化は挙動変更になるため)。
- (c) helper 抽出案は取らない (削除後に残る共通処理が無いため)。`test/support/` への影響は無い。
- `0135` 確定までは現行の `test/` 配置に従う。
- モックとスタブは使わない。

## 完了条件

- [ ] 7 group から実効の無い boilerplate が削除され、setUp コメントが実装と一致している。
- [ ] FFI 有効・無効の両条件で実行し、skip 条件と実行結果が変更前と unchanged である。
- [ ] `flutter analyze` と `flutter test test/sora_media_stream_test.dart test/sora_connection_test.dart` が成功する。

## 関連

- `issues/0150-refactor-webrtc-client-test-teardown-shared-factory-leak.md`
  (前提充足済み。テスト側の helper 整備は本 issue が所有する)
- `issues/closed/0080-bug-fix-local-video-track-dispose-sync-throw.md`
  (本 issue の起点)
