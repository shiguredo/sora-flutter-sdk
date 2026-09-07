# `_ensureSharedFactory` の ADM 生成 6 ブロックの重複を解消する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-adm-creation
- Polished: 2026-09-07

## 目的

`WebrtcClient._ensureSharedFactory` 内の macOS / Windows / Linux × `useAudioDevice` = 6 ブロックの同型コードを、単一のヘルパーに集約する。将来 ADM API に変更が入ったときに 6 箇所すべてを揃えて直す前提を解消する。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient._ensureSharedFactory` は、macOS / Windows / Linux × `useAudioDevice` (true/false) の 6 ブロックが「create → `pcFactoryDependenciesSetAdm(deps, adm)` → 既存 ADM release → `_sharedAdmRef` 代入 → `_initAudioDeviceModule` (失敗時は `throw StateError`)」の同一シーケンスを繰り返している。全体は try / catch 構造であり、catch で `_releaseSharedFactoryResources` による解放と static field リセットを行う (`0082` 決着後の形)。差分は:

- macOS + useAudioDevice=true: `sharedLib.createAudioDeviceModule(env, kPlatformDefaultAudio)`
- Windows + useAudioDevice=true: `sharedLib.soraCreateAudioDeviceModule(env, kPlatformDefaultAudio)`（setjmp/longjmp で abort 捕捉）
- Linux + useAudioDevice=true: `sharedLib.createAudioDeviceModule(env, kPlatformDefaultAudio)`
- useAudioDevice=false: 全プラットフォーム `sharedLib.soraCreatePushAudioDevice()`
- ログ変数名: `initRcMac` / `initRcWin` / `initRcLinux`

## 設計方針

- 6 ブロックを `_installAdm({required Pointer<WebrtcPeerConnectionFactoryDependencies> deps, required Pointer<WebrtcAudioDeviceModuleRefcounted>? Function() builder, required bool managesEnv})` 相当の単一ヘルパー呼び出しに置き換える。ヘルパー内で `pcFactoryDependenciesSetAdm`、既存 `_sharedAdmRef` の release、代入、`_initAudioDeviceModule` と失敗時 throw を行う。`adm == nullptr` 時は無操作とする。
- `env` の生成・破棄 (`createEnvironment` / `environmentDelete`) は `managesEnv == true` の場合のみヘルパー側で行い、`useAudioDevice=false` 系 (env なし) と共用する。差分の生成関数は builder lambda に押し込む。ログ変数名は共通の `initRc` に統一する。
- Windows の setjmp/longjmp 経路は builder 側で `soraCreateAudioDeviceModule` を呼ぶことで統合できる。
- `0082` は closed 済みであり前提は満たされている。ヘルパー化後も `0082` の保証 (`_sharedAdmRef` 代入は init より前、catch 節の解放経路との連携) を維持し、順序を変えない。
- Android 分岐 (`createAndroidAudioDeviceModule` 系の異型シーケンス) は対象外とし、変更しない。
- 挙動変更はしない。

## 完了条件

- [ ] 6 ブロックが単一ヘルパー呼び出しに置き換わり、`_installAdm` 相当以外の重複シーケンスが残っていない。
- [ ] `0082` の保証 (代入順序・catch 解放経路) が維持されている。
- [ ] `flutter analyze` と `flutter test test/webrtc_client_test.dart` が成功する。
