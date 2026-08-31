# `_ensureSharedFactory` の ADM 生成 6 ブロックの重複を解消する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-adm-creation
- Polished: {YYYY-MM-DD}

## 目的

`WebrtcClient._ensureSharedFactory` 内の macOS / Windows / Linux × `useAudioDevice` = 6 ブロックの同型コードを、単一のヘルパーに集約する。将来 ADM API に変更が入ったときに 6 箇所すべてを揃えて直す前提を解消する。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient._ensureSharedFactory` は、macOS / Windows / Linux × `useAudioDevice` (true/false) の 6 ブロックが「create → set → 既存 ADM release → `_sharedAdmRef` 代入 → `audioDeviceModuleInit`」の同一シーケンスを繰り返している。差分は:

- macOS + useAudioDevice=true: `sharedLib.createAudioDeviceModule(env, kPlatformDefaultAudio)`
- Windows + useAudioDevice=true: `sharedLib.soraCreateAudioDeviceModule(env, kPlatformDefaultAudio)`（setjmp/longjmp で abort 捕捉）
- Linux + useAudioDevice=true: `sharedLib.createAudioDeviceModule(env, kPlatformDefaultAudio)`
- useAudioDevice=false: 全プラットフォーム `sharedLib.soraCreatePushAudioDevice()`
- ログ変数名: `initRcMac` / `initRcWin` / `initRcLinux`

## 設計方針

- `Pointer<WebrtcAudioDeviceModuleRefcounted> Function()` を引数に取る `_installAdm(builder)` を 1 本用意し、プラットフォーム分岐から呼び出す形にまとめる。
- 差分は builder 関数 lambda に押し込む。ログ変数名は共通の `initRc` に統一する。
- Windows の setjmp/longjmp 経路は builder 側で `soraCreateAudioDeviceModule` を呼ぶことで統合できる。
- 別 issue の `_ensureSharedFactory` 途中 throw の leak 修正（0082）と連携する。leak 修正を先に完了させてから本 refactor を進めるのが安全。
- 挙動変更はしない。既存の全プラットフォーム分岐で挙動が変わらないことをテストで担保する。

## 完了条件

- [ ] `_ensureSharedFactory` の ADM 生成が単一ヘルパーで表現され、プラットフォーム分岐が簡潔になる。
- [ ] 既存の全プラットフォームでの挙動が変わらない。
- [ ] `flutter analyze` と関連テストが成功する。
