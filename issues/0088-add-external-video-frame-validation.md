# `ExternalVideoFrame` の validation を追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-external-video-frame-validation
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`LocalVideoTrack.writeFrame` に渡す `ExternalVideoFrame` の `rotation` / `width` / `height` / `timestampUs` を Dart 側で validation し、libwebrtc の `VideoRotation` 制約や overflow を安全に扱う。現状は width / height の正値と plane / stride のみ validation されており、rotation は素通しで無効値が native に届く可能性がある。

## 現状

`lib/src/sora_media_stream.dart` の `validateExternalVideoFrame` は width / height の正値、plane 長、stride のみ検証する。`rotation` の値検証は無い。

- `ExternalVideoFrame.rotation` の dartdoc は「0, 90, 180, 270」と明記しているが実装は任意の int を受け入れる。無効値は `soraVideoFrameCreate(..., frame.rotation, ...)` にそのまま渡り、libwebrtc の `VideoRotation` enum（`kVideoRotation_0` = 0, `kVideoRotation_90` = 90, `kVideoRotation_180` = 180, `kVideoRotation_270` = 270）の想定外値になる。
- width / height は上限が無く、極端値が渡された場合 Dart int (64bit) から C `int` (32bit) 相当（FFI の `Int32`）への変換で silent overflow の可能性がある。
- `timestampUs` の負値も未検証。

## 設計方針

- `validateExternalVideoFrame` に以下の検証を追加する:
  - `rotation ∈ {0, 90, 180, 270}` 以外は `StateError` で拒否する（既存の検証が StateError で統一されているため）
  - `width` / `height` の上限を 8192 に設定し、超過は `StateError` で拒否する。libwebrtc の `I420Buffer::Create` 自体には寸法上限は無いため、上限値は 4K 解像度の 2 倍 (7680) を超える 8192 を SDK 側の防御的な上限として定める。上限値の根拠は dartdoc に明記する
  - `timestampUs` が `null` でなければ非負であることを検証する
- 検証失敗時のエラーメッセージは英語で統一（規約準拠）。dartdoc の記述は日本語で「rotation は 0, 90, 180, 270 のみ有効」等と補足する。

## 完了条件

- [ ] rotation 無効値・width/height 上限超過 (8192 超)・timestampUs 負値が確実に例外化する。
- [ ] 上記シナリオを exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。
