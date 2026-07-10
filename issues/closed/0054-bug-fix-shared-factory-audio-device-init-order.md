# sharedFactory の音声デバイス初期化が静的副作用に依存する問題を修正する

- Priority: High
- Created: 2026-07-08
- Completed: 2026-07-10
- Model: GPT-5 Codex
- Polished: 2026-07-08
- Branch: feature/fix-shared-factory-audio-device-init-order

## 目的

`useAudioDevice: false` を指定した接続でも、`MediaDevices.*` が `Sora.createConnection()` より先に呼ばれると `WebrtcClient.sharedFactory` が既定値 (`true`) で初期化され、実音声デバイスの `AudioDeviceModule` 初期化に失敗する問題を SDK 側で解消する。

問題の本質は「`_useAudioDevice` という静的 mutable field への副作用依存」にある。呼び出し順は症状であり、原因は静的フィールド `_useAudioDevice` の既定値 (`true`) が `SoraConnectionConfig` 経由の設定より先に参照される点にある。

## 優先度根拠

- Linux の GitHub Actions E2E で `audio: false` / `useAudioDevice: false` のテストが `AudioDeviceModule init failed: rc=-1` で継続的に失敗している
- devtools や E2E で呼び出し順を調整すれば一時回避はできるが、SDK の公開 API 契約としては不自然で再発余地が高い
- `MediaDevices` の利用順序に依存して接続可否が変わる状態は、利用者コードでも潜在バグになりうるため High とする

## 関連 issue

- **0052**: `MediaDevices.createExternalAudioTrack()` を追加する issue。本 issue で shared factory の API が変更される場合、0052 の実装は本 issue のマージ後に rebase して新しい初期化パターンに追従する必要がある
- **0052 / 0025 / 0033**: いずれも `_ensureSharedFactory()` 内の ADM 分岐を触っている。本 issue で `_ensureSharedFactory()` のシグネチャが変わる場合、各ブランチとの競合に注意する

## 現状

### コード上の問題構造

- `lib/src/ffi/webrtc_client.dart` の `WebrtcClient.sharedFactory` は引数を取らず、初回アクセス時に `_ensureSharedFactory()` を実行する
- `_ensureSharedFactory()` の ADM 分岐は静的フィールド `_useAudioDevice` に依存している
- `_useAudioDevice` は `WebrtcClient.create()` 内で `config['useAudioDevice'] ?? true` から設定される
- `lib/src/sora_media_devices.dart` の `createMediaStream()`、`createAudioTrack()`、`createCameraVideoTrack()`、`createExternalVideoTrack()`、`getUserMedia()` はいずれも内部で `WebrtcClient.sharedFactory` を参照する
- そのため `Sora.createConnection()` より前に `MediaDevices.*` を呼ぶと、`SoraConnectionConfig.useAudioDevice` が反映される前に shared factory が生成される

### Android の特殊性

Android は `_ensureSharedFactory()` 内で `_useAudioDevice` を参照せず、常に `createAndroidAudioDeviceModule()` で実 ADM を生成する (`webrtc_client.dart:264-273`)。そのため本バグは Android では再現しない。修正範囲は macOS / Windows / Linux に限定される。

### E2E テストの現状

2026-07-08 時点で以下の E2E 失敗を確認している:

- `local_media_toggle_e2e_test.dart` の `local_media_toggle_video`
- `sendrecv_smoke_e2e_test.dart`

いずれも stack trace は `MediaDevices.createMediaStream()` → `WebrtcClient.sharedFactory` → `AudioDeviceModule init failed: rc=-1` を示している。

また、上記の直接失敗に加えて、`useAudioDevice: false` を指定する全 E2E テスト (`notify_metadata_e2e_test.dart`, `dispose_api_guard_e2e_test.dart`, `track_event_e2e_test.dart`, `connection_failure_e2e_test.dart`, `messaging_only_e2e_test.dart`, `recvonly_e2e_test.dart`, `custom_data_channel_e2e_test.dart`, `bundle_id_isolation_e2e_test.dart`, `sendonly_dummy_video_e2e_test.dart`, `two_party_media_e2e_test.dart`, `replace_video_track_e2e_test.dart`, `remote_media_stream_e2e_test.dart`) は現状の `Sora.createConnection()` を先に呼ぶ workaround に依存している。これらのテストは workaround が崩れた場合に同じエラーで落ちる潜在リスクを持つ。

### 現状の一時回避

