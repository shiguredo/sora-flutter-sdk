# 自前コードから SystemBootTime に分類される Required Reason API の利用をなくす

- Created: 2026-11-04
- Completed: 2026-11-05
- Branch: feature/change-replace-system-uptime-api
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
- `.github/workflows/ci.yml` の `build-apple` ジョブで Required Reason API の再導入を検査する。検査は 2 段構えとし、Release ビルド後の `sora_sdk.o` の未定義シンボルと `ios/sora_sdk/Sources` / `macos/sora_sdk/Sources` の Swift ソースを対象にする。対象カテゴリは SystemBootTime だけでなく FileTimestamp / DiskSpace / ActiveKeyboards / UserDefaults を含む 5 カテゴリとする。libwebrtc_c が `_mach_absolute_time` を参照するため、最終バイナリ `Runner` ではなく自前 Swift コードのオブジェクトを対象にする。オブジェクトのパスはビルド成果物に合わせて `find` で特定し、オブジェクトが見つからない場合と `nm` が失敗した場合は step を失敗させる。ソース検査は行コメントを除外し、対象ファイル数が 0 件の場合と `git grep` が失敗した場合も step を失敗させる。
- `CHANGELOG.md` の `## develop` に `[UPDATE]` で時刻取得 API の変更を追記し、CI 検査の追加は `### misc` に追記する。

## 変更対象

- `ios/sora_sdk/Sources/sora_sdk/SoraScreenCapturer.swift`
- `.github/workflows/ci.yml`
- `CHANGELOG.md`

## 完了条件

- [ ] `grep -rn "systemUptime" ios/sora_sdk/Sources` が 0 件 (コメントを含む)
- [ ] `grep -rn -i "uptime" ios/sora_sdk/Sources` が 0 件
- [ ] Release ビルド後の `sora_sdk.o` (例: `devtools/build/ios/Release-iphoneos/sora_sdk.o`) を `nm -u` して `_objc_msgSend$systemUptime` がない
- [ ] `build-apple` に `sora_sdk.o` の未定義シンボル検査と `ios/sora_sdk/Sources` / `macos/sora_sdk/Sources` のソース検査の step が追加され、CI が成功する
- [ ] 画面キャプチャのフレーム間引きとメディアタイムスタンプのフォールバックの挙動が変わっていない
- [ ] 公開 API が変わっていない
- [ ] `CHANGELOG.md` の `## develop` に追記されている
- [ ] モックやスタブを使用していない

## 解決方法

自前 Swift コードから Required Reason API の利用をなくし、再導入を検出する CI 検査を追加した。

- `ios/sora_sdk/Sources/sora_sdk/SoraScreenCapturer.swift` の `SoraScreenCapturer` で `ProcessInfo.processInfo.systemUptime` を `CACurrentMediaTime()` に置き換え、`import QuartzCore` を追加した。`lastSentUptime` を `lastSentMediaTime` に改名し、関連コメントを実態に合わせた。フレーム間引きのフォールバック判定は `shouldSendFrameWithMediaTime()` に切り出した。PTS が無効な場合の間引き動作、メディアタイムスタンプのフォールバック、公開 API は変えていない
- `.github/workflows/ci.yml` の `build-apple` に 2 つの検査 step を追加した。1 つは Release ビルド後の `sora_sdk.o` を `nm -u` して Required Reason API のシンボルが無いことを確認し、もう 1 つは `ios/sora_sdk/Sources` と `macos/sora_sdk/Sources` の Swift ソースを `git grep` して API の利用が無いことを確認する。どちらも 5 カテゴリを対象とし、ソース検査は行コメントを除外する。オブジェクトが見つからない場合、`nm` が失敗した場合、対象ファイルが 0 件の場合、`git grep` が失敗した場合は step を失敗させる
- `CHANGELOG.md` の `## develop` に時刻取得 API の変更を、`### misc` に CI 検査の追加を `[UPDATE]` で追記した

### 検証

- `grep -rn -i "uptime" ios/sora_sdk/Sources macos/sora_sdk/Sources` が 0 件
- `nm -u devtools/build/ios/Release-iphoneos/sora_sdk.o` に `_objc_msgSend$systemUptime` と `_mach_absolute_time` が無く、`_CACurrentMediaTime` がある
- 追加した 2 つの検査 step をローカルで実行し、正常系で成功すること、`_mach_absolute_time` を含むオブジェクトとソース中の `systemUptime` の利用を検出して失敗することを確認した
- `swift format lint --strict` と `swiftlint lint --strict` が成功する
- Release ビルドと CI は PR 上で確認する

## 関連

- sora-ios-sdk の 0199: https://github.com/shiguredo/sora-ios-sdk/blob/develop/issues/0199-remove-system-boot-time-api.md
- 0179 (iOS に PrivacyInfo.xcprivacy を同梱する)
- 0069 (iOS の画面キャプチャ)
