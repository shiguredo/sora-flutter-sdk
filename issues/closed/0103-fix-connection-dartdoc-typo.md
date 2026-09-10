# `SoraConnection._currentAudioTrack` / `_currentVideoTrack` の dartdoc の日本語文法誤字を修正する

- Created: 2026-08-27
- Completed: 2026-09-10
- Branch: feature/fix-connection-dartdoc-typo
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`SoraConnection._currentAudioTrack` / `_currentVideoTrack` の dartdoc の日本語文法誤字「現在保持しているの」を修正する。private フィールドの dartdoc のため利用者影響はゼロだが、コード品質の規範として直す。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection._currentAudioTrack` / `_currentVideoTrack` の dartdoc:

```dart
/// 現在保持しているのローカル音声トラック
LocalAudioTrack? _currentAudioTrack;

/// 現在保持しているのローカル映像トラック
LocalVideoTrack? _currentVideoTrack;
```

「現在保持している**の**ローカル…」は日本語文法として誤り。「現在保持しているローカル…」に直す。

## 設計方針

- 「現在保持している」の後の「の」を削除する:
  - 「現在保持しているローカル音声トラック」
  - 「現在保持しているローカル映像トラック」
- 他のフィールドへの波及は行わず、当該 2 箇所のみを修正する。
- 挙動変更なし。dartdoc のみの修正。

## 完了条件

- [ ] 該当 2 箇所の dartdoc が文法的に正しい。
- [ ] `flutter analyze` が成功する。コメントのみの修正のため専用の関連テストはなし。

## 解決方法

- `lib/src/sora_connection.dart` の `_currentAudioTrack` / `_currentVideoTrack` の dartdoc 「現在保持しているのローカル…」から「の」を削除し、「現在保持しているローカル…」に修正した。
- `flutter analyze --fatal-infos lib test` 成功。