E2E 側では `ObservedConnection.create()` / `Sora.createConnection()` を先に呼ぶ一時回避を入れたが、これは SDK の根本問題を隠しているだけである。また `e2e_test_app/integration_test/helpers/push_audio_track.dart` の `E2ePushAudioTrack.create()` (同:32-39) も `MediaDevices.createAudioTrack()` で暗黙に shared factory に依存しており、workaround なしでは動作しない (caller が事前に `Sora.createConnection()` を呼ぶことを前提としている)。

## 設計方針

### 核心: 静的副作用からの脱却

根本原因は `_useAudioDevice` という静的 mutable field の値が `WebrtcClient.create()` の副作用として初めて設定され、それ以前の `MediaDevices.*` 呼び出しでは既定値 (`true`) が使われることにある。呼び出し順ではなく、**初期化パラメータを明示的に渡せる設計** へ変更する。

### 設計判断

1. **`_ensureSharedFactory()` は `bool useAudioDevice` を受け取る**: `_ensureSharedFactory()` のシグネチャを `static void _ensureSharedFactory({bool useAudioDevice = true})` とし、ADM 分岐はこの引数に基づいて選択する
2. **`sharedFactory` getter は変更しないが、内部で `_useAudioDevice` の現在値を `_ensureSharedFactory()` へ渡す**: getter に引数は追加できないため、`_useAudioDevice` 静的フィールドを setter (`WebrtcClient.setUseAudioDevice`) で公開し、必要に応じて事前設定できるようにする。デフォルトは `true` で維持する
3. **衝突時の挙動は `StateError` で確定**: 既に shared factory が生成された後に異なる `useAudioDevice` が要求された場合、`StateError` をスローする。再利用も別 factory 戦略も行わない
   - `_ensureSharedFactory()` 内で初回初期化時に `_initialUseAudioDevice` を記録し、2 回目以降の要求値と不一致なら `StateError` とする
4. **`WebrtcClient.create()` の副作用としての `_useAudioDevice` 設定は廃止する**: `WebrtcClient.create()` 内の `_useAudioDevice = (config['useAudioDevice'] as bool?) ?? true;` (webrtc_client.dart:450) を削除し、`SoraConnectionConfig.useAudioDevice` はシグナリングメッセージの構成要素としてのみ残す。`sharedFactory` 初期化には影響しない
5. **`SoraConnectionConfig.useAudioDevice` は存続**: 既存の `toMap()` 互換と platform 側への通知のために残す。ただし `WebrtcClient` の ADM 選択には使わない。プロセス内の全接続で最初に有効な値で factory が初期化される設計となる
6. **`MediaDevices` の API 設計**: 音声に関係するメソッドのみ `useAudioDevice` パラメータを追加する。映像専用メソッドはパラメータを追加せず、グローバル設定 (`MediaDevices.setUseAudioDevice(bool)` または `WebrtcClient.useAudioDevice`) に委ねる
   - `createAudioTrack({bool? useAudioDevice})`: 明示指定可能。省略時はグローバル設定を使用する
   - `getUserMedia(GetUserMediaOptions)`: `GetUserMediaOptions` に `useAudioDevice` フィールドを追加する。`audio: true` + `useAudioDevice: false` の組み合わせは「音声トラックは含めるが実デバイスは使わない (PushAudioDevice を利用する)」場合に使用する
   - `createMediaStream()`: パラメータ追加なし。グローバル設定に依存する
   - `createCameraVideoTrack()`, `createExternalVideoTrack()`: パラメータ追加なし。グローバル設定に依存する
7. **`MediaDevices.setUseAudioDevice(bool)` 静的メソッドを追加**: 映像専用 API を `Sora.createConnection()` より前に使う場合の escape hatch として提供する。`MediaDevices` クラスに静的な現在値を持ち、内部で `WebrtcClient._useAudioDevice` に反映する
8. **Android はスコープ外**: Android は常に実 ADM を使い、`_useAudioDevice` を参照しないため、本 issue の修正対象としない。`SoraConnectionConfig.useAudioDevice` のドキュメント (`sora_connection_config.dart:66-67`) にある「Android では無視される」記述は維持する

### 制約

- 一時回避のため E2E で行った呼び出し順の調整は残してよいが、本 issue の完了条件にはしない

## 完了条件

### API 設計

