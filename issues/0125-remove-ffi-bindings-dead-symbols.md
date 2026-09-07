# `ffi/bindings.dart` の内部限定 dead 定数 / API を削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-ffi-bindings-dead-symbols
- Polished: 2026-09-07

## 目的

`lib/src/ffi/bindings.dart` に `lib/` 内部からも呼び出しが無い定数 / API を削除する。`lib/sora_sdk.dart` から export されていない内部限定のため、公開 API としての後方互換影響は無い。ただし `src/` 配下は直接 import が技術的に可能であり、`test/` が直接参照している場合は合わせて修正する。まだ正式リリース前のため直接削除する。`CHANGELOG.md` への記載は行わない (`CODEBASE.md` の「正式リリース前」節に従う)。

## 現状

以下の定数 / API が `lib/src/ffi/bindings.dart` に存在するが、`lib/` 全体で使用箇所ゼロ:

- 定数: `kLinuxPulseAudio`, `kLinuxAlsaAudio`, `kDummyAudio`
- 定数: `videoRotation0`
- 定数: `dcStateConnecting`（Open/Closing/Closed のみ判定に使う）
- 関数: `videoFrameUniqueGet`, `videoFrameUniqueDelete`, `videoFrameVideoFrameBuffer`（Sora 独自 `SoraVideoFrame` 経路のみ使用）
- 関数: `i420BufferWidth`, `i420BufferHeight`

`sdpTypeAnswer` は `lib/` 内では `sdpTypeOffer` のみ使用だが、`test/sdp_negotiation_test.dart` の `_createAnswerDescription` が `WebrtcConstants(dylib).sdpTypeAnswer` を使って Answer 用 SDP を生成している。Offer / Answer は対になる正当な定数のため、本 issue の削除対象には含めない。

`kDummyAudio` はコード参照がゼロだが、`lib/src/sora_connection_config.dart` の `useAudioDevice` の dartdoc に言及が残っている。`0092-fix-use-audio-device-dartdoc` が本 issue への委譲を明記しているため、本 issue で dartdoc 言及の除去まで行う。

`bindings.dart` は手書き dart:ffi バインディングである (`bindings.dart` 冒頭に明記)。`LibWebrtcC` は `late final` による遅延 lookup のため、未参照 symbol の lookup コストは発生しない。削除の動機は lookup 失敗回避ではなく、未使用 API 表面の削減と誤用防止である。

native 側の symbol 実体は外部の `libwebrtc-c` プロジェクトの prebuilt バイナリであり、本リポジトリからは削除できない。本 issue は Dart 側 binding の削除に限定し、native 側の削除は行わない。

## 設計方針

- 上記シンボルを Dart 側 binding から削除する。`sdpTypeAnswer` は対象外として残す。
- 将来予約のためのコメントは残さない。対応する open issue が無い symbol は削除する。
- `lib/src/sora_connection_config.dart` の `useAudioDevice` の dartdoc に残る `kDummyAudio` 言及を除去する (`0092` との委譲関係による)。
- native 側の symbol 削除は行わない。Dart 側削除後に `flutter test` が lookup エラーなく成功することで整合を確認する。
- `CHANGELOG.md` への記載は行わない。
- `bindings.dart` は手書きのため、差分は削除対象に最小限に留める。

## 完了条件

- [ ] 上記 dead シンボル (`sdpTypeAnswer` を除く) が `bindings.dart` から削除されている。
- [ ] `sdpTypeAnswer` が残っている。
- [ ] `sora_connection_config.dart` の dartdoc から `kDummyAudio` 言及が除去されている。
- [ ] `lib/` と `test/` に削除シンボルの参照が残っていない。
- [ ] `flutter analyze` と `flutter test test/sdp_negotiation_test.dart` を含む関連テストが成功する。
