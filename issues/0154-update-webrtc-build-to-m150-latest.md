# WebRTC build を M150 の最新リリースに更新する

- Created: 2026-09-02
- Completed: {YYYY-MM-DD}
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

- [ ] `scripts/native_deps.json` のバージョンが `libwebrtc_c: 0.150.3`、`webrtc: m150.7871.3.1` になっている。
- [ ] Android / Linux / Windows 向けアーカイブの URL と SHA-256 が対象リリースと一致している。
- [ ] iOS / macOS の `Package.swift` が `libwebrtc_c` `0.150.3` を参照している。
- [ ] `lib/src/sora_sdk_version.g.dart` が `libwebrtc_c` `0.150.3` と `Shiguredo-Build M150` を表示している。
- [ ] `rtpSenderSetParameters` の Dart FFI 定義と呼び出しが `0.150.3` の out パラメータ形式になっている。
- [ ] Android / Linux / Windows のネイティブ依存取得が成功し、`required_paths` がすべて揃っている。
- [ ] 対応する Android / Linux / Windows のビルドが成功している。
- [ ] iOS / macOS の Swift Package Manager による XCFramework 取得とビルドが成功している。
- [ ] 更新対象の設定・生成物に `m150.7871.0.0` と `0.150.0` が残っていない。

## 解決方法

1. `scripts/native_deps.json` を更新する。

   `libwebrtc_c` `0.150.3` の対象 SHA-256:

   - Android: `cf166d261bbccd0c69ca9433444b94d19d6b459af530db0ad008789c9f60b28d`
   - Ubuntu 22.04: `24e129c8e74a6743671f3e4c4a1c4cec8d742fedfd6f47f3d51030302c695a61`
   - Ubuntu 24.04: `e07ed13b7f18f8f88157c6907488503919f9d46042028996bb120c534b996131`
   - Windows: `a99d782fd693687b80e2376740c5e4a9e76ec256bd77653fb0145b62c39be17e`
   - Apple XCFramework: `0b830c49d9bdfe7a16a24624765bed70c7d773347b9f466f4836555f4c275c23`

   `webrtc` `m150.7871.3.1` の対象 SHA-256:

   - Android: `f8af34a6930d2d3dd89005e1f126a5cca6906f88c5f00093109560341b51f300`
   - Ubuntu 22.04: `b94ce9403f2303ab11eee796b7643d4713c25a0900a1e702582524d854a2328d`
   - Ubuntu 24.04: `4fd5a7b6d88b3460ed77b6a55aeffcd54c7171be32ca80ade6a6ac5d05c174bf`
   - Windows: `6b63edbc0ad4ab2a736f02503c51e0a4f26dddc258d078dd39dba60111a247d7`

2. `dart run scripts/update_apple_native_binary.dart` を実行し、iOS / macOS の `Package.swift` を更新する。

3. `dart run scripts/generate_sdk_version.dart` を実行し、`lib/src/sora_sdk_version.g.dart` を更新する。

4. `lib/src/ffi/bindings.dart` の `rtpSenderSetParameters` を `void` + `out_rtc_error` 形式へ更新する。

5. `lib/src/ffi/webrtc_client.dart` の呼び出しを out パラメータ形式へ更新する。

6. 次のプラットフォームの依存取得を実行する。

   `dart run scripts/fetch_native_deps.dart android_arm64 linux_ubuntu_22_04_x86_64 linux_ubuntu_24_04_x86_64 windows_x86_64`

7. 各プラットフォームのビルドと既存テストを実行する。
   ローカルでできないプラットフォームのビルドは CI に任せてよい。
