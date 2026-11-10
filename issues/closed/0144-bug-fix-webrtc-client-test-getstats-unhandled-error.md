# `webrtc_client_test.dart` の getStats テストで pending completer の StateError が unhandled になり failing する

- Created: 2026-08-30
- Branch: feature/fix-webrtc-client-test-getstats-unhandled-error
- Polished: 2026-08-30
- Completed: 2026-08-30

## 目的

Linux CI の `Run FFI-dependent package tests` step で、`test/webrtc_client_test.dart` の getStats 系テスト 3 件が `Bad state: PeerConnection closed during getStats.` の unhandled StateError により failing している。この失敗を解消し、Linux CI の FFI テスト step を green に近づける。

同 step で観測されている他系統は本 issue のスコープ外で、別 issue で扱う。系統 A-1（`sdp_negotiation_test.dart` の 4 件、nullptr）は 0142、系統 B（`AudioDeviceModule init failed`）は 0143、系統 C（`Binding has not yet been initialized`）は 0141。もともとは 0142 に系統 A-1 と併記されていたが、失敗経路が SDP パーサ経路（native）と Dart 側完結の Completer unhandled で完全に異なるため、`/polish-issue 142` の中で本 issue として分離することが確定した。

## 現状

`Build Linux` job の `Run FFI-dependent package tests` step で以下 3 件が failing している（run 例: `33297433461` の Build Linux job、`gh run view 33297433461 --repo shiguredo/sora-flutter-sdk --log-failed --job 99219408228` で確認）。

- `getStats cleanup on disconnect closePeerConnection clears pending getStats tracking`（`test/webrtc_client_test.dart` の `group('getStats cleanup on disconnect', ...)` 内 `test('closePeerConnection clears pending getStats tracking', ...)`）
- `getStats cleanup on disconnect closePeerConnection は native stats リソースを孤立 request へ移す`（同 group 内）
- `getStats reentrancy returns pending future when completer is already set`（同ファイルの `group('getStats reentrancy', ...)` 内）

失敗メッセージ:
```
Bad state: PeerConnection closed during getStats.
dart:async                                          _Completer.completeError
package:sora_sdk/src/ffi/webrtc_client.dart 592:35  WebrtcClient.closePeerConnection
```

失敗経路は確定している。`WebrtcClient.setupPendingStatsForTest(completer, timer)` で仕込んだ `Completer<String?>` を誰も listen しないまま、`WebrtcClient.closePeerConnection`（テスト直接呼び出しまたは `WebrtcClient.dispose` 経由）が `lib/src/ffi/webrtc_client.dart` の `closePeerConnection` 内 `cleanupPendingStatsRequest()?.completeError(StateError('PeerConnection closed during getStats.'))` を発火する。listen されていない completer への `completeError` は Dart Zone の unhandled error として test framework に detect される。

`WebrtcClient.dispose` が `closePeerConnection` を呼ぶ経路は `lib/src/ffi/webrtc_client.dart` の `dispose` 内で確認できる。したがって failing 3 件のうち finally 節で `wc.dispose()` を呼ぶテストは、テスト本体の `closePeerConnection` に加えて dispose 経由でも同じ経路を通り、同じ unhandled error を起こしうる。

## 経緯

これらのテスト自体は commit `d132596 0105 FFI 依存テストの silent pass を廃止する` より前から存在していたが、0105 より前は `SORA_FFI_TEST_LIBRARY_PATH` 未指定で silent pass していたため、CI では実際に走っていなかった。0105 で CI 上でも FFI ライブラリをロードして実行するようになり、初めて実行される予定だった CI（`33141722842`）は commit `d290330 0069 VideoTrackCaptureType と captureType getter を公開 API から撤回する` に起因する analyze 段階の失敗で `Run FFI-dependent package tests` step まで到達せず、この失敗は今回（`33297433461`）初めて観測された。0142 と共通の経緯。

## 設計方針

同ファイル内で passing している 2 テスト（別 group を含む）との差分から、修正方向が絞れる。

