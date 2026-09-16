# `PushAudio` の class-static バッファの共有範囲を dartdoc に明記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-push-audio-isolate-note
- Polished: 2026-09-07

## 目的

`PushAudio._buffer` / `_bufferLength` が class-static で共有される範囲を dartdoc に明記して、共有範囲の誤解による誤用を防ぐ。

## 現状

`lib/src/sora_push_audio.dart` の `PushAudio._buffer` / `_bufferLength` は class-static であり、同一 isolate 内で共有される。一方 Dart の isolate はメモリを共有しないため、static は isolate ごとに独立である (同一リポジトリ内の `closed/0143` 72 行目、`test/webrtc_client_test.dart` 147-155 行目の per-isolate 記述と一致)。各 isolate は初回利用時に `_ensureBuffer` で別バッファを `calloc` するため、他 isolate の使用中バッファを `_disposeBuffer` で free することはない。

`pushPcm` / `pullPcm` / `_ensureBuffer` はいずれも `await` を含まない完全同期関数のため、同一 isolate 内では呼び出し完了まで割り込まれず race しない。

現在の class dartdoc (1 行目) と `pushPcm` / `pullPcm` の dartdoc には共有範囲の説明が無く、読み手が「static = プロセス全体で共有」と誤解する余地がある。

## 設計方針

- `PushAudio` の class dartdoc に以下を明記する:
  - `_buffer` / `_bufferLength` は同一 isolate 内で共有され、isolate ごとに独立したバッファを遅延確保する。
  - 関数は完全同期のため同一 isolate 内での並行呼び出しによる race はない。
- `pushPcm` / `pullPcm` の dartdoc から class dartdoc へリンクで参照する (文面の複写はしない)。
- native 側 PushAudioDevice のスレッド安全性は本 issue の範囲外とし、調査が必要になった場合は別 issue で扱う。
- `0093-fix-push-audio-dartdoc-japanese` と同ファイルの dartdoc 編集で重なるため、`0093` の完了後に実施する。
- 挙動変更なし。ドキュメントのみ。

## 完了条件

- [ ] `PushAudio` の class dartdoc にバッファの共有範囲 (同一 isolate 内共有・isolate 間独立・遅延確保) が明記されている。
- [ ] `pushPcm` / `pullPcm` の dartdoc から class dartdoc へリンクで参照されている。
- [ ] `flutter analyze` が成功する。コメントのみの変更のため専用の関連テストはなし。
