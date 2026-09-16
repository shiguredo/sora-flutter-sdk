# LocalMediaStream の track キャッシュ生成で `_mediaTrackRef` を double-release する

- Created: 2026-08-27
- Completed: 2026-08-28
- Branch: feature/fix-media-track-ref-double-release
- Polished: 2026-08-27

## 解決方法

- `LocalMediaStream._reuseOrCreateAudioTrack` / `_reuseOrCreateVideoTrack` の cache-miss 経路から `mediaStreamTrackRelease(nativeTrack)` を削除し、`ownedMediaTrackRef` の所有権を新規 wrapper へ委譲した。cache-hit 経路だけが release を行う。
- `getAudioTracks()` / `getVideoTracks()` に、`audioTrackRefcountedVectorGet` / `videoTrackRefcountedVectorGet` が返した owned ref を `audioTrackRelease(audioTrackRefcountedGet(...))` / `videoTrackRelease(videoTrackRefcountedGet(...))` で解放する処理を追加した。これにより呼び出しごとの ref リークを解消した。
- `_reuseOrCreateAudioTrack` / `_reuseOrCreateVideoTrack` の cache-hit 判定に `!cachedTrack.isDisposed` を追加し、dispose 済み wrapper を cache から再利用しないようにした。dispose 後の再取得では新規 wrapper が生成される。
- cache の参照契約をコメントで明示した（cache-hit のみ release / cache-miss は所有権委譲 / vectorGet の owned ref は取得側で release / dispose 済み cache は再利用しない）。
- 検証コマンド: `flutter analyze --fatal-infos lib test`（成功）、`flutter test`（成功）。FFI 依存テストは `test/sora_media_stream_test.dart` に 5 件追加し、CI の `build-linux` ジョブの FFI テスト実行対象へ同ファイルを追加した。

## 目的

`LocalMediaStream.getAudioTracks()` / `getVideoTracks()` 経由で初めて `LocalAudioTrack` / `LocalVideoTrack` ラッパーを生成する経路で、native の refcounted なメディアトラック参照が二重解放され、参照管理の会計が破綻するバグを修正する。

## 現状

`lib/src/sora_media_stream.dart` の `LocalMediaStream.getAudioTracks()` / `getVideoTracks()` は、`audioTrackRefcountedVectorGet` / `videoTrackRefcountedVectorGet` が返す owned refcount を `audioTrackCastToMediaStreamTrack` / `videoTrackCastToMediaStreamTrack` で新規 owned ref に変換し、`_reuseOrCreateAudioTrack` / `_reuseOrCreateVideoTrack` へ渡す。この関数は cache-hit と cache-miss の両方で無条件に `WebrtcClient.sharedLib.mediaStreamTrackRelease(nativeTrack)` を呼んでいる。

- cache-hit 側は、`audioTrackCastToMediaStreamTrack` / `videoTrackCastToMediaStreamTrack` が新規に返した owned refcount を破棄する意味で正しい。
- cache-miss 側は、`LocalAudioTrack.fromNativeMediaTrack(ownedMediaTrackRef)` / `LocalVideoTrack.fromNativeMediaTrack(ownedMediaTrackRef, ...)` に所有権を transfer した直後に同じ ref を release してしまう。`LocalMediaStreamTrack._` は AddRef しないため、wrapper が保持する ref の二重解放になり、参照管理の会計が破綻する。

さらに、次の 2 点が現状のコードに存在する。

- `getAudioTracks()` / `getVideoTracks()` は `audioTrackRefcountedVectorGet` / `videoTrackRefcountedVectorGet` が返した owned ref を `borrowedTrackRef` として一切 release していない。vectorGet は新規 owned ref を返す設計のため、呼び出しごとに 1 ref がリークする。このリークされた ref が track オブジェクトを生かし続けるため、cache-miss の二重解放直後でも refcount は 0 に落ちず、即時の use-after-free にはならない。実害は呼び出しごとの ref リークと、wrapper が自分の ref を実は持っていない会計破綻（dispose() 時に意図しない参照を解放する）である。
- `_audioTrackCache` / `_videoTrackCache` は track の `dispose()` では無効化されない。dispose 済み wrapper が cache に残ると、cache-hit で dispose 済み wrapper がそのまま返り、使用時に `ensureNotDisposed` の `StateError` になる。

同じ refcount 慣習は `LocalAudioTrack.withNativeTrackRefcounted` / `LocalVideoTrack.withNativeTrackRefcounted` の finally での `Release(RefcountedGet(...))` や `retainNativeTrackRefcounted` の設計と一貫している。cache-miss 側だけがこの慣習を破っている。

## 設計方針

- cache-miss 経路では、`ownedMediaTrackRef` の所有権を新規 `LocalAudioTrack` / `LocalVideoTrack` に委譲する。`LocalMediaStream._reuseOrCreateAudioTrack` / `_reuseOrCreateVideoTrack` は cache-hit の破棄用の `mediaStreamTrackRelease(nativeTrack)` のみを行い、cache-miss 経路では release しない。
- `getAudioTracks()` / `getVideoTracks()` は、`audioTrackRefcountedVectorGet` / `videoTrackRefcountedVectorGet` が返した owned ref を確実に release する（`audioTrackRelease` / `videoTrackRelease` 相当）。vectorGet の owned ref は cast が返す新規 ref とは別に存在するため、両方の release / 委譲を漏らさない。
- cache 内の track が dispose 済みの場合は cache として再利用しない。cache-hit 判定の前に `cachedTrack.isDisposed` を確認し、dispose 済みなら cache を破棄して cache-miss として新規 wrapper を生成する。dispose 後の再取得で新規 wrapper が返ることを保証する。
- コメントで「cache-hit のみ release する。cache-miss は owned ref を LocalXxxTrack に transfer する」「vectorGet の owned ref は取得側で release する」「dispose 済み cache は再利用しない」を明示する。
- `LocalMediaStreamTrack._` 側の refcount 引き継ぎ設計は変更しない。

## 完了条件

- [ ] `_reuseOrCreateAudioTrack` / `_reuseOrCreateVideoTrack` の cache-miss 経路で `mediaStreamTrackRelease` が呼ばれない。
- [ ] `getAudioTracks()` / `getVideoTracks()` が vectorGet の owned ref をリークしない。
- [ ] dispose 済み track が cache から再利用されず、dispose 後の再取得で新規 wrapper が生成され、crash / 例外が発生しない。
- [ ] cache-hit / cache-miss / cache 入れ替わり（`removeTrack()` + 別 track の `addTrack()`、または track が消えた後の再取得）の各シナリオを exercise するテストを追加する。refcount の絶対値は Dart 側から検証できないため、各シナリオで crash / 例外が発生しないこと、cache-hit では同一インスタンスが返り、cache-miss では新規インスタンスが返ることを観測対象にする。
- [ ] 既存の `test/sora_media_stream_test.dart` を含むテストが成功する。
- [ ] `flutter analyze` が成功する。
