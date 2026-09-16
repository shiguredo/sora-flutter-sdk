# `sora_connection_test.dart` の FFI テストで `TestWidgetsFlutterBinding.ensureInitialized()` 未呼び出しで `Binding has not yet been initialized` になる

- Created: 2026-08-30
- Branch: feature/fix-sora-connection-test-binding-not-initialized
- Polished: 2026-08-30
- Completed: 2026-08-30

## 目的

`test/sora_connection_test.dart` の FFI 依存テスト 5 件が Linux CI の `Run FFI-dependent package tests` step で `Binding has not yet been initialized` により失敗している。この失敗を解消し、Linux CI の FFI テスト step を green に近づける。系統 A（`Pointer<Never>` 失敗）と系統 B（`AudioDeviceModule init failed`）は同じ CI step 内の別原因の失敗であり、それぞれ別 issue（0142 / 0143）で扱う。

## 現状

`Build Linux` job の `Run FFI-dependent package tests` step で以下 5 件のテストが失敗している（run 例: `33297433461` の Build Linux job）。

- `SoraConnection._handleWebrtcEvent の想定外イベント処理 kind が空の remote_track_added で error event が発火する`
- `SoraConnection._handleWebrtcEvent の想定外イベント処理 trackId が空の remote_track_removed で error event が発火する`
- `SoraConnection._handleWebrtcEvent の想定外イベント処理 Sora フォーマット外 trackId で error event が発火する`
- `SoraConnection._handleWebrtcEvent の想定外イベント処理 正常な remote_track_added では error event が発火しない`
- `SoraConnection._handleWebrtcEvent の想定外イベント処理 異常終了の teardown 失敗が zone unhandled error にならない`

失敗メッセージ:
```
Binding has not yet been initialized.
The "instance" getter on the ServicesBinding binding mixin is only available once that binding has been initialized.
Typically, this is done by calling "WidgetsFlutterBinding.ensureInitialized()" or "runApp()" (the latter calls the former).
In a test, one can call "TestWidgetsFlutterBinding.ensureInitialized()" as the first line in the test's "main()" method to initialize the binding.
```

同じ「Binding has not yet been initialized」が各テストで複数回発生する。CI ログ上では次の 2 経路で発火している。

- `SoraConnection.createForTest` → `SoraConnection` コンストラクタ内の `_eventChannel.receiveBroadcastStream().listen(...)` → `ServicesBinding.instance` 参照時に失敗
- 各テストの `finally { await connection.dispose(); }` → `SoraConnection.dispose` → `soraMethodChannel.invokeMethod<void>('disposeClient', ...)` → `ServicesBinding.instance` 参照時に失敗

該当テストは `9283f32 0075 _handleWebrtcEvent が返す Future を捨てているため _require* の StateError が silent drop するのを修正する` と `c1cef36 0079 unawaited(_handleAbnormalTermination(...)) の .catchError 欠如で teardown 例外が zone unhandled になるのを修正する` で新規追加された。追加時点の CI（`33141722842`）は同時期に merge された `d290330 0069 VideoTrackCaptureType と captureType getter を公開 API から撤回する` が起因する devtools analyze 失敗で早期停止したため、`Run FFI-dependent package tests` step が一度も実行されず、この失敗はこれまで観測されていなかった。

## 設計方針

`SoraConnection.createForTest` と `SoraConnection.dispose` の両方で MethodChannel / EventChannel を経由する API を呼ぶため、テスト側で Flutter binding を初期化する必要がある。

