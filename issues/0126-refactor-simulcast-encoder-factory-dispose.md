# `SimulcastVideoEncoderFactory.dispose()` の寿命契約をコメントに明記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-simulcast-encoder-factory-dispose
- Polished: 2026-09-07

## 目的

`SimulcastVideoEncoderFactory.dispose()` の呼び出し条件と `_sharedSimulcastVideoEncoderFactory` の寿命契約がコードコメントに明記されていない。成功時はプロセス寿命まで保持され、失敗時は解放される二面性を読み手が推測しなければならない状態を解消する。

## 現状

`lib/src/ffi/simulcast_video_encoder_factory.dart` の `SimulcastVideoEncoderFactory.dispose()` の呼び出し元は以下である:

- `lib/src/ffi/webrtc_client.dart` の `_releaseSharedFactoryResources` (失敗経路のクリーンアップ。`0082` で導入)
- `test/simulcast_video_encoder_factory_test.dart` (dispose 系 3 テストで計 4 呼び出し)

寿命契約は二面性を持つ:

- 成功時: `_sharedSimulcastVideoEncoderFactory` は `WebrtcClient._ensureSharedFactory` で生成後に所有権移譲され、プロセス寿命まで保持される。`WebrtcClient.dispose()` (per-client) では解放しない。
- 失敗時: `_ensureSharedFactory` の catch → `_releaseSharedFactoryResources` で `dispose()` して null クリアする。

共有リソースの正常系 dispose 方針 (プロセス寿命として明文化するか、共有 dispose API を追加するか) は `0150-refactor-webrtc-client-test-teardown-shared-factory-leak` が所有するため、本 issue では触れない。`0150` で共有 dispose を新設する場合は simulcast も一体で扱い、本 issue のコメントと整合させること。

## 設計方針

- `_sharedSimulcastVideoEncoderFactory` の宣言部に寿命契約 (成功時はプロセス寿命、失敗時は `_releaseSharedFactoryResources` で解放) をコメントで明記する。
- 削除・`@visibleForTesting` 化は行わない (本番失敗経路で使用中のため)。
- 内部限定なので CHANGELOG への記載は不要。

## 完了条件

- [ ] 寿命契約がコードコメントに明記されている。
- [ ] `0150` の issue 本文とコメント内容を突き合わせて矛盾が無い。
- [ ] `flutter analyze` と `flutter test test/simulcast_video_encoder_factory_test.dart` が成功する。
