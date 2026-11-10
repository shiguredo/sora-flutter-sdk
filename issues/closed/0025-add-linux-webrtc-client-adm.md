# WebrtcClient に Linux の AudioDeviceModule 初期化パスを追加する

- Priority: High
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-linux-webrtc-client-adm
- Polished: 2026-06-03

## 目的

`WebrtcClient._ensureSharedFactory()` は現在 Android / macOS のみ AudioDeviceModule (ADM) を生成して PeerConnectionFactory に積んでいる。Linux ではこの分岐に該当せず ADM が積まれないため、音声入出力が機能しない。Linux で音声が動作するよう ADM 初期化パスを追加する。

本 issue のスコープは ADM を PeerConnectionFactory に積むところまで。デバイス切り替え (0028) やプラグイン側の音声初期化は後続 issue に委ねる。

## 関連 issue

- **0033 (Windows)**: 同じ `webrtc_client.dart` を編集する。片方が先にマージされたらもう片方を rebase する。ADM の release/保持方針が同一の場合に限り `Platform.isLinux \|\| Platform.isWindows` への統合を検討する (方針が異なる場合は統合しない)。

## 優先度根拠

- Linux での音声送受信の前提であり、対応無しでは音声が一切使えない
- Dart 側の 1 分岐追加で対応できる
- High とする

## 現状

- `lib/src/ffi/webrtc_client.dart` の `_ensureSharedFactory()` で ADM を分岐生成している:
  - Android: `createAndroidAudioDeviceModule(env)` で生成し、`pcFactoryDependenciesSetAdm` で積んだ後 `audioDeviceModuleRelease(refcountedGet(adm))` で即時 release
  - macOS: `createAudioDeviceModule(env, kPlatformDefaultAudio)` で生成し、`pcFactoryDependenciesSetAdm` で積んだ後 `_sharedAdmRef` に参照を保持 (Dart から `SetRecordingDevice` を直接 FFI 操作するため)
  - Linux: いずれの分岐にも該当せず、ADM 無しでフォールスルー
- `kPlatformDefaultAudio` は `int` (`Int32`)。`bindings.dart` で `webrtc_AudioDeviceModule_kPlatformDefaultAudio` シンボルから動的解決される。値はプラットフォーム既定 (通常 `0`)
- Linux の音声デバイス選択は 0028 で MethodChannel 経由の設計が予定されている。Dart で生成した ADM のポインタを MethodChannel 経由でネイティブ側に安全に引き渡すことはできない。そのため Linux ネイティブ側は Dart 側 ADM とは別に独自に ADM を生成する必要があり、0028 の責務となる
- macOS の `_sharedAdmRef` は `_ensureSharedFactory()` 内で代入されるのみで、プロセス生存期間中 release されない。Android の ADM も `pcFactoryDependenciesSetAdm` が内部で refcount を保持するため、即時 release しても問題ない

## 設計方針

### ADM 生成と参照管理

- macOS ブロックの直後に `else if (Platform.isLinux)` 分岐を追加する
- 生成: `createAudioDeviceModule(env, kPlatformDefaultAudio)` を使用する。`createAndroidAudioDeviceModule` は Java ADM 用であり Linux では使えない
- 参照管理: Android と同様に `pcFactoryDependenciesSetAdm(deps, adm)` で積んだ後、`audioDeviceModuleRelease(audioDeviceModuleRefcountedGet(adm))` で即時 release する。`_sharedAdmRef` への保持は行わない
  - 理由: Linux ネイティブ側は Dart 側 ADM にアクセスできないため、`_sharedAdmRef` を保持しても FFI 経由で操作する手段がない。デバイス切り替え等の操作は 0028 でネイティブ側が独自 ADM を生成して行う
- `adm == nullptr` の場合は既存の Android/macOS 分岐と同様にフォールスルーする (ADM 無しで PCF が構築される)

### 0028 との責任分界

- 本 issue: ADM を生成し PCF に積むこと。音声入出力の基本動作に必要な最小限の初期化
- 0028: 音声デバイス列挙・選択。ネイティブ側で独自 ADM を生成するか MethodChannel 経由でデバイス指定するかは 0028 で決定する
- 本 issue は 0028 の設計に関わらず完了できる (ADM を積むだけであり、デバイス切り替えには関与しない)

## 完了条件

- `_ensureSharedFactory()` に `else if (Platform.isLinux)` 分岐が追加され、`kPlatformDefaultAudio` で ADM が生成・積載される
- `flutter analyze` がエラー 0 で通過する
- `CHANGES.md` の `## develop` の `### sora_sdk` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] WebrtcClient に Linux の AudioDeviceModule 初期化パスを追加する
    - Linux の PeerConnectionFactory 生成時に `kPlatformDefaultAudio` で ADM を初期化し、音声入出力を有効化する
    - @{実装者のユーザー名}
  ```

## 制約

- Linux 実機での音声送受信の確認は、Linux プラグイン実装 (0026-0028) と統合した段階で行う。本 issue 単体では静的解析の通過のみを保証する
- libwebrtc-c が Linux でプラットフォーム既定 ADM (`kPlatformDefaultAudio`) を提供することは、0024 の Step 1 で確認する

## 解決方法

1. `webrtc_client.dart` の `_ensureSharedFactory()` の macOS ブロック (`}` の直後) に `else if (Platform.isLinux)` 分岐を追加し、以下を実装する:
   ```dart
   } else if (Platform.isLinux) {
     final env = sharedLib.createEnvironment();
     final adm = sharedLib.createAudioDeviceModule(
       env,
       sharedConsts.kPlatformDefaultAudio,
     );
     sharedLib.environmentDelete(env);
     if (adm != nullptr) {
       sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
       sharedLib.audioDeviceModuleRelease(
         sharedLib.audioDeviceModuleRefcountedGet(adm),
       );
     }
   }
   ```
2. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する
