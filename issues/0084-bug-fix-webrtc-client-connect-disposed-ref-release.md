# `WebrtcClient.connect()` が `_disposed` 時に受け取った refcounted 参照を release しない

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-webrtc-client-connect-disposed-ref-release
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`WebrtcClient.connect()` が既に `_disposed == true` の場合に受け取った `localAudioTrackRef` / `localVideoTrackRef` を release せずに early return しているため、呼び出し側が `retainNativeTrackRefcounted()` で確保した refcount が leak するバグを修正する。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient.connect` は先頭で `if (_disposed) return;` を実行するが、それより先に受け取っている `Pointer<WebrtcAudioTrackInterfaceRefcounted>? localAudioTrackRef` と `Pointer<WebrtcVideoTrackInterfaceRefcounted>? localVideoTrackRef` を release しない。ここでの `_disposed` は `WebrtcClient._disposed` であり、`SoraConnection._disposed` とは独立である。

- `SoraConnection._connect` は `SoraConnection` 側の disposed 検査後に `retainNativeTrackRefcounted` で確保して `WebrtcClient.connect` へ渡す。retain 後から `connect` 呼び出し前の間に `SoraConnection.dispose` 経由で `WebrtcClient.dispose` が走ると、`WebrtcClient._disposed` が真の状態で owned ref が渡される race window がある。通常は起きないが、API の防御性が欠けており、将来他所から呼ばれた場合も含めてリークする。
- 他の受け取り経路との一貫性としても、受け取った owned refcount は必ず解放するのが望ましい。

## 設計方針

- `WebrtcClient.connect` の `_disposed` 早期 return 経路で、`localAudioTrackRef != null` なら `_lib.audioTrackRelease(_lib.audioTrackRefcountedGet(localAudioTrackRef!))`、`localVideoTrackRef != null` なら同様に `_lib.videoTrackRelease(_lib.videoTrackRefcountedGet(localVideoTrackRef!))` を呼ぶ。release 順序は audio から video の順で `closePeerConnection` と同一にする。
- `WebrtcClient.connect` の dartdoc に所有権契約を明記する。正常系は受け取った owned ref を保持し `closePeerConnection` で解放すること、dispose 済みの場合は即時解放することを書く。
- テスト観測のため `WebrtcClient` に `@visibleForTesting` の release 記録カウンタ（audio 用と video 用の 2 件）を追加する。`connect` の disposed 経路でのみ加算し、正常系の release では加算しない。`setupPendingStatsForTest` は pending 差し替え用であり前例にしない。

## 完了条件

- [ ] `WebrtcClient.connect` の `_disposed` 早期 return 経路で `localAudioTrackRef` / `localVideoTrackRef` が確実に release される。
- [ ] disposed 経路の release をユニットテストで確認する。audio のみ、video のみ、両方あり、両方 null の 4 通りを `retainNativeTrackRefcounted` で取得した実 track で exercise し、設計方針の release 記録カウンタで判定する（モックやスタブは使わない）。libwebrtc-c が利用できない環境では `prepareFfiTestEnvironment()` + `skip:` の既存パターン（`test/webrtc_client_test.dart` の `ffiTestEnvironment.skipReason`、closed issue 0105 で確立）に倣ってスキップする。
- [ ] 正常系の回帰は `test/webrtc_client_test.dart` と `test/sora_connection_test.dart` の成功で担保する。
- [ ] `flutter analyze` と関連テストが成功する。