- `test/sora_connection_test.dart` の `void main()` の冒頭で `TestWidgetsFlutterBinding.ensureInitialized()` を呼ぶ。
- 同様に MethodChannel を経由する dispose 経路を持つ他の FFI テストファイルにも同じ対応が必要か確認する（例: `test/sora_data_channel_controller_test.dart`、`test/sora_media_stream_test.dart` など）。ただし本 issue のスコープは `sora_connection_test.dart` のみとし、追加対応が必要なら別 issue に分ける。
- MethodChannel を Mock する等の抜け道は取らない（`AGENTS.md` 「モックやスタブは絶対に利用しないこと」に反するため、および実 dispose 経路を検証したいテスト意図に反するため）。
- `TestWidgetsFlutterBinding` は `flutter_test` パッケージが提供する。追加の依存は不要。
- `TestWidgetsFlutterBinding.ensureInitialized()` を追加すると `Binding has not yet been initialized` は解消するが、`SoraConnection.dispose` の `soraMethodChannel.invokeMethod<void>('disposeClient', ...)` は例外を握り潰さない実装のため、失敗理由が `MissingPluginException: No implementation found for method disposeClient on channel sora_sdk/method` に切り替わることが予想される（`sora_sdk/method` チャネルの handler が未登録のテスト binding では `TestDefaultBinaryMessenger` が null response を返し、`invokeMethod` が `missingOk: false` で `MissingPluginException` を投げる）。実装フェーズで実際に走らせて挙動を確認し、切り替わった場合は次のいずれかで追加対応する。Mock 登録を用いる案（`TestDefaultBinaryMessenger.setMockMethodCallHandler` 等）は上の「Mock する等の抜け道は取らない」方針に反するため採用しない。
  - 案 1: `SoraConnection.dispose` 側で `soraMethodChannel.invokeMethod<void>('disposeClient', ...)` の `MissingPluginException` のみを握り潰す。ただし本番挙動（Android / iOS / macOS / Windows / Linux 実機）で `disposeClient` の実装が欠落した状態を silent に許容してしまうため、本番のリソース解放が失敗しても検知できなくなる副作用を評価する。
  - 案 2: テスト側で `try { await connection.dispose(); } on MissingPluginException { ... }` によりテスト環境固有の期待挙動として吸収する。dispose の native 側完了を検証するテストではないため、既存 5 テストの意図には反しない。

## 完了条件

- [ ] `test/sora_connection_test.dart` に `TestWidgetsFlutterBinding.ensureInitialized()` を追加する
- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を設定した状態で 5 テストを実行し、`Binding has not yet been initialized` が解消することを確認する
- [ ] 追加対応が必要になった場合は、上記案 1 / 案 2 のいずれかを採用した根拠を issue 本文か PR 説明に記録する
- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を設定した状態で、上記 5 テストがすべて pass する
- [ ] Linux CI の `Build Linux` job の `Run FFI-dependent package tests` step で、これらのテストが `Binding has not yet been initialized` および `MissingPluginException` で失敗しない
- [ ] 系統 A / 系統 B（issue 0142 / 0143）が未解決でも、系統 C の失敗が消えて件数が減っていることを CI ログで確認できる

## 解決方法

`test/sora_connection_test.dart` を次のとおり修正した。

- `main()` 冒頭で `TestWidgetsFlutterBinding.ensureInitialized()` を呼び、`SoraConnection` のコンストラクタと `dispose` から参照される `ServicesBinding.instance` が未初期化のまま `Binding has not yet been initialized` が発火する経路を解消した。
- 予想通り、`SoraConnection.dispose` の末尾で走る `soraMethodChannel.invokeMethod<void>('disposeClient', ...)` はテスト binding に `sora_sdk/method` の handler が登録されていないため `MissingPluginException` を送出するようになる。この点は「## 設計方針」の案 2 を採用し、`disposeConnection(SoraConnection)` ヘルパで `try { await connection.dispose(); } on MissingPluginException catch (_) { ... }` として吸収した。案 1（`SoraConnection.dispose` 側で握り潰す）を採用しなかったのは、本番実装（Android / iOS / macOS / Windows / Linux）で `disposeClient` の handler が欠落した場合に silent に許容してしまい、実機のリソース解放失敗を検知できなくなる副作用を避けるため。
- EventChannel 側の `listen` / `cancel` 経路（`_subscription = _eventChannel.receiveBroadcastStream().listen(...)` と `_subscription?.cancel()`）で発生する `MissingPluginException` は Flutter services 層で `FlutterError.reportError` に吸収され、`await connection.dispose()` の catch までは届かない。macOS 上で最小再現テストを走らせた結果、`test()`（`testWidgets()` ではない）は EventChannel の未登録 handler 由来の `MissingPluginException` で fail しないことを確認したため、CI 側で対処しなければならない追加処理は導入しなかった。
- 5 テストの `finally { await connection.dispose(); }` を `await disposeConnection(connection)` に置換した。ヘルパは group 内に閉じておき、他 FFI テストへの共有化は必要性が生じたときに別 issue で扱う。
- test 5「異常終了の teardown 失敗が zone unhandled error にならない」の待ち合わせを `await Future<void>.delayed(Duration.zero)` から `await pumpEventQueue()` へ差し替えた。`_handleAbnormalTermination` は `_closeSignalingTransport` と `_teardownNativeSession` の複数 await gap を経由してから `.catchError` が debug message を emit するため、単一 microtask では assert 対象の debug message 到達を待てず isTrue が false になる（Linux CI run `33312038430` で顕在化）。`pumpEventQueue` で pending のマイクロタスクとタイマーを最後まで処理する。
