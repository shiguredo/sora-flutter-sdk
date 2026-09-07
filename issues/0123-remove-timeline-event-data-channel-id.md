# `SoraTimelineEvent.dataChannelId` は書き込みが 1 度も無い dead field なので削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-timeline-event-data-channel-id
- Polished: 2026-09-07

## 目的

`SoraTimelineEvent.dataChannelId` は SDK 内で書き込みが一度も無く、常に null で運用されている。公開 API に露出しているが値を得る経路が存在しないため削除する。まだ正式リリース前のため、公開 API であっても直接削除する。`CHANGELOG.md` への記載は行わない (`CODEBASE.md` の「正式リリース前」節に従う)。

## 現状

- `lib/src/sora_timeline_event.dart` の `SoraTimelineEvent.dataChannelId` は int? として定義され、コンストラクタ引数もあるが、`lib/` 内で書き込みが行われていない。常に null。
- 利用者が `SoraTimelineEvent` を自分で生成すれば値を渡せるが、通常の SDK 利用シナリオでは Timeline event は SDK 内で生成される。ユーザーが読み手として `dataChannelId` を参照しても常に null が返る dead 値。
- ただし同一リポジトリ内の `devtools/lib/src/devtools_logging_support.dart` の `formatTimelineLog` が `event.dataChannelId` を読み取っている。`devtools` は `sora_sdk` に依存するインレポ消費者のため、削除と合わせて修正する。

## 設計方針

- `SoraTimelineEvent.dataChannelId` フィールドとコンストラクタ引数を直接削除する。
- `devtools/lib/src/devtools_logging_support.dart` の `formatTimelineLog` における `dataChannelId` 読み取り分岐を削除する。
- 正式リリース前のため `@Deprecated` 付与の段階は挟まない。
- `CHANGELOG.md` への記載は行わない。
- 将来、DataChannel ID を Timeline に含める必要が出てきた場合は別途 add issue として扱う。

## 完了条件

- [ ] `SoraTimelineEvent.dataChannelId` が削除されている。
- [ ] `devtools` の `dataChannelId` 読み取りが削除されている。
- [ ] `lib/` と `devtools/` の `flutter analyze` が成功する。
