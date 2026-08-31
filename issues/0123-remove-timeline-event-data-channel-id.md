# `SoraTimelineEvent.dataChannelId` は書き込みが 1 度も無い dead field なので削除する（要 CHANGE）

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-timeline-event-data-channel-id
- Polished: {YYYY-MM-DD}

## 目的

`SoraTimelineEvent.dataChannelId` は SDK 内で書き込みが一度も無く、常に null で運用されている。公開 API に露出しているが値を得る経路が存在しないため削除する。2026.1.0 リリース済のため後方互換のない変更（CHANGE）となる。

## 現状

- `lib/src/sora_timeline_event.dart` の `SoraTimelineEvent.dataChannelId` は int? として定義され、コンストラクタ引数もあるが、`grep -rn dataChannelId lib/` の結果、SDK 内で書き込みが行われていない。常に null。
- 利用者が `SoraTimelineEvent` を自分で生成すれば値を渡せるが、通常の SDK 利用シナリオでは Timeline event は SDK 内で生成される。ユーザーが読み手として `dataChannelId` を参照しても常に null が返る dead 値。

## 設計方針

- `SoraTimelineEvent.dataChannelId` フィールドとコンストラクタ引数を削除する。
- 削除前に `@Deprecated('Removed in 2026.2.0. Always null and unused.')` を付与し、次リリースで実削除する 2 段階方式を採用する。
- CHANGELOG に CHANGE として記載する。
- 将来、DataChannel ID を Timeline に含める必要が出てきた場合は別途 add issue として扱う。

## 完了条件

- [ ] `SoraTimelineEvent.dataChannelId` に `@Deprecated` が付与されている（実削除は次リリース）。
- [ ] CHANGELOG に CHANGE として記載されている。
- [ ] `flutter analyze` と関連テストが成功する。
