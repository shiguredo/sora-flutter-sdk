# `SimulcastVideoEncoderFactory.dispose()` の扱いを整理する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-simulcast-encoder-factory-dispose
- Polished: {YYYY-MM-DD}

## 目的

`SimulcastVideoEncoderFactory.dispose()` は外部からの呼び出しが無く、プロセス生存中は `_sharedSimulcastVideoEncoderFactory` に保持され続けるだけ。将来解放したくなった時のために残すのか、削除するのか、テスト専用にするのかを明確化する。

## 現状

`lib/src/ffi/simulcast_video_encoder_factory.dart` の `SimulcastVideoEncoderFactory.dispose()` は SDK 内・test 内のいずれからも呼び出されていない。`_sharedSimulcastVideoEncoderFactory` は `WebrtcClient._ensureSharedFactory` で生成されてプロセス生存中は解放されない設計。

- 使う予定が無いなら dead code なので削除する。
- テスト専用として残すなら `@visibleForTesting` を付ける。
- 将来のプロセス dispose に備えて残すならその意図をコメントで残し、`WebrtcClient` の dispose と繋げる設計を検討する。

## 設計方針

以下のいずれかに整理する:

- **A. 削除**: 使う予定が無いなら削除する。将来必要になったら別 issue で再導入する。
- **B. `@visibleForTesting` を付与**: テスト側から使う予定があるなら明示する。
- **C. `WebrtcClient` の dispose 経路で呼び出す**: プロセス全体の dispose 設計に組み込む。

推奨は A（削除）。使う予定が無い public API は残しておくと将来の refactor コストが増える。

いずれの案でも:
- 決定を CODEBASE.md 相当のドキュメントに残す。
- 内部限定なので CHANGELOG への記載は不要。

## 完了条件

- [ ] `SimulcastVideoEncoderFactory.dispose()` の扱いが明確化されている（削除、`@visibleForTesting`、または dispose 経路統合）。
- [ ] 決定内容がコメントに残されている。
- [ ] `flutter analyze` と関連テストが成功する。
