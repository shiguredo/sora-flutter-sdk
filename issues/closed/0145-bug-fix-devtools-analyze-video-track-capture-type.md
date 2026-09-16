# devtools/lib/main.dart で @internal の VideoTrackCaptureType を参照し flutter analyze が失敗する

- Created: 2026-08-30
- Branch: feature/fix-devtools-analyze-video-track-capture-type
- Polished: 2026-08-30
- Completed: 2026-08-30

## 目的

`devtools/lib/main.dart` から `@internal` 化された `VideoTrackCaptureType` と `LocalVideoTrack.captureType` を参照しているため、CI の `devtools Flutter analyze` step が `undefined_identifier` と `invalid_use_of_internal_member` で失敗している。この失敗により Linux / Apple / Windows / Android の全 Build job が analyze step で早期停止し、FFI 依存テスト step 以降に到達できない状態が続いている。参照を落として devtools が analyze を通るようにし、CI 全体の実行を再開する。同時に issue 0141 / 0142 / 0143 の CI 通過ブロッカーを解除する。

## 現状

`.github/workflows/ci.yml` の各 Build job が実行する `Run devtools Flutter analyze` step (`flutter analyze --fatal-infos lib test`) で以下の 2 件が報告されて exit code 1 になる。

```
warning • The member 'captureType' can only be used within its package • lib/main.dart:1147:31 • invalid_use_of_internal_member
error   • Undefined name 'VideoTrackCaptureType'. Try correcting the name to one that is defined, or defining the name • lib/main.dart:1147:46 • undefined_identifier
```

該当は `devtools/lib/main.dart` の `_connect` ハンドラ内の以下ブロック。

```dart
if (_useExternalVideoTrack && _publishesVideo && localStream != null) {
  final videoTracks = localStream.getVideoTracks();
  if (videoTracks.isNotEmpty &&
      videoTracks.first.captureType == VideoTrackCaptureType.external) {
    await _cameraManager.start(videoTracks.first);
  }
}
```

`VideoTrackCaptureType` と `LocalVideoTrack.captureType` は commit `d290330 0069 VideoTrackCaptureType と captureType getter を公開 API から撤回する` で `@internal` に変更され、`sora_sdk.dart` の export からも除外された（実装は `lib/src/sora_media_stream.dart` の `enum VideoTrackCaptureType` と `LocalVideoTrack.captureType`）。この撤回に伴う devtools 側の参照追従が漏れており、closed 済み issue `issues/closed/0069-add-ios-screen-capture.md` の解決方法にある「devtools / e2e / テストの画面キャプチャ処理を削除し」は screen capture 経路を指す作業で、本件が扱う external video track 経路の参照 1 箇所（`main.dart` の `_connect` 内）は撤去対象から漏れている。

直近の develop の CI run (`33141722842`) と本ブロッカー特定に使った `33297433461` および現ブランチの `33306954289` はいずれも同じ analyze エラーで早期停止しており、issue 0141 / 0142 / 0143 の CI 実測ができない。

## 設計方針

内側の `captureType == VideoTrackCaptureType.external` 比較を撤去し、外側の `if (_useExternalVideoTrack && _publishesVideo && localStream != null)` で「external video track を使う publish 経路」であることが確定していることを根拠として、`videoTracks.isNotEmpty` のみで `_cameraManager.start(videoTracks.first)` を呼ぶ形にする。

- `_useExternalVideoTrack` は devtools の UI トグルで external video track 経路を選んだ場合のみ true になる (`devtools/lib/main.dart` の同名フィールド)。
- `_publishesVideo` は `_isSendingRole && _connectVideo` で、送信ロール + video 送信有効時のみ true。
- `main.dart` の `_buildConnectRequest` が `useExternalVideoTrack: _useExternalVideoTrack && _publishesVideo` を渡し、これを受けた `devtools/lib/src/devtools_connection_controller.dart` の `_prepareLocalStream` は `request.useExternalVideoTrack` が真のときに限り `_createExternalVideoTrack()` (`MediaDevices.createExternalVideoTrack()`) だけを `localStream.addTrack` する。したがって外側条件 2 つが両方 true の場合、`localStream` が持つ video track は必ず external track である。
- この経路で生成された track に対する内側 `captureType` 比較は防御的重複であり、`@internal` API へ依存する正当性がない。

同 devtools 内で他に `VideoTrackCaptureType` を参照している箇所は `devtools/lib/src/devtools_external_camera_manager.dart` の doc コメント 1 行のみ (`/// [track] は [VideoTrackCaptureType.external] の video track。`)。doc 上の参照はコンパイル対象ではないため analyze には影響しないが、公開 API から外れたシンボルを doc から参照するのはリンク切れになるため、記述を「external video track」等の説明に置き換える。

`sora_sdk` 側の `@internal` 付与や export 除外は変更しない（本 issue はあくまで devtools 側の追従修正）。

## 完了条件

- [ ] `devtools/lib/main.dart` の `_connect` 内の外部 video track start ブロックから `VideoTrackCaptureType` と `captureType` 参照を撤去する
- [ ] `devtools/lib/src/devtools_external_camera_manager.dart` の doc コメントから `[VideoTrackCaptureType.external]` の参照を落とし、リンク切れを解消する
- [ ] `devtools` 配下で `flutter analyze --fatal-infos lib test` が `No issues found` で pass する
- [ ] CI の Linux / Apple / Windows / Android 各 Build job が `Run devtools Flutter analyze` step を通過する

## 解決方法

- `devtools/lib/main.dart` の `_connect` ハンドラ内で、`_useExternalVideoTrack && _publishesVideo && localStream != null` 直下の内側条件 `videoTracks.first.captureType == VideoTrackCaptureType.external` を撤去し、`videoTracks.isNotEmpty` のみで `_cameraManager.start(videoTracks.first)` を呼ぶ形に変更した。撤去理由（外側 2 条件が両方 true のとき `_prepareLocalStream` は `_createExternalVideoTrack()` で生成した external video track のみを `addTrack` する経路をとる）をコメントで残した。
- `devtools/lib/src/devtools_external_camera_manager.dart` の `start` メソッドの doc コメント内 `[VideoTrackCaptureType.external]` パラメータリンクを外し、`external video track` の自然文に置き換えた。`@internal` 化された enum への doc 参照を残さない。
- `sora_sdk` 側の `@internal` 付与および export 除外は変更しない（本 issue は devtools 側の追従修正）。
- 手元 (macOS) で `devtools` 配下 `flutter analyze --fatal-infos lib test` が `No issues found` で pass することを確認した。
