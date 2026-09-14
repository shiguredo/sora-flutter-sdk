# Windows アプリの COM 初期化要件 (MTA) を扱う

- Created: 2026-09-11
- Completed: {YYYY-MM-DD}
- Branch: feature/add-windows-com-mta-support
- Polished: {YYYY-MM-DD}

## 目的

Flutter Windows テンプレート既定の runner は COM を STA (`COINIT_APARTMENTTHREADED`) で初期化する。
Windows の実 ADM (`webrtc::AudioDeviceWindowsCore`) は MTA を要求するため、テンプレート既定のまま
`useAudioDevice: true` を使うと ADM 生成が abort し、音声デバイスを利用できない。
実アプリで音声を利用するための要件を明確にし、テンプレート既定の runner でも動くようにする。

## 現状

- `WebrtcClient._ensureSharedFactory` は Windows で `LibWebrtcC.soraCreateAudioDeviceModule` を呼ぶ。`windows_bridge.c` の setjmp ラッパーは abort を捕捉して NULL を返す
- ADM が NULL の場合、`WebrtcClient.sharedAudioDeviceModule` も null になり、`WebrtcClient.setRecordingDeviceByGuid` が `StateError('AudioDeviceModule is not initialized.')` を投げる
- devtools は `devtools/windows/runner/main.cpp` で MTA 初期化済み。e2e_test_app も実音声デバイスのテストのために MTA 化した
- 実アプリ向けの要件や回避策は README / ドキュメントに記載されていない
- `useAudioDevice` の既定値は true のため、既定設定のまま接続するアプリがこの問題に当たる

## 設計方針

候補:

- README またはドキュメントに Windows アプリの COM MTA 初期化要件を明記する
- SDK 側で ADM 生成と破棄を MTA の専用スレッドで行う。`AudioDeviceWindowsCore` のコンストラクタは `ScopedCOMInitializer` を保持し、破棄も同じスレッドで行う必要があるため、ADM のライフサイクル全体の設計が必要
- ADM 生成に失敗した場合に、原因 (MTA 要件) が分かるエラーを接続側へ通知する

## 完了条件

- [ ] Windows の実アプリがテンプレート既定の runner で `useAudioDevice: true` を利用できる、または要件と回避策が文書化されている
- [ ] 要件または回避策が README またはドキュメントに記載されている
