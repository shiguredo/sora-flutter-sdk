# WebRTC client の worker thread を network thread に統一する

- Created: 2026-09-15
- Completed: 2026-09-15
- Branch: feature/refactor-unify-worker-thread
- Polished: {YYYY-MM-DD}

## 目的

libwebrtc の issue 558821261「Deprecate and remove PeerConnectionFactoryDependencies::worker_thread」で worker thread が廃止される。CL 501620「Default worker thread to network thread」と CL 502480「Warn when a distinct worker thread is configured」はマージ済みで、削除系 CL (499302 / 501640 / 501720 / 502000 / 502500 / 502860 / 502940 / 502960) はレビュー中である。`PeerConnectionFactoryDependencies::worker_thread` と `PeerConnectionFactoryInterface::worker_thread()` は将来削除される。

対応は 2 段階に分ける。本 issue は第 1 段階 (方針 1) で、いますぐ実施する内容として専用 worker thread をやめて network thread を使う。第 2 段階 (方針 2) の「worker thread の利用箇所と API を全て無くす」は、558821261 を実装した libwebrtc を pin で取り込んだ後に実施するため、`issues/0177-remove-worker-thread.md` に分ける。

## 現状

- `lib/src/ffi/webrtc_client.dart` の `WebrtcClient` が `_sharedNetworkThread` / `_sharedWorkerThread` / `_sharedSignalingThread` を static フィールドで保持している。
  - `_ensureSharedFactory()` が `threadCreateWithSocketServer()` (network) / `threadCreate()` (worker) / `threadCreate()` (signaling) で 3 スレッドを生成し、`threadStart()` で起動して `pcFactoryDependenciesSetNetworkThread` / `pcFactoryDependenciesSetWorkerThread` / `pcFactoryDependenciesSetSignalingThread` で deps に渡している。
  - `_sharedWorkerThread` は、共有 factory が生成途中で確保したリソースを保持しているかを返すテスト用フック `hasSharedFactoryResourcesForTest` でも参照している。
  - `_releaseSharedFactoryResources()` が `_destroySharedThread(_sharedWorkerThread)` で worker thread を停止・解放している。
- worker thread 上で `BlockingCall` している箇所は本リポジトリには存在しない (`lib/` に `BlockingCall` の使用が 0 件で、`lib/src/ffi/bindings.dart` に `webrtc_Thread_BlockingCall` のバインディングも無い)。
- ADM は Dart 側のスレッドから生成して `pcFactoryDependenciesSetAdm` で deps に積んでいる。worker thread を必要としない。
- `lib/src/ffi/bindings.dart` は libwebrtc-c C API の手書きの dart:ffi バインディングで、`pcFactoryDependenciesSetWorkerThread` と `pcFactoryDependenciesSetNetworkThread` の両方を定義している (`pcFactoryDependenciesSetNetworkThread` は既にある)。
- 本リポジトリは libwebrtc を直接使わず、shiguredo/webrtc-rs が提供する C API (libwebrtc_c) のリリース済みバイナリを `scripts/native_deps.json` で pin して使っている。現在の pin は `libwebrtc_c` が `0.150.3`、`webrtc` が `m150.7871.3.1` である。

## 設計方針

- 専用 worker thread の生成 / 開始 / 破棄と `pcFactoryDependenciesSetWorkerThread` の呼び出しを削除し、factory の worker thread として network thread を使う (`pcFactoryDependenciesSetWorkerThread` に network thread を渡す)。
- `_sharedWorkerThread` を削除し、テスト用フック `hasSharedFactoryResourcesForTest` と `_releaseSharedFactoryResources` を network thread と signaling thread の 2 スレッド構成に合わせる。
- `pcFactoryDependenciesSetWorkerThread` のバインディングと `android/src/main/cpp/libwebrtc_c_api.ldflags` / `linux/libwebrtc_c_api.ldflags` の `-Wl,--undefined=webrtc_PeerConnectionFactoryDependencies_set_worker_thread` は方針 1 では削除しない。方針 2 (`issues/0177-remove-worker-thread.md`) で削除する。
- `libwebrtc_c` の pin を CL 501620 収録版へ上げるまでは、`worker_thread` を未設定にすると libwebrtc 内部で専用スレッドが生成される。スレッド数を減らすため、network thread を明示的に渡す。

## 完了条件

- [ ] `_sharedWorkerThread` が削除され、`_ensureSharedFactory()` が専用 worker thread を生成・起動していない。
- [ ] `pcFactoryDependenciesSetWorkerThread` の呼び出しが消え、factory の worker thread に network thread が渡されている。
- [ ] `hasSharedFactoryResourcesForTest` と `_releaseSharedFactoryResources` が network thread と signaling thread の 2 スレッド構成に合った内容になっている。
- [ ] `pcFactoryDependenciesSetWorkerThread` のバインディングと 2 つの `libwebrtc_c_api.ldflags` の該当行が方針 2 まで残っている。
- [ ] `flutter analyze` と `flutter test` が成功する。
- [ ] モックやスタブを使用していない。
- [ ] `CHANGELOG.md` への記載は正式リリース前のため行わない (`CODEBASE.md` の「正式リリース前」節に従う)。正式リリース確定時に追記する。

## 解決方法

WebRTC client の worker thread として network thread を使うようにした。

- `lib/src/ffi/webrtc_client.dart` から `_sharedWorkerThread` フィールドと worker thread の生成、開始、破棄を削除し、`pcFactoryDependenciesSetWorkerThread` に network thread を渡すようにした
- テスト用フック `hasSharedFactoryResourcesForTest` と `_releaseSharedFactoryResources` を 2 スレッド構成に合わせた
- `test/webrtc_client_test.dart` のコメントを 2 スレッドに更新した

確認:

- `flutter analyze --fatal-infos lib test` が通ることを確認した
- `flutter test` が通ることを確認した（175 passed。`SORA_FFI_TEST_LIBRARY_PATH` が未設定のため FFI 依存のテストは skip）

## 関連

- `issues/0177-remove-worker-thread.md` (方針 2。worker thread の利用箇所と C API のバインディングを削除する)
- `issues/0150-refactor-webrtc-client-test-teardown-shared-factory-leak.md` (`hasSharedFactoryResourcesForTest` が対象とする共有リソースの寿命)
