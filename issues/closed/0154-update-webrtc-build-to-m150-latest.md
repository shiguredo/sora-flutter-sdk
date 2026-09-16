# WebRTC build を M150 の最新リリースに更新する

- Created: 2026-09-02
- Completed: 2026-09-02
- Branch: feature/update-webrtc-build-to-m150-latest
- Polished: 2026-09-02
- Milestone: 2026.1.0

## 目的

現在の SDK は M150 の初回リリース (`m150.7871.0.0`) を基準にしたネイティブ依存を使用している。

[webrtc-build の M150 最新リリース (`m150.7871.3.1`)](https://github.com/shiguredo-webrtc-build/webrtc-build/releases/tag/m150.7871.3.1) と、対応する [`libwebrtc_c` `0.150.3`](https://github.com/shiguredo/webrtc-rs/releases/tag/0.150.3) へ更新し、2026.1.0 のリリースに M150 系列の最新 WebRTC バイナリを使用する。

`libwebrtc_c` `0.150.1` 以降ではエラー伝達が out パラメータ方式に統一されており、依存更新と同時に Dart FFI も追従する。

## 現状

- `scripts/native_deps.json` の `libwebrtc_c.version` は `0.150.0` である。
- `scripts/native_deps.json` の `webrtc.version` は `m150.7871.0.0` である。
- `webrtc-rs` `0.150.3` のパッケージメタデータは、内部の WebRTC 依存として `m150.7871.3.1` を指定している。
- Android / Linux / Windows は `webrtc-build` のアーカイブを `scripts/fetch_native_deps.dart` で取得する。
- iOS / macOS は `webrtc-rs` の `libwebrtc_c.xcframework.zip` を Swift Package Manager で取得する。
- `ios/sora_sdk/Package.swift` と `macos/sora_sdk/Package.swift` は `libwebrtc_c` `0.150.0` を参照している。
- `lib/src/sora_sdk_version.g.dart` は `libwebrtc_c` `0.150.0` と `Shiguredo-Build M150` を表示している。
- `lib/src/ffi/bindings.dart` の `rtpSenderSetParameters` は、`webrtc_RtpSenderInterface_SetParameters` を `RTCError_unique*` 戻り値形式で lookup している。
- `lib/src/ffi/webrtc_client.dart` は、その戻り値を受け取る呼び出し方で simulcast encodings 適用に `rtpSenderSetParameters` を使っている。
- `libwebrtc_c` `0.150.3` の `webrtc_RtpSenderInterface_SetParameters` は `void` 戻り値と `out_rtc_error` 引数の形式へ変わっている。
- `webrtc_RtpTransceiverInterface_SetCodecPreferences` も同様の形式変更があるが、現行 SDK の Dart コードは未使用である。

## 設計方針

- `scripts/native_deps.json` を依存関係の正本として更新する。
- `libwebrtc_c` は `0.150.0` から対応する `0.150.3` へ更新する。
- `webrtc` は `m150.7871.0.0` から `m150.7871.3.1` へ更新する。
- 各プラットフォームのアーカイブ名は現在の構成を維持し、対象リリースの SHA-256 に更新する。
- iOS / macOS は `webrtc-build` の `WebRTC.xcframework.zip` ではなく、既存どおり `webrtc-rs` の `libwebrtc_c.xcframework.zip` を使用する。
- `Package.swift` と `sora_sdk_version.g.dart` は更新スクリプトで生成する。
- `lib/src/ffi/bindings.dart` の `rtpSenderSetParameters` を `0.150.3` の out パラメータ形式に合わせる。
- `lib/src/ffi/webrtc_client.dart` の呼び出し側も out パラメータ形式に合わせる。
- `SetCodecPreferences` は SDK 未使用のため、本 issue では変更しない。
- 正式リリース前のため `CHANGELOG.md` には追記しない（`CODEBASE.md`）。

## 完了条件

- [x] `scripts/native_deps.json` のバージョンが `libwebrtc_c: 0.150.3`、`webrtc: m150.7871.3.1` になっている。
- [x] Android / Linux / Windows 向けアーカイブの URL と SHA-256 が対象リリースと一致している。
- [x] iOS / macOS の `Package.swift` が `libwebrtc_c` `0.150.3` を参照している。
- [x] `lib/src/sora_sdk_version.g.dart` が `libwebrtc_c` `0.150.3` と `Shiguredo-Build M150` を表示している。
- [x] `rtpSenderSetParameters` の Dart FFI 定義と呼び出しが `0.150.3` の out パラメータ形式になっている。
- [x] Android / Linux / Windows のネイティブ依存取得が成功し、`required_paths` がすべて揃っている。
- [ ] 対応する Android / Linux / Windows のビルドが成功している（CI で確認）。
- [ ] iOS / macOS の Swift Package Manager による XCFramework 取得とビルドが成功している（CI で確認）。
- [x] 更新対象の設定・生成物に `m150.7871.0.0` と `0.150.0` が残っていない。

## 解決方法

1. `scripts/native_deps.json` を `libwebrtc_c` `0.150.3` / `webrtc` `m150.7871.3.1` と各 SHA-256 へ更新した。
2. `dart run scripts/update_apple_native_binary.dart` で iOS / macOS の `Package.swift` を更新した。
3. `dart run scripts/generate_sdk_version.dart` で `lib/src/sora_sdk_version.g.dart` を更新した。
4. `lib/src/ffi/bindings.dart` の `rtpSenderSetParameters` を `void` + `out_rtc_error` 形式へ更新した。
5. `lib/src/ffi/webrtc_client.dart` の呼び出しを `pcAddTrack` と同様の `rtcErrorMessage` パターンへ更新した。
6. `dart run scripts/fetch_native_deps.dart` で Android / Linux / Windows 向け依存取得が成功した。
7. `flutter test` を実行した。各プラットフォームのビルドは CI で確認する。
