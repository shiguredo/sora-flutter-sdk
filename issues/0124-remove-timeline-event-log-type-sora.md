# `SoraTimelineEventLogType.sora` は利用箇所ゼロの dead enum 値なので削除する（要 CHANGE）

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-timeline-event-log-type-sora
- Polished: {YYYY-MM-DD}

## 目的

`SoraTimelineEventLogType.sora` は enum 値のうち利用箇所がゼロの dead 値。公開 API に露出しているため削除する。2026.1.0 リリース済のため後方互換のない変更（CHANGE）となる。

## 現状

- `lib/src/sora_timeline_event.dart` の `SoraTimelineEventLogType.sora` は enum 値として定義されているが、SDK 内で `SoraTimelineEventLogType.sora` を代入する箇所が無い。
- 利用者側で分岐する意味も無く、単なる dead 値。

## 設計方針

- `SoraTimelineEventLogType.sora` を削除する。
- 削除前に `@Deprecated('Removed in 2026.2.0. Unused.')` を付与し、次リリースで実削除する 2 段階方式を採用する。
- CHANGELOG に CHANGE として記載する。

## 完了条件

- [ ] `SoraTimelineEventLogType.sora` に `@Deprecated` が付与されている（実削除は次リリース）。
- [ ] CHANGELOG に CHANGE として記載されている。
- [ ] `flutter analyze` と関連テストが成功する。
