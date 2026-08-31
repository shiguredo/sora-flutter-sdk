# `_ensureSharedFactory` の途中 throw で thread / deps / ADM が leak し、リトライごとに 3 スレッドずつ堆積する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-ensure-shared-factory-thread-leak
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`WebrtcClient._ensureSharedFactory` の途中で `AudioDeviceModule init failed` の StateError が投げられると、既に作成した network / worker / signaling スレッド、`pcFactoryDependencies`、ADM 参照が解放されずリークするバグを修正する。ADM init 失敗のリトライごとに 3 スレッドずつ堆積する。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient._ensureSharedFactory` は以下の順で初期化する:

1. `threadCreateWithSocketServer` / `threadCreate` で 3 スレッドを create/start
2. `pcFactoryDependenciesNew()` で deps を確保
3. macOS / Windows / Linux の各分岐で ADM を作成し、`audioDeviceModuleInit(...)` の rc != 0 で `throw StateError('AudioDeviceModule init failed: rc=...')` を投げる（6 分岐で計 6 箇所）

throw 発生時は `pcFactoryDependenciesDelete(deps)` や thread stop / delete に到達しない。static field（`_sharedNetworkThread`, `_sharedWorkerThread`, `_sharedSignalingThread`）にはスレッドハンドルが保持されたままで、`_sharedFactoryRef` は null のため、次回 `_ensureSharedFactory` は最初から動き、上書きで新規スレッドを 3 本 create/start する。前世代スレッドは running のまま参照喪失。

## 設計方針

- `_ensureSharedFactory` 全体を try/catch で包み、catch 節で「作成済みの thread / deps / ADM を確実に解放する」処理を実行してから rethrow する。
- 具体的には以下の cleanup を catch で行う:
  - `pcFactoryDependenciesDelete(deps)` （既に取得している場合）
  - 3 スレッドの `threadStop` + `threadUniqueDelete` 相当（既に create している場合）
  - `_sharedAdmRef` が保持している ADM を release（実コードでは `_sharedAdmRef = adm` が `audioDeviceModuleInit` より前に必ず実行されるため、throw 時点で新規 ADM は代入済み。解放対象は「代入前の中間 ADM」ではなく現在の `_sharedAdmRef` の値）
  - static field のリセット（`_sharedNetworkThread` / `_sharedWorkerThread` / `_sharedSignalingThread` / `_sharedAdmRef`）
- Cleanup 処理をトップレベルの `finally` に置くと成功時にも破壊してしまうため、成功時と失敗時で分岐する。成功時は `_sharedFactoryRef = ...` の確定と native リソース保持、失敗時は破棄する構造にする。
- ADM 生成 6 ブロックの重複解消（issue 0109）と併せて設計する余地があるが、リーク修正を優先する。0109 側も本 issue の修正を先に完了させてから進める前提である。

## 完了条件

- [ ] `_ensureSharedFactory` が途中で throw しても network / worker / signaling スレッドがリークしない。
- [ ] deps / ADM 中間参照も同様にリークしない。
- [ ] ADM init 失敗を模擬するテストを追加し、失敗後に static field（`_sharedNetworkThread` / `_sharedWorkerThread` / `_sharedSignalingThread` / `_sharedAdmRef` / `_sharedFactoryRef`）がリセットされ、リトライで再生成が 1 セットに収まることを検証する。注入手段は `@visibleForTesting` テストフック（ADM init の rc を強制的に失敗させるフック）を production コードに追加して実施し、モックやスタブは使わない。
- [ ] `flutter analyze` と関連テストが成功する。