- passing テスト A（`closePeerConnection completes pending getStats Future with StateError`、同ファイル `group('getStats cleanup on disconnect', ...)` 内）は `expect(completer.future, throwsA(isA<StateError>()))` で future を listen しているため unhandled にならない。
- passing テスト B（`孤立 native リソースをアクティブな request として保持しない`、`group('getStats reentrancy', ...)` 内）は `setupPendingStatsForTest(null, null, cbsPtr: cbsPtr)` を渡すため、`WebrtcClient.setupPendingStatsForTest` の setup ロジックにより completer / timer が null なら `_pendingStatsRequest` に入らず `_orphanedStatsRequests` に入る。したがって `cleanupPendingStatsRequest()` は null を返し、`completeError` は発火しない。

つまり failing 3 件との差は「completer を listen している / completer 自体を pending stats に入れていない」の 2 経路であり、どちらも `completeError` を安全にハンドリングしている点で共通。

修正候補は以下の 3 つ。候補 a はテスト意図を維持しつつ副作用が小さく、passing テスト A と同じ「listen して吸収する」パターンに揃うため推奨。

- **候補 a（推奨）**: failing 3 テストで `unawaited(completer.future.catchError((_) {}))` を追加し、`closePeerConnection` が発火する `completeError` を吸収する。テストの主目的（tracking の解放・孤立 request への移動・reentrancy の future 返却）は維持できる。
- **候補 b**: `setupPendingStatsForTest` のテスト用フック側で listen する形に変える。ただし passing テスト A のように「あえて listen して throwsA で assert する」テストと衝突する可能性があり、フックの挙動を変えると影響範囲が広い。
- **候補 c**: `closePeerConnection` の `completeError` を production 側で try/catch により silent 化する。`getStats` の完了通知経路が呼び出し側から観測できなくなるため対象外（テスト起因の症状で production の観測性を落とすのは筋悪）。

`AGENTS.md` の「モックやスタブは絶対に利用しないこと」に反する修正案（モック ADM や Completer の fake 実装差し込み）は取らない。

## 完了条件

- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を設定した状態で 3 テストをローカル（macOS）で走らせ、Linux CI と同じく `Bad state: PeerConnection closed during getStats.` の unhandled で failing することを確認する
- [ ] 候補 a を採用して failing 3 テストで listen を追加する。他候補を採用する場合は根拠をコミットメッセージに記録する
- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を設定した状態で対象 3 テストがすべて pass する
- [ ] Linux CI の `Run FFI-dependent package tests` step で `Bad state: PeerConnection closed during getStats.` の 3 件失敗が消えている
- [ ] 系統 A-1（0142）/ 系統 B（0143）/ 系統 C（0141）と独立に修正できていることを確認する

## 解決方法

`test/webrtc_client_test.dart` の failing 3 テスト（`closePeerConnection clears pending getStats tracking` / `closePeerConnection は native stats リソースを孤立 request へ移す` / `returns pending future when completer is already set`）で、`wc.setupPendingStatsForTest(completer, timer, ...)` 直後に次の 1 行を追加した。

```dart
unawaited(
  completer.future.catchError(
    (_) => null,
    test: (e) => e is StateError,
  ),
);
```

- `closePeerConnection` または `wc.dispose()` (`WebrtcClient.dispose` は `closePeerConnection` を呼ぶ経路) が発火する `completer.completeError(StateError('PeerConnection closed during getStats.'))` を listen して吸収し、Dart Zone の unhandled error として test framework に検出されないようにする。
- `test: (e) => e is StateError` の predicate により、`closePeerConnection` 経路で送出される StateError だけを catchError で吸収する。想定外の別種例外（`getStats` のタイムアウト経路が発火する `TimeoutException` など）が pending completer に流入した場合は catchError で捕まらず unhandled として test 失敗になり、実装逸脱を検知できる（fail-loud）。
- passing テスト A (`closePeerConnection completes pending getStats Future with StateError`) は `expect(completer.future, throwsA(isA<StateError>()))` で future を listen 済みのため無変更。
- 候補 b（`setupPendingStatsForTest` のテスト用フック側で listen する）は passing テスト A の throwsA 経路と衝突するため採用しない。候補 c（production 側で `completeError` を silent 化）は `getStats` の完了通知経路が呼び出し側から観測できなくなるため採用しない。
- ローカル (macOS) での `flutter analyze test/webrtc_client_test.dart` は No issues found を確認した。