- `_ensureSharedFactory()` が `bool useAudioDevice` を受け取り、ADM 分岐をこの引数に基づいて選択する
- `WebrtcClient` に静的 setter (`setUseAudioDevice(bool)`) が追加され、`WebrtcClient.create()` より前に呼び出しても初期化設定が可能である
- `WebrtcClient.create()` の `_useAudioDevice` 副作用設定が削除されている (webrtc_client.dart:450)
- `MediaDevices` に `setUseAudioDevice(bool)` 静的メソッドが追加され、映像専用 API (`createMediaStream()`、`createCameraVideoTrack()`、`createExternalVideoTrack()`) の `useAudioDevice` 設定をグローバルに指定できる
- `createAudioTrack()` が `bool? useAudioDevice` 引数を受け付け、省略時はグローバル設定を使用する
- `GetUserMediaOptions` に `bool useAudioDevice` フィールドが追加されている
- 既に shared factory が生成された後に異なる `useAudioDevice` が要求された場合、`StateError` がスローされる

### 動作保証

- `Sora.createConnection(useAudioDevice: false)` より前に `MediaDevices.createAudioTrack()` を呼んでも、実 ADM 初期化が発生しない
- `Sora.createConnection(useAudioDevice: false)` より前に `MediaDevices.createMediaStream()` / `createCameraVideoTrack()` / `createExternalVideoTrack()` を呼んでも、`_useAudioDevice` 既定値 (true) で実 ADM 初期化が発生しない (グローバル設定が `false` の場合)
- `MediaDevices.setUseAudioDevice(false)` → `createCameraVideoTrack()` → `Sora.createConnection(useAudioDevice: true)` の順で呼んだ場合、最初の `createCameraVideoTrack()` で factory が `false` で初期化され、後続の `createConnection` で `StateError` がスローされる

### テスト通過条件

- Linux の `sendrecv_smoke_e2e_test.dart`、`local_media_toggle_e2e_test.dart`、`remote_media_stream_e2e_test.dart` で、E2E 側の呼び出し順 workaround を除去しても `AudioDeviceModule init failed: rc=-1` が再現しない
  - `remote_media_stream_e2e_test.dart` は現状直接の失敗を確認していないが、`useAudioDevice: false` の依存関係を持つため regression 防止として完了条件に含める
- `e2e_test_app/integration_test/helpers/push_audio_track.dart` が新 API に対応し、`Sora.createConnection()` より前に `E2ePushAudioTrack.create()` を呼んでも動作する
- `flutter analyze --fatal-infos` がエラー 0 で通過する
- 既存 unit test (`test/sora_connection_config_test.dart` 等) がすべて通過する
- `CHANGES.md` の `## develop` の `### sora_sdk` セクションに `[FIX]` エントリが追加されている

### ドキュメント

- `README.md` の `MediaDevices` 利用例が新 API と一致している (変更がある場合のみ更新。変更がない場合は更新不要)
- 必要な場合は `e2e_test_app/README.md` も同様に更新する

### 非対象

- Android はスコープ外。既存動作に変更は加えない

## 解決方法

### Step 1: `_ensureSharedFactory()` のシグネチャ変更

`lib/src/ffi/webrtc_client.dart`:

- `_ensureSharedFactory()` のシグネチャを `static void _ensureSharedFactory({bool useAudioDevice = true})` に変更する
- 各プラットフォーム分岐 (macOS / Windows / Linux) の ADM 選択をこの引数 `useAudioDevice` に基づいて行う
- 初回初期化時に `_initialUseAudioDevice` (新規静的フィールド) に使用値を記録する
- `_ensureSharedFactory()` が 2 回目以降に呼ばれた場合 (つまり `_sharedFactoryRef != null`)、要求された `useAudioDevice` と `_initialUseAudioDevice` を比較し、不一致なら `StateError` をスローする
- `WebrtcClient.useAudioDevice` 静的 setter を追加: `static void set useAudioDevice(bool value)` → `_useAudioDevice = value;`
- `sharedFactory` getter の内部で `_ensureSharedFactory(useAudioDevice: _useAudioDevice)` を呼ぶ
- `WebrtcClient.create()` (webrtc_client.dart:450) の `_useAudioDevice = (config['useAudioDevice'] as bool?) ?? true;` を削除する
  - 後方互換のため `config` から `useAudioDevice` を読むコード自体は残してもよいが、`_useAudioDevice` の設定としては使わない

### Step 2: `MediaDevices` API の拡張

`lib/src/sora_media_devices.dart`:

