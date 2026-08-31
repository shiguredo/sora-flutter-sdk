# `PushAudio` の class-static バッファに関する isolate 制約を dartdoc に明記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-push-audio-isolate-note
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`PushAudio._buffer` / `_bufferLength` が class-static で共有されており、複数 isolate から `pushPcm` / `pullPcm` を並行して呼ぶと race する可能性がある。使用契約を dartdoc に明記して誤用を防ぐ。

## 現状

`lib/src/sora_push_audio.dart` の `PushAudio._buffer` / `_bufferLength` は class-static。同一 isolate なら Dart のシングルスレッド性から安全だが、複数 isolate から `pushPcm` / `pullPcm` を並行呼び出しした場合、`_ensureBuffer` が同時実行されて、一方がまだ使っている ptr を `_disposeBuffer` で free してしまう可能性がある。10ms 周期でループする用途上、誤用しやすい。

## 設計方針

- `PushAudio` の class dartdoc に「同一 isolate からのみ呼ぶこと。複数 isolate からの並行呼び出しは未サポート」旨を明記する。
- ロングタームでは isolate group 対応のバッファ確保に切り替える案もあるが、本 issue のスコープは dartdoc 追記のみ。
- 挙動変更なし。ドキュメントのみ。

## 完了条件

- [ ] `PushAudio` の class dartdoc に isolate 制約が明記されている。
- [ ] `pushPcm` / `pullPcm` の dartdoc からも参照されている。
- [ ] `flutter analyze` と関連テストが成功する。
