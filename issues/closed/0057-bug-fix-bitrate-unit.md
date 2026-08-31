# ビットレートの単位表記を kbps に統一し、有効範囲検証を追加する

- Created: 2026-08-03
- Completed: 2026-08-20
- Branch: feature/fix-bitrate-unit
- Polished: 2026-08-03

## 目的

`SoraConnectionConfig.audioBitRate` と `SoraConnectionConfig.videoBitRate` の単位を Sora のシグナリング仕様と一致させ、利用者が bps の値を誤って指定して仕様範囲外の値を送信する問題を防ぐ。

[Sora の WebSocket 経由のシグナリング仕様](https://sora-doc.shiguredo.jp/WEBSOCKET_SIGNALING) では、`audio.bit_rate` は Opus の最大ビットレートとして `6` 〜 `510 kbps`、`video.bit_rate` は最大ビットレートとして `1` 〜 `50000 kbps` を指定する。

また、devtools アプリ内でも音声ビットレートの入力欄と概要表示が `bps` になっており、映像ビットレートの入力欄には単位が表示されていないため、両方を `kbps` に統一する。

## 現状

- `lib/src/sora_connection_config.dart` の `audioBitRate` と `videoBitRate` の DartDoc は単位を `bps` と記載している
- `lib/src/sora_connection_signaling.dart` の `_optionalAudioConnectValue` / `_audioConnectValueWhenExplicitlyOn` と `_optionalVideoConnectValue` / `_videoConnectValueWhenExplicitlyOn` は、指定された値を単位変換せず `bit_rate` として送信する。`audio` / `video` が `false` の場合は、対応するビットレートを connect メッセージへ含めない
- `README.md` の設定例では `audioBitRate: 64` と `videoBitRate: 2500` を使用しており、実質的に `kbps` として扱っている
- DartDoc に従って `64000` や `2500000` を指定すると、Sora の許容範囲を超える値が送信される
- `devtools/lib/main.dart` の音声ビットレート概要表示と `devtools/lib/src/devtools_settings_sections.dart` の音声入力欄は `bps` 表記である。映像入力欄は単位がなく、概要表示だけが `kbps` 表記である
- `devtools/lib/src/devtools_connection_controller.dart` の `selectedAudioBitRate` のコメントも `bps` 表記である
- `devtools/lib/src/devtools_input_validation.dart` の `validateOptionalPositiveInt` は音声ビットレートを正の整数としてしか検証せず、`64000` も受け付ける
- devtools のテスト `devtools/test/devtools_connection_controller_test.dart` では `audioBitRate` に `64000`（bps 想定値）が指定されている

## 再現条件

1. `role: SoraRole.sendrecv`、`audio: true`、`video: true` の `SoraConnectionConfig` を作成する
2. `audioBitRate` に `64000`、または `videoBitRate` に `2500000` を指定して Sora へ接続する
3. 指定値が単位変換されず、そのまま connect メッセージの `audio.bit_rate` / `video.bit_rate` に含まれる
4. Sora の仕様範囲外の値が送信され、意図したビットレートにならない

## 設計方針

- `audioBitRate` と `videoBitRate` のフィールド名、および connect メッセージ内のキー名は変更しない
- 値の単位は `kbps` に統一し、`bps` から `kbps` への自動変換は行わない。既存の `64` や `2500` のような `kbps` の指定は維持し、DartDoc に従って `bps` で指定していた利用者は値を `kbps` へ変更する
- DartDoc に単位が `kbps` であること、および指定可能範囲を明記する
  - `audioBitRate`: `6` 〜 `510 kbps`
  - `videoBitRate`: `1` 〜 `50000 kbps`
- `SoraConnectionConfig` の `const` コンストラクタは維持する。Dart の `const` コンストラクタでは例外を送出できないため、範囲検証は `SoraConnectionConfig.toMap()` の実行時に行い、範囲外の場合は `RangeError` を送出する。`null`（未指定）はエラーとしない
- `SoraConnection.internalCreate()` はネイティブクライアント作成前に `config.toMap()` を呼び出すため、不正な値をネイティブ側へ渡さずに検出できるようにする
- `video: false`、`audio: false`、`role: SoraRole.recvonly` であっても `audioBitRate` / `videoBitRate` の範囲検証は行う。無効なメディアの connect メッセージには従来どおり対応するビットレートを含めない
- `_buildConnectMessage()` と音声・映像の各 connect 値生成関数は、検証済みの指定値を単位変換せずそのまま `bit_rate` に設定する
- `videoBitRate` の上限は仕様に記載された `50000 kbps` とする。仕様にある `15 Mbps` 超は現時点でサポート外という注意書きによる追加制限や値の丸めは、この issue では行わない
- `README.md` の設定例でビットレートの単位と指定値が `kbps` であることを明記する
- devtools の音声・映像ビットレートの入力欄、概要表示、設定値コメントを `kbps` 表記に統一する。音声入力欄では `6` 〜 `510` の範囲も検証する

## 完了条件

- [x] `audioBitRate` と `videoBitRate` の DartDoc に単位が `kbps` と記載され、最大ビットレートであることが分かる
- [x] それぞれの指定可能範囲が DartDoc に記載されている（`audioBitRate` は `6` 〜 `510 kbps`、`videoBitRate` は `1` 〜 `50000 kbps`）
- [x] `SoraConnectionConfig` の `const` コンストラクタが維持されている
- [x] `SoraConnectionConfig.toMap()` で範囲外の値を指定した場合、`RangeError` が送出される
- [x] null（未指定）は範囲検証の対象外である
- [x] `video: false`、`audio: false`、`role: SoraRole.recvonly` の設定時でも範囲検証が有効である
- [x] `64` と `2500` を指定した場合、connect メッセージの `audio.bit_rate` / `video.bit_rate` に同じ値が設定される
- [x] `audio: false` / `video: false` の connect メッセージが従来どおり `false` となり、ビットレートを含まない
- [x] `README.md` の設定例に `kbps` の単位と指定値の意味が明記されている
- [x] devtools の音声・映像ビットレートの入力欄、概要表示、コメントが `kbps` 表記になっている
- [x] devtools の音声入力欄が空欄または `6` 〜 `510` を受け付け、範囲外をエラー表示する
- [x] 境界値と範囲外の値を検証するテストが追加されている（`test/sora_connection_config_test.dart`、`devtools/test/widget_test.dart` 等）
- [x] devtools のテストで音声ビットレートが `64`（kbps 想定値）に更新されている
- [x] モックやスタブを使用していない
- [x] `flutter analyze` と関連するテストが成功する

## 解決方法

`SoraConnectionConfig.audioBitRate` と `SoraConnectionConfig.videoBitRate` の DartDoc を `kbps` 表記へ修正し、Sora の仕様に基づく指定可能範囲を明記した。

`SoraConnectionConfig.toMap()` の実行時に音声を `6` 〜 `510 kbps`、映像を `1` 〜 `50000 kbps` の範囲で検証し、範囲外の場合は `RangeError` を送出するようにした。`const` コンストラクタは維持し、`null` は未指定として許可した。

connect メッセージの音声・映像値生成処理を `lib/src/sora_connect_message.dart` へ切り出し、指定値を変換せず `bit_rate` へ設定する既存動作を維持した。`audio: false` / `video: false` の場合はビットレートを含めない。

README と devtools のビットレート表記を `kbps` に統一し、devtools の音声入力値を `6` 〜 `510` の範囲で検証するようにした。境界値、範囲外、未指定、無効メディア、connect 値のテストを追加し、SDK 本体と devtools の解析・テスト・E2E を確認した。
