/// screen キャプチャ (ReplayKit 等) の開始失敗時に
/// `SoraConnectionErrorDetails.platformError` へ載せる文字列を決定する
/// 内部ヘルパ。camera 経路は現状 `details=null` なので本ファイルの対象外。
///
/// SDK 内部専用のため `sora_sdk.dart` からは export しない。
library;

import 'package:flutter/services.dart';

/// `PlatformException` なら `code` を、それ以外の例外種別 (`StateError`,
/// `TimeoutException`, `Exception` 等) は既定値 `'screen_capture_error'` を
/// 返す。
String screenCapturePlatformErrorCode(Object error) {
  return error is PlatformException ? error.code : 'screen_capture_error';
}
