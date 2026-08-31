# `pubspec.yaml` の description / topics / issue_tracker を整備する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/update-pubspec-metadata
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`pubspec.yaml` のメタデータを pub.dev のパッケージスコアリング（pana）と検索性の観点から整備する。description の拡張、topics への `sora` 追加、`issue_tracker` の方針明記を行う。

## 現状

- `description`: `Flutter plugin for Sora powered by libwebrtc-c.` は 48 文字。pana のパッケージスコアリング側で description 長は減点対象になりうる（推奨 60〜180 文字）。正式リリース版として不利。
- `topics`: `webrtc`, `flutter` のみ。自 SDK の名称 `sora` が含まれておらず、pub.dev 検索で見つかりにくい。
- `issue_tracker`: 明示指定なし。プロジェクトは Discord 誘導でありバグ報告を GitHub issues に頂きたくない場合、明示的に方針を明記する必要がある。

## 設計方針

- `description` を 60〜180 文字程度に拡張する。以下相当:
  - WebRTC SFU Sora 向け Flutter SDK。libwebrtc-c ベースで iOS/macOS/Android/Windows/Linux に対応する。
  - 正確な文言はプロジェクトオーナー確認の上で決定する。
- `topics` に `sora` を追加する。`webrtc-sfu` など追加候補があれば併せて検討する。
- `issue_tracker` 方針:
  - **A. 現状維持**: 明示せず、pub.dev が repository から自動推定する。バグ報告方針は README で Discord へ誘導する。
  - **B. Discord URL を書く**: pub.dev のフィールドは Web URL 前提のため Discord の招待 URL を書く。
  - **C. GitHub Discussions URL を書く**: 段階的移行。
  - 選択と `CODEBASE.md` への方針記載を合わせて行う。
- pubspec の他フィールド（`repository`, `homepage`）と整合を取る。

## 完了条件

- [ ] `pubspec.yaml` の `description` が 60〜180 文字に拡張されている。
- [ ] `topics` に `sora` が含まれている。
- [ ] `issue_tracker` の方針が決定され、必要に応じて記載されている。
- [ ] `CODEBASE.md` の関連節と整合が取れている。
- [ ] `flutter analyze` と関連テストが成功する。
