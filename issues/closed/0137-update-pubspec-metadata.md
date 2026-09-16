# `pubspec.yaml` の description 拡張と `issue_tracker` 方針確定

- Created: 2026-08-27
- Completed: 2026-09-10
- Branch: feature/update-pubspec-metadata
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`pubspec.yaml` のメタデータを pub.dev での説明不足解消の観点から整備する。`description` の拡張と `issue_tracker` の方針確定を行う。`topics` は `0066-change-add-pubspec-topics` で `webrtc` / `flutter` に確定済み (`sora` は混同回避のため除外) のため、本 issue では変更しない。

## 現状

- `description`: `Flutter plugin for Sora powered by libwebrtc-c.` は 47 文字 (文字数、ピリオド込み) で、pub.dev 上の説明として短い。目安 60-180 文字 (pana の推奨とされる範囲。一次資料未確認のため厳密な閾値ではなく目安として扱う) を下回る。
- `topics`: `webrtc`, `flutter` のみ。`0066` で `sora` 除外が確定済み (Sorani Kurdish や OpenAI Sora 関連との混同回避) のため現状維持とする。
- `issue_tracker`: 明示指定なし。プロジェクトは Discord 誘導であり (`README.md` 505-511 行目「Discord のみで受け付ける」「バグ報告は Discord へ」)、GitHub issues でのバグ報告を受け付けていない。

## 設計方針

- `description` を英語のまま 60-180 文字程度に拡張する。確定文言は以下とする (110 文字):
  - `Flutter plugin for WebRTC SFU Sora powered by libwebrtc-c, supporting iOS, macOS, Android, Windows, and Linux.`
  - 対応プラットフォームは `README.md` 456-464 行目の対応表と一致する。
- `topics` は変更しない (`0066` 決着を維持する)。
- `issue_tracker` 方針は A. 現状維持 (明示せず、バグ報告方針は README の Discord 誘導で足りる) とする。Discord 招待 URL や GitHub Discussions URL の記載は行わない。
- `repository` / `homepage` (`0065` で確定済み) は変更せず、値の存在確認のみ行う。
- 挙動変更なし。`pubspec.yaml` のみの修正。

## 完了条件

- [ ] `pubspec.yaml` の `description` が上記確定文言に更新されている (文字数は `wc -m` 等で確認する)。
- [ ] `topics` が `webrtc` / `flutter` のまま変更されていない。
- [ ] `issue_tracker` が記載されていない (A. 現状維持)。
- [ ] `repository` / `homepage` が存在している (値の変更は行わない)。
- [ ] `flutter pub publish --dry-run` の出力に topics / description 関連のエラーや警告がない (CHANGELOG のバージョン警告は `0063` の範囲であり対象外)。

## 解決方法

- `pubspec.yaml` の `description` を 110 文字の確定文言 `Flutter plugin for WebRTC SFU Sora powered by libwebrtc-c, supporting iOS, macOS, Android, Windows, and Linux.` に更新した。
- `topics` は `webrtc` / `flutter` のまま変更していない。
- `issue_tracker` は追加していない (現状維持)。
- `repository` / `homepage` は変更していない。
- `dart pub publish --dry-run` で topics / description 関連の警告・エラーが無いことを確認した (CHANGELOG のバージョン警告は `0063` の範囲)。
