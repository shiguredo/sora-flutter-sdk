# `_applyVideoCaptureBackend` の catch で `PlatformException.code` が消失し、エラー通知が汎用コードになる

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-video-capture-backend-platform-error-code
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`SoraConnection._applyVideoCaptureBackend` が全例外を `StateError` にラップし直しているため、`_emitVideoCaptureBackendError` の `error is PlatformException` 分岐が到達不能になり、画面キャプチャ開始失敗時にアプリ側が具体的なプラットフォームエラーコードを受け取れないバグを修正する。本 issue の主目的は screen（iOS の ReplayKit 等）のキャプチャ開始失敗で `platformError` に詳細を載せることだが、`_applyVideoCaptureBackend` は camera と screen の共有メソッドのため、catch 削除は camera 経路の公開エラー型（`StateError` → 元例外）も変える。この副作用はエラー内容がより正確になるため許容する。camera の `details` は既存設計どおり null のまま変更しない。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection._applyVideoCaptureBackend` は `catch (e) { throw StateError('Failed to apply video capture backend: $e'); }` で全例外を `StateError` にラップする。

- `_emitVideoCaptureBackendError(track, error)` の `SoraConnectionErrorDetails.platformError` は `error is PlatformException ? error.code : 'screen_capture_error'` を返すが、`_applyVideoCaptureBackend` からの例外は常に `StateError` なので `PlatformException` 分岐は決して到達しない。
- 呼び出し経路は `SoraConnection.connect` 経由の初回 capture 起動と `SoraConnection._replaceVideoTrackInternal` 経由の切替後 capture 起動の 2 つが影響を受ける。各呼び出し元の `catch (e)` は `e` をそのまま `_emitVideoCaptureBackendError(track, e)` に渡すため、`_applyVideoCaptureBackend` がラップせず rethrow すれば `PlatformException` はそのまま伝搬する。

結果として、iOS の ReplayKit がキャンセルされた場合等の詳細を、アプリ側は識別できない。

## 設計方針

- `_applyVideoCaptureBackend` の `catch (e) { throw StateError(...); }` を削除し、元の例外を rethrow する。これは camera / screen の共有メソッドのため、camera 経路でも `StateError` ラップが無くなり元例外が伝搬するが、これを許容する（camera の `details` は従来どおり null）。
- rethrow 後、呼び出し元（`SoraConnection.connect` / `_replaceVideoTrackInternal`）が `_emitVideoCaptureBackendError(track, e)` を呼ぶ経路で `e` が `PlatformException` のまま伝搬するように整える。
- `_emitVideoCaptureBackendError` の `platformError` 決定ロジック（`error is PlatformException ? error.code : 'screen_capture_error'`）をテスト可能な純粋関数として分離し、screen のキャプチャ開始失敗で `PlatformException.code` が `SoraConnectionErrorDetails.platformError` に載ることをユニットテストで検証する。モックやスタブは使わず、純粋関数に `PlatformException` の実インスタンスを渡して検証する。
- 例外種別が想定外の場合のフォールバック（`'screen_capture_error'`）と、screen 以外の分類（`SoraErrorCode.cameraOpenError` 等）は現行の分類を維持する。camera の `details` は従来どおり null のまま変更しない。

## 完了条件

- [x] `_applyVideoCaptureBackend` が `PlatformException` を wrap せずに伝搬する。
- [x] screen のキャプチャ開始失敗で `PlatformException.code` が `platformError` に載る経路がユニットテストで検証されている（純粋関数の検証。モックやスタブは使わない）。
- [x] `flutter analyze` と関連テストが成功する。

## 解決方法

`lib/src/sora_connection.dart` の `_applyVideoCaptureBackend` から `catch (e) { throw StateError(...); }` を削除し、発生した例外を元の型のままそのまま伝搬させるように変更した。呼び出し元 (`connect` / `_replaceVideoTrackInternal` の初回起動と rollback path) の `catch (e)` は `Object` 型で受けており、`_emitVideoCaptureBackendError(track, e)` にそのまま渡るため、screen (ReplayKit 等) の `PlatformException` は `SoraConnectionErrorDetails.platformError` に具体的な `code` として載る。camera 経路も元例外が伝搬するようになるが、`_emitVideoCaptureBackendError` は camera では `details` を null にする既存設計を維持する。

`platformError` 文字列の決定ロジックは `lib/src/sora_video_capture_error.dart` に純粋関数 `screenCapturePlatformErrorCode(Object error)` として切り出した。`PlatformException` なら `code` を、それ以外の例外種別 (`StateError` / `TimeoutException` / `Exception` 等) は既定値 `'screen_capture_error'` を返す。この関数は SDK 内部専用のため `sora_sdk.dart` からは export しない。テストは `package:sora_sdk/src/sora_video_capture_error.dart` を直接 import して純粋関数として検証する (既存 test の慣例)。

`_emitVideoCaptureBackendError` は上記の抽出関数を呼び出す形に更新した。camera 経路の `details=null` は現状維持。screen 以外の分類 (`SoraErrorCode.cameraOpenError`) と fallback 文字列 (`'screen_capture_error'`) も維持する。

テストは `test/sora_video_capture_error_test.dart` を新規作成。5 ケースを検証する:

- `PlatformException` (`code: 'ReplayKit_User_Declined'`) → `code` を返す
- `StateError` → フォールバック `'screen_capture_error'`
- `Exception('generic')` → フォールバック
- `String` (非例外オブジェクト) → フォールバック
- `PlatformException(code: '')` → 空文字列をそのまま返す (caller で「空 code の PlatformException」と「非 PlatformException」を区別可能にするため)
