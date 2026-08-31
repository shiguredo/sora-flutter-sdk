# `sora_push_audio.dart` の英語 dartdoc を日本語化する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-push-audio-dartdoc-japanese
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

AGENTS.md 「コメントは全て日本語にすること」に反して英語で書かれた dartdoc を日本語化する。

## 現状

`lib/src/sora_push_audio.dart` の `PushAudio._buffer` に付いている dartdoc:

- 「Pre-allocated native buffer for PCM data. null if not initialized.」

他のファイルの dartdoc / コメントは日本語で統一されているのに対し、ここだけ英語。AGENTS.md line 11「コメントは全て日本語にすること」に違反している。

## 設計方針

- 対象 dartdoc を日本語に書き換える。例:
  - 「PCM データ用に事前確保したネイティブバッファ。未初期化のときは `null`。」
- 併せて `_bufferLength` など他の private フィールドの dartdoc が英語混じりになっていないかを確認し、あれば統一する。
- ログメッセージ（英語規約）は変更しない。

## 完了条件

- [ ] `sora_push_audio.dart` の dartdoc がすべて日本語で書かれている。
- [ ] 他のファイルにも英語 dartdoc が残っていないことを目視で確認する（grep で `^[[:space:]]*///[[:space:]]+[A-Z]` などを走らせて確認）。
- [ ] `flutter analyze` と関連テストが成功する。
