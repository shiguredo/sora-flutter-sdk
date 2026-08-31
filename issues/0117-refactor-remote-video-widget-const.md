# `SoraRemoteVideoWidget` のコンストラクタを `const` にする

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-remote-video-widget-const
- Polished: {YYYY-MM-DD}

## 目的

`SoraRemoteVideoWidget` のコンストラクタが `assert` を含むため `const` になっていないが、`assert` 式は `const` コンストラクタでも許容されるため `const` 化できる。呼び出し側でも `const` 化可能になり Widget 再生成コスト削減につながる。

## 現状

`lib/src/sora_video_widget.dart` の `SoraRemoteVideoWidget` のコンストラクタは `assert` を含むために `const` になっていない。

Dart 言語仕様では `const` コンストラクタでも initializer list で `assert` を書けるため、`const SoraRemoteVideoWidget({...}) : assert(track.kind == 'video', ...);` に書き換えられる。

## 設計方針

- `SoraRemoteVideoWidget` のコンストラクタに `const` を付ける。initializer list の `assert` は既存のまま残す。
- `SoraLocalVideoWidget` にも同種の余地がないか確認し、あれば併せて `const` 化する。
- 挙動変更なし。呼び出し側で `const` として使えるようになるだけ。

## 完了条件

- [ ] `SoraRemoteVideoWidget` のコンストラクタが `const` になっている。
- [ ] `SoraLocalVideoWidget` も同様に評価される。
- [ ] `flutter analyze` と関連テストが成功する。
