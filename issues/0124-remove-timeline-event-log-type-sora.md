# `SoraTimelineEventLogType.sora` は利用箇所ゼロの dead enum 値なので削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-timeline-event-log-type-sora
- Polished: 2026-09-07

## 目的

`SoraTimelineEventLogType.sora` は enum 値のうち利用箇所がゼロの dead 値。公開 API に露出しているため削除する。まだ正式リリース前のため、公開 API であっても直接削除する。`CHANGELOG.md` への記載は行わない (`CODEBASE.md` の「正式リリース前」節に従う)。

## 現状

- `lib/src/sora_timeline_event.dart` の `SoraTimelineEventLogType.sora` は enum 値として定義されているが、SDK 内で `SoraTimelineEventLogType.sora` を代入する箇所が無い。
- 利用者側で分岐する意味も無く、単なる dead 値。

## 設計方針

- `SoraTimelineEventLogType.sora` を直接削除する。
- 正式リリース前のため `@Deprecated` 付与の段階は挟まない。
- `CHANGELOG.md` への記載は行わない。

## 完了条件

- [ ] `SoraTimelineEventLogType.sora` が削除されている。
- [ ] `flutter analyze` と関連テストが成功する。
