# `SoraRemoteVideoWidget` のコンストラクタを `const` にする

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-remote-video-widget-const
- Polished: 2026-09-07

## 目的

`SoraRemoteVideoWidget` のコンストラクタが `assert` を含むため `const` になっていないが、`assert` 式は `const` コンストラクタでも許容されるため `const` 化できる。`const` な引数を渡せる箇所では `const` 呼び出しが可能になる。

## 現状

`lib/src/sora_video_widget.dart` の `SoraRemoteVideoWidget` のコンストラクタは `assert` を含むために `const` になっていない。

Dart 言語仕様では `const` コンストラクタでも initializer list で `assert` を書けるため、`const SoraRemoteVideoWidget({...}) : assert(track.kind == 'video', ...);` に書き換えられる。

## 設計方針

- `SoraRemoteVideoWidget` のコンストラクタに `const` を付ける。initializer list の `assert` は既存のまま残す。
- `SoraLocalVideoWidget` は既に `const` であるため対象外とする。
- 本 issue の範囲はコンストラクタ宣言への `const` 付与のみとし、呼び出し側の変更は含まない。
- 挙動変更なし。

## 完了条件

- [ ] `SoraRemoteVideoWidget` のコンストラクタが `const` になっている。
- [ ] `flutter analyze` と `flutter test test/sora_video_widget_test.dart` が成功する。
