# `LocalVideoTrack.dispose()` が非 async な Future を返しつつ sync throw する

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-local-video-track-dispose-sync-throw
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`LocalVideoTrack.dispose()` が接続にアタッチ中の場合に同期例外を投げるため、基底 `LocalMediaStreamTrack` の非同期契約（throw は Future.error にラップされる）と食い違うバグを修正する。修正後は `dispose()` が返す Future に `StateError` が載り、呼び出し側が `await` / `.catchError` で捕捉できるようになる。

## 現状

`lib/src/sora_media_stream.dart` の `LocalVideoTrack.dispose()` は `Future<void>` を返すが `async` が付いていない non-async 関数として実装されており、`_connectionOwners.isNotEmpty` の場合に `throw StateError('Cannot dispose a video track while it is attached to a connection.')` を同期例外として呼び出し元に伝播する。

- 基底 `LocalMediaStreamTrack.dispose()` は `async Future<void>` として実装されており、throw は Future.error にラップされる。`LocalAudioTrack` は dispose を override しておらず、基底の async 契約を継承している。
- `LocalMediaStreamTrack.dispose()` の dartdoc は `unawaited(track.dispose())` の利用を明示的に推奨している。`unawaited()` は Future の error を処理しないため、`unawaited(track.dispose().catchError(...))` としなければ例外は zone unhandled error になる。同期 throw のままではこの対処すらできない。
- 呼び出し元は基底の非同期契約を前提にしており、サブクラスだけ挙動が違うのは呼び出し規約違反。

## 設計方針

- `LocalVideoTrack.dispose()` に `async` を付ける、または `return Future.error(StateError(...));` を明示的に返す形に変更する。どちらの実装でも throw が常に Future.error として届くようにする（`async` 付与が簡潔）。
- `_disposed` の早期 return や `_disposeFuture` のメモ化などの既存挙動は維持する。
- 挙動変更にあわせて dartdoc に「接続にアタッチ中の dispose は Future.error になる」旨を追記する。
- なお、`unawaited(track.dispose())` 単独の用法では修正後も Future の error は zone unhandled error になるため、この用法を safe にするには `.catchError` を併用する必要がある。本 issue は dispose の同期 throw を解消することに限定し、`unawaited` 単独の用法まで安全化することは対象としない。

## 完了条件

- [x] `LocalVideoTrack.dispose()` の StateError が Future.error として呼び出し側に届く（同期 throw しない）。
- [x] `unawaited(videoTrack.dispose().catchError(...))` の用法で `videoTrack` が接続にアタッチ中の例外を捕捉できる（zone unhandled error にならない）。
- [x] 上記シナリオを exercise するユニットテストを追加する（`attachToConnection` を直接呼んでアタッチ状態を再現し、`MediaDevices.createExternalVideoTrack` 経由で実 track を生成する。`@visibleForTesting` の追加公開経路は不要と判断した ── 「## 解決方法」参照）。
- [x] `flutter analyze` と関連テストが成功する。

## 解決方法

`lib/src/sora_media_stream.dart` の `LocalVideoTrack.dispose()` に `async` を付け、
`_connectionOwners.isNotEmpty` のときの `throw StateError(...)` が同期例外ではなく
Future.error として呼び出し側に届くようにした。基底 `LocalMediaStreamTrack.dispose()` /
`LocalAudioTrack.dispose()` (どちらも `async Future<void>`) と非同期契約が揃うことに
なる。既存の `_disposed` 早期 return と `_disposeFuture` メモ化の挙動は維持している
(throw 経路では `_disposed` / `_disposeFuture` に触らないため、detach 後の 2 回目
`dispose()` で通常経路を通れる)。

docstring に「接続にアタッチ中の dispose は `StateError` を返す Future.error として
完了する」旨と、以前の同期 throw を捕捉していた既存コード (`try` / `catch`) を
`await` または `.catchError` に置き換える必要がある点を追記した。

テストは `test/sora_media_stream_test.dart` に新 group
`LocalVideoTrack.dispose の非同期契約 (FFI)` を追加し、次の 2 つを検証する。

- `attachToConnection(1)` した状態で `dispose()` が `Future.error(StateError)`
  を返すこと、および throw 経路後も `isDisposed` が false のまま維持されて
  detach → 通常 dispose ができること。
- `unawaited(dispose().catchError(...))` パターンで `StateError` を捕捉できること
  と、`runZonedGuarded` で zone unhandled error が 0 件であること。

完了条件では `attachToConnection` / `fromNativeMediaTrack` が `@internal` である
ことを理由に `@visibleForTesting` ラッパーの追加を検討していたが、`@internal` は
パッケージ跨ぎ利用のみが lint 警告対象であり、同一 `package:sora_sdk` 内の
`test/` からは直接呼び出せる (analyzer 警告なし) ため、追加ラッパーを設けずに
直接呼ぶ形にした。native track の生成には共有 factory が必要なため、既存の
`prepareFfiTestEnvironment().skipReason` で FFI 未設定環境ではテストを skip する。

`CHANGELOG.md` は `CODEBASE.md` の運用に従い触っていない (直近の 0072 / 0073 /
0074 / 0076 / 0077 / 0078 と同じ)。
