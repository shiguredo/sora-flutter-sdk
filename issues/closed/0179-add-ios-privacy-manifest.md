# iOS に PrivacyInfo.xcprivacy を同梱する

- Created: 2026-11-04
- Completed: 2026-11-11
- Branch: feature/ios-required-reason-api
- Polished: {YYYY-MM-DD}

## 目的

本 SDK の iOS 実装は Required Reason API を利用しているが、PrivacyInfo.xcprivacy を同梱していない。SDK を利用するアプリが App Store Connect で ITMS-91053 の指摘を受ける状態を解消するため、SDK 側で Required Reason API の利用理由を宣言した manifest を同梱する。

sora-ios-sdk は WebRTC を dynamic framework (WebRTC.framework) として取り込み、WebRTC.framework が PrivacyInfo.xcprivacy を同梱している。一方、本 SDK の libwebrtc_c は静的ライブラリ (`.a`) のみで構成され、manifest を同梱できない。SwiftPM の binaryTarget にも resources を宣言できないため、SDK 側の manifest で WebRTC 由来の分も含めて宣言する必要がある。

## 現状

- `ios/sora_sdk` に PrivacyInfo.xcprivacy はなく、`Package.swift` の `sora_sdk` target にも resources 宣言はない。
- `ios/sora_sdk/Sources/sora_sdk/SoraScreenCapturer.swift` の `ProcessInfo.processInfo.systemUptime` 利用は SystemBootTime に分類される (0178 で解消する)。
- libwebrtc_c 0.150.3 の iOS スライス `ios-arm64/lib00.a` は静的アーカイブで、PrivacyInfo.xcprivacy を含まない。未定義シンボルに `_mach_absolute_time`、`_stat`、`_fstat`、`_lstat`、`_statvfs` を含む。
- 実際の Release ビルド (`flutter build ios --release --no-codesign`) の `Runner.app/Runner` に `_mach_absolute_time` と `_stat` が残る。dead_strip が有効でも消えない。`_stat` は `webrtc_objc_blob.o` の `RTCFileLogger` が ObjC クラスリスト経由で残り、`file_rotating_stream.o` を引き込むためである。
- 独立スキャナで確認した結果、最終バイナリから検出されるカテゴリは SystemBootTime と FileTimestamp の 2 つである。
- sora-ios-sdk が利用する WebRTC.xcframework の manifest は、SystemBootTime に `35F9.1` と `8FFB.1`、FileTimestamp に `C617.1` を宣言している。
- 現在の `Runner.app` 直下に manifest はない。`Flutter.framework/PrivacyInfo.xcprivacy` は Flutter.framework 自身の宣言であり、`Runner` に静的リンクされた本 SDK の分はカバーしない。

## 設計方針

- `ios/sora_sdk/Sources/sora_sdk/Resources/PrivacyInfo.xcprivacy` を追加する。
  - `NSPrivacyTracking`: `false`
  - `NSPrivacyTrackingDomains`: 空
  - `NSPrivacyCollectedDataTypes`: 空
  - `NSPrivacyAccessedAPITypes`:
    - `NSPrivacyAccessedAPICategorySystemBootTime`: `35F9.1`, `8FFB.1`
    - `NSPrivacyAccessedAPICategoryFileTimestamp`: `C617.1`
  - `8FFB.1` は上流の WebRTC.xcframework の manifest と揃える。FileTimestamp は `RTCFileLogger` の `stat` 参照に由来する。
- `ios/sora_sdk/Package.swift` の `sora_sdk` target に `resources: [.process("Resources/PrivacyInfo.xcprivacy")]` を追加する。
- macOS は Apple の Required Reason API の対象外であり、`macos/sora_sdk` に画面キャプチャもないため変更しない。
- `.github/workflows/ci.yml` の `build-apple` ジョブで、Release ビルド後に次を検査する。
  - `Runner.app` に `sora_sdk` の resource bundle の `PrivacyInfo.xcprivacy` が含まれ、`plutil -lint` が通ること
  - その manifest が SystemBootTime と FileTimestamp を宣言していること
  - `Runner.app/Runner` を `nm -u` と `strings` で走査し、検出した Required Reason API のカテゴリが、アプリ内の manifest (本 SDK の resource bundle、Flutter.framework など) の宣言で全てカバーされていること
  - これにより、WebRTC のバージョン更新でカテゴリが増えた場合も検知できる
