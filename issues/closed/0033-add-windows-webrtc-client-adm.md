# WebrtcClient に Windows の AudioDeviceModule 初期化パスを追加する

- Priority: Medium
- Created: 2026-06-03
- Completed: 2026-06-11
- Model: Opus 4.8
- Branch: feature/add-windows-webrtc-client-adm
- Polished: 2026-06-03

## 目的

`WebrtcClient._ensureSharedFactory()` は現在 Android / macOS のみ AudioDeviceModule (ADM) を生成して PeerConnectionFactory に積んでいる。Windows ではこの分岐に該当せず ADM が積まれないため、音声入出力が機能しない。Windows で音声が動作するよう ADM 初期化パスを追加する。

本 issue のスコープは ADM を PeerConnectionFactory に積むところまで。デバイス切り替え (0036) やプラグイン側の音声初期化は後続 issue に委ねる。

## 関連 issue

- **0025 (Linux)**: 同じ `webrtc_client.dart` を編集する。片方が先にマージされたらもう片方を rebase する。ADM の release/保持方針が同一の場合に限り `Platform.isLinux || Platform.isWindows` への統合を検討する (方針が異なる場合は統合しない)。

## 優先度根拠

- Windows での音声送受信の前提であり、対応無しでは音声が一切使えない
- Linux 先行のため Medium とする

## 現状

- `lib/src/ffi/webrtc_client.dart` の `_ensureSharedFactory()` で ADM を分岐生成している:
  - Android: `createAndroidAudioDeviceModule(env)` → 積んだ後即時 release
  - macOS: `createAudioDeviceModule(env, kPlatformDefaultAudio)` → 積んだ後 `_sharedAdmRef` に参照保持
  - Linux (0025): `createAudioDeviceModule(env, kPlatformDefaultAudio)` → 積んだ後即時 release
  - Windows: いずれの分岐にも該当せず、ADM 無しでフォールスルー
- `kPlatformDefaultAudio` は `int` (`Int32`) で、WASAPI のプラットフォーム既定 ADM を指定する
- Windows の音声デバイス選択は 0036 で MethodChannel 経由の設計が予定されている。Dart で生成した ADM のポインタを MethodChannel 経由でネイティブ側に安全に引き渡すことはできない
- そのため Windows ネイティブ側は Dart 側 ADM とは別に独自に ADM を生成する必要があり、0036 の責務となる

## 設計方針

### ADM 生成と参照管理

- macOS ブロックの直後 (Linux ブロックの後) に `else if (Platform.isWindows)` 分岐を追加する
- 生成: `createAudioDeviceModule(env, kPlatformDefaultAudio)` を使用する
- 参照管理: Android / Linux と同様に `pcFactoryDependenciesSetAdm(deps, adm)` で積んだ後、`audioDeviceModuleRelease(audioDeviceModuleRefcountedGet(adm))` で即時 release する。`_sharedAdmRef` への保持は行わない
  - 理由: Windows ネイティブ側は Dart 側 ADM にアクセスできないため、`_sharedAdmRef` を保持しても操作する手段がない。デバイス切り替え等の操作は 0036 でネイティブ側が独自 ADM を生成して行う

- `adm == nullptr` の場合は既存の Android/macOS/Linux 分岐と同様にフォールスルーする

### 0036 との責任分界

- 本 issue: ADM を生成し PCF に積むこと
- 0036: 音声デバイス列挙・選択。ネイティブ側で独自 ADM を生成するか MethodChannel 経由でデバイス指定するかは 0036 で決定する

## 完了条件

- `_ensureSharedFactory()` に `else if (Platform.isWindows)` 分岐が追加され、`kPlatformDefaultAudio` で ADM が生成・積載される
- `flutter analyze` がエラー 0 で通過する
- `CHANGES.md` の `## develop` の `### sora_sdk` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] WebrtcClient に Windows の AudioDeviceModule 初期化パスを追加する
    - Windows の PeerConnectionFactory 生成時に `kPlatformDefaultAudio` で ADM を初期化し、音声入出力を有効化する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. `webrtc_client.dart` の `_ensureSharedFactory()` に `else if (Platform.isWindows)` 分岐を追加する。実装は Linux (0025) と同一パターンで `createAudioDeviceModule(env, kPlatformDefaultAudio)` → `pcFactoryDependenciesSetAdm` → `audioDeviceModuleRelease` の流れ
2. 0025 がマージ済みなら `Platform.isLinux || Platform.isWindows` への統合を検討する (release 方針が同一のため統合可能)
3. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する
