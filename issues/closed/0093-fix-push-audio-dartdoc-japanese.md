# `sora_push_audio.dart` の英語 dartdoc を日本語化する

- Created: 2026-08-27
- Completed: 2026-09-10
- Branch: feature/fix-push-audio-dartdoc-japanese
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

AGENTS.md 「コメントは全て日本語にすること」に反して英語で書かれた dartdoc を日本語化する。

## 現状

`lib/src/sora_push_audio.dart` の `PushAudio._buffer` に付いている dartdoc:

- 「Pre-allocated native buffer for PCM data. null if not initialized.」(`sora_push_audio.dart` 13 行目)

純粋英語で書かれた `///` dartdoc は当該 1 箇所のみである。AGENTS.md line 11「コメントは全て日本語にすること」に違反している。なお `//` の英語セクションヘッダは `0112-fix-comment-conventions` の範囲であり、本 issue では扱わない。

## 設計方針

- 対象 dartdoc (13 行目) を日本語に書き換える。例:
  - 「PCM データ用に事前確保したネイティブバッファ。未初期化のときは `null`。」
- WebRTC 仕様固有の英字名やコード識別子 (PCM、`null` 等) は残しつつ、日本語で意味付けを添える (`0112` と同等の基準)。
- `_bufferLength` (15 行目) には現時点で dartdoc が無いことを確認済みであり、新規付与は行わない。他の private メンバーへの新規 dartdoc 追加も行わない。
- 対象は `sora_push_audio.dart` に限定する。`lib/` 全体の `///` sweep は行わず、`//` セクションヘッダは `0112` が担当する。
- ログメッセージ（英語規約）は変更しない。

## 完了条件

- [ ] `sora_push_audio.dart` 13 行目の dartdoc が日本語で書かれている。
- [ ] `flutter analyze` が成功する。コメントのみの変更のため専用の関連テストはなし。

## 解決方法

- `lib/src/sora_push_audio.dart` の `PushAudio._buffer` の英語 dartdoc を「PCM データ用に事前確保したネイティブバッファ。未初期化のときは `null`。」に日本語化した。
- 他の private メンバーへの dartdoc 追加は行っていない（設計方針どおり）。
- `flutter analyze --fatal-infos lib test` 成功。