- `MediaDevices` クラスに静的メソッドを追加:
  ```dart
  static void setUseAudioDevice(bool value) {
    WebrtcClient.useAudioDevice = value;
  }
  ```
- `createAudioTrack()` に `bool? useAudioDevice` 引数を追加:
  ```dart
  static Future<LocalAudioTrack> createAudioTrack({
    String? audioDeviceId,
    bool? useAudioDevice,
  }) async {
    if (useAudioDevice != null) {
      WebrtcClient.useAudioDevice = useAudioDevice;
    }
    // 既存の処理...
  }
  ```
- `GetUserMediaOptions` にフィールド追加:
  ```dart
  final bool useAudioDevice;
  ```
- `getUserMedia()` で `GetUserMediaOptions.useAudioDevice` が明示された場合、内部の `createAudioTrack()` 呼び出し前にグローバル設定を更新する
- `createMediaStream()`、`createCameraVideoTrack()`、`createExternalVideoTrack()` は変更なし (グローバル設定 `_useAudioDevice` の現在値に依存)

### Step 3: `SoraConnectionConfig` の変更

`lib/src/sora_connection_config.dart`:

- `useAudioDevice` フィールドは存続し、`toMap()` の出力にも含める (platform 側への通知用)
- `SoraConnectionConfig.useAudioDevice` のドキュメント (sora_connection_config.dart:62-64) を更新し、`WebrtcClient` の ADM 選択には影響しないことを明記する
  - 代わりに `MediaDevices.setUseAudioDevice()` または各 `MediaDevices` API の引数を使用するよう案内する
  - Android では無視される旨の既存記述は維持する

### Step 4: `SoraConnection.internalCreate()` の変更

`lib/src/sora_connection.dart`:

- `WebrtcClient.create()` を呼ぶ前に、`config.useAudioDevice` を `MediaDevices.setUseAudioDevice()` / `WebrtcClient.useAudioDevice` に反映するコードを削除する (もしくは `create()` 内の `_useAudioDevice` 設定削除により自動的に無効化される)
- `SoraConnectionConfig.useAudioDevice` はそのままシグナリングメッセージに含まれ続ける (platform 側との互換性維持)

### Step 5: テストの更新

- 既存 unit test (`test/sora_connection_config_test.dart`) で `toMap()` の `useAudioDevice` が正しく出力されることを確認 (変更なしで通過するはず)
- 新たに以下を unit test または E2E で検証:
  - `MediaDevices.setUseAudioDevice(false)` → `createCameraVideoTrack()` で実 ADM が初期化されない
  - `MediaDevices.setUseAudioDevice(false)` → `createAudioTrack()` で実 ADM が初期化されない
  - `createAudioTrack(useAudioDevice: false)` で実 ADM が初期化されない
  - `Sora.createConnection()` より前に `MediaDevices.createMediaStream()` を呼んでも、グローバル設定が `false` なら実 ADM が初期化されない
  - 異なる `useAudioDevice` の衝突で `StateError` がスローされる

### Step 6: E2E / helpers の更新

- `e2e_test_app/integration_test/helpers/push_audio_track.dart` の `E2ePushAudioTrack.create()` に `useAudioDevice` 設定を追加 (明示的に `false` を指定)
- 各 E2E テストから呼び出し順の workaround (`Sora.createConnection()` を先に呼ぶ) を削除し、初期化順に依存しないことを確認する
- `devtools` のコード変更があれば追従する

### Step 7: CHANGES.md の更新

`CHANGES.md` の `## develop` → `### sora_sdk` に以下を追記:

```
- [FIX] sharedFactory の音声デバイス初期化が静的副作用に依存する問題を修正する
  - `MediaDevices` 各 API で `useAudioDevice` を明示できるようにし、`Sora.createConnection()` より先に呼んでも正しく動作するよう修正する
  - @{実装者のユーザー名}

## 解決方法

- 共有 factory の音声デバイス設定を、`WebrtcClient.create()` の副作用ではなく明示的な設定値で初期化するよう変更した
- `MediaDevices.setUseAudioDevice()`、`createAudioTrack(useAudioDevice: ...)`、`GetUserMediaOptions.useAudioDevice` を追加した
- 接続生成より前にメディア API を呼ぶ E2E テストを追加し、macOS で関連 E2E 13 件中 11 件が成功した
- 誤った設定変更を暗黙に無視せず、共有 factory 生成後の値の衝突を `StateError` で通知するよう変更した
```