- `README.md` に Privacy Manifest の節を追加する。本 SDK の宣言は同梱済みで、アプリ側で本 SDK 分の追記は不要であること、アプリ本体や他の SDK の分は別途必要であることを明記する。
- `CHANGELOG.md` の `## develop` に `[ADD]` で追記する。
- 最終確認として、この SDK を利用するアプリを App Store Connect にアップロードし、SystemBootTime と FileTimestamp について ITMS-91053 が出ないことを確認する。CI ではこの確認はできないため、実装後の別作業とする。

## 変更対象

- `ios/sora_sdk/Sources/sora_sdk/Resources/PrivacyInfo.xcprivacy` (新規)
- `ios/sora_sdk/Package.swift`
- `.github/workflows/ci.yml`
- `README.md`
- `CHANGELOG.md`

## 完了条件

- [ ] `PrivacyInfo.xcprivacy` が追加され、`plutil -lint` が通る
- [ ] `Package.swift` の `sora_sdk` target に resources が宣言されている
- [ ] Release ビルド後の `Runner.app` に `sora_sdk` の resource bundle の `PrivacyInfo.xcprivacy` が含まれる
- [ ] 本 SDK の manifest が SystemBootTime と FileTimestamp を宣言している
- [ ] `Runner.app/Runner` から検出される Required Reason API のカテゴリが、アプリ内の manifest の宣言で全てカバーされている
- [ ] `build-apple` に上記の検査 step が追加され、CI が成功する
- [ ] README と CHANGELOG.md が更新されている
- [ ] モックやスタブを使用していない

## 解決方法

iOS 向けに Required Reason API の利用理由を宣言した manifest を SDK 側で同梱し、最終バイナリから検出されるカテゴリが宣言でカバーされていることを CI で検査するようにした。

- `ios/sora_sdk/Sources/sora_sdk/Resources/PrivacyInfo.xcprivacy` を追加した。SystemBootTime に `35F9.1` と `8FFB.1`、FileTimestamp に `C617.1` を宣言し、`NSPrivacyTracking` を `false`、`NSPrivacyTrackingDomains` と `NSPrivacyCollectedDataTypes` を空にした。内容は libwebrtc_c 0.150.3 が同梱する WebRTC.framework の manifest と揃えた
- `ios/sora_sdk/Package.swift` の `sora_sdk` target に `resources: [.process("Resources/PrivacyInfo.xcprivacy")]` を追加した。libwebrtc_c は静的ライブラリで、SwiftPM の binaryTarget は resources をアプリへ届けないため SDK 側で同梱する必要がある。この制約と manifest の出典、更新時の確認方法をコメントで残した
- `.github/workflows/ci.yml` の `build-apple` に `Verify iOS privacy manifest` を追加した。`Runner.app` の `sora_sdk` の resource bundle に manifest が含まれること、`plutil -lint` が通ること、SystemBootTime と FileTimestamp が宣言されていること、`Runner` を `nm -u` と `strings` で走査して検出したシンボルのカテゴリがアプリ内の manifest の宣言で全てカバーされていることを検査する
- `CHANGELOG.md` の 2026.2.0 に `[ADD]` で追記した
- `README.md` には追記しない。README は複数プラットフォームを横断する構成であり、iOS 単独プラットフォーム向けの情報をインストール手順の直後に載せない方針とした

### 検証

- `plutil -lint ios/sora_sdk/Sources/sora_sdk/Resources/PrivacyInfo.xcprivacy` が成功する
- Release ビルドの `Runner.app/sora_sdk_sora_sdk.bundle/PrivacyInfo.xcprivacy` に manifest が含まれ、宣言カテゴリが SystemBootTime と FileTimestamp である
- `Runner.app/Runner` から `_mach_absolute_time` と `_stat` を検出し、どちらも同梱した manifest の宣言でカバーされている
- PR #34 (run 41960941544) の CI、develop の最新 CI、2026.2.0 のリリース CI で `Build Apple` が成功している
- 公開済みの pub.dev の 2026.2.0 に manifest と `Package.swift` の `resources` 宣言が含まれ、内容がリポジトリと一致する

### 残作業

- App Store Connect へアプリをアップロードし、SystemBootTime と FileTimestamp について ITMS-91053 が出ないことを確認する。設計方針どおり実装後の別作業とする

## 関連

- 0178 (自前コードから SystemBootTime に分類される Required Reason API の利用をなくす)
- sora-ios-sdk の 0199: https://github.com/shiguredo/sora-ios-sdk/blob/develop/issues/0199-remove-system-boot-time-api.md
- sora-ios-sdk の 0198 (プライバシーマニフェストを同梱する別方針)
- Apple のドキュメント: Privacy manifest files / Describing use of required reason API / NSPrivacyAccessedAPIType
