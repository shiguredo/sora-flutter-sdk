# 自前コードから SystemBootTime に分類される Required Reason API の利用をなくす

- Created: 2026-11-04
- Completed: {YYYY-MM-DD}
- Branch: feature/ios-required-reason-api
- Polished: {YYYY-MM-DD}

## 目的

sora-ios-sdk の 0199 (SystemBootTime に分類される Required Reason API の利用をなくす) に追従し、本 SDK の自前 Swift コードから Required Reason API の利用をなくす。Apple の Required Reason API は API 名ベースで運用されているため、自前コードでは一覧に含まれる API を利用しない方針に揃える。

本 SDK は libwebrtc_c を静的リンクしており、WebRTC 由来の `mach_absolute_time` と `stat` は最終バイナリに残る。したがって、この変更だけでは PrivacyInfo.xcprivacy は不要にならない。manifest の同梱は 0179 で扱う。

## 現状

- `ios/sora_sdk/Sources/sora_sdk/SoraScreenCapturer.swift` の `SoraScreenCapturer.shouldSendFrame(_:)`、`markFrameSent(_:)`、`timestampUs(from:)` が `ProcessInfo.processInfo.systemUptime` を利用している。`lastSentUptime` プロパティで前回送信時刻を保持している。
- 用途は、PTS が無効な場合のフレーム間引きと、同じく PTS が無効な場合のメディアタイムスタンプのフォールバックである。
- `ios/sora_sdk/Sources` と `macos/sora_sdk/Sources` に、他の Required Reason API (ファイル時刻、UserDefaults、ディスク容量、キーボード、`mach_absolute_time`) の利用はない。
- Release ビルドの `sora_sdk.o` に `_objc_msgSend$systemUptime` が参照シンボルとして残る。
- sora-ios-sdk の 0199 は、`ProcessInfo.processInfo.systemUptime` を `CACurrentMediaTime()` に置き換える方針を採っている。

## 設計方針

- `ProcessInfo.processInfo.systemUptime` を `CACurrentMediaTime()` (QuartzCore) に置き換える。`import QuartzCore` を追加する。
- `lastSentUptime` の名前と関連コメントを実態に合わせる (例: `lastSentMediaTime`)。
- 経過時間の計算方法、PTS が無効な場合の間引き動作、メディアタイムスタンプのフォールバックは変更しない。
- `CACurrentMediaTime()` は現在の Apple の Required Reason API 一覧に含まれていない。Apple のドキュメント上は `mach_absolute_time()` を秒に換算した値であるため、一覧の趣旨に照らした再検討が必要になった場合は、本 issue では実装を進めず pending にしてユーザーに判断を仰ぐ。この前提は sora-ios-sdk の 0199 と同じである。
- 公開 API は変更しない。Dart 側の挙動も変えない。
- `.github/workflows/ci.yml` の `build-apple` ジョブで、Release ビルド後の `sora_sdk.o` に `_objc_msgSend$systemUptime` が含まれないことを検査する。libwebrtc_c が `_mach_absolute_time` を参照するため、最終バイナリ `Runner` ではなく自前 Swift コードのオブジェクトを対象にする。オブジェクトのパスはビルド成果物に合わせて `find` で特定し、見つからない場合は step を失敗させる。
- `CHANGELOG.md` の `## develop` に `### misc` を追加し、`[UPDATE]` で時刻取得 API の変更を追記する。

## 変更対象

- `ios/sora_sdk/Sources/sora_sdk/SoraScreenCapturer.swift`
- `.github/workflows/ci.yml`
- `CHANGELOG.md`

## 完了条件

- [ ] `grep -rn "systemUptime" ios/sora_sdk/Sources` が 0 件 (コメントを含む)
- [ ] `grep -rn -i "uptime" ios/sora_sdk/Sources` が 0 件
- [ ] Release ビルド後の `sora_sdk.o` (例: `devtools/build/ios/Release-iphoneos/sora_sdk.o`) を `nm -u` して `_objc_msgSend$systemUptime` がない
- [ ] `build-apple` に上記の検査 step が追加され、CI が成功する
- [ ] 画面キャプチャのフレーム間引きとメディアタイムスタンプのフォールバックの挙動が変わっていない
- [ ] 公開 API が変わっていない
- [ ] `CHANGELOG.md` の `## develop` に追記されている
- [ ] モックやスタブを使用していない

## 関連

- sora-ios-sdk の 0199: https://github.com/shiguredo/sora-ios-sdk/blob/develop/issues/0199-remove-system-boot-time-api.md
- 0179 (iOS に PrivacyInfo.xcprivacy を同梱する)
- 0069 (iOS の画面キャプチャ)
