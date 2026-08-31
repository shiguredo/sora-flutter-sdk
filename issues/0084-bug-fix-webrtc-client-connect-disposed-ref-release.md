# `WebrtcClient.connect()` が `_disposed` 時に受け取った refcounted 参照を release しない

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-webrtc-client-connect-disposed-ref-release
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`WebrtcClient.connect()` が既に `_disposed == true` の場合に受け取った `localAudioTrackRef` / `localVideoTrackRef` を release せずに early return しているため、呼び出し側が `retainNativeTrackRefcounted()` で確保した refcount が leak するバグを修正する。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient.connect` は先頭で `if (_disposed) return;` を実行するが、それより先に受け取っている `Pointer<WebrtcAudioTrackInterfaceRefcounted>? localAudioTrackRef` と `Pointer<WebrtcVideoTrackInterfaceRefcounted>? localVideoTrackRef` を release しない。

- 現状の呼び出し経路（`SoraConnection._connect`）で `_disposed == true` の並行状態は通常起きないが、API の防御性が欠けており、将来他所から呼ばれた場合や race で `_disposed` になった直後のケースでリークする。
- 他の受け取り経路との一貫性としても、受け取った owned refcount は必ず解放するのが望ましい。

## 設計方針

- `WebrtcClient.connect` の `_disposed` 早期 return 経路で、`localAudioTrackRef != null` なら `sharedLib.audioTrackRelease(sharedLib.audioTrackRefcountedGet(localAudioTrackRef!))`、`localVideoTrackRef != null` なら同様に `videoTrackRelease` を呼ぶ。
- release 順序は audio → video のいずれでも構わないが、既存の解放パターンに合わせる。
- 変更後の挙動を dartdoc に明記する（「dispose 済みの場合でも、渡された ref は必ず解放される」）。

## 完了条件

- [ ] `WebrtcClient.connect` の `_disposed` 早期 return 経路で `localAudioTrackRef` / `localVideoTrackRef` が確実に release される。
- [ ] `_disposed == true` の状態で `connect(localAudioTrackRef: ...)` を呼び、release 処理が実行されることをユニットテストで確認する。refcount の絶対値は Dart 側から検証できないため、release 呼び出しを記録する `@visibleForTesting` テストフック（`setupPendingStatsForTest` 等の前例に倣う）を production コードに追加して観測する。テストに渡す有効な ref は実 track から `retainNativeTrackRefcounted()` で取得し、libwebrtc-c が利用できない環境では `_ffiAvailable()` ガード（`webrtc_client_test.dart` の前例）に倣ってテストをスキップする。また、正常経路の呼び出し元（`SoraConnection._connect`）の挙動が変わらないこと（crash / 例外が発生しないこと）も確認する（モックやスタブは使わない）。
- [ ] `flutter analyze` と関連テストが成功する。
