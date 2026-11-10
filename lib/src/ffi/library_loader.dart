// ignore_for_file: public_member_api_docs
// libwebrtc-c のプラットフォーム別 DynamicLibrary ロード

import 'dart:ffi';
import 'dart:io';

// プラットフォームに応じて libwebrtc-c を含む共有ライブラリをロードする。
//
// Android / Linux / Windows は共有ライブラリを明示的に開き、
// iOS / macOS はアプリプロセスに静的リンクされたシンボルを
// `DynamicLibrary.process()` から解決する。
DynamicLibrary loadLibWebrtcC() {
  if (Platform.isAndroid) {
    // Android: libsora_sdk.so に libwebrtc-c.a + libwebrtc.a が静的リンク済み
    return DynamicLibrary.open('libsora_sdk.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS/macOS: フレームワークに静的リンク済み
    return DynamicLibrary.process();
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libsora_sdk.so');
  }
  if (Platform.isWindows) {
    // Flutter Windows プラグインの出力 DLL (libwebrtc-c / ブリッジを同梱)
    return DynamicLibrary.open('sora_sdk_plugin.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}
